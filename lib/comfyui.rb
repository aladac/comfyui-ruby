# frozen_string_literal: true

require_relative "comfyui/version"
require_relative "comfyui/client"
require_relative "comfyui/workflow"
require_relative "comfyui/result"

module ComfyUI
  DEFAULT_URL = "http://127.0.0.1:8188"

  class Error < StandardError; end
  class ConnectionError < Error; end
  class APIError < Error; end
  class TimeoutError < Error; end
end
