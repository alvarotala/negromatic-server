# frozen_string_literal: true

module Negromatic
  module Tools
    class SaveMemory < Base
      def self.definition
        {
          type: 'function',
          function: {
            name: 'save_memory',
            description: 'Save a persistent memory for the current contact. Use this to remember important facts, preferences, or context about the user.',
            parameters: {
              type: 'object',
              properties: {
                content: { type: 'string', description: 'The information to remember.' }
              },
              required: %w[content]
            }
          }
        }
      end

      def execute(args)
        log("Saving memory for contact #{contact.id}: #{args['content']}")
        
        Memory.create!(
          assistant_id: assistant.id,
          contact_id: contact.id,
          content: args['content']
        )
        
        "_[Memory saved]_"
      rescue => e
        "Error saving memory: #{e.message}"
      end
    end
  end
end
