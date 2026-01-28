ENV['RACK_ENV'] = 'test'
ENV['DB_DATABASE'] = 'negromatic_test'

require 'minitest/autorun'
require_relative '../app'

# Force connection to test database to avoid polluting production/dev DB
# usage of 'postgres' adapter is assumed based on boot.rb
db_config = ActiveRecord::Base.connection_db_config.configuration_hash.merge(database: 'negromatic_test')
ActiveRecord::Base.establish_connection(db_config)

# MOCK AI module to avoid burning tokens
module AI
  def self.chat(messages, tools: [], model: nil, temperature: nil)
    # puts "\n--- [MOCK AI] ---"
    # puts "Messages: #{messages.last[:content]}"

    # Simulate a response based on input
    if messages.last[:content].include?('help')
      { content: 'I can certainly help you with that!', tool_calls: nil }
    elsif messages.last[:content].include?('supervisor')
      { content: nil,
        tool_calls: [{ 'id' => 'call_1',
                       'function' => { 'name' => 'notify_supervisor',
                                       'arguments' => '{"content": "User is asking for a manager"}' } }] }
    else
      { content: 'This is a generic mock response.', tool_calls: nil }
    end
  end

  def self.generate_image(prompt)
    'http://mock-image.url/gen.png'
  end
end

# MOCK Channel to avoid actual API calls
module Negromatic
  module Channels
    class MockProvider < Base
      class << self
        attr_accessor :sent_messages, :supervisor_notifications

        def reset!
          @sent_messages = []
          @supervisor_notifications = []
        end
      end

      def initialize(channel)
        super
        # Ensure arrays are initialized
        self.class.sent_messages ||= []
        self.class.supervisor_notifications ||= []
      end

      def send_message(contact, content, metadata = {})
        self.class.sent_messages << { contact: contact.external_id, content: content }
        true
      end

      def notify_supervisor(content, metadata = {})
        self.class.supervisor_notifications << content
        true
      end
    end
  end
end

class Minitest::Test
  def setup
    # Clear DB before each test
    Interaction.delete_all
    Memory.delete_all
    ScheduledTask.delete_all
    ContactIdentity.delete_all
    Contact.delete_all
    Channel.delete_all
    Assistant.delete_all
    User.delete_all
    Negromatic::Channels::MockProvider.reset!
  end
end
