class EquitySnapshot < ActiveRecord::Base
  belongs_to :user

  validates :user_id, :total_balance, :unrealized_pnl, :equity, presence: true

  def self.latest_for(user)
    user.equity_snapshots.order(timestamp: :desc).limit(1).pick(:timestamp)
  end

  def self.record_if_due(user:, balance:, unrealized:, interval: 1.hour)
    last_snapshot = latest_for(user)
    return if last_snapshot && last_snapshot > interval.ago

    user.equity_snapshots.create(
      total_balance: balance,
      unrealized_pnl: unrealized,
      equity: balance + unrealized,
      timestamp: Time.now
    )
  end
end
