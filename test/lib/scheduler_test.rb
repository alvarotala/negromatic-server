require_relative '../test_helper'

class SchedulerTest < Minitest::Test
  def setup
    super
    @user = User.create!(email: 'sched_test@example.com', password: 'password')
    @assistant = Assistant.create!(name: 'SchedBot', user: @user)

    @channel = Channel.create!(
      assistant: @assistant,
      provider: 'mock_provider',
      provider_uid: 'SCHED_123',
      active: true
    )
    @channel.reload
  end

  def test_process_social_post_task
    skip 'TaskProcessor implementation deferred'
    # task = ScheduledTask.create!(
    #   assistant: @assistant,
    #   task_type: 'social_post',
    #   run_at: 10.minutes.ago,
    #   payload: {
    #     'content' => 'Hello World!',
    #     'image_prompt' => 'A happy robot'
    #   },
    #   status: 'pending'
    # )

    # Negromatic::TaskProcessor.process(task)

    # task.reload
    # assert_equal 'completed', task.status
  end

  def test_process_follow_up_task
    contact = Contact.resolve(@assistant, 'mock', '9999', name: 'User2')
    task = ScheduledTask.create!(
      assistant: @assistant,
      task_type: 'follow_up',
      run_at: 5.minutes.ago,
      payload: {
        'contact_id' => contact.id,
        'message' => 'Just checking in!'
      },
      status: 'pending'
    )

    # task.reload
    # assert_equal 'completed', task.status
    skip 'TaskProcessor implementation deferred'
  end
end
