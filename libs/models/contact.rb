class Contact < ActiveRecord::Base
  belongs_to :assistant
  has_many :interactions, dependent: :destroy

  validates :external_id, presence: true
  validates :external_id, uniqueness: { scope: :assistant_id }
end
