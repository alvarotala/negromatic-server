class AiAction < ActiveRecord::Base
  belongs_to :user
  belongs_to :asset
  belongs_to :strategy

  validates :user_id, :asset_id, :strategy_id, :action_type, :side, :amount, presence: true

  def self.log_actions(user:, asset:, strategy:, actions:)
    return if actions.blank?

    actions.each do |action|
      next unless action.is_a?(Hash)
      next if action['type'].blank? || action['side'].blank?

      user.ai_actions.create(
        asset_id: asset.id,
        strategy_id: strategy.id,
        action_type: action['type'],
        side: action['side'],
        amount: action['amount'].to_f,
        status: 'pending',
        timestamp: Time.now
      )
    end
  end
end
