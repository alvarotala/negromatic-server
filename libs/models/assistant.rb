class Assistant < ActiveRecord::Base
  belongs_to :user
  has_many :channels, dependent: :destroy
  has_many :contacts, dependent: :destroy
  has_many :interactions, dependent: :destroy
  has_many :memories, dependent: :destroy

  validates :name, presence: true

  # AVAILABLE TOOLS DEFINITION
  # Dynamically load tools
  def self.available_tools
    [
      Negromatic::Tools::NotifySupervisor,
      Negromatic::Tools::ScheduleTask,
      Negromatic::Tools::GenerateImage,
      Negromatic::Tools::ManageContact,
      Negromatic::Tools::ContactMemory,
      Negromatic::Tools::GlobalMemory
    ]
  end

  # Main processing loop
  def process_message(contact, channel, text)
    # 0. Save inbound interaction
    interactions.create!(
      contact: contact,
      channel: channel,
      direction: 'inbound',
      content: text
    )

    # 1. Fetch recent memories (Global + Contact Specific)
    global_memories = memories.where(contact_id: nil).limit(10).order(id: :desc)
    contact_memories = memories.where(contact_id: contact.id).limit(10).order(id: :desc)

    global_memories_str = global_memories.map(&:content).join("\n---\n") || 'No global memories'
    contact_memories_str = contact_memories.map(&:content).join("\n---\n") || 'No contact memories'

    log("Global (Memories):\r\n#{global_memories_str}\r\n\r\n", level: :debug, color: :cyan)
    log("Contact (Memories):\r\n#{contact_memories_str}\r\n\r\n", level: :debug, color: :magenta)

    # 2. Build History (Last 20 interactions)
    recent_interactions = interactions.where(contact_id: contact.id)
                                      .order(timestamp: :desc)
                                      .limit(20)
                                      .reverse

    history_msgs = recent_interactions.map do |i|
      { role: i.direction == 'inbound' ? 'user' : 'assistant', content: i.content }
    end

    # 3. Build System Prompt
    system_prompt = <<~TEXT
      IDENTITY:
      #{identity}

      GLOBAL KNOWLEDGE:
      #{global_memories_str}

      CONTACT CONTEXT:
      Name: #{contact.name}
      Profile: #{contact.profile_data.to_json}
      Provider: #{channel.provider}
      External ID: #{contact.external_id}

      CONTACT MEMORIES:
      #{contact_memories_str}

      INSTRUCTIONS:
      - You are communicating with #{contact.name}.
      - Act fully as your persona.
      - Use tools only if helpful.
      - If you need to send a message, just output the text content.
      - If you use a tool, do not output text content unless necessary.
    TEXT

    log("System Prompt:\n#{system_prompt}", level: :debug)

    messages = [{ role: 'system', content: system_prompt }]

    # 3. Add History
    messages.concat(history_msgs)

    log("History count: #{history_msgs.count}", level: :debug, color: :yellow)

    messages << { role: 'user', content: text }

    # 4. Call AI
    response = AI.chat(messages, tools: Assistant.available_tools.map(&:definition))

    interactions.create!(
      contact: contact,
      channel: channel,
      direction: 'inbound',
      content: text
    )

    # 5. Handle Response
    if response[:tool_calls]
      tool_calls_results = []
      response[:tool_calls].each do |tool_call|
        tool_calls_results << handle_tool_call(tool_call, contact, channel)
      end

      log("Tool calls results: #{tool_calls_results}", level: :debug, color: :yellow) if tool_calls_results.any?

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

    # Find the tool class
    tool_class = Assistant.available_tools.find { |t| t.definition.dig(:function, :name) == name }

    if tool_class
      tool_instance = tool_class.new(self, contact, channel)
      return tool_instance.execute(args)
    end

    { error: "Unknown tool: #{name}" }
  rescue StandardError => e
    log("TOOL ERROR: #{e.message}\n\n", level: :error, color: :red)
    log(e.backtrace, level: :error)

    { error: e.message }
  end

  def send_reply(contact, channel, text)
    # Save outbound interaction
    interactions.create!(
      contact: contact,
      channel: channel,
      direction: 'outbound',
      content: text
    )

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
