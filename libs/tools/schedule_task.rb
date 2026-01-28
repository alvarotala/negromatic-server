# frozen_string_literal: true

module Negromatic
  module Tools
    class ScheduleTask < Base
      def self.definition
        {
          type: 'function',
          function: {
            name: 'schedule_task',
            description: 'Schedule a future task (e.g. follow up, post to social media).',
            parameters: {
              type: 'object',
              properties: {
                task_type: { type: 'string', enum: %w[follow_up social_post] },
                payload: { type: 'object', description: 'Data required for the task (e.g., {"message": "..."})' },
                run_at: { type: 'string', description: 'ISO8601 timestamp for when to run the task' }
              },
              required: %w[task_type run_at]
            }
          }
        }
      end

      def execute(args)
        log("Scheduling task: #{args}")
        
        ScheduledTask.create!(
          assistant_id: assistant.id,
          task_type: args['task_type'],
          payload: args['payload'],
          run_at: args['run_at'],
          status: 'pending'
        )
        
        "_[Task scheduled]_"
      end
    end
  end
end
