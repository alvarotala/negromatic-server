require 'net/http'
require 'json'

module Negromatic
  module Channels
    class Telegram < Base
      def send_message(contact, content, metadata = {})
        token = channel.config['bot_token']
        chat_id = contact.external_id
        
        success = post_to_telegram(token, "sendMessage", {
          chat_id: chat_id,
          text: content
        })

        log_interaction(contact, 'outbound', content, metadata) if success
        success
      end

      def notify_supervisor(content, metadata = {})
        token = channel.config['bot_token']
        supervisor_chat_id = channel.config['supervisor_chat_id']
        
        post_to_telegram(token, "sendMessage", {
          chat_id: supervisor_chat_id,
          text: "🔔 *Supervisor Notification*\n\n#{content}",
          parse_mode: 'Markdown'
        })
      end

      private

      def post_to_telegram(token, method, payload)
        uri = URI("https://api.telegram.org/bot#{token}/#{method}")
        response = Net::HTTP.post(uri, payload.to_json, { "Content-Type" => "application/json" })
        JSON.parse(response.body)['ok']
      rescue => e
        puts "Telegram Error: #{e.message}"
        false
      end
    end
  end
end
