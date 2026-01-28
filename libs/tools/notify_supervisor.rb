# frozen_string_literal: true

module Negromatic
  module Tools
    class NotifySupervisor < Base
      def self.definition
        {
          type: 'function',
          function: {
            name: 'notify_supervisor',
            description: 'Escalate a situation or report to the human supervisor. Use this when you are unsure, blocked, or need approval.',
            parameters: {
              type: 'object',
              properties: {
                content: { type: 'string', description: 'The message for the supervisor' }
              },
              required: ['content']
            }
          }
        }
      end

      def execute(args)
        content = args['content'] || 'Error: No content provided'
        log("Escalating to supervisor: #{content}")

        '__NOTIFY_SUPERVISOR__'
      end
    end
  end
end
