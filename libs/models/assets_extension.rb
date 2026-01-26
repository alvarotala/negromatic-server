class AssetsExtension < ActiveRecord::Base
  belongs_to :extension
  belongs_to :asset

  def positions
    Position.where(extension_id: self.extension_id, asset_id: self.asset_id)
  end

  def open_positions
    positions.where(status: 'open')
  end

  validates :extension_id, uniqueness: { scope: :asset_id }
end
