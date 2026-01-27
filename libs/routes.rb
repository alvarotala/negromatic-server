require_relative './ticker_ingest'

get '/' do
  @title = "Tradero"
  erb :index
end

get '/login' do
  @title = "Trader Bot - Login"
  erb :login
end

post '/login' do
  email = params[:email]
  password = params[:password]
  
  user = User.authenticate(email, password)
  
  if user
    session[:user_id] = user.id
    flash[:notice] = "Logged in successfully"
    redirect '/dashboard'
  else
    flash[:error] = "Invalid email or password"
    erb :login
  end
end

get '/logout' do
  session.clear
  flash[:notice] = "You have been logged out"
  redirect '/login'
end

get '/dashboard' do
  protected!
  @title = "Trader Bot - Dashboard"
  prepare_dashboard_data
  erb :dashboard
end

get '/dashboard/refresh' do
  unless logged_in?
    halt 401, "Session expired. Please log in again."
  end
  prepare_dashboard_data
  erb :_dashboard_content, layout: false
end

get '/positions' do
  protected!
  @title = "Trader Bot - Positions"

  page = (params[:page].to_i <= 0 ? 1 : params[:page].to_i)
  per_page = 100
  offset = (page - 1) * per_page

  @positions = current_user.positions.where(status: 'closed')
                           .order(closed_at: :desc)
                           .limit(per_page)
                           .offset(offset)

  erb :positions_index
end

get '/assets' do
  protected!
  @title = "Trader Bot - Active Assets"
  
  # Fetch all active assets across all extensions for the current user
  @active_assets = AssetsExtension.joins(:extension)
                                  .where(extensions: { user_id: current_user.id })
                                  .includes(:asset, :extension)
                                  .order('extensions.account ASC, assets.value ASC')
                                  
  erb :assets_index
end

get '/extensions/:extension_id/assets/:asset_id/debug' do
  protected!
  @extension = current_user.extensions.find(params[:extension_id])
  @assets_extension = @extension.assets_extensions.find_by!(asset_id: params[:asset_id])
  @title = "Trader Bot - Asset Debug"

  # We might not have a specific position context here
  @position = @assets_extension.open_positions.last

  debug_for_assets_extension(@assets_extension, template: :asset_debug)
end

get '/extensions/:extension_id/assets/:asset_id/debug/refresh' do
  unless logged_in?
    halt 401, "Session expired. Please log in again."
  end
  @extension = current_user.extensions.find(params[:extension_id])
  @assets_extension = @extension.assets_extensions.find_by!(asset_id: params[:asset_id])
  
  debug_for_assets_extension(@assets_extension, template: :_asset_debug_content, layout: false)
end

post '/extensions/:extension_id/assets/:asset_id/debug/clear_chat' do
  protected!
  @extension = current_user.extensions.find(params[:extension_id])
  @assets_extension = @extension.assets_extensions.find_by!(asset_id: params[:asset_id])
  
  if @assets_extension.update(ai_history: [])
    flash[:notice] = "AI Chat history cleared for #{@assets_extension.asset.value}"
  else
    flash[:error] = "Error clearing history: #{@assets_extension.errors.full_messages.join(', ')}"
  end
  
  redirect "/extensions/#{params[:extension_id]}/assets/#{params[:asset_id]}/debug"
end

