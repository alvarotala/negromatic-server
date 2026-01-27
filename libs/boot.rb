require 'dotenv'
Dotenv.load(File.join(File.dirname(__dir__), '.env'))

require 'active_support/all'
require 'active_record'
require 'pastel'
require_relative 'logger'

# Establish ActiveRecord connection from .env
ActiveRecord::Base.establish_connection(
  adapter:  ENV['DB_ADAPTER'] || 'postgresql',
  host:     ENV['DB_HOST'] || 'localhost',
  database: ENV['DB_DATABASE'] || 'tradero',
  username: ENV['DB_USERNAME'],
  password: ENV['DB_PASSWORD']
)

# Silence ActiveRecord logs; only explicit puts will be shown
ActiveRecord::Base.logger = nil

# Load Channels
Dir[File.join(File.dirname(__dir__), 'libs', 'channels', '**', '*.rb')].each { |file| require file }

# Load ActiveRecord models
Dir[File.join(File.dirname(__dir__), 'libs', 'models', '**', '*.rb')].each { |file| require file }
