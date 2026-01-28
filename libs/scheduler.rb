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
        task.update(status: 'processing')
        
        begin
          assistant = task.assistant
          payload = task.payload || {}

          case task.task_type
          when 'social_post'
            log_scheduler "Processing social post for Assistant #{assistant.name}"
            
            content = payload['content']
            image_prompt = payload['image_prompt']
            
            # Generate image if requested
            image_url = nil
            if image_prompt && !image_prompt.empty?
              log_scheduler "Generating image for prompt: #{image_prompt}"
              image_url = AI.generate_image(image_prompt)
              content = "#{content}\n\n#{image_url}" if image_url
            end

            # Post to the assistant's primary channel (or specific one if configured)
            # For now, we broadcast to all active channels or just the first one
            channel = assistant.channels.where(active: true).first
            
            if channel
              log_scheduler "Posting to #{channel.provider}..."
              # In a real app, we might distinguish between 'send_message' and 'post_media'
              # For now, we use send_message which in our stubs just logs/sends text
              
              # If we have a dedicated provider class, instantiate it
              klass = "Negromatic::Channels::#{channel.provider.camelize}".constantize
              client = klass.new(channel)
              
              # Helper to send - logic might vary by provider (e.g. Instagram vs WhatsApp)
              if client.respond_to?(:send_message)
                 # Dummy contact for social posts? Or broadcast? 
                 # Usually social posts don't have a single contact. 
                 # This acts more like a broadcast or feed post.
                 # For MVP, we might just log it or send to a "Self" contact if required by API.
                 # Let's assume send_message handles it or we log it.
                 client.send_message(OpenStruct.new(external_id: 'BROADCAST', name: 'Followers'), content)
              end
            else
              log_scheduler "No active channel found for assistant."
            end

          when 'follow_up'
            log_scheduler "Processing follow-up for Assistant #{assistant.name}"
            contact_id = payload['contact_id']
            message = payload['message']
            
            contact = Contact.find_by(id: contact_id)
            if contact && message
               channel = assistant.channels.where(active: true).first
               if channel
                 klass = "Negromatic::Channels::#{channel.provider.camelize}".constantize
                 client = klass.new(channel)
                 client.send_message(contact, message)
               end
            else
               log_scheduler "Invalid contact or message for follow-up."
            end
          end
          
          task.update(status: 'completed')
          log_scheduler "Task #{task.id} completed."
        rescue => e
          log_scheduler "Task #{task.id} Failed: #{e.message}"
          log_scheduler e.backtrace.join("\n")
          task.update(status: 'failed', payload: task.payload.merge(error: e.message))
        end
      end
    rescue => e
      log_scheduler "Global Loop Error: #{e.message}"
    end
  end
end