helpers do
  def prepare_dashboard_data
    stats = current_user.trading_stats

    # Main stats
    @total_realized_pnl = stats[:total_realized_pnl]
    @pnl_24h = stats[:pnl_24h]
    @total_trades = stats[:total_trades]
    @win_rate = stats[:win_rate]

    # Detailed breakdown
    @closed_realized_pnl = stats[:closed_realized_pnl]
    @open_running_realized_pnl = stats[:open_running_realized_pnl]
    @winning_trades = stats[:winning_trades]
    @losing_trades = stats[:losing_trades]
    @partial_close_count = stats[:partial_close_count]
    @partial_close_profit = stats[:partial_close_profit]
    @avg_profit_per_trade = stats[:avg_profit_per_trade]
    
    # Mark positions as stale when telemetry stops.
    stale_cutoff = 5.minutes.ago
    current_user.positions.where(status: 'open').where('last_activity_at < ?', stale_cutoff).find_each do |pos|
      pos.mark_stale!(reason: 'telemetry_lost')
    end

    # Extensions with readiness info
    @extensions = current_user.extensions.map do |ext|
      total_assets = ext.assets.count
      ready_assets = ext.assets_extensions.where(status: 'ready').count
      
      ext.instance_variable_set(:@ready_count, ready_assets)
      ext.instance_variable_set(:@total_count, total_assets)
      ext.define_singleton_method(:ready_count) { instance_variable_get(:@ready_count) }
      ext.define_singleton_method(:total_count) { instance_variable_get(:@total_count) }
      ext
    end

    @open_positions = current_user.positions.where(status: 'open').order(last_activity_at: :desc)
    @stale_positions = current_user.positions.where(status: 'stale').order(last_activity_at: :desc)
    
    @total_unrealized_pnl = @open_positions.sum { |pos| pos.unrealized_pnl }
    @has_active_strategy = !!current_user.active_strategy
    @has_assets = current_user.extensions.joins(:assets).any?

    # Calculate next AI trigger time across all active assets
    @next_ai_trigger = AssetsExtension.joins(:extension)
                                      .where(extensions: { user_id: current_user.id, status: 'trading' })
                                      .where.not(last_ai_check_at: nil)
                                      .map { |ae| ae.last_ai_check_at + current_user.ai_interval_minutes.minutes }
                                      .min
  end

  def debug_for_assets_extension(ae, template: :position_debug, **options)
    @assets_extension = ae
    history = @assets_extension&.ai_history
    @ai_history = history.is_a?(Array) ? history : []

    @ai_actions = current_user.ai_actions.where(asset_id: @assets_extension.asset_id)
                            .order(timestamp: :desc)
                            .limit(100)

    # Calculate next AI trigger for this specific asset
    if @assets_extension.extension.status == 'trading' && @assets_extension.last_ai_check_at
      @next_ai_trigger = @assets_extension.last_ai_check_at + current_user.ai_interval_minutes.minutes
    end

    erb template, options
  end
end

get '/settings' do
  protected!
  @title = "Trader Bot - Settings"
  @user = current_user
  erb :settings
end

post '/settings' do
  protected!
  @user = current_user
  
  email = params[:email]
  password = params[:password]
  password_confirmation = params[:password_confirmation]
  ai_interval_minutes_param = params[:ai_interval_minutes]

  update_params = { email: email }

  if password.to_s.strip != "" || password_confirmation.to_s.strip != ""
    if password == password_confirmation
      update_params[:password] = password
    else
      flash[:error] = "Passwords do not match"
      return erb :settings
    end
  end

  # AI interval (minutes). Minimum is 5.
  if ai_interval_minutes_param.present?
    ai_interval_minutes = ai_interval_minutes_param.to_i
    if ai_interval_minutes < 5
      ai_interval_minutes = 5
    end
    update_params[:ai_interval_minutes] = ai_interval_minutes
  end

  if @user.update(update_params)
    flash[:notice] = "Account updated successfully"
    redirect '/settings'
  else
    flash[:error] = "Error updating account: #{@user.errors.full_messages.join(', ')}"
    erb :settings
  end
end

get '/extensions/new' do
  protected!
  @title = "Trader Bot - Link Extension"
  erb :extensions_new
end

post '/extensions/new' do
  protected!
  uuid = params[:uuid]
  ex_type = params[:ex_type]
  account = params[:account]
  api_key = params[:api_key].to_s.strip
  api_secret = params[:api_secret].to_s.strip

  if uuid.blank?
    flash[:error] = "Extension UUID is required"
    return erb :extensions_new
  end

  extension = current_user.extensions.new(
    uuid: uuid, 
    ex_type: ex_type, 
    account: account,
    api_key: api_key.presence,
    api_secret: api_secret.presence
  )

  if extension.save
    flash[:notice] = "Extension linked successfully"
    redirect '/dashboard'
  else
    flash[:error] = "Error linking extension: #{extension.errors.full_messages.join(', ')}"
    erb :extensions_new
  end
end

get '/extensions/:id/edit' do
  protected!
  @extension = current_user.extensions.find(params[:id])
  @title = "Trader Bot - Edit Extension"
  erb :extensions_edit
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Extension not found"
  redirect '/dashboard'
end

post '/extensions/:id/edit' do
  protected!
  @extension = current_user.extensions.find(params[:id])
  
  update_params = {
    uuid: params[:uuid],
    account: params[:account],
    api_key: params[:api_key].to_s.strip.presence
  }

  # Don't accidentally wipe secrets on edit if left blank
  incoming_secret = params[:api_secret].to_s.strip
  update_params[:api_secret] = incoming_secret if incoming_secret.present?

  if @extension.update(update_params)
    flash[:notice] = "Extension updated successfully"
    redirect '/dashboard'
  else
    flash[:error] = "Error updating extension: #{@extension.errors.full_messages.join(', ')}"
    erb :extensions_edit
  end
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Extension not found"
  redirect '/dashboard'
