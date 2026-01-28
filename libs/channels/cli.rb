# frozen_string_literal: true

require 'pastel'

module Negromatic
  module Channels
    class Cli < Base
      def send_message(contact, content, metadata = {})
        pastel = Pastel.new
        puts pastel.bold.green("\n[#{channel.assistant.name}] -> [#{contact.name}]: ") + content
        
        log_interaction(contact, 'outbound', content, metadata)
        true
      end

      def notify_supervisor(content, metadata = {})
        pastel = Pastel.new
        puts pastel.bold.red("\n🚨 [SUPERVISOR NOTIFICATION]: ") + content
        true
      end

      def receive_message(payload)
        # payload expected: { 'text' => '...', 'sender_id' => '...', 'sender_name' => '...' }
        text = payload['text']
        sender_id = payload['sender_id'] || 'cli-user'
        sender_name = payload['sender_name'] || 'CLI User'

        contact = channel.assistant.contacts.find_or_create_by!(external_id: sender_id) do |c|
          c.name = sender_name
        end

        log_interaction(contact, 'inbound', text)

        contact
      end
    end
  end
end
