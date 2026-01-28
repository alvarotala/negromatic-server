class Assistant < ActiveRecord::Base
  belongs_to :user
  has_many :channels, dependent: :destroy
  has_many :contacts, dependent: :destroy
  has_many :interactions, dependent: :destroy
  has_many :memories, dependent: :destroy

  validates :name, presence: true

  # AVAILABLE TOOLS DEFINITION
  TOOLS = [
    {
      type: 'function',
      function: {
        name: 'notify_supervisor',
        description: 'Escalate a situation or report to the human supervisor. Use this when you are unsure, blocked, or need approval.',
        parameters: {
          type: 'object',
          properties: {
            content: { type: 'string', description: 'The message for the supervisor' }
          },
          required: ['content']
        }
      }
    },
    {
      type: 'function',
      function: {
        name: 'schedule_task',
        description: 'Schedule a future task (e.g. follow up, post to social media).',
        parameters: {
          type: 'object',
          properties: {
            task_type: { type: 'string', enum: %w[follow_up social_post] },
            payload: { type: 'object', description: 'Data required for the task (e.g., {"message": "..."})' },
            run_at: { type: 'string', description: 'ISO8601 timestamp for when to run the task' }
          },
          required: %w[task_type run_at]
        }
      }
    },
    {
      type: 'function',
      function: {
        name: 'generate_image',
        description: 'Generate an image. Returns the image URL.',
        parameters: {
          type: 'object',
          properties: {
            prompt: { type: 'string' }
          },
          required: ['prompt']
        }
      }
    }
  ].freeze

  def notify_supervisor(content, metadata = {})
    # Find a channel that supports supervisor notifications (e.g., telegram)
    notification_channel = channels.find_by(provider: 'telegram', active: true)

    # Fallback to any active channel if no telegram
    notification_channel ||= channels.where(active: true).first

    return false unless notification_channel

    # Ideally we should have a SupervisorChannel abstraction, but for now reusing the notification method
    # In a real scenario, this sends a message to the supervisor's ID, not the contact's.
    # Assuming the channel implementation knows how to route 'notify_supervisor'.

    # For now, let's just log it if we can't find a dedicated supervisor channel logic
    log("SUPERVISOR NOTIFICATION: #{content}", level: :warn)

    return unless notification_channel

    begin
      # Some channels might support direct supervisor notification
      client = "Negromatic::Channels::#{notification_channel.provider.camelize}".constantize.new(notification_channel)
      if client.respond_to?(:notify_supervisor)
        client.notify_supervisor(content, metadata)
      else
        # Fallback
        false
      end
    rescue StandardError => e
      log("Failed to notify supervisor: #{e.message}", level: :error)
      false
    end
  end

  # Main processing loop
  def process_message(contact, channel, text)
    # 1. Fetch relevant memories
    # TODO: Phase 2 - Use Vector Search
    contact_context = Memory.search(text, assistant_id: id, contact_id: contact.id, limit: 5)

    context_str = contact_context.map(&:content).join("\n---\n")

    log("Context (Memories): #{contact_context.count} Contact specific", level: :debug)
    log(context_str, level: :debug) if context_str.present?

    # 2. Build History (Last 5 interactions)
    recent_interactions = interactions.where(contact_id: contact.id)
                                      .order(timestamp: :desc)
                                      .limit(5)
                                      .reverse

    history_msgs = recent_interactions.map do |i|
      role = i.direction == 'inbound' ? 'user' : 'assistant'
      { role: role, content: i.content }
    end

    # 3. Build System Prompt
    system_prompt = <<~TEXT
      IDENTITY:
      #{identity}

      GLOBAL KNOWLEDGE:
      #{global_memory}

      RELEVANT MEMORIES:
      #{context_str}

      INSTRUCTIONS:
      - You are communicating with #{contact.name} via #{channel.provider}.
      - Act fully as your persona.
      - Use tools only if helpful.
      - If you need to send a message, just output the text content.
      - If you use a tool, do not output text content unless necessary.
    TEXT

    log("System Prompt:\n#{system_prompt}", level: :debug)

    messages = [{ role: 'system', content: system_prompt }]
    messages.concat(history_msgs)
    messages << { role: 'user', content: text }

    # 4. Call AI
    response = AI.chat(messages, tools: TOOLS)

    # 5. Handle Response
    if response[:tool_calls]
      response[:tool_calls].each do |tool_call|
        handle_tool_call(tool_call, contact, channel)
      end
      # NOTE: We might want to loop back to AI with tool results,
      # but for this MVP 1-turn tool usage is often enough or we end conversation here.
      # For now, we don't send a text reply if tools were used,
      # unless the AI also returned content (which is possible).
    end

    return unless response[:content] && !response[:content].empty?

    send_reply(contact, channel, response[:content])
  end

  private

  def handle_tool_call(tool_call, contact, channel)
    name = tool_call.dig('function', 'name')
    args = JSON.parse(tool_call.dig('function', 'arguments') || '{}')

    log("TOOL CALL: #{name} with #{args}", level: :info, color: :blue)
    log(args, level: :debug) # Log full args structure

    case name
    when 'notify_supervisor'
      notify_supervisor(args['content'])
      send_reply(contact, channel, '_[Sends a notification to supervisor]_') # Optional feedback to user? Or keep silent.
    when 'schedule_task'
      ScheduledTask.create!(
        assistant_id: id,
        task_type: args['task_type'],
        payload: args['payload'],
        run_at: args['run_at'],
        status: 'pending'
      )
      send_reply(contact, channel, '_[Task scheduled]_')
    when 'generate_image'
      url = AI.generate_image(args['prompt'])
      if url
        send_reply(contact, channel, url) # Send the image URL (channel should handle it)
      else
        send_reply(contact, channel, 'I tried to generate an image but failed.')
      end
    else
      log("Unknown tool: #{name}", level: :error)
    end
  end

  def send_reply(contact, channel, text)
    # Using the Channel implementation to send the message
    klass = "Negromatic::Channels::#{channel.provider.camelize}".constantize
    client = klass.new(channel)
    client.send_message(contact, text)
  end

  def log(msg, level: :info, color: :white)
    prefix = "[Assistant:#{id}]"
    # If msg is rich (hash/array), we let AppLogger handle formatting, just prepending our prefix string if it's simple
    if msg.is_a?(String)
      AppLogger.log("#{prefix} #{msg}", level: level, color: color)
    else
      AppLogger.log(msg, level: level, color: color)
    end
  end
end
