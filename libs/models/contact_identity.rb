class ContactIdentity < ActiveRecord::Base
  belongs_to :contact
  belongs_to :assistant
  
  validates :provider, presence: true
  validates :external_id, presence: true
  validates :external_id, uniqueness: { scope: [:assistant_id, :provider] }
end
