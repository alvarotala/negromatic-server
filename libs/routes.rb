# frozen_string_literal: true

get '/' do
  @title = "Negromatic"
  erb :index
end

get '/login' do
  @title = "Negromatic - Login"
  erb :login
end

post '/login' do
  email = params[:email]
  password = params[:password]
  
  user = User.authenticate(email, password)
  
  if user
    session[:user_id] = user.id
    flash[:notice] = "Logged in successfully"
    redirect '/assistants'
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
  redirect '/assistants'
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

get '/settings' do
  protected!
  @title = "Negromatic - Settings"
  @user = current_user
  erb :settings
end

post '/settings' do
  protected!
  @user = current_user
  
  email = params[:email]
  password = params[:password]
  password_confirmation = params[:password_confirmation]

  update_params = { email: email }

  if password.to_s.strip != "" || password_confirmation.to_s.strip != ""
    if password == password_confirmation
      update_params[:password] = password
    else
      flash[:error] = "Passwords do not match"
      return erb :settings
    end
  end

  if @user.update(update_params)
    flash[:notice] = "Account updated successfully"
    redirect '/settings'
  else
    flash[:error] = "Error updating account: #{@user.errors.full_messages.join(', ')}"
    erb :settings
  end
end

# API Routes
namespace '/api' do
  # Webhook endpoint for incoming messages from various providers
  post '/webhooks/:provider/:token' do
    provider = params[:provider]
    # In a real app, verify the token
    
    payload = JSON.parse(request.body.read) rescue {}
    
    # Logic to find the channel and assistant based on payload/provider
    # channel = Channel.find_by(...)
    # if channel
    #   contact = channel.client.receive_message(payload)
    #   channel.assistant.process_message(contact, channel, payload['body']) if contact
    # end
    
    json success: true
  end
end
