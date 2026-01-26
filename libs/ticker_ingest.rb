require 'json'

module TickerIngest
  # Processes a `/api/ticker`-compatible payload (HTTP-facing).
  #
  # Returns a hash suitable for `json ...` in Sinatra:
  # - On success: { success: 1, status: 'trading'|'idle', actions: [...] }
  # - On failure: { error: '...' }
  def self.process!(data)
    asset_symbol = data['asset'].to_s
    return { error: 'Asset symbol is required' } if asset_symbol.blank?

    extension = Extension.find_by(uuid: data['extension'])
    return { error: 'Extension not found' } if extension.nil?

    asset = Asset.find_by(value: asset_symbol, ex_type: extension.ex_type)
    return { error: "Asset #{asset_symbol} not found for #{extension.ex_type}" } if asset.nil?

    process_for_extension_asset!(
      extension: extension,
      asset: asset,
      info: data['info'],
      positions: data['positions'],
      meta: data['meta']
    )
  rescue JSON::ParserError
    { error: 'Invalid JSON payload' }
  rescue => e
    { error: "Ticker ingest failed: #{e.message}" }
  end

  # Core ingest used internally (scheduler/API extensions).
  # This avoids re-resolving extension UUID and asset symbol, and keeps API runners slim.
  def self.process_for_extension_asset!(extension:, asset:, info:, positions:, meta: nil)
    extension.update(connected: true, updated_at: Time.now)

    ae = AssetsExtension.find_by(extension_id: extension.id, asset_id: asset.id)
    if ae.nil?
      return {
        error: "Asset #{asset.value} is not active for this extension. Please activate it in the Extension Assets section."
      }
    end

    ae.update(status: 'ready', last_activity_at: Time.now)

    info_hash = info.is_a?(Hash) ? info : {}
    positions_arr = Array(positions)

    # Record equity snapshot at most once every hour to be DB-friendly
    balance = info_hash['availableBalance'].to_f
    unrealized = positions_arr.sum { |p| p.dig('info', 'unrealizedPnl').to_f }
    EquitySnapshot.record_if_due(user: extension.user, balance: balance, unrealized: unrealized)

    # Positions telemetry safety:
    meta_hash = meta.is_a?(Hash) ? meta : {}
    positions_parsed = meta_hash.key?('positions_parsed') ? !!meta_hash['positions_parsed'] : true

    if positions_parsed
      active_sides = positions_arr.map { |p| p['side'].to_s.downcase }
      Position.close_missing_for_asset(extension: extension, asset: asset, active_sides: active_sides)
      positions_arr.each { |pos_data| Position.upsert_from_payload(extension: extension, pos_data: pos_data) }
    end

    maybe_refresh_ai_actions!(extension: extension, ae: ae, asset: asset, info: info_hash)
    snapshot_close_on_dispatch!(extension: extension, asset: asset)
    fail_stale_actions!(extension: extension, asset: asset)

    { success: 1, status: extension.status, actions: serialize_pending_actions(extension: extension, asset: asset) }
  end

  def self.maybe_refresh_ai_actions!(extension:, ae:, asset:, info:)
    ai_interval_cutoff = extension.user.ai_interval_minutes.to_i.minutes.ago
    return unless extension.status == 'trading'
    return unless ae.last_ai_check_at.nil? || ae.last_ai_check_at < ai_interval_cutoff

    strategy = extension.user.strategies.find_by(active: true)
    return if strategy.nil?

    extension.user.ai_actions.where(asset_id: asset.id, status: 'pending')
              .update_all(status: 'failed', info: { error: 'Superseded by new AI advice' })

    ae.update(last_ai_check_at: Time.now)

    new_actions = AI.get_actions_advice(ae, strategy, info)
    AiAction.log_actions(user: extension.user, asset: asset, strategy: strategy, actions: new_actions)
  end

  def self.snapshot_close_on_dispatch!(extension:, asset:)
    pending_actions = extension.user.ai_actions.where(asset_id: asset.id, status: 'pending').order(timestamp: :asc)

    pending_actions.each do |pa|
      next unless pa.action_type == 'CLOSE_MARKET_ORDER'

      info = pa.info.is_a?(Hash) ? pa.info : {}
      next if info['dispatched_at']
      dispatched_at = Time.now.utc.iso8601

      extension.user.positions.where(
        extension_id: extension.id,
        asset_id: asset.id,
        side: pa.side.to_s.downcase,
        status: %w(open stale)
      ).find_each do |pos|
        pos.close_from_ai_action!(
          action_id: pa.id,
          action_amount: pa.amount,
          dispatched_at: dispatched_at
        )
      end

      pa.update(info: info.merge('dispatched_at' => dispatched_at))
    end
  end

  def self.fail_stale_actions!(extension:, asset:)
    extension.user.ai_actions.where(asset_id: asset.id, status: 'pending').order(timestamp: :asc).find_each do |pa|
      pa.increment!(:retry_count)
      if pa.retry_count > 10
        pa.update(status: 'failed', info: { error: 'Action timed out: Max retries (10) reached without confirmation' })
      end
    end
  end

  def self.serialize_pending_actions(extension:, asset:)
    extension.user.ai_actions.where(asset_id: asset.id, status: 'pending').order(timestamp: :asc).map do |pa|
      {
        id: pa.id,
        type: pa.action_type,
        asset: asset.value,
        side: pa.side,
        amount: pa.amount.positive? ? pa.amount : nil
      }
    end
  end
end

