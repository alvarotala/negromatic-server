class Asset < ActiveRecord::Base
  has_many :assets_extensions, dependent: :destroy
  has_many :extensions, through: :assets_extensions
  has_many :positions, dependent: :destroy
  validates :value, uniqueness: { scope: :ex_type, message: "and ex_type combination must be unique" }
end
