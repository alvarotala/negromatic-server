

require_relative './libs/boot'
require_relative './libs/ai'
require_relative './libs/scheduler'


require 'http'
require 'openssl'
require 'socket'
require 'base64'
require 'securerandom'

require 'sinatra'
require 'sinatra/json'
require 'sinatra/namespace'
require 'sinatra/reloader'
require 'sinatra/content_for'
require 'sinatra/flash'

class ActiveRecordQueryCacheMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    ActiveRecord::Base.cache { @app.call(env) }
  end
end

class ActiveRecordConnectionManagementMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  ensure
    # Always return checked-out connections to the pool, even on exceptions.
    ActiveRecord::Base.connection_handler.clear_active_connections!
  end
end

# Configure Sinatra for development environment
configure :development do
  register Sinatra::Reloader
  # Reload all models in libs/models
  Dir[File.join(__dir__, 'libs', 'models', '**', '*.rb')].each { |file| also_reload file }
end

# Enable sessions for authentication
set :session_secret, ENV['SESSION_SECRET'] || SecureRandom.hex(64)
enable :sessions

# Set Sinatra server configurations
set :bind, ENV['bind'] || '0.0.0.0'
set :port, ENV['port']&.to_i || 3010
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')
# Silence Sinatra/Rack access logs
disable :logging
# Attempt to silence handler-specific access logs (e.g., WEBrick)
set :server_settings, AccessLog: []

# Set allowed HTTP methods and headers for CORS
before do   
  headers 'Access-Control-Allow-Origin' => '*', 
          'Access-Control-Allow-Methods' => ['OPTIONS', 'HEAD', 'GET', 'POST']
end

use ActiveRecordQueryCacheMiddleware
use ActiveRecordConnectionManagementMiddleware

# Authentication helpers
helpers do
  def logged_in?
    !session[:user_id].nil?
  end

  def current_user
    @current_user ||= User.find(session[:user_id]) if logged_in?
  end

  def protected!
    unless logged_in?
      flash[:error] = "Please log in to access this page"
      redirect '/login'
    end
  end

  def time_ago_in_words(time)
    return "never" unless time
    diff = Time.now - time
    if diff < 60
      "#{diff.to_i}s"
    elsif diff < 3600
      "#{(diff / 60).to_i}m"
    elsif diff < 86400
      "#{(diff / 3600).to_i}h"
    else
      "#{(diff / 86400).to_i}d"
    end
  end
end

require_relative './libs/routes'
