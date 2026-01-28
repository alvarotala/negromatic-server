require 'rufus-scheduler'

# Ensure models are loaded
require_relative 'boot'
require_relative 'ai'

scheduler = Rufus::Scheduler.new

def log_scheduler(msg)
  puts "[Scheduler] #{msg}"
end

# Task to process scheduled tasks every minute
scheduler.every '1m' do
  ActiveRecord::Base.connection_pool.with_connection do
    begin
      # Find tasks that are pending and due
      pending_tasks = ScheduledTask.where(status: 'pending')
                                  .where('run_at <= ?', Time.now)
                                  .limit(10)
      
      if pending_tasks.any?
        log_scheduler "Found #{pending_tasks.count} pending tasks."
      end

      pending_tasks.each do |task|
        Negromatic::TaskProcessor.process(task)
      end
    rescue => e
      log_scheduler "Global Loop Error: #{e.message}"
    end
  end
end
