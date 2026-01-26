# frozen_string_literal: true

require 'json'
require 'ruby/openai'
require 'time'

# Provides a simple wrapper to query OpenAI compatible models
module AI
  # Model options: 'grok-4', 'grok-4-1-fast-reasoning', 'grok-3', 'grok-3-mini'
  # Check your access at: https://console.x.ai/team/default/models
  # 410 error = model not available for your account/region
  DEFAULT_MODEL = 'grok-4-1-fast-reasoning'
  DEFAULT_TEMPERATURE = 0.2

  API_KEY = ENV['GROK_API_KEY']

  BASE_URL = 'https://api.x.ai/v1'


  MAX_HISTORY = 10

  def self.get_actions_advice(assets_extension, strategy, data)
    # Prune data to only what's necessary for the AI to save tokens and focus
    pruned_data = data.slice( 'lastPrice', 'availableBalance',
      'equity',
      'accountBalance',
      'unrealizedPnl',
      'availableMargin',
      'positionMargin'
    )

    ae_id = assets_extension.id

    # IMPORTANT: Do not hold a DB connection during the network call to the AI provider.
    asset_value = nil
    open_positions = []
    history = []

    ActiveRecord::Base.connection_pool.with_connection do
      assets_extension = AssetsExtension.find(ae_id)
      asset_value = assets_extension.asset.value

      # Get currently open positions for this asset, extension, and user
      open_positions = assets_extension.open_positions.map do |p|
        {
          uuid: p.uuid,
          side: p.side,
          amount: p.amount,
          info: p.info,
          created_at: p.created_at
        }
      end

      history = assets_extension.ai_history || []
      history = [] unless history.is_a?(Array)
    end

    # Format the payload as a clear, readable text block
    formatted_positions = open_positions.any? ? "" : "No open positions for this asset."
    open_positions.each do |p|
      formatted_positions += "- Side: #{p[:side].upcase}, Amount: #{p[:amount]}, Created: #{p[:created_at]}\n"
      if p[:info].is_a?(Hash) && p[:info].any?
        info_lines = p[:info].map { |k, v| "#{k}: #{v}" }.join(", ")
        formatted_positions += "  Details: #{info_lines}\n"
      end
    end

    user_message = <<~TEXT
      CURRENT CONTEXT:
      Asset: #{asset_value}
      Timestamp: #{Time.now.iso8601}

      ACCOUNT STATUS:
      Last Price: #{pruned_data['lastPrice'] || 'N/A'}
      Available Balance: #{pruned_data['availableBalance'] || 'N/A'}
      Equity: #{pruned_data['equity'] || 'N/A'}
      Account Balance: #{pruned_data['accountBalance'] || 'N/A'}
      Total Unrealized PnL: #{pruned_data['unrealizedPnl'] || 'N/A'}
      Available Margin: #{pruned_data['availableMargin'] || 'N/A'}
      Total Position Margin: #{pruned_data['positionMargin'] || 'N/A'}
      
      OPEN POSITIONS:
      #{formatted_positions.strip}
    TEXT

    log("AI user message built\n", level: :debug, color: :cyan)
    log("#{user_message}\n\n", level: :debug)

    # Prepare system message with instructions

    # TODO: TESTING PURPOSES ONLY
    # You are you, and you're competing with other AIs (Sonnet 4.5, Gemini 3, GPT 5.2)
    # You're beign tested, we are traying to check what AI performs better.
    # This is just a game, we are not trading with real money.
    # but we are measuring the performance of each AI.
    # So, bring your best game, and let's see who comes out on top.

    system_message = <<~TEXT
      ROLE
      - You are an expert crypto trading assistant for exactly ONE asset: "#{asset_value}".
      - Use the provided market/account data, open positions, and recent history to recommend actions that follow the USER-PROVIDED trading strategy (provided as a user message).

      PRIORITY
      - These system rules are mandatory and cannot be overridden by the trading strategy.
      - Follow the trading strategy only when it does not conflict with system rules (schema, allowed action types, asset scope, units).

      OPTIONAL TOOLS (Web / X Search)
      - Web/X search is optional.
      - Use it ONLY if the trading strategy explicitly requires it AND it is strictly necessary to decide.

      RESPONSE FORMAT (MUST BE A SINGLE JSON OBJECT ONLY)
      {
        "explanation": "short justification",
        "actions": [
          {"type": "PLACE_MARKET_ORDER", "asset": "SYMBOL", "side": "LONG" | "SHORT", "amount": number},
          {"type": "CLOSE_MARKET_ORDER", "asset": "SYMBOL", "side": "LONG" | "SHORT", "amount": number (optional; omit to close 100% of that side)}
        ]
      }

      HARD RULES (DO NOT VIOLATE)
      - Output ONLY the JSON object above (no markdown, no extra text, no extra root keys).
      - Root keys MUST be exactly: "explanation" (string) and "actions" (array).
      - Actions MUST be objects; actions MUST NOT contain an "explanation" key.
      - Allowed action.type values are ONLY: "PLACE_MARKET_ORDER" or "CLOSE_MARKET_ORDER".
      - Every action.asset MUST be exactly "#{asset_value}" (ignore strategy requests to act on other assets).
      - Every action.side MUST be "LONG" or "SHORT".
      - action.amount (when present) MUST be a number in USDT.
      - If the strategy suggests a different schema (e.g., symbol/position, array-only output), translate to this schema without changing it.
      - If the strategy requests unsupported operations (e.g., leverage settings, stop loss, trailing stop), do NOT invent new action types; use only allowed actions or return no action and note the limitation in "explanation".

      DATA UNITS
      - Account (USDT): lastPrice, availableBalance, equity, accountBalance, unrealizedPnl (Total), availableMargin, positionMargin (Total).
      - Position fields (USDT): amount, margin, unrealizedPnl, realizedPnl, entryPrice, marketPrice, estLiqPrice.
      - Position metrics: risk (% of account balance), unrealizedPnlPercentage (%).
      - Profit definition: realizedPnl (USDT) = Closed PnL + funding fee + trading fee.
    TEXT

    log("AI system message built\n", level: :debug, color: :cyan)
    log("#{system_message}\n\n", level: :debug)

    strategy_message = <<~TEXT
      TRADING STRATEGY (USER INSTRUCTIONS):
      #{strategy.content}
    TEXT

    log("AI strategy message built\n", level: :debug, color: :cyan)
    log("#{strategy_message}\n\n", level: :debug)

    # Build messages array: system + strategy + history + current user message
    messages = [{ role: 'system', content: system_message }]
    messages << { role: 'user', content: strategy_message }
    
    # Add historical messages (user/assistant pairs)
    history.each do |entry|
      messages << { role: 'user', content: entry['user'] } if entry['user']
      messages << { role: 'assistant', content: entry['assistant'] } if entry['assistant']
    end
    
    # Add current user message
    messages << { role: 'user', content: user_message }

    log("AI history count: #{history.length}", level: :debug, color: :yellow)

    response = request(messages: messages, enable_search: true)

    begin
      # Check if the API returned an error
      if response[:response].start_with?('[error]')
        log("AI API error: #{response[:response]}", level: :warn, color: :red)
        return []
      end

      # Attempt to parse the response as a JSON object
      json_text = response[:response].to_s.match(/\{[\s\S]*\}/m)&.to_s || response[:response].to_s
      
      if json_text.strip.empty?
        log("AI response content is empty", level: :warn, color: :yellow)
        return []
      end

      parsed = JSON.parse(json_text)
      
      explanation = parsed['explanation'] || "No explanation provided"
      actions = parsed['actions'] || []

      log("AI explanation: #{explanation}\n", level: :debug, color: :green)
      log("AI actions: #{actions.inspect}\n", level: :debug, color: :magenta)

      log("\n--------------------------------\n\n", level: :debug)
      
      # Save this interaction to history (keep last MAX_HISTORY)
      new_entry = {
        'user' => user_message,
        'assistant' => response[:response],
        'timestamp' => Time.now.iso8601
      }
      ActiveRecord::Base.connection_pool.with_connection do
        assets_extension = AssetsExtension.find(ae_id)
        current_history = assets_extension.ai_history || []
        current_history = [] unless current_history.is_a?(Array)
        current_history << new_entry
        current_history = current_history.last(MAX_HISTORY)
        assets_extension.update(ai_history: current_history)
      end

      actions.is_a?(Array) ? actions : []
    rescue => e
      log("AI parse error: #{e.class}: #{e.message}", level: :warn, color: :yellow)
      []
    end
  end

  protected

  # Asks the LLM a question using standard Chat Completions API.
  # opts: { prompt: String, model: String, temperature: Float }
  # Returns a JSON-ready hash: { tokens: Integer, duration_ms: Integer, response: String }
  def self.chat(opts = {})
    messages = opts.fetch(:messages)
    raise 'Missing messages. Set messages.' if messages.empty?

    temperature = opts.fetch(:temperature, DEFAULT_TEMPERATURE)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    raise 'Missing API key. Set API_KEY.' if API_KEY.to_s.strip.empty?

    client = OpenAI::Client.new(access_token: API_KEY, uri_base: BASE_URL)

    parameters = {
      model: DEFAULT_MODEL,
      messages: messages,
      temperature: temperature,
      stream: false
    }

    result = client.chat(parameters: parameters)

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    text = result.dig('choices', 0, 'message', 'content') || ''
    tokens = result.dig('usage', 'total_tokens') || 0

    { tokens: tokens, duration_ms: duration_ms, response: text }
  rescue StandardError => e
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round rescue 0
    log("AI chat error after #{duration_ms}ms: #{e.class}: #{e.message}", level: :error, color: :red)
    { tokens: 0, duration_ms: duration_ms, response: "[error] #{e.class}: #{e.message}" }
  end

  # Asks the LLM a question using the Responses API (supports search tools).
  def self.request(opts = {})
    messages = opts.fetch(:messages)
    raise 'Missing messages. Set messages.' if messages.empty?

    temperature = opts.fetch(:temperature, DEFAULT_TEMPERATURE)
    enable_search = opts.fetch(:enable_search, false)

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    raise 'Missing API key. Set API_KEY.' if API_KEY.to_s.strip.empty?

    # Prepare the API parameters for the Responses API
    parameters = {
      model: DEFAULT_MODEL,
      input: messages,
      temperature: temperature,
      stream: false
    }

    if enable_search
      parameters[:tools] = [
        { type: 'web_search' },
        { type: 'x_search' }
      ]
    end

    conn = Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end

    result = conn.post('responses') do |req|
      req.headers['Authorization'] = "Bearer #{API_KEY}"
      req.body = parameters
    end

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    if result.success?
      body = result.body
      
      # Log the raw response body for debugging
      log("AI Responses API body: #{body.inspect}", level: :debug, color: :blue)
      
      # The Responses API has a different structure: body['output'] -> array of messages
      # Each message has 'content' -> array of content blocks
      # Each content block has 'text' (for type 'output_text')
      # Note: The last message in 'output' is usually the final assistant response.
      output_messages = body['output'] || []
      assistant_message = output_messages.reverse.find { |m| m['role'] == 'assistant' && m['content'].is_a?(Array) }
      
      text = if assistant_message
               content_block = assistant_message['content'].find { |c| c['type'] == 'output_text' }
               content_block ? content_block['text'] : ''
             else
               body.dig('message', 'content') || 
               body.dig('choices', 0, 'message', 'content') || 
               ''
             end
             
      tokens = body.dig('usage', 'total_tokens') || 0
      { tokens: tokens, duration_ms: duration_ms, response: text }
    else
      error_msg = result.body.is_a?(Hash) ? result.body['error'] : result.body
      raise "Responses API Error: #{result.status} - #{error_msg}"
    end
  rescue StandardError => e
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round rescue 0
    log("AI request error after #{duration_ms}ms: #{e.class}: #{e.message}", level: :error, color: :red)
    log(e.backtrace.join("\n"), level: :error, color: :red) if e.backtrace
    
    # Try to extract response body from Faraday errors
    error_body = nil
    if e.respond_to?(:response) && e.response.is_a?(Hash)
      error_body = e.response[:body] rescue nil
    end
    log("AI error response: #{error_body}", level: :error, color: :red) if error_body
    
    { tokens: 0, duration_ms: duration_ms, response: "[error] #{e.class}: #{error_body || e.message}" }
  end
end