end

get '/extensions/:id/assets' do
  protected!
  @extension = current_user.extensions.find(params[:id])
  # Fetch all assets matching this extension's type
  @available_assets = Asset.where(ex_type: @extension.ex_type).order(name: :asc)
  # Map which ones are currently linked to this extension
  @linked_asset_ids = @extension.asset_ids
  # Fetch readiness info for linked assets
  @assets_readiness = @extension.assets_extensions.each_with_object({}) do |ae, hash|
    hash[ae.asset_id] = { status: ae.status, last_activity_at: ae.last_activity_at }
  end

  @title = "Trader Bot - Extension Assets"
  erb :extensions_assets
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Extension not found"
  redirect '/dashboard'
end

post '/extensions/:id/assets/toggle' do
  protected!
  @extension = current_user.extensions.find(params[:id])
  asset_id = params[:asset_id].to_i
  active = params[:active] == 'true'
  
  asset = Asset.find(asset_id)
  
  if active
    @extension.assets << asset unless @extension.assets.include?(asset)
  else
    @extension.assets.delete(asset)
  end
  
  json success: true
rescue ActiveRecord::RecordNotFound
  json success: false, error: "Extension or Asset not found"
end

post '/extensions/:id/toggle_status' do
  protected!
  @extension = current_user.extensions.find(params[:id])
  
  new_status = @extension.status == 'trading' ? 'idle' : 'trading'
  
  if new_status == 'trading' && !@extension.connected
    return json success: false, error: "Cannot set extension to trading while it is disconnected."
  end
  
  if @extension.update(status: new_status)
    # If we set it to idle, reset the AI check time for all linked assets 
    # so when we resume, it triggers AI advice immediately.
    if new_status == 'idle'
      @extension.assets_extensions.update_all(last_ai_check_at: nil)
    end
    json success: true, status: new_status
  else
    json success: false, error: @extension.errors.full_messages.join(', ')
  end
rescue ActiveRecord::RecordNotFound
  json success: false, error: "Extension not found"
end

post '/extensions/:id/delete' do
  protected!
  @extension = current_user.extensions.find(params[:id])
  @extension.destroy
  flash[:notice] = "Extension deleted successfully"
  redirect '/dashboard'
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Extension not found"
  redirect '/dashboard'
end

# Strategies CRUD
get '/strategies' do
  protected!
  @user_strategies = current_user.strategies.order(active: :desc, created_at: :desc)
  @global_strategies = Strategy.where(user_id: nil).order(name: :asc)
  @title = "Trader Bot - Strategies"
  erb :strategies_index
end

get '/strategies/new' do
  protected!
  @title = "Trader Bot - New Strategy"
  erb :strategies_new
end

get '/strategies/:id' do
  protected!
  @strategy = Strategy.find(params[:id])
  
  # Security check: users can only see their own strategies or global ones
  if @strategy.user_id && @strategy.user_id != current_user.id
    flash[:error] = "Access denied"
    redirect '/strategies'
  end

  @title = "Trader Bot - Preview Strategy"
  erb :strategies_show
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Strategy not found"
  redirect '/strategies'
end

post '/strategies' do
  protected!
  name = params[:name]
  content = params[:content]
  active = params[:active] == 'on'

  if name.blank?
    flash[:error] = "Name is required"
    return erb :strategies_new
  end

  strategy = current_user.strategies.new(name: name, content: content, active: active)

  if strategy.save
    flash[:notice] = "Strategy created successfully"
    redirect '/strategies'
  else
    flash[:error] = "Error creating strategy: #{strategy.errors.full_messages.join(', ')}"
    erb :strategies_new
  end
end

get '/strategies/:id/edit' do
  protected!
  @strategy = current_user.strategies.find(params[:id])
  @title = "Trader Bot - Edit Strategy"
  erb :strategies_edit
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Strategy not found"
  redirect '/strategies'
end

post '/strategies/:id' do
  protected!
  @strategy = current_user.strategies.find(params[:id])
  
  if @strategy.update(name: params[:name], content: params[:content], active: params[:active] == 'on')
    flash[:notice] = "Strategy updated successfully"
    redirect '/strategies'
  else
    flash[:error] = "Error updating strategy: #{@strategy.errors.full_messages.join(', ')}"
    erb :strategies_edit
  end
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Strategy not found"
  redirect '/strategies'
end

