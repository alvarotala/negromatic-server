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
end
