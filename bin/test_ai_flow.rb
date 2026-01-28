require_relative '../app'

# MOCK AI module to avoid burning tokens
module AI
  def self.chat(messages, tools: [], model: nil, temperature: nil)
    puts "\n--- [MOCK AI] ---"
    puts "Messages: #{messages.last[:content]}"
    puts "System Prompt Length: #{messages.first[:content].length}"

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
      def send_message(contact, content, metadata = {})
        puts "\n>>> [SENDING TO #{contact.external_id}]: #{content}"
        true
      end

      def notify_supervisor(content, metadata = {})
        puts "\n>>> [SUPERVISOR NOTIFICATION]: #{content}"
        true
      end
    end
  end
end

puts 'Setting up test data...'

# Setup Dummy Data
# We use transaction rollback to clean up
ActiveRecord::Base.transaction do
  user = User.create!(email: 'test@example.com', password: 'password')
  assistant = Assistant.create!(
    name: 'Tester',
    identity: 'You are a helpful assistant.',
    global_memory: 'We sell apples.',
    user: user
  )
  contact = Contact.create!(
    name: 'John Doe',
    external_id: '123456',
    assistant: assistant
  )

  # Create a Mock Channel
  Channel.create!(
    assistant: assistant,
    provider: 'mock_provider',
    provider_uid: '123',
    active: true
  )

  channel = assistant.channels.first

  puts "\nTest 1: Normal Chat"
  assistant.process_message(contact, channel, 'Hello, do you sell apples?')

  puts "\nTest 2: Tool Usage (Supervisor)"
  assistant.process_message(contact, channel, 'I want to speak to your supervisor.')

  raise ActiveRecord::Rollback
end

puts "\nDone."
