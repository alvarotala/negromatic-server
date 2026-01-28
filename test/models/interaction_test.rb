require_relative '../test_helper'

class InteractionTest < Minitest::Test
  def setup
    super
    @user = User.create!(email: 'persist_test@example.com', password: 'password')
    @assistant = Assistant.create!(name: 'PersistBot', user: @user)
    @contact = Contact.create!(name: 'User1', assistant: @assistant)
    ContactIdentity.create!(contact: @contact, assistant: @assistant, provider: 'mock_provider', external_id: '123456')
    
    @channel = Channel.create!(
      assistant: @assistant,
      provider: 'mock_provider',
      provider_uid: '123',
      active: true
    )
    @channel.reload
  end

  def test_interaction_persistence
    message_text = "Hello, can you remember me?"
    
    # Since we use MockAI from test_helper, we don't need to redefine it unless we want specific response.
    # The default mock response in test_helper is "This is a generic mock response." unless 'help' or 'supervisor'.
    # So if we want to match specific outbound content, we might accept the generic one.
    
    @assistant.process_message(@contact, @channel, message_text)
    
    inbound = Interaction.where(contact: @contact, direction: 'inbound').last
    outbound = Interaction.where(contact: @contact, direction: 'outbound').last
    
    assert inbound, "Inbound interaction should exist"
    assert_equal message_text, inbound.content
    
    assert outbound, "Outbound interaction should exist"
    # Helper returns "This is a generic mock response."
    assert_equal "This is a generic mock response.", outbound.content
  end
end
