# frozen_string_literal: true

module Negromatic
  module Tools
    class GlobalMemory < Base
      def self.definition
        {
          type: 'function',
          function: {
            name: 'global_memory',
            description: 'Manage assistant global memories. Allows saving new facts or searching for existing ones that apply assistant-wide.',
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
        log("Saving global memory for assistant #{assistant.id}: #{content}")
        Memory.create!(
          assistant_id: assistant.id,
          contact_id: nil,
          content: content
        )
        "_[Global memory saved]_"
      rescue => e
        "Error saving global memory: #{e.message}"
      end

      def search_memories(query)
        log("Searching global memories for: #{query}")
        results = Memory.search(query, assistant_id: assistant.id, contact_id: nil)
        
        if results.any?
          results.map { |r| "- #{r.content}" }.join("\n")
        else
          "No global memories found for: #{query}"
        end
      rescue => e
        "Error searching global memories: #{e.message}"
      end
    end
  end
end
