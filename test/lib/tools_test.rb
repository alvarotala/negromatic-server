require_relative '../test_helper'

class ToolsTest < Minitest::Test
  def setup
    super
    @user = User.create!(email: 'tools_test@example.com', password: 'password')
    @assistant = Assistant.create!(name: 'ToolBot', user: @user)
    @contact = Contact.resolve(@assistant, 'mock_provider', 'TOOL_USER', name: 'Tool User')
    @channel = Channel.create!(
      assistant: @assistant,
      provider: 'mock_provider',
      provider_uid: 'TOOL_CHANNEL',
      active: true
    )
  end

  def test_global_memory_tool
    tool = Negromatic::Tools::GlobalMemory.new(@assistant, @contact, @channel)

    # Save
    res = tool.execute({ 'action' => 'save', 'content' => 'Global fact: The sky is blue.' })
    assert_includes res, 'Global memory saved'

    # Search
    # Note: FTS usually updates instantly in Postgres unless explicitly deferred or if test transaction prevents it?
    # Test helper clears DB but uses transaction for each test? Minitest::Test doesn't use transaction by default unless Rails.
    # We are using ActiveRecord directly.
    # In `test_refactored_memories` it did `sleep 2`.
    # Let's see if we need sleep.
    
    res = tool.execute({ 'action' => 'search', 'query' => 'sky blue' })
    assert_includes res, 'The sky is blue'
    
    # Isolation: Should NOT see contact memories
    # Create contact memory first
    Negromatic::Tools::ContactMemory.new(@assistant, @contact, @channel).execute({ 'action' => 'save', 'content' => 'User likes spicy food.' })
    
    res = tool.execute({ 'action' => 'search', 'query' => 'spicy food' })
    assert_includes res, 'No global memories found'
  end

  def test_contact_memory_tool
    tool = Negromatic::Tools::ContactMemory.new(@assistant, @contact, @channel)

    # Save
    res = tool.execute({ 'action' => 'save', 'content' => 'User fact: Likes spicy food.' })
    assert_includes res, 'Contact memory saved'

    # Search
    res = tool.execute({ 'action' => 'search', 'query' => 'spicy food' })
    assert_includes res, 'Likes spicy food'
  end

  def test_manage_contact_tool
    tool = Negromatic::Tools::ManageContact.new(@assistant, @contact, @channel)
    
    # Update profile
    res = tool.execute({ 'action' => 'update_profile', 'data' => { 'phone' => '555-0100', 'email' => 'user@example.com' } })
    assert_includes res, 'Contact profile updated'
    
    @contact.reload
    assert_equal '555-0100', @contact.profile_data['phone']
    assert_equal 'user@example.com', @contact.profile_data['email']
  end
end
