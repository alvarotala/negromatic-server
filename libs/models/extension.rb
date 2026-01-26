class Extension < ActiveRecord::Base
  belongs_to :user
  has_many :positions, dependent: :destroy
  has_many :assets_extensions, dependent: :destroy
  has_many :assets, through: :assets_extensions

  validates :uuid, presence: true
  validates :user_id, presence: true
  validates :status, inclusion: { in: %w(trading idle) }, allow_nil: true
end