post '/strategies/:id/toggle_active' do
  protected!
  @strategy = Strategy.find(params[:id])
  
  # Prevent toggling global strategies
  if @strategy.user_id.nil?
    return json success: false, error: "Global strategies cannot be activated directly. Please clone it first."
  end

  # Security check: users can only toggle their own strategies
  if @strategy.user_id != current_user.id
    return json success: false, error: "Access denied"
  end
  
  # When activating, other strategies are deactivated in the model callback
  if @strategy.update(active: !@strategy.active)
    json success: true, active: @strategy.active
  else
    json success: false, error: @strategy.errors.full_messages.join(', ')
  end
rescue ActiveRecord::RecordNotFound
  json success: false, error: "Strategy not found"
end

post '/strategies/:id/clone' do
  protected!
  # Security: Only allow cloning if it's a global template OR owned by the user
  strategy_to_clone = Strategy.where(id: params[:id])
                              .where("user_id IS NULL OR user_id = ?", current_user.id)
                              .first

  if strategy_to_clone.nil?
    flash[:error] = "Strategy not found or access denied"
    redirect '/strategies'
    return
  end
  
  new_strategy = current_user.strategies.new(
    name: "#{strategy_to_clone.name} (Copy)",
    content: strategy_to_clone.content,
    active: false
  )

  if new_strategy.save
    flash[:notice] = "Strategy copied! You can now edit and activate it."
    redirect "/strategies/#{new_strategy.id}/edit"
  else
    flash[:error] = "Failed to copy strategy: #{new_strategy.errors.full_messages.join(', ')}"
    redirect '/strategies'
  end
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Strategy not found"
  redirect '/strategies'
end

post '/strategies/:id/delete' do
  protected!
  @strategy = current_user.strategies.find(params[:id])
  @strategy.destroy
  flash[:notice] = "Strategy deleted successfully"
  redirect '/strategies'
end

# Mark as "stale" (telemetry lost). This is NOT a confirmed exchange close.
post '/positions/:id/stale' do
  protected!
  @position = current_user.positions.find(params[:id])
  
  if @position.mark_stale!(reason: 'manual_review')
    flash[:notice] = "Position marked as stale (needs verification)"
  else
    flash[:error] = "Error marking position as stale: #{@position.errors.full_messages.join(', ')}"
  end
  redirect '/dashboard'
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Position not found"
  redirect '/dashboard'
end

# Assistants CRUD
get '/assistants' do
  protected!
  @assistants = current_user.assistants.order(created_at: :desc)
  @title = "Negromatic - Assistants"
  erb :assistants_index
end

get '/assistants/new' do
  protected!
  @title = "Negromatic - New Assistant"
  erb :assistants_new
end

post '/assistants' do
  protected!
  assistant = current_user.assistants.new(
    name: params[:name],
    identity: params[:identity],
    global_memory: params[:global_memory]
  )

  if assistant.save
    flash[:notice] = "Assistant created successfully"
    redirect '/assistants'
  else
    flash[:error] = "Error creating assistant: #{assistant.errors.full_messages.join(', ')}"
    erb :assistants_new
  end
end

get '/assistants/:id/edit' do
  protected!
  @assistant = current_user.assistants.find(params[:id])
  @title = "Negromatic - Edit Assistant"
  erb :assistants_edit
end

post '/assistants/:id' do
  protected!
  @assistant = current_user.assistants.find(params[:id])
  
  if @assistant.update(
    name: params[:name],
    identity: params[:identity],
    global_memory: params[:global_memory]
  )
    flash[:notice] = "Assistant updated successfully"
    redirect '/assistants'
  else
    flash[:error] = "Error updating assistant: #{@assistant.errors.full_messages.join(', ')}"
    erb :assistants_edit
  end
end

post '/assistants/:id/delete' do
  protected!
  @assistant = current_user.assistants.find(params[:id])
  @assistant.destroy
  flash[:notice] = "Assistant deleted successfully"
  redirect '/assistants'
end

# Backward-compatible alias: old route used to "close" inactive positions.
post '/positions/:id/close' do
  call env.merge('PATH_INFO' => "/positions/#{params[:id]}/stale")
end

# Human confirms the stale position was closed on the exchange.
# This counts for stats since it's a confirmed exchange close.
post '/positions/:id/confirm_closed' do
  protected!
  @position = current_user.positions.find(params[:id])

  if @position.close_from_stale_confirmation!
    flash[:notice] = "Position confirmed closed (counts toward stats)"
  else
    flash[:error] = "Error confirming close: #{@position.errors.full_messages.join(', ')}"
  end
  redirect '/dashboard'
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Position not found"
  redirect '/dashboard'
