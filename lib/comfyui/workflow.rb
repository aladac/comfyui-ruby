# frozen_string_literal: true

require "json"
require "securerandom"

module ComfyUI
  # Default SDXL/Illustrious/Pony compatible workflow template.
  # Uses separate VAE loader for better quality with modern models.
  DEFAULT_WORKFLOW = {
    "3" => {
      "class_type" => "KSampler",
      "inputs" => {
        "seed" => 0,
        "steps" => 20,
        "cfg" => 7.0,
        "sampler_name" => "euler",
        "scheduler" => "normal",
        "denoise" => 1.0,
        "model" => ["4", 0],
        "positive" => ["6", 0],
        "negative" => ["7", 0],
        "latent_image" => ["5", 0]
      }
    },
    "4" => {
      "class_type" => "CheckpointLoaderSimple",
      "inputs" => {"ckpt_name" => ""}
    },
    "5" => {
      "class_type" => "EmptyLatentImage",
      "inputs" => {"width" => 1024, "height" => 1024, "batch_size" => 1}
    },
    "6" => {
      "class_type" => "CLIPTextEncode",
      "inputs" => {"text" => "", "clip" => ["4", 1]}
    },
    "7" => {
      "class_type" => "CLIPTextEncode",
      "inputs" => {"text" => "", "clip" => ["4", 1]}
    },
    "8" => {
      "class_type" => "VAEDecode",
      "inputs" => {"samples" => ["3", 0], "vae" => ["11", 0]}
    },
    "9" => {
      "class_type" => "SaveImage",
      "inputs" => {"filename_prefix" => "comfy", "images" => ["8", 0]}
    },
    "11" => {
      "class_type" => "VAELoader",
      "inputs" => {"vae_name" => "sdxl_vae.safetensors"}
    }
  }.freeze

  LORA_LOADER_NODE = {
    "class_type" => "LoraLoader",
    "inputs" => {
      "lora_name" => "",
      "strength_model" => 1.0,
      "strength_clip" => 1.0,
      "model" => ["4", 0],
      "clip" => ["4", 1]
    }
  }.freeze

  DEFAULT_VAE = "sdxl_vae.safetensors"

  module Workflow
    module_function

    # Build a text-to-image workflow from parameters.
    #
    # @param prompt [String] positive prompt
    # @param negative_prompt [String] negative prompt
    # @param model [String, nil] checkpoint filename
    # @param width [Integer] image width
    # @param height [Integer] image height
    # @param steps [Integer] sampling steps
    # @param cfg [Float] CFG scale
    # @param seed [Integer] random seed (-1 for random)
    # @param sampler [String] sampler name
    # @param scheduler [String] scheduler name
    # @param lora_name [String, nil] LoRA filename
    # @param lora_strength [Float] LoRA strength
    # @param batch_size [Integer] images per batch
    # @param vae [String, nil] VAE filename (nil = use checkpoint's VAE)
    # @return [Hash] ComfyUI API workflow
    def build(
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
      vae: nil
    )
      wf = JSON.parse(JSON.generate(DEFAULT_WORKFLOW)) # deep copy

      actual_seed = seed >= 0 ? seed : rand(2**32)

      # KSampler
      wf["3"]["inputs"].merge!(
        "seed" => actual_seed,
        "steps" => steps,
        "cfg" => cfg,
        "sampler_name" => sampler,
        "scheduler" => scheduler
      )

      # Checkpoint
      wf["4"]["inputs"]["ckpt_name"] = model if model

      # Dimensions
      wf["5"]["inputs"].merge!("width" => width, "height" => height, "batch_size" => batch_size)

      # Prompts
      wf["6"]["inputs"]["text"] = prompt
      wf["7"]["inputs"]["text"] = negative_prompt

      # VAE
      if vae
        wf["11"]["inputs"]["vae_name"] = vae
      else
        wf.delete("11")
        wf["8"]["inputs"]["vae"] = ["4", 2]
      end

      # LoRA injection
      if lora_name
        lora = JSON.parse(JSON.generate(LORA_LOADER_NODE))
        lora["inputs"].merge!(
          "lora_name" => lora_name,
          "strength_model" => lora_strength,
          "strength_clip" => lora_strength,
          "model" => ["4", 0],
          "clip" => ["4", 1]
        )
        wf["10"] = lora

        wf["3"]["inputs"]["model"] = ["10", 0]
        wf["6"]["inputs"]["clip"] = ["10", 1]
        wf["7"]["inputs"]["clip"] = ["10", 1]
      end

      wf
    end
  end
end
