class Channel < ActiveRecord::Base
  belongs_to :assistant
  has_many :interactions, dependent: :destroy

  validates :provider, presence: true
  validates :provider_uid, presence: true
  validates :provider, uniqueness: { scope: :assistant_id }

  def self.providers
    ['whatsapp', 'telegram', 'instagram', 'cli']
  end
end
