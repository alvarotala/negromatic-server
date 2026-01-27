class Interaction < ActiveRecord::Base
  belongs_to :contact
  belongs_to :assistant
  belongs_to :channel

  validates :direction, inclusion: { in: %w[inbound outbound] }
  validates :content, presence: true
end
