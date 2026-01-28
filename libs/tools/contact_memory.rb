# frozen_string_literal: true

module Negromatic
  module Tools
    class ContactMemory < Base
      def self.definition
        {
          type: 'function',
          function: {
            name: 'contact_memory',
            description: 'Manage contact-specific memories. Allows saving new facts or searching for existing ones about the current user.',
            parameters: {
              type: 'object',
              properties: {
                action: {
                  type: 'string',
                  enum: %w[save search],
                  description: 'Action to perform: save a new memory or search for existing ones.'
                },
                content: {
                  type: 'string',
                  description: 'The information to remember (required for save).'
                },
                query: {
                  type: 'string',
                  description: 'The search term (required for search).'
                }
              },
              required: ['action']
            }
          }
        }
      end

      def execute(args)
        case args['action']
        when 'save'
          return "Error: content is required for save action" unless args['content']
          save_memory(args['content'])
        when 'search'
          return "Error: query is required for search action" unless args['query']
          search_memories(args['query'])
        else
          "Error: Unknown action #{args['action']}"
        end
      end

      private

      def save_memory(content)
        log("Saving contact memory for contact #{contact.id}: #{content}")
        Memory.create!(
          assistant_id: assistant.id,
          contact_id: contact.id,
          content: content
        )
        "_[Contact memory saved]_"
      rescue => e
        "Error saving contact memory: #{e.message}"
      end

      def search_memories(query)
        log("Searching contact memories for: #{query}")
        results = Memory.search(query, assistant_id: assistant.id, contact_id: contact.id)
        
        if results.any?
          results.map { |r| "- #{r.content}" }.join("\n")
        else
          "No contact memories found for: #{query}"
        end
      rescue => e
        "Error searching contact memories: #{e.message}"
      end
    end
  end
end
