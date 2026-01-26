class Strategy < ActiveRecord::Base
  belongs_to :user, optional: true
  has_many :positions, dependent: :nullify
  has_many :ai_actions, dependent: :destroy

  validates :name, presence: true
  validate :global_strategy_cannot_be_active

  before_save :ensure_single_active_strategy, if: :active_changed?
  after_save :reset_user_ai_history, if: :should_reset_history?

  private

  def global_strategy_cannot_be_active
    if user_id.nil? && active
      errors.add(:active, "Global strategies cannot be active. Please clone them first.")
    end
  end

  def ensure_single_active_strategy
    if active && user
      user.strategies.where.not(id: id).update_all(active: false)
    end
  end

  def should_reset_history?
    # Reset if this is the active strategy and content changed,
    # or if active status just changed to true.
    (active && user && saved_change_to_content?) || (saved_change_to_active? && active && user)
  end

  def reset_user_ai_history
    user.reset_ai_history! if user
  end
end
