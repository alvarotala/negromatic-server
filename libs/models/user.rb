# frozen_string_literal: true

require 'bcrypt'

class User < ActiveRecord::Base
  include BCrypt
  has_many :extensions, dependent: :destroy
  has_many :strategies, dependent: :destroy
  has_many :positions, dependent: :destroy
  has_many :equity_snapshots, dependent: :destroy
  has_many :ai_actions, dependent: :destroy

  def active_strategy
    strategies.find_by(active: true)
  end

  # Comprehensive trading statistics
  # Returns a hash with all key metrics for dashboard display
  def trading_stats
    # All closed positions (for reference)
    all_closed = positions.where(status: 'closed')

    # Stats-eligible positions (exclude manual archives)
    stats_positions = all_closed.where(close_reason: Position::STATS_ELIGIBLE_REASONS)
    complete_trades = all_closed.where(close_reason: Position::COMPLETE_TRADE_REASONS)
    partial_closes = all_closed.where(close_reason: 'ai_partial_close')

    # Total realized PnL from closed positions (complete trades + partials)
    # Partial closes have estimated profit based on % of position closed
    closed_realized = stats_positions.sum(:realized_pnl).to_f

    # Running realized PnL from open positions = delta from baseline
    # This captures fees, funding, and any exchange-side partial closes since position opened
    open_running_realized = positions.where(status: %w[open stale]).sum do |pos|
      pos.lifetime_realized_delta
    end

    # Total realized = closed + running from open positions
    total_realized = closed_realized + open_running_realized

    # Last 24h realized (only from closed positions with closed_at in range)
    pnl_24h = stats_positions.where('closed_at > ?', 24.hours.ago).sum(:realized_pnl).to_f

    # Trade counts - only complete trades for win rate calculation
    total_complete_trades = complete_trades.count
    winning_complete_trades = complete_trades.where('realized_pnl > 0').count
    losing_complete_trades = complete_trades.where('realized_pnl < 0').count

    # Win rate based on complete trades only (not partials)
    win_rate = if total_complete_trades.positive?
                 (winning_complete_trades.to_f / total_complete_trades * 100).round(2)
               else
                 0
               end

    # Partial close stats
    partial_close_count = partial_closes.count
    partial_close_profit = partial_closes.sum(:realized_pnl).to_f

    # Best and worst trade
    best_trade = stats_positions.order(realized_pnl: :desc).first
    worst_trade = stats_positions.order(realized_pnl: :asc).first

    # Average profit per complete trade
    avg_profit_per_trade = if total_complete_trades.positive?
                              (complete_trades.sum(:realized_pnl).to_f / total_complete_trades).round(2)
                            else
                              0
                            end

    {
      # Main dashboard stats
      total_realized_pnl: total_realized,
      pnl_24h: pnl_24h,
      total_trades: total_complete_trades,
      win_rate: win_rate,

      # Breakdown
      closed_realized_pnl: closed_realized,
      open_running_realized_pnl: open_running_realized,

      # Complete trade stats
      winning_trades: winning_complete_trades,
      losing_trades: losing_complete_trades,
      avg_profit_per_trade: avg_profit_per_trade,

      # Partial close stats (profit taking)
      partial_close_count: partial_close_count,
      partial_close_profit: partial_close_profit,

      # Extremes
      best_trade_pnl: best_trade&.realized_pnl.to_f,
      worst_trade_pnl: worst_trade&.realized_pnl.to_f
    }
  end

  def reset_ai_history!
    extensions.each do |extension|
      extension.assets_extensions.update_all(ai_history: [], last_ai_check_at: nil)
    end
  end

  # Hash password before saving if it has changed
  def password
    @password ||= Password.new(read_attribute(:password)) if read_attribute(:password).present?
  end

  def password=(new_password)
    @password = Password.create(new_password)
    write_attribute(:password, @password)
  end

  def self.authenticate(email, password)
    user = find_by(email: email)
    return user if user && user.password == password
    nil
  end
end
