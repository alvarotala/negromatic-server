require 'http'
require 'openssl'
require 'json'
require_relative '../ticker_ingest'

module BinxApi
  class Error < StandardError; end

  DEFAULT_LEVERAGE = 20
  DEFAULT_MARGIN_MODE = 'CROSSED' # ISOLATED or CROSSED
  DEFAULT_HEDGE_MODE = true # true for Hedge Mode, false for One-way Mode

  # Minimal BingX Swap client (REST) for:
  # - Quote price (public)
  # - Balance / positions (signed)
  # - Market orders (signed)
  # - Account/Trade settings (signed)
  #
  # Credentials:
  # - `BINX_API_KEY` supports either:
  #   - "apiKey:secretKey" (recommended)
  #   - "apiKey" (public endpoints only)
  class Client
    ROOT_URL = 'https://open-api.bingx.com'

    def self.from_env!
      raw = ENV['BINX_API_KEY'].to_s.strip
      raise Error, 'BINX_API_KEY is missing' if raw.empty?

      api_key, secret_key =
        if raw.include?(':')
          raw.split(':', 2).map(&:strip)
        else
          [raw, ENV['BINX_API_SECRET'].to_s.strip]
        end

      secret_key = nil if secret_key.to_s.strip.empty?
      new(api_key:, secret_key:)
    end

    def initialize(api_key:, secret_key: nil)
      @api_key = api_key
      @secret_key = secret_key
    end

    def quote_price(symbol)
      res = get('/openApi/swap/v2/quote/price', params: { symbol: symbol }, signed: false)
      res.fetch('data').fetch('price').to_f
    end

    def perpetual_balance
      signed_get('/openApi/swap/v2/user/balance', params: { timestamp: timestamp_ms, recvWindow: '10000' })
    end

    def perpetual_positions
      signed_get('/openApi/swap/v2/user/positions', params: { timestamp: timestamp_ms, recvWindow: '10000' })
    end

    def set_leverage(symbol:, side:, leverage:)
      # side: LONG or SHORT
      signed_post('/openApi/swap/v2/trade/leverage', params: {
        symbol: symbol,
        side: side.to_s.upcase,
        leverage: leverage.to_i,
        timestamp: timestamp_ms
      })
    end

    def set_margin_mode(symbol:, margin_type:)
      # margin_type: ISOLATED or CROSSED
      signed_post('/openApi/swap/v2/trade/marginType', params: {
        symbol: symbol,
        marginType: margin_type.to_s.upcase,
        timestamp: timestamp_ms
      })
    end

    def set_position_mode(hedge: true)
      # dualSidePosition: true (Hedge Mode), false (One-way Mode)
      signed_post('/openApi/swap/v2/trade/positionMode', params: {
        dualSidePosition: hedge.to_s,
        timestamp: timestamp_ms
      })
    end

    def ensure_trade_settings!(symbol:)
      # Defaulting to user's request: 20X, Cross, Hedge
      set_position_mode(hedge: DEFAULT_HEDGE_MODE) rescue nil
      set_margin_mode(symbol: symbol, margin_type: DEFAULT_MARGIN_MODE) rescue nil
      set_leverage(symbol: symbol, side: 'LONG', leverage: DEFAULT_LEVERAGE) rescue nil
      set_leverage(symbol: symbol, side: 'SHORT', leverage: DEFAULT_LEVERAGE) rescue nil
    end

    def open_market_order(symbol:, position_side:, quantity:, client_order_id: nil)
      side = position_side.to_s.upcase == 'LONG' ? 'BUY' : 'SELL'
      place_market_order(symbol:, side:, position_side:, quantity:, client_order_id:)
    end

    def close_market_order(symbol:, position_side:, quantity:, client_order_id: nil)
      side = position_side.to_s.upcase == 'LONG' ? 'SELL' : 'BUY'
      place_market_order(symbol:, side:, position_side:, quantity:, client_order_id:)
    end

    private

    def place_market_order(symbol:, side:, position_side:, quantity:, client_order_id:)
      params = {
        symbol: symbol,
        type: 'MARKET',
        side: side,
        positionSide: position_side.to_s.upcase,
        quantity: quantity.to_f,
        timestamp: timestamp_ms,
        recvWindow: '10000'
      }
      params[:clientOrderID] = client_order_id if client_order_id

      signed_post('/openApi/swap/v2/trade/order', params:)
    end

    def signed_get(path, params:)
      ensure_secret!
      get(path, params:, signed: true)
    end

    def signed_post(path, params:)
      ensure_secret!
      post(path, params:, signed: true)
    end

    def ensure_secret!
      return unless @secret_key.to_s.strip.empty?
      raise Error, 'BINX_API_KEY secret is missing (use "apiKey:secretKey" or set BINX_API_SECRET)'
    end

    def headers
      {
        'User-Agent' => 'tradero-binx-api',
        'X-BX-APIKEY' => @api_key
      }
    end

    def timestamp_ms
      (Time.now.to_f * 1000).to_i
    end

    def get(path, params:, signed:)
      qs = build_query(params)
      qs = sign_query(qs) if signed

      url = ROOT_URL + path
      url += "?#{qs}" unless qs.empty?

      resp = HTTP.headers(headers).get(url)
      parse_response(resp)
    end

    def post(path, params:, signed:)
      qs = build_query(params)
      qs = sign_query(qs) if signed

      resp = HTTP.headers(headers.merge('Content-Type' => 'application/x-www-form-urlencoded'))
                 .post(ROOT_URL + path, body: qs)
      parse_response(resp)
    end

    # BingX signature (swap): HMAC-SHA256 hex digest of the query string.
    def sign_query(qs)
      sig = OpenSSL::HMAC.hexdigest('SHA256', @secret_key, qs)
      qs.empty? ? "signature=#{sig}" : "#{qs}&signature=#{sig}"
    end

    def build_query(params)
      # BingX signing expects the raw query string (no URL escaping),
      # matching the reference implementations in their ecosystem.
      params
        .compact
        .reject { |_k, v| v.to_s == 'NULL' }
        .map { |k, v| "#{k}=#{v}" }
        .join('&')
    end

    def parse_response(resp)
      data = JSON.parse(resp.to_s) rescue nil
      raise Error, "Non-JSON response (HTTP #{resp.code})" if data.nil?

      # BingX commonly uses { code: 0, msg: "...", data: ... }
      if data.is_a?(Hash) && data.key?('code') && data['code'].to_i != 0
        raise Error, "BingX error #{data['code']}: #{data['msg']}"
      end

      data
    end
  end

  module Telemetry
    module_function

    # Normalizes BingX `/openApi/swap/v2/user/balance` into the keys
    # expected by our AI prompt and UI:
    # - availableBalance, equity, accountBalance, unrealizedPnl, availableMargin, positionMargin
    #
    # Ref shape (from community SDKs):
    # { "data": { "balance": { balance, equity, unrealizedProfit, availableMargin, usedMargin, ... } } }
    def extract_account_info(balance_json)
      data = (balance_json || {})['data'] rescue nil
      data ||= (balance_json || {})[:data] rescue nil
      return {} unless data

      b = if data.is_a?(Hash)
            data['balance'] || data[:balance]
          end

      # Some variants may return an array of balances; pick USDT if present.
      if b.is_a?(Array)
        b = b.find { |x| x.is_a?(Hash) && (x['asset'] == 'USDT' || x['currency'] == 'USDT') } || b.first
      end

      b = {} unless b.is_a?(Hash)

      account_balance = (b['balance'] || b['accountBalance'] || b['account_balance']).to_f
      equity = (b['equity'] || b['totalEquity'] || b['total_equity']).to_f
      unrealized = (b['unrealizedProfit'] || b['unrealizedPnl'] || b['unRealizedProfit']).to_f
      available_margin = (b['availableMargin'] || b['available_balance'] || b['available']).to_f
      used_margin = (b['usedMargin'] || b['positionMargin'] || b['margin']).to_f

      # In our app, "Available Balance" for AI purposes maps best to "availableMargin" for swap accounts.
      {
        'availableBalance' => available_margin,
        'equity' => (equity.zero? ? (account_balance + unrealized) : equity),
        'accountBalance' => account_balance,
        'unrealizedPnl' => unrealized,
        'availableMargin' => available_margin,
        'positionMargin' => used_margin
      }
    end

    def extract_available_balance(balance_json)
      info = extract_account_info(balance_json)
      info['availableBalance'].to_f
    end

    def group_positions_by_symbol(positions_json)
      data = (positions_json || {})['data'] rescue nil
      data ||= (positions_json || {})[:data] rescue nil
      arr = Array(data)

      grouped = arr.group_by do |p|
        next nil unless p.is_a?(Hash)
        p['symbol'] || p['asset'] || p['currency']
      end
      grouped.delete(nil)
      grouped
    end

    def build_positions_payload(positions:, symbol:, last_price:)
      Array(positions).filter_map do |p|
        next unless p.is_a?(Hash)

        sym = p['symbol'] || p['asset'] || p['currency']
        next unless sym.to_s == symbol.to_s

        raw_amt =
          p['positionAmt'] || p['positionAmt'.downcase] ||
          p['position_amt'] || p['positionSize'] || p['quantity'] || p['qty']

        amt = raw_amt.to_f
        next if amt == 0.0

        side =
          if p['positionSide']
            p['positionSide'].to_s.upcase
          elsif amt < 0
            'SHORT'
          else
            'LONG'
          end

        amt = amt.abs

        margin = (p['initialMargin'] || p['positionMargin'] || p['isolatedMargin'] || p['margin'] || 0).to_f
        unreal = (p['unrealizedProfit'] || p['unrealizedPnl'] || p['unRealizedProfit'] || 0).to_f
        unreal_pct = if margin.positive?
                       (unreal / margin * 100).round(4)
                     else
                       (p['unrealizedPnlRatio'] || p['unrealizedPnlPercentage'] || 0).to_f
                     end

        info = {
          'margin' => margin,
          'unrealizedPnl' => unreal,
          'unrealizedPnlPercentage' => unreal_pct,
          'realizedPnl' => (p['realisedProfit'] || p['realizedPnl'] || p['realizedProfit'] || 0).to_f,
          'entryPrice' => (p['avgPrice'] || p['entryPrice'] || p['avgEntryPrice'] || 0).to_f,
          'marketPrice' => (p['markPrice'] || p['marketPrice'] || last_price || 0).to_f,
          'estLiqPrice' => p['liquidationPrice'] || p['estLiqPrice'],
          'risk' => (p['risk'] || p['riskRate'] || 0).to_f,
          'leverage' => (p['leverage'] || 0).to_f
        }

        {
          'asset' => symbol,
          'side' => side,
          'amount' => amt,
          'info' => info
        }
      end
    end
  end

  module Actions
    module_function

    def execute!(client:, extension:, actions:, last_price:)
      stats = { executed: 0, failed: 0, skipped: 0 }
      Array(actions).each do |a|
        next unless a.is_a?(Hash)

        action_id = a[:id] || a['id']
        action_type = a[:type] || a['type']
        symbol = a[:asset] || a['asset']
        position_side = a[:side] || a['side']

        if action_id.nil?
          stats[:skipped] += 1
          next
        end

        ai_action = extension.user.ai_actions.where(id: action_id).first
        if ai_action.nil? || ai_action.status != 'pending'
          stats[:skipped] += 1
          next
        end

        begin
          usdt_amount = ai_action.amount.to_f
          raise "Invalid amount for action #{action_id}" if usdt_amount <= 0
          raise "Missing last_price for quantity calculation" if last_price.to_f <= 0

          # BingX Swap V2 quantity is in base currency (e.g. BTC), not USDT.
          # We convert our USDT amount from the AI into contract quantity.
          qty = (usdt_amount / last_price.to_f).round(6)

          log("[binx_api] exec action ##{action_id} #{action_type} #{symbol} #{position_side} usdt=#{usdt_amount} qty=#{qty}", level: :debug, color: :cyan)

          # Ensure 20X, Cross, Hedge before placing order
          client.ensure_trade_settings!(symbol: symbol)

          resp =
            case action_type
            when 'PLACE_MARKET_ORDER'
              client.open_market_order(symbol: symbol, position_side: position_side, quantity: qty, client_order_id: action_id.to_s)
            when 'CLOSE_MARKET_ORDER'
              client.close_market_order(symbol: symbol, position_side: position_side, quantity: qty, client_order_id: action_id.to_s)
            else
              raise "Unsupported action type: #{action_type}"
            end

          info = ai_action.info.is_a?(Hash) ? ai_action.info : {}
          ai_action.update(
            status: 'executed',
            info: info.merge('executed_at' => Time.now.utc.iso8601, 'exchange_response' => resp, 'executed_qty' => qty, 'executed_price' => last_price)
          )
          stats[:executed] += 1
        rescue => e
          ai_action.update(status: 'failed', info: { error: e.message })
          stats[:failed] += 1
          log("[binx_api] action ##{action_id} failed: #{e.message}", level: :warn, color: :yellow)
        end
      end
      stats
    end
  end

  class Runner
    def self.tick_all!
      count = Extension.where(ex_type: 'binx_api').count
      log("[binx_api] tick_all start extensions=#{count}", level: :debug, color: :cyan)

      Extension.where(ex_type: 'binx_api').find_each { |ext| tick_extension!(ext) }
    rescue => e
      log("[binx_api] tick_all error: #{e.message}", level: :error, color: :red)
    ensure
      log("[binx_api] tick_all end", level: :debug, color: :cyan)
    end

    def self.tick_extension!(ext)
      return unless ext.assets.exists?

      log("[binx_api] tick ext_id=#{ext.id} uuid=#{ext.uuid} account=#{ext.account || '-'} assets=#{ext.assets.count}", level: :debug, color: :cyan)
      client = client_for(ext)
      return if client.nil?

      balance_json = safe { client.perpetual_balance }
      positions_json = safe { client.perpetual_positions }

      # If we cannot fetch positions, do NOT ingest (it would incorrectly close DB positions).
      if positions_json.nil?
        ext.update(connected: false) rescue nil
        log("[binx_api] failed to fetch positions ext_id=#{ext.id} uuid=#{ext.uuid}", level: :warn, color: :yellow)
        return
      end

      account_info = Telemetry.extract_account_info(balance_json)
      log("[binx_api] account info ext_id=#{ext.id} availBalance=#{account_info['availableBalance']} equity=#{account_info['equity']} accountBalance=#{account_info['accountBalance']}", level: :debug, color: :cyan)
      positions_by_symbol = Telemetry.group_positions_by_symbol(positions_json)
      log("[binx_api] positions fetched ext_id=#{ext.id} symbols=#{positions_by_symbol.keys.size}", level: :debug, color: :cyan)

      ext.assets.find_each do |asset|
        symbol = asset.value
        last_price = safe { client.quote_price(symbol) }

        raw_positions = positions_by_symbol[symbol] || []
        payload_positions = Telemetry.build_positions_payload(
          positions: raw_positions,
          symbol: symbol,
          last_price: last_price
        )

        # Safety: if exchange reported positions for this symbol but we failed to parse them,
        # do NOT send "empty positions" into ingest, because it would close DB positions.
        positions_parsed = !(raw_positions.any? && payload_positions.empty?)

        log("[binx_api] asset=#{symbol} lastPrice=#{last_price} raw_positions=#{raw_positions.size} parsed_positions=#{payload_positions.size} positions_parsed=#{positions_parsed}", level: :debug, color: :cyan)

        ingest_res = TickerIngest.process_for_extension_asset!(
          extension: ext,
          asset: asset,
          info: account_info.merge('lastPrice' => last_price),
          positions: payload_positions,
          meta: { 'positions_parsed' => positions_parsed }
        )
        next if (ingest_res.is_a?(Hash) && (ingest_res[:error] || ingest_res['error']))

        actions = ingest_res[:actions] || ingest_res['actions']
        log("[binx_api] ingest ok asset=#{symbol} status=#{ingest_res[:status] || ingest_res['status']} pending_actions=#{Array(actions).size}", level: :debug, color: :cyan)

        stats = Actions.execute!(client: client, extension: ext, actions: actions, last_price: last_price)
        log("[binx_api] actions result asset=#{symbol} executed=#{stats[:executed]} failed=#{stats[:failed]} skipped=#{stats[:skipped]}", level: :debug, color: :cyan)
      end
    rescue => e
      log("[binx_api] tick ext_id=#{ext&.id} uuid=#{ext&.uuid} error: #{e.message}", level: :error, color: :red)
    end

    def self.client_for(ext)
      api_key = present(ext.api_key) ? ext.api_key.to_s.strip : ENV['BINX_API_KEY'].to_s.strip.split(':', 2).first
      api_secret = present(ext.api_secret) ? ext.api_secret.to_s.strip : nil

      if api_secret.nil?
        env_raw = ENV['BINX_API_KEY'].to_s.strip
        env_secret = env_raw.include?(':') ? env_raw.split(':', 2)[1] : nil
        api_secret = (env_secret.to_s.strip.empty? ? ENV['BINX_API_SECRET'].to_s.strip : env_secret.to_s.strip)
        api_secret = nil if api_secret.to_s.strip.empty?
      end

      raise Error, 'Missing api_key (set extension.api_key or BINX_API_KEY)' if api_key.to_s.strip.empty?

      log("[binx_api] client_for ext_id=#{ext.id} uuid=#{ext.uuid} key_source=#{present(ext.api_key) ? 'extension' : 'env'} secret_present=#{!api_secret.to_s.strip.empty?}", level: :debug, color: :cyan)
      Client.new(api_key: api_key, secret_key: api_secret)
    rescue => e
      ext.update(connected: false) rescue nil
      log("[binx_api] disabled ext_id=#{ext.id} uuid=#{ext.uuid}: #{e.message}", level: :warn, color: :yellow)
      nil
    end

    def self.present(v)
      !v.nil? && !v.to_s.strip.empty?
    end

    def self.safe
      yield
    rescue
      nil
    end
  end
end
