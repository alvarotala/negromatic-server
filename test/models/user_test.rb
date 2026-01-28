require_relative '../test_helper'

class UserTest < Minitest::Test
  def setup
    super
    # Clear because we test specific emails
    User.delete_all
  end

  def test_password_hashing
    user = User.new(email: 'auth_test@example.com')
    user.password = 'secret123'
    user.save!

    assert_instance_of BCrypt::Password, user.password
    assert user.password == 'secret123'
  end

  def test_authentication
    user = User.create!(email: 'login_test@example.com', password: 'password123')

    authenticated = User.authenticate('login_test@example.com', 'password123')
    assert_equal user.id, authenticated.id

    failed = User.authenticate('login_test@example.com', 'wrongpassword')
    assert_nil failed

    missing = User.authenticate('nobody@example.com', 'password123')
    assert_nil missing
  end

  def test_stats
    user = User.create!(email: 'stats_test@example.com', password: 'password')
    assistant = Assistant.create!(name: 'StatsBot', user: user)

    # Channel
    Channel.create!(assistant: assistant, provider: 'mock', provider_uid: '1', active: true)

    # Contact & Interaction
    contact = Contact.resolve(assistant, 'mock', '1', { name: 'User' })
    channel = Channel.first
    Interaction.create!(assistant: assistant, contact: contact, channel: channel, direction: 'inbound', content: 'Hi')

    stats = user.stats
    assert_equal 1, stats[:assistants_count]
    assert_equal 1, stats[:active_channels]
    assert_equal 1, stats[:total_contacts]
    assert_equal 1, stats[:total_interactions]
  end
end
