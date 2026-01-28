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
    # Find tasks that are pending and due
    pending_tasks = ScheduledTask.where(status: 'pending')
                                 .where('run_at <= ?', Time.now)
                                 .limit(10)

    log_scheduler "Found #{pending_tasks.count} pending tasks." if pending_tasks.any?

    pending_tasks.each do |task|
      # TODO: Process task.. not yet!
    end
  rescue StandardError => e
    log_scheduler "Global Loop Error: #{e.message}"
  end
end
