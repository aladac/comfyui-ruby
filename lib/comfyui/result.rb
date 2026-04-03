# frozen_string_literal: true

module ComfyUI
  GenerationResult = Data.define(:prompt_id, :images, :node_errors, :success) do
    def initialize(prompt_id:, images: [], node_errors: {}, success: true)
      super
    end
  end

  WorkflowResult = Data.define(:prompt_id, :outputs, :node_errors, :success) do
    def initialize(prompt_id:, outputs: {}, node_errors: {}, success: true)
      super
    end
  end
end
