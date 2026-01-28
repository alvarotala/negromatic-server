require_relative '../app'

puts 'Setting up test data for Interaction Persistence...'

# Mocking MockProvider
module Negromatic
  module Channels
    class MockProvider
      def initialize(channel)
        @channel = channel
      end
      def send_message(contact, text)
        puts ">>> [MOCK SEND]: #{text}"
      end
    end
  end
end

ActiveRecord::Base.transaction do
  user = User.create!(email: 'persist_test@example.com', password: 'password')
  assistant = Assistant.create!(name: 'PersistBot', user: user)
  contact = Contact.create!(name: 'User1', assistant: assistant)
  ContactIdentity.create!(contact: contact, assistant: assistant, provider: 'mock_provider', external_id: '123456')
  
  channel = Channel.create!(
    assistant: assistant,
    provider: 'mock_provider',
    provider_uid: '123',
    active: true
  )

  puts "\n--- Test: Process a message and check interactions ---"
  message_text = "Hello, can you remember me?"
  
  # Mock AI to return a specific response
  def AI.chat(messages, tools: [], model: nil, temperature: nil)
    { content: "Yes, I can remember you.", tool_calls: nil }
  end

  assistant.process_message(contact, channel, message_text)
  
  inbound = Interaction.where(contact: contact, direction: 'inbound').last
  outbound = Interaction.where(contact: contact, direction: 'outbound').last
  
  if inbound && inbound.content == message_text
    puts "✓ Inbound interaction saved correctly: #{inbound.content}"
  else
    puts "❌ Inbound interaction NOT saved or incorrect."
    exit 1
  end

  if outbound && outbound.content == "Yes, I can remember you."
    puts "✓ Outbound interaction saved correctly: #{outbound.content}"
  else
    puts "❌ Outbound interaction NOT saved or incorrect."
    exit 1
  end

  raise ActiveRecord::Rollback
end

puts "\n✓ Interaction Persistence Verified Successfully!"
