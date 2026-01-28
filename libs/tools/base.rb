# frozen_string_literal: true

module Negromatic
  module Tools
    class Base
      attr_reader :assistant, :contact, :channel

      def initialize(assistant, contact, channel)
        @assistant = assistant
        @contact = contact
        @channel = channel
      end

      # Should return the JSON schema for the tool
      def self.definition
        raise NotImplementedError
      end

      # Should execute the tool logic
      def execute(args)
        raise NotImplementedError
      end
      
      protected
      
      def log(msg, level: :info)
        AppLogger.log("[Tool:#{self.class.name.demodulize}] #{msg}", level: level)
      end
    end
  end
end
