require_relative '../test_helper'

class ToolsExtendedTest < Minitest::Test
  def setup
    super
    @user = User.create!(email: 'tools_ext@example.com', password: 'password')
    @assistant = Assistant.create!(name: 'ToolExtBot', user: @user)
    @contact = Contact.resolve(@assistant, 'mock_provider', 'TOOL_USER', name: 'Tool User')
    @channel = Channel.create!(
      assistant: @assistant,
      provider: 'mock_provider',
      provider_uid: 'TOOL_CHANNEL',
      active: true
    )
  end

  def test_generate_image_tool
    tool = Negromatic::Tools::GenerateImage.new(@assistant, @contact, @channel)

    # We expect it to call AI.generate_image, which is mocked in test_helper
    res = tool.execute({ 'prompt' => 'A cute cat' })

    # Mock return is http://mock-image.url/gen.png
    assert_equal 'http://mock-image.url/gen.png', res
  end

  def test_notify_supervisor_tool
    tool = Negromatic::Tools::NotifySupervisor.new(@assistant, @contact, @channel)

    # Needs to capture side effect
    res = tool.execute({ 'content' => 'Problem here' })

    assert_match(/Notification sent/, res)

    # Verify mock provider received it
    notifications = Negromatic::Channels::MockProvider.supervisor_notifications
    assert(notifications.any? { |n| n.include?('Problem here') })
  end

  def test_schedule_task_tool
    tool = Negromatic::Tools::ScheduleTask.new(@assistant, @contact, @channel)

    run_at = (Time.now + 3600).iso8601
    payload = { 'message' => 'Future hello' }

    res = tool.execute({
                         'task_type' => 'follow_up',
                         'run_at' => run_at,
                         'payload' => payload
                       })

    assert_match(/Task scheduled/, res)

    task = ScheduledTask.last
    assert_equal 'follow_up', task.task_type
    assert_equal payload, task.payload
    assert_equal 'pending', task.status
  end
end
