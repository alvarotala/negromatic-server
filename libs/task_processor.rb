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
      @task.update(status: 'processing')

      begin
        case @task.task_type
        when 'social_post'
          process_social_post
        when 'follow_up'
          process_follow_up
        end

        @task.update(status: 'completed')
        log "Task #{@task.id} completed."
      rescue StandardError => e
        log "Task #{@task.id} Failed: #{e.message}"
        # log e.backtrace.join("\n")
        @task.update(status: 'failed', payload: @payload.merge(error: e.message))
      end
    end

    private

    def process_social_post
      log "Processing social post for Assistant #{@assistant.name}"

      content = @payload['content']
      image_prompt = @payload['image_prompt']

      # Generate image if requested
      if image_prompt && !image_prompt.empty?
        log "Generating image for prompt: #{image_prompt}"
        # AI module must be available
        image_url = AI.generate_image(image_prompt)
        content = "#{content}\n\n#{image_url}" if image_url
      end

      channel = @assistant.channels.where(active: true).first

      if channel
        log "Posting to #{channel.provider}..."
        send_to_channel(channel, ::OpenStruct.new(external_id: 'BROADCAST', name: 'Followers'), content)
      else
        log 'No active channel found for assistant.'
      end
    end

    def process_follow_up
      log "Processing follow-up for Assistant #{@assistant.name}"
      contact_id = @payload['contact_id']
      message = @payload['message']

      contact = Contact.find_by(id: contact_id)
      if contact && message
        channel = @assistant.channels.where(active: true).first
        send_to_channel(channel, contact, message) if channel
      else
        log 'Invalid contact or message for follow-up.'
      end
    end

    def send_to_channel(channel, contact, content)
      klass = "Negromatic::Channels::#{channel.provider.camelize}".constantize
      client = klass.new(channel)

      return unless client.respond_to?(:send_message)

      client.send_message(contact, content)
    end
  end
end
