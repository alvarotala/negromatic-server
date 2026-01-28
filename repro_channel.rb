ENV['APP_ENV'] = 'test'
require_relative 'app'
require 'rack/test'
require 'minitest/autorun'

class ChannelRouteTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    User.destroy_all
    @user = User.create(email: 'test@example.com', password: 'password')
    @assistant = @user.assistants.create!(name: 'TestAssistant')
  end

  def test_create_channel_cli_empty_config
    # Login
    post '/login', { email: 'test@example.com', password: 'password' }
    
    # Create Channel
    post "/assistants/#{@assistant.id}/channels", {
      provider: 'cli',
      provider_uid: 'cli-test-uid',
      config_json: '', # Empty config
      active: 'true'
    }

    assert last_response.redirect?, "Should redirect on success"
    follow_redirect!
    assert_match /Channel added successfully/, last_response.body
    
    channel = @assistant.channels.last
    assert_equal 'cli', channel.provider
    assert_equal 'cli-test-uid', channel.provider_uid
    assert_equal({}, channel.config)
  end

  def test_create_channel_invalid_json
    # Login
    post '/login', { email: 'test@example.com', password: 'password' }
    
    # Create Channel
    post "/assistants/#{@assistant.id}/channels", {
      provider: 'cli',
      provider_uid: 'cli-test-uid-2',
      config_json: '{ invalid json }', 
      active: 'true'
    }

    assert_match /Invalid JSON/, last_response.body
    
    # Should render the form again
    assert_match /Add Channel/, last_response.body
    assert_equal 200, last_response.status
  end
end
