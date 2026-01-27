require 'rufus-scheduler'

scheduler = Rufus::Scheduler.new

# Task to process scheduled tasks every minute
scheduler.every '1m' do
  ActiveRecord::Base.connection_pool.with_connection do
    begin
      pending_tasks = ScheduledTask.where(status: 'pending')
                                  .where('run_at <= ?', Time.now)
                                  .limit(10)
      
      pending_tasks.each do |task|
        task.update(status: 'processing')
        
        begin
          case task.task_type
          when 'social_post'
            # Logic for automated social post
            puts "[Scheduler] Processing social post for Assistant #{task.assistant_id}"
            # This would call the relevant Channel and send an image/text
          when 'follow_up'
            # Logic for follow-up message
            puts "[Scheduler] Processing follow-up for Assistant #{task.assistant_id}"
          end
          
          task.update(status: 'completed')
        rescue => e
          puts "[Scheduler] Task Error: #{e.message}"
          task.update(status: 'failed', payload: task.payload.merge(error: e.message))
        end
      end
    rescue => e
      puts "[Scheduler] Global Error: #{e.message}"
    end
  end
end
