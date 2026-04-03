# frozen_string_literal: true

require "faraday"
require "json"
require "securerandom"

module ComfyUI
  # Ruby client for the ComfyUI HTTP + WebSocket API.
  #
  # @example
  #   client = ComfyUI::Client.new("http://localhost:8188")
  #   client.system_stats
  #   client.models
  #   client.generate(prompt: "a cat in space")
  #
  class Client
    attr_reader :url

    # @param url [String] ComfyUI base URL
    # @param timeout [Integer] HTTP timeout in seconds
    def initialize(url = nil, timeout: 30)
      @url = url || ENV.fetch("COMFYUI_URL", DEFAULT_URL)
      @conn = Faraday.new(url: @url) do |f|
        f.options.timeout = timeout
        f.options.open_timeout = 10
        f.request :json
        f.response :json
        f.response :raise_error
      end
      @raw_conn = Faraday.new(url: @url) do |f|
        f.options.timeout = timeout
      end
    end

    # ----------------------------------------------------------------
    # Query endpoints
    # ----------------------------------------------------------------

    # Get system stats (GPU, RAM, etc.)
    # @return [Hash]
    def system_stats
      get("/system_stats")
    end

    # Get queue status.
    # @return [Hash] with queue_running and queue_pending
    def queue_status
      get("/queue")
    end

    # Clear the queue.
    # @return [Boolean]
    def clear_queue
      post("/queue", {clear: true})
      true
    end

    # Get available nodes and their configurations.
    # @return [Hash]
    def object_info
      get("/object_info")
    end

    # Get available models grouped by type.
    # @return [Hash{String => Array<String>}]
    def models
      info = object_info
      result = {}

      model_types = {
        "checkpoints" => ["CheckpointLoaderSimple", "ckpt_name"],
        "loras" => ["LoraLoader", "lora_name"],
        "vae" => ["VAELoader", "vae_name"],
        "clip" => ["CLIPLoader", "clip_name"],
        "controlnet" => ["ControlNetLoader", "control_net_name"],
        "upscale_models" => ["UpscaleModelLoader", "model_name"]
      }

      model_types.each do |type, (node_class, input_name)|
        next unless info[node_class]

        inputs = info.dig(node_class, "input", "required") || {}
        next unless inputs[input_name]

        input_def = inputs[input_name]
        if input_def.is_a?(Array) && input_def[0].is_a?(Array)
          result[type] = input_def[0]
        end
      end

      result
    end

    # Get generation history.
    # @param prompt_id [String, nil] specific prompt ID (nil = recent history)
    # @param max_items [Integer] maximum items to return
    # @return [Hash]
    def history(prompt_id: nil, max_items: 100)
      if prompt_id
        get("/history/#{prompt_id}")
      else
        get("/history", max_items: max_items)
      end
    end

    # ----------------------------------------------------------------
    # Workflow execution
    # ----------------------------------------------------------------

    # Queue a workflow for execution.
    # @param workflow [Hash] ComfyUI API format workflow
    # @param client_id [String] client ID for WebSocket tracking
    # @return [Hash] with prompt_id and number
    def queue_prompt(workflow, client_id: nil)
      client_id ||= SecureRandom.uuid
      payload = {prompt: workflow, client_id: client_id}
      result = post("/prompt", payload)

      if result["error"]
        raise APIError, "Workflow error: #{result["error"]}"
      end

      result
    end

    # Run a workflow and wait for completion via polling.
    # @param workflow [Hash] ComfyUI API format workflow
    # @param timeout [Float] max wait in seconds
    # @param on_progress [Proc, nil] callback(step, total, message)
    # @return [WorkflowResult]
    def run_workflow(workflow, timeout: 600, on_progress: nil)
      client_id = SecureRandom.uuid
      result = queue_prompt(workflow, client_id: client_id)
      prompt_id = result["prompt_id"]

      poll_for_completion(prompt_id, timeout: timeout, on_progress: on_progress)
    end

    # Generate an image with a simple text-to-image workflow.
    # @param prompt [String] positive prompt
    # @param negative_prompt [String] negative prompt
    # @param model [String, nil] checkpoint name (nil = first available)
    # @param width [Integer] image width
    # @param height [Integer] image height
    # @param steps [Integer] sampling steps
    # @param cfg [Float] CFG scale
    # @param seed [Integer] seed (-1 = random)
    # @param sampler [String] sampler name
    # @param scheduler [String] scheduler name
    # @param lora_name [String, nil] LoRA filename
    # @param lora_strength [Float] LoRA strength
    # @param batch_size [Integer] images per batch
    # @param vae [String, nil] VAE filename
    # @param timeout [Float] max wait in seconds
    # @param on_progress [Proc, nil] callback(step, total, message)
    # @return [GenerationResult]
    def generate(
      prompt:,
      negative_prompt: "",
      model: nil,
      width: 1024,
      height: 1024,
      steps: 20,
      cfg: 7.0,
      seed: -1,
      sampler: "euler",
      scheduler: "normal",
      lora_name: nil,
      lora_strength: 1.0,
      batch_size: 1,
      vae: nil,
      timeout: 600,
      on_progress: nil
    )
      # Auto-select first checkpoint if none specified
      unless model
        available = models
        model = available["checkpoints"]&.first
        raise Error, "No checkpoints available" unless model
      end

      workflow = ComfyUI::Workflow.build(
        prompt: prompt,
        negative_prompt: negative_prompt,
        model: model,
        width: width,
        height: height,
        steps: steps,
        cfg: cfg,
        seed: seed,
        sampler: sampler,
        scheduler: scheduler,
        lora_name: lora_name,
        lora_strength: lora_strength,
        batch_size: batch_size,
        vae: vae
      )

      result = run_workflow(workflow, timeout: timeout, on_progress: on_progress)

      images = result.outputs.each_with_object([]) do |(_node_id, output), acc|
        next unless output["images"]

        output["images"].each do |img_info|
          filename = img_info["filename"]
          subfolder = img_info["subfolder"] || ""
          type = img_info["type"] || "output"
          acc << {filename: filename, subfolder: subfolder, type: type} if type == "output"
        end
      end

      GenerationResult.new(
        prompt_id: result.prompt_id,
        images: images,
        node_errors: result.node_errors,
        success: result.success
      )
    end

    # Download a generated image.
    # @param filename [String] image filename
    # @param subfolder [String] subfolder
    # @param folder_type [String] output, input, or temp
    # @return [String] image bytes
    def image(filename, subfolder: "", folder_type: "output")
      response = @raw_conn.get("/view", {
        filename: filename,
        subfolder: subfolder,
        type: folder_type
      })
      response.body
    end

    private

    def get(path, params = {})
      response = @conn.get(path, params)
      response.body
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
      raise ConnectionError, "Failed to connect to ComfyUI at #{@url}: #{e.message}"
    rescue Faraday::ClientError, Faraday::ServerError => e
      raise APIError, "ComfyUI API error: #{e.message}"
    end

    def post(path, body = {})
      response = @conn.post(path) { |req| req.body = body }
      response.body
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
      raise ConnectionError, "Failed to connect to ComfyUI at #{@url}: #{e.message}"
    rescue Faraday::ClientError, Faraday::ServerError => e
      raise APIError, "ComfyUI API error: #{e.message}"
    end

    def poll_for_completion(prompt_id, timeout: 600, on_progress: nil)
      start = Time.now
      interval = 0.5

      loop do
        elapsed = Time.now - start
        raise TimeoutError, "Workflow did not complete within #{timeout}s" if elapsed > timeout

        hist = history(prompt_id: prompt_id)

        if hist[prompt_id]
          entry = hist[prompt_id]
          outputs = entry["outputs"] || {}
          status = entry.dig("status", "status_str")

          if status == "error"
            return WorkflowResult.new(
              prompt_id: prompt_id,
              outputs: outputs,
              node_errors: entry.dig("status", "messages") || {},
              success: false
            )
          end

          return WorkflowResult.new(
            prompt_id: prompt_id,
            outputs: outputs,
            success: true
          )
        end

        on_progress&.call(0, 0, "Running...")
        sleep interval
      end
    end
  end
end
