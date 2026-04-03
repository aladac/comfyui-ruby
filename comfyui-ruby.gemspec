# frozen_string_literal: true

require_relative "lib/comfyui/version"

Gem::Specification.new do |spec|
  spec.name = "comfyui-ruby"
  spec.version = ComfyUI::VERSION
  spec.authors = ["aladac"]
  spec.email = ["aladac@saiden.dev"]

  spec.summary = "Ruby client for the ComfyUI API"
  spec.description = "A Ruby client for ComfyUI — query models, queue workflows, " \
    "generate images, and track progress via WebSocket."
  spec.homepage = "https://github.com/aladac/comfyui-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faye-websocket", "~> 0.11"
end
