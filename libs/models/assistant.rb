class Assistant < ActiveRecord::Base
  belongs_to :user
  has_many :channels, dependent: :destroy
  has_many :contacts, dependent: :destroy
  has_many :interactions, dependent: :destroy

  validates :name, presence: true

  def notify_supervisor(content, metadata = {})
    # Find a channel that supports supervisor notifications (e.g., telegram)
    # or use a default one configured for the assistant.
    notification_channel = channels.find_by(provider: 'telegram', active: true)
    return false unless notification_channel

    client = Negromatic::Channels::Telegram.new(notification_channel)
    client.notify_supervisor(content, metadata)
  end

  def process_message(contact, channel, text)
    # 1. Fetch relevant memories
    global_context = Memory.search(text, assistant_id: id, limit: 3)
    contact_context = Memory.search(text, assistant_id: id, contact_id: contact.id, limit: 3)
    
    context = (global_context + contact_context).map(&:content).join("\n---\n")

    # 2. Build the prompt for Grok
    system_prompt = <<~TEXT
      #{identity}
      
      GLOBAL KNOWLEDGE:
      #{global_memory}
      
      RELEVANT CONTEXT FROM MEMORY:
      #{context}
      
      You are interacting with #{contact.name} via #{channel.provider}.
      Use your tools to reply or notify your supervisor if needed.
    TEXT

    # 3. Query Grok (using the AI module)
    # Note: AI.get_actions_advice needs to be adapted or a new method created
    # for generic chat with tools.
    # For now, let's assume a simpler version or just a direct reply.
    
    # ... (Integration with AI module for tool-calling) ...
  end
end
