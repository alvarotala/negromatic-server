# frozen_string_literal: true

require 'httparty'

module Negromatic
  module Channels
    class Whatsapp < Base
      # WAHA API Base URL (internal docker network)
      WAHA_BASE_URL = ENV['WAHA_URL'] || 'http://waha:3000'

      def send_message(contact, content, metadata = {})
        session = channel.config['session'] || 'default'
        
        response = HTTParty.post("#{WAHA_BASE_URL}/api/sendText", 
          headers: { 'Content-Type' => 'application/json' },
          body: {
            session: session,
            chatId: format_whatsapp_id(contact.external_id),
            text: content
          }.to_json
        )

        if response.success?
          log_interaction(contact, 'outbound', content, metadata)
          true
        else
          false
        end
      end

      def notify_supervisor(content, metadata = {})
        # Typically supervisors are notified via Telegram or a specific WA group
        # If the supervisor is on WhatsApp, we can send it here.
        supervisor_phone = channel.config['supervisor_phone']
        return false unless supervisor_phone

        session = channel.config['session'] || 'default'
        
        HTTParty.post("#{WAHA_BASE_URL}/api/sendText", 
          headers: { 'Content-Type' => 'application/json' },
          body: {
            session: session,
            chatId: format_whatsapp_id(supervisor_phone),
            text: "🚨 [SUPERVISOR NOTIFICATION]\n\n#{content}"
          }.to_json
        ).success?
      end

      def receive_message(payload)
        # WAHA Webhook payload processing
        # Example payload: { "event": "message", "payload": { "id": "...", "from": "...", "body": "..." } }
        return unless payload['event'] == 'message'

        msg = payload['payload']
        external_id = msg['from'].split('@').first # Basic normalization
        
        contact = channel.assistant.contacts.find_or_create_by!(external_id: external_id) do |c|
          c.name = msg['pushName'] || "WhatsApp User"
        end

        log_interaction(contact, 'inbound', msg['body'])
        
        contact
      end

      private

      def format_whatsapp_id(id)
        # Ensure it ends with @c.us for WAHA
        id.include?('@') ? id : "#{id}@c.us"
      end
    end
  end
end