end

# Human manually archives a position (bookkeeping only, doesn't affect stats)
post '/positions/:id/archive' do
  protected!
  @position = current_user.positions.find(params[:id])

  if @position.archive_manually!
    flash[:notice] = "Position archived (bookkeeping only, not counted in stats)"
  else
    flash[:error] = "Error archiving: #{@position.errors.full_messages.join(', ')}"
  end
  redirect '/dashboard'
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Position not found"
  redirect '/dashboard'
end

# Human confirms the position is still open (or telemetry resumed).
post '/positions/:id/reopen' do
  protected!
  @position = current_user.positions.find(params[:id])

  if @position.reopen!
    flash[:notice] = "Position moved back to open"
  else
    flash[:error] = "Error reopening position: #{@position.errors.full_messages.join(', ')}"
  end
  redirect '/dashboard'
rescue ActiveRecord::RecordNotFound
  flash[:error] = "Position not found"
  redirect '/dashboard'
end

# API Routes

namespace '/api' do

  # Example payload for data:
  # DON'T REMOVE!
  # {
  #   "extension": "gbmlcdbgbjhecmhllikjplfefnlcoila",
  #   "asset": "BTC-USDT",
  #   "positions": [
  #     {
  #       "asset": "BTC-USDT",
  #       "side": "LONG",
  #       "amount": 4991.56,
  #       "info": {
  #         "margin": 249.555,
  #         "unrealizedPnl": 0.4414,
  #         "unrealizedPnlPercentage": 0.17,
  #         "realizedPnl": 0.4,
  #         "entryPrice": 91579.8,
  #         "marketPrice": 91590.7,
  #         "estLiqPrice": null,
  #         "risk": 0.02
  #       }
  #     }
  #   ],
  #   "info": {
  #     "availableBalance": 100486.3938,
  #     "lastPrice": 91808.3,
  #     "equity": 100250.0,
  #     "accountBalance": 100486.3938,
  #     "availableMargin": 98350.22,
  #     "positionMargin": 249.555
  #   }
  # }

  post '/ticker' do
    begin
      data = JSON.parse(request.body.read)
    rescue JSON::ParserError
      return json error: 'Invalid JSON payload'
    end

    json TickerIngest.process!(data)
  end

  post '/actions/confirm' do
    data = JSON.parse(request.body.read) rescue {}
    extension_uuid = data['extension']
    
    if extension_uuid.blank?
      return json error: 'Extension UUID is required'
    end

    extension = Extension.find_by(uuid: extension_uuid)
    if extension.nil?
      return json error: 'Extension not found'
    end

    results = Array(data['results'])
    
    results.each do |res|
      next if res['id'].blank?
      
      status = res['status'] == 'executed' ? 'executed' : 'failed'
      error_msg = res['error']
      
      # Security: Only update actions belonging to the user of this extension
      extension.user.ai_actions.where(id: res['id']).update_all(
        status: status, 
        info: error_msg ? { error: error_msg } : nil
      ) rescue nil
    end
    
    json success: true
  end

  post '/ai/strategy_edit' do
    protected!
    data = JSON.parse(request.body.read) rescue {}
    current_content = data['current_content'].to_s
    instruction = data['instruction'].to_s

    if instruction.blank?
      return json error: 'Instruction is required'
    end

    system_prompt = <<~TEXT
      You are an expert trading strategy developer. Your task is to edit the provided strategy based on the user's instructions.
      Respond ONLY with the COMPLETE AND FINAL updated strategy content. 
      Do NOT include any explanations, markdown code blocks, or preamble.
      Do NOT respond with a diff or just the changes. 
      You MUST provide the entire strategy text from start to finish, including the parts that did not change.
      Keep the formatting consistent with the original.
    TEXT

    user_message = <<~TEXT
      CURRENT STRATEGY CONTENT:
      ---
      #{current_content}
      ---

      INSTRUCTION:
      #{instruction}
    TEXT

    response = AI.chat(messages: [
      { role: 'system', content: system_prompt },
      { role: 'user', content: user_message }
    ])

    if response[:response].start_with?("[error]")
      json error: response[:response]
    else
      # Clean up any accidental markdown fences the AI might include despite instructions
      cleaned = response[:response].gsub(/\A```[a-z]*\n/i, '').gsub(/\n```\z/, '')
      # Remove lines that contain only "---" (optionally surrounded by whitespace)
      cleaned = cleaned.gsub(/^\s*---\s*$(\r?\n)?/, '')
      json success: true, content: cleaned
    end
  end

end
