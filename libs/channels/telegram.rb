# frozen_string_literal: true

require 'httparty'

module Negromatic
  module Channels
    class Telegram < Base
      TELEGRAM_API_URL = 'https://api.telegram.org/bot'

      def send_message(contact, content, metadata = {})
        token = channel.config['token']
        return false unless token

        response = HTTParty.post("#{TELEGRAM_API_URL}#{token}/sendMessage", 
          body: {
            chat_id: contact.external_id,
            text: content,
            parse_mode: 'HTML'
          }
        )

        if response.success?
          log_interaction(contact, 'outbound', content, metadata)
          true
        else
          false
        end
      end

      def notify_supervisor(content, metadata = {})
        token = channel.config['token']
        chat_id = channel.config['supervisor_chat_id']
        return false unless token && chat_id

        HTTParty.post("#{TELEGRAM_API_URL}#{token}/sendMessage", 
          body: {
            chat_id: chat_id,
            text: "🚨 <b>[SUPERVISOR NOTIFICATION]</b>\n\n#{content}",
            parse_mode: 'HTML'
          }
        ).success?
      end

      def receive_message(payload)
        # Telegram Webhook payload
        # payload is the 'message' object from Telegram
        msg = payload['message'] || payload['callback_query']&.[]('message')
        return unless msg

        from = msg['from']
        external_id = from['id'].to_s
        
        contact = channel.assistant.contacts.find_or_create_by!(external_id: external_id) do |c|
          c.name = [from['first_name'], from['last_name']].compact.join(' ')
        end

        log_interaction(contact, 'inbound', msg['text'])
        
        contact
      end
    end
  end
end
