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
      Negromatic::Tools::ManageContact
    ]
  end



  # Main processing loop
  def process_message(contact, channel, text)
    # 1. Fetch relevant memories
    # TODO: Phase 2 - Use Vector Search
    contact_context = Memory.search(text, assistant_id: id, contact_id: contact.id, limit: 10)

    context_str = contact_context.map(&:content).join("\n---\n")

    log("Context (Memories): #{contact_context.count} Contact specific", level: :debug)
    log(context_str, level: :debug) if context_str.present?

    # 2. Build History (Last 20 interactions)
    recent_interactions = interactions.where(contact_id: contact.id)
                                      .order(timestamp: :desc)
                                      .limit(20)
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

      CONTACT CONTEXT:
      Name: #{contact.name}
      Bio/Notes: #{contact.memory}
      Profile: #{contact.profile_data.to_json}

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
    response = AI.chat(messages, tools: Assistant.available_tools.map(&:definition))

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

    if response[:content] && !response[:content].empty?
      send_reply(contact, channel, response[:content])
    end
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
      result = tool_instance.execute(args)
      log("TOOL RESULT: #{name} #{result}", level: :debug)
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
