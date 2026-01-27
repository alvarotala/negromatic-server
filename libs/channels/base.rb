module Negromatic
  module Channels
    class Base
      attr_reader :channel

      def initialize(channel)
        @channel = channel
      end

      # Send a message to a specific contact
      def send_message(contact, content, metadata = {})
        raise NotImplementedError, "#{self.class} must implement #send_message"
      end

      # Send a notification to the supervisor
      def notify_supervisor(content, metadata = {})
        raise NotImplementedError, "#{self.class} must implement #notify_supervisor"
      end

      # Process an incoming message
      def receive_message(payload)
        raise NotImplementedError, "#{self.class} must implement #receive_message"
      end

      protected

      def log_interaction(contact, direction, content, metadata = {})
        Interaction.create!(
          assistant: channel.assistant,
          contact: contact,
          channel: channel,
          direction: direction,
          content: content,
          metadata: metadata
        )
      end
    end
  end
end
