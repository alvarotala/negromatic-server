# frozen_string_literal: true

module Negromatic
  module Tools
    class SaveGlobalMemory < Base
      def self.definition
        {
          type: 'function',
          function: {
            name: 'save_global_memory',
            description: 'Save a persistent global memory for the assistant. Use this for facts, rules, or information that applies to all users and is not specific to the current contact.',
            parameters: {
              type: 'object',
              properties: {
                content: { type: 'string', description: 'The global information to remember.' }
              },
              required: %w[content]
            }
          }
        }
      end

      def execute(args)
        log("Saving global memory for assistant #{assistant.id}: #{args['content']}")
        
        Memory.create!(
          assistant_id: assistant.id,
          contact_id: nil,
          content: args['content']
        )
        
        "_[Global memory saved]_"
      rescue => e
        "Error saving global memory: #{e.message}"
      end
    end
  end
end
