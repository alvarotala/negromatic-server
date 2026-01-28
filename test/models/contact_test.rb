require_relative '../test_helper'

class ContactTest < Minitest::Test
  def setup
    super
    @user = User.create!(email: 'contact_test@example.com', password: 'password')
    @assistant = Assistant.create!(name: 'ContactBot', user: @user)
  end

  def test_resolve_creates_new_contact
    contact = Contact.resolve(@assistant, 'whatsapp', '123456789',
                              { 'name' => 'New User', 'email' => 'new@example.com' })

    assert contact.persisted?
    assert_equal 'New User', contact.name
    assert_equal 'new@example.com', contact.profile_data['email']
    assert_equal 1, contact.identities.count
    assert_equal 'whatsapp', contact.identities.first.provider
    assert_equal '123456789', contact.identities.first.external_id
  end

  def test_resolve_returns_existing_contact
    # Create first
    original = Contact.resolve(@assistant, 'whatsapp', '987654321', { 'name' => 'Existing User' })

    # Resolve again
    resolved = Contact.resolve(@assistant, 'whatsapp', '987654321', { 'name' => 'Updated Name' })

    assert_equal original.id, resolved.id
    # It should NOT update name if already present (per implementation)
    resolved.reload
    assert_equal 'Existing User', resolved.name
  end

  def test_merge_contacts
    contact_a = Contact.resolve(@assistant, 'whatsapp', 'A111', { 'name' => 'Alice' })
    contact_b = Contact.resolve(@assistant, 'telegram', 'B222', { 'name' => '' })

    # Add some data to B
    Memory.create!(contact: contact_b, assistant: @assistant, content: 'Loves cats')
    # Channel needed for interaction
    channel_b = Channel.create!(assistant: @assistant, provider: 'telegram', provider_uid: 'B222', active: true)
    Interaction.create!(contact: contact_b, assistant: @assistant, channel: channel_b, direction: 'inbound',
                        content: 'Hi from Telegram')

    # Merge B into A
    contact_a.merge(contact_b)

    contact_a.reload

    # B should be gone
    assert_nil Contact.find_by(id: contact_b.id)

    # A should have B's identity
    assert_equal 2, contact_a.identities.count
    assert contact_a.identities.exists?(provider: 'telegram', external_id: 'B222')

    # A should have B's memory
    assert contact_a.memories.exists?(content: 'Loves cats')

    # A should have B's interaction
    assert contact_a.interactions.exists?(content: 'Hi from Telegram')
  end
end
