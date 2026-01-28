# frozen_string_literal: true

module Negromatic
  module Tools
    class GenerateImage < Base
      def self.definition
        {
          type: 'function',
          function: {
            name: 'generate_image',
            description: 'Generate an image. Returns the image URL.',
            parameters: {
              type: 'object',
              properties: {
                prompt: { type: 'string' }
              },
              required: ['prompt']
            }
          }
        }
      end

      def execute(args)
        log("Generating image: #{args['prompt']}")
        
        url = AI.generate_image(args['prompt'])
        
        if url
          url # Return the URL string
        else
          "I tried to generate an image but failed."
        end
      end
    end
  end
end
