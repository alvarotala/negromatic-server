module Negromatic
  require 'ostruct'

  class TaskProcessor
    def self.process(task)
      new(task).process
    end

    def initialize(task)
      @task = task
      @assistant = task.assistant
      @payload = task.payload || {}
    end

    def log(msg)
      puts "[TaskProcessor] #{msg}"
    end

    def process
      # @task.update(status: 'processing')
      @task.update(status: 'completed')
      log "Task #{@task.id} completed."
    end
  end
end
