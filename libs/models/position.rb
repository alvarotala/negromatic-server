# frozen_string_literal: true

class Position < ActiveRecord::Base
  belongs_to :user
  belongs_to :asset
  belongs_to :extension
  belongs_to :strategy

  before_validation :set_realized_defaults, on: :create

  validates :uuid, presence: true, uniqueness: true
  validates :amount, :side, :status, :user_id, :asset_id, :extension_id, presence: true
  validates :status, inclusion: { in: %w(open stale closed) }
  validates :realized_pnl, :realized_pnl_percentage, presence: true, if: -> { status == 'closed' }

  # Close reasons for stats categorization
  CLOSE_REASONS = {
    telemetry_gone: 'telemetry_gone',       # Position disappeared from exchange (auto-detected)
    ai_full_close: 'ai_full_close',         # AI issued 100% close
    ai_partial_close: 'ai_partial_close',   # AI issued partial close (profit taking)
    stale_confirmed: 'stale_confirmed',     # Human confirmed stale is closed
    manual_archive: 'manual_archive'        # Human archived (bookkeeping only)
  }.freeze

  # Reasons that count as "complete trades" for win rate
  COMPLETE_TRADE_REASONS = %w[telemetry_gone ai_full_close stale_confirmed].freeze

  # Reasons that count for realized PnL stats
  STATS_ELIGIBLE_REASONS = %w[telemetry_gone ai_full_close ai_partial_close stale_confirmed].freeze

  def unrealized_pnl
    (info || {})['unrealizedPnl'].to_f
  end

  def unrealized_pnl_percentage
    (info || {})['unrealizedPnlPercentage'].to_f
  end

  # Returns running realized PnL from open position (fees, funding, partial closes on exchange)
  def running_realized_pnl
    (info || {})['realizedPnl'].to_f
  end

  # Returns the baseline realizedPnl when this position record was created
  # Used to calculate delta/profit for this position's lifetime
  def baseline_realized_pnl
    (info || {})['baselineRealizedPnl'].to_f
  end

  # Returns the profit generated during THIS position record's lifetime
  # = current realizedPnl - baseline (what we started with)
  def lifetime_realized_delta
    running_realized_pnl - baseline_realized_pnl
  end

  # Check if this position counts as a complete trade for win rate
  def complete_trade?
    COMPLETE_TRADE_REASONS.include?(close_reason.to_s)
  end

  # Check if this position counts for stats (not manual archive)
  def stats_eligible?
    STATS_ELIGIBLE_REASONS.include?(close_reason.to_s)
  end

  # Closes the position when it disappears from telemetry (auto-detected full close)
  # This is a complete trade - the position is fully closed on the exchange
  def close_from_telemetry!
    payload = (info || {}).dup
    baseline = payload['baselineRealizedPnl'].to_f
    
    payload['closeAudit'] = {
      'reason' => 'telemetry_gone',
      'closedAt' => Time.now.utc.iso8601,
      'note' => 'Position no longer reported by exchange telemetry',
      'baselineRealizedPnl' => baseline
    }

    # Total profit for THIS position record = unrealized + (realized delta since baseline)
    # This correctly handles positions that were "reopened" after a partial close
    realized_now = payload['unrealizedPnl'].to_f
    realized_delta = payload['realizedPnl'].to_f - baseline
    total_pnl = realized_now + realized_delta

    attrs = build_close_attrs(
      payload: payload,
      close_reason: 'telemetry_gone',
      realized_pnl: total_pnl
    )

    update(attrs)
  end

  # Closes the position due to an AI CLOSE_MARKET_ORDER action
  # partial: true if AI specified an amount (profit taking), false for 100% close
  #
  # IMPORTANT: On Binance Futures, partial closes work like this:
  # 1. The OLD position is completely closed on the exchange
  # 2. A NEW position opens with the remaining size
  # 3. The new position has FRESH realizedPnl (doesn't carry history)
  #
  # So we MUST estimate the profit from the partial at dispatch time.
  def close_from_ai_action!(action_id:, action_amount: nil, dispatched_at: nil)
    payload = (info || {}).dup
    position_amount = self.amount.to_f
    close_amount = action_amount.to_f
    is_partial = close_amount > 0 && close_amount < position_amount
    
    current_unrealized = payload['unrealizedPnl'].to_f
    current_realized = payload['realizedPnl'].to_f
    baseline = payload['baselineRealizedPnl'].to_f

    if is_partial
      # PARTIAL CLOSE: Estimate profit based on the portion being closed
      # On Binance Futures, the old position closes and a new one opens with remaining size.
      # The new position won't have the realizedPnl history, so we must capture now.
      #
      # Estimated profit = (unrealized PnL) * (close_amount / position_amount)
      # Plus the proportional share of realized delta (fees, funding)
      close_ratio = close_amount / position_amount
      estimated_unrealized_portion = current_unrealized * close_ratio
      realized_delta = current_realized - baseline
      estimated_realized_portion = realized_delta * close_ratio
      
      total_pnl = estimated_unrealized_portion + estimated_realized_portion
      
      payload['closeAudit'] = {
        'reason' => 'ai_partial_close',
        'closedAt' => Time.now.utc.iso8601,
        'actionId' => action_id,
        'actionAmount' => close_amount,
        'positionAmount' => position_amount,
        'closeRatio' => close_ratio.round(4),
        'dispatchedAt' => dispatched_at,
        'note' => "AI partial close #{(close_ratio * 100).round(1)}% (estimated profit)",
        'calculation' => {
          'unrealizedPnl' => current_unrealized,
          'realizedPnl' => current_realized,
          'baselineRealizedPnl' => baseline,
          'estimatedUnrealizedPortion' => estimated_unrealized_portion.round(4),
          'estimatedRealizedPortion' => estimated_realized_portion.round(4),
          'totalEstimatedPnl' => total_pnl.round(4)
        }
      }
    else
      # FULL CLOSE (100%): Capture everything
      realized_delta = current_realized - baseline
      total_pnl = current_unrealized + realized_delta
      
      payload['closeAudit'] = {
        'reason' => 'ai_full_close',
        'closedAt' => Time.now.utc.iso8601,
        'actionId' => action_id,
        'actionAmount' => close_amount,
        'dispatchedAt' => dispatched_at,
        'note' => 'AI full close (100%)',
        'calculation' => {
          'unrealizedPnl' => current_unrealized,
          'realizedPnl' => current_realized,
          'baselineRealizedPnl' => baseline,
          'realizedDelta' => realized_delta.round(4),
          'totalPnl' => total_pnl.round(4)
        }
      }
    end

    attrs = build_close_attrs(
      payload: payload,
      close_reason: is_partial ? 'ai_partial_close' : 'ai_full_close',
      realized_pnl: total_pnl
    )

    update(attrs)
  end

  # Human confirms a stale position is closed on the exchange
  def close_from_stale_confirmation!
    payload = (info || {}).dup
    baseline = payload['baselineRealizedPnl'].to_f
    
    payload['closeAudit'] = {
      'reason' => 'stale_confirmed',
      'closedAt' => Time.now.utc.iso8601,
      'note' => 'Human confirmed position is closed on exchange',
      'baselineRealizedPnl' => baseline
    }

    # Use the last known snapshot - profit = unrealized + delta realized
    realized_now = payload['unrealizedPnl'].to_f
    realized_delta = payload['realizedPnl'].to_f - baseline
    total_pnl = realized_now + realized_delta

    attrs = build_close_attrs(
      payload: payload,
      close_reason: 'stale_confirmed',
      realized_pnl: total_pnl
    )

    update(attrs)
  end

  # Human manually archives a position (bookkeeping, doesn't affect stats)
  def archive_manually!
    payload = (info || {}).dup
    payload['closeAudit'] = {
      'reason' => 'manual_archive',
      'closedAt' => Time.now.utc.iso8601,
      'note' => 'Manually archived by user (bookkeeping only, not counted in stats)'
    }

    attrs = {
      status: 'closed',
      closed_at: Time.now,
      info: payload,
      close_reason: 'manual_archive',
      # Don't set realized_pnl for manual archives - keeps stats clean
      realized_pnl: 0,
      realized_pnl_percentage: 0
    }

    update(attrs)
  end

  def mark_stale!(reason: nil)
    payload = (info || {}).dup
    payload['staleReason'] = reason.to_s if reason
    payload['staleAt'] = Time.now.utc.iso8601

    update(status: 'stale', info: payload)
  end

  def reopen!
    attrs = {
      status: 'open',
      closed_at: nil,
      close_reason: nil,
      last_activity_at: Time.now,
      realized_pnl: 0,
      realized_pnl_percentage: 0
    }

    # Clear close audit and reset baseline for fresh profit tracking
    if info.is_a?(Hash)
      new_info = info.dup
      new_info.delete('closeAudit')
      new_info.delete('staleReason')
      new_info.delete('staleAt')
      # Reset baseline to current realizedPnl for fresh profit tracking
      new_info['baselineRealizedPnl'] = new_info['realizedPnl'].to_f
      new_info['positionCreatedAt'] = Time.now.utc.iso8601
      attrs[:info] = new_info
    end

    update(attrs)
  end

  # Close positions that are no longer reported by telemetry
  def self.close_missing_for_asset(extension:, asset:, active_sides:)
    where(extension_id: extension.id, asset_id: asset.id, status: %w(open stale)).find_each do |pos|
      next if active_sides.include?(pos.side)
      pos.close_from_telemetry!
    end
  end

  # Create or update position from telemetry payload
  def self.upsert_from_payload(extension:, pos_data:)
    pos_asset = Asset.find_by(value: pos_data['asset'], ex_type: extension.ex_type)
    return unless pos_asset

    position = where(
      user_id: extension.user_id,
      extension_id: extension.id,
      asset_id: pos_asset.id,
      side: pos_data['side'].to_s.downcase,
      status: %w(open stale)
    ).first_or_initialize(status: 'open')

    is_new_record = position.new_record?
    
    position.strategy_id ||= extension.user.active_strategy&.id
    position.uuid ||= SecureRandom.uuid
    position.status = 'open'
    position.amount = pos_data['amount']
    position.last_activity_at = Time.now
    
    # Build info hash, preserving baseline for existing records
    new_info = (pos_data['info'] || {}).dup
    
    if is_new_record
      # NEW position: set baseline to current realizedPnl
      # This is the starting point for profit calculation
      new_info['baselineRealizedPnl'] = new_info['realizedPnl'].to_f
      new_info['positionCreatedAt'] = Time.now.utc.iso8601
    else
      # EXISTING position: preserve the original baseline
      old_info = position.info || {}
      new_info['baselineRealizedPnl'] = old_info['baselineRealizedPnl'] || old_info['realizedPnl'].to_f
      new_info['positionCreatedAt'] = old_info['positionCreatedAt']
    end
    
    position.info = new_info
    position.save
  end

  private

  def build_close_attrs(payload:, close_reason:, realized_pnl:)
    margin = payload['margin'].to_f
    pnl_pct = if margin > 0
                (realized_pnl / margin * 100).round(2)
              else
                payload['unrealizedPnlPercentage'].to_f
              end

    {
      status: 'closed',
      closed_at: Time.now,
      info: payload,
      close_reason: close_reason,
      realized_pnl: realized_pnl,
      realized_pnl_percentage: pnl_pct
    }
  end

  def set_realized_defaults
    self.realized_pnl = 0 if realized_pnl.nil?
    self.realized_pnl_percentage = 0 if realized_pnl_percentage.nil?
  end
end
