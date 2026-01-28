# frozen_string_literal: true

require 'httparty'

module Negromatic
  module Channels
    class Instagram < Base
      FB_GRAPH_URL = 'https://graph.facebook.com/v19.0'

      def send_message(contact, content, metadata = {})
        access_token = channel.config['access_token']
        page_id = channel.config['page_id']
        return false unless access_token && page_id

        # Instagram DM via Messenger API
        response = HTTParty.post("#{FB_GRAPH_URL}/me/messages", 
          query: { access_token: access_token },
          body: {
            recipient: { id: contact.external_id },
            message: { text: content }
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
        # Instagram doesn't usually have a "supervisor" notification path like Telegram
        # We can fallback to a configured Telegram channel or skip
        false
      end

      def receive_message(payload)
        # Instagram Webhook payload (Webhook for 'messages')
        # This is a complex nested structure, simplified here for the abstraction
        entry = payload['entry']&.first
        messaging = entry&.[]('messaging')&.first
        return unless messaging && messaging['message']

        external_id = messaging['sender']['id']
        text = messaging['message']['text']
        
        contact = Contact.resolve(channel.assistant, 'instagram', external_id, { name: "Instagram User" })

        log_interaction(contact, 'inbound', text)
        
        contact
      end
    end
  end
end
