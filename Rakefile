require_relative 'libs/boot'
require 'securerandom'

DEFAULT_STRATEGY_FILES = [
  { name: 'Close All With Any Profit Strategy', path: 'docs/close-all-with-any-profit.txt' },
  { name: 'Reach ≥ 2% Unrealized PnL Strategy', path: 'docs/reach-≥-2%-unrealized-PnL.txt' },
].freeze

def seed_global_strategies!
  DEFAULT_STRATEGY_FILES.each do |s|
    begin
      full_path = File.join(__dir__, s[:path])
      content = File.read(full_path)

      # Use user_id: nil to make it global/template
      strategy = Strategy.find_or_initialize_by(name: s[:name], user_id: nil)
      strategy.content = content
      strategy.active = false

      if strategy.save
        puts "✓ Global strategy created: #{strategy.name}"
      else
        puts "✗ Failed to create global strategy #{s[:name]}: #{strategy.errors.full_messages.join(', ')}"
      end
    rescue => e
      puts "✗ Failed to read/create global strategy #{s[:name]} from #{s[:path]}: #{e.message}"
    end
  end
end

desc "Show help and examples for all available commands"
task :help do
  puts "\nTrader Bot Server - Available Commands"
  puts "======================================"
  puts "\nGeneral:"
  puts "  rake start                 - Start the app in development mode"
  puts "  rake build                 - Full build: migrate, populate, and start"
  puts "  rake help                  - Show this help message"
  puts "\nDatabase (db namespace):"
  puts "  rake db:migrate            - Run the schema from tradero.sql"
    puts "  rake db:populate           - Fill the database with sample data (users, extensions, strategies)"
    puts "  rake db:seed_strategies    - Seed/update global recommended strategies only"
    puts "  rake db:reset              - Clear all positions, snapshots, and AI actions"
  puts "\nUser (user namespace):"
  puts "  rake \"user:create[email]\"  - Create a new user with a random password and default strategy"
  puts "\nAI (ai namespace):"
  puts "  rake ai:chat               - Open an interactive console to chat with the AI"
  puts "\nExamples:"
  puts "  rake start port=3020"
  puts ""
end

task default: :help

desc "Start the app in development mode with Sinatra reloading"
task :start do
  ENV['APP_ENV'] = 'development'
  port = ENV['port'] || 3010
  puts "Starting Trader Bot Server on port #{port} in development mode..."
  # Executing the app.rb with bundle exec to ensure all gems are loaded
  sh "bundle exec ruby app.rb"
end

desc "Build environment: migrate, populate, start"
task build: ['db:migrate', 'db:populate', :start]

namespace :db do
  desc "Execute tradero.sql to update the database schema"
  task :migrate do
    db_config = ActiveRecord::Base.connection_db_config.configuration_hash

    puts "Connecting to #{db_config[:database]} using #{db_config[:adapter]}..."
    
    begin
      sql_content = File.read('tradero.sql')
      
      # Naive split by semicolon. Note: MySQL/MariaDB dumps may contain semicolons in comments or strings.
      # For a more robust solution, one would use the client CLI tool, but this fulfills the request via Rake.
      statements = sql_content.split(';')
      
      ActiveRecord::Base.transaction do
        # Split by semicolon but preserve statements that might have leading comments
        # We filter out purely comment lines or empty statements
        statements.each do |stmt|
          # Remove comments from the statement for the purpose of checking if it's empty
          # but we can execute the whole thing as Postgres handles comments
          executable_content = stmt.gsub(/--.*$/, '').strip
          next if executable_content.empty?
          
          begin
            puts "Executing: #{executable_content.truncate(50)}..."
            ActiveRecord::Base.connection.execute(stmt)
          rescue => e
            puts "Error: Statement failed: #{e.message.truncate(200)}"
            raise e
          end
        end
      end
      
      puts "Database migration task completed."
    rescue => e
      puts "Failed to connect or migrate: #{e.message}"
    end
  end

  desc "Populate database with sample data: users, extensions, and strategies"
  task :populate do
    require_relative 'libs/boot'
    
    puts "Populating database with sample data..."
    
    # Create users
    user1 = User.find_or_initialize_by(email: 'admin@tradero.com')
    user1.password = '12345'
    user1.save
    puts "✓ User created: admin@tradero.com"
    
    # Create extensions for user1
    ext1 = user1.extensions.find_or_initialize_by(uuid: 'sample-extension-uuid-001')
    ext1.account = 'Main Trading Account'
    ext1.ex_type = 'binx'
    ext1.status = 'idle'
    ext1.connected = false
    ext1.save
    puts "✓ Extension created: #{ext1.account}"

    # Sample BINX API extension (server-side polling)
    ext2 = user1.extensions.find_or_initialize_by(uuid: 'sample-binx-api-uuid-001')
    ext2.account = 'Main Trading Account (API)'
    ext2.ex_type = 'binx_api'
    ext2.status = 'idle'
    ext2.connected = false
    ext2.save
    puts "✓ Extension created: #{ext2.account}"
    
    # Create global strategies (recommended templates)
    seed_global_strategies!
    
    # Create assets
    coins = [
      'BTC-USDT', 'ETH-USDT', 'SOL-USDT', 'XRP-USDT', 'ADA-USDT',
      'DOGE-USDT', 'AVAX-USDT', 'DOT-USDT', 'LINK-USDT', 'POL-USDT',
      'SHIB-USDT', 'BCH-USDT', 'LTC-USDT', 'TRX-USDT', 'UNI-USDT',
      'ATOM-USDT', 'XLM-USDT', 'NEAR-USDT', 'APT-USDT', 'OP-USDT'
    ]

    coins.each do |coin|
      [
        { ex_type: 'binx', name: 'Binx Futures Perp' },
        { ex_type: 'binx_api', name: 'Binx API Futures Perp' }
      ].each do |cfg|
        asset = Asset.find_or_initialize_by(value: coin, ex_type: cfg[:ex_type])
        asset.name = cfg[:name]
        asset.url = "https://bingx.com/en/perpetual/#{coin}"
        asset.save
      end
    end
    puts "✓ Created #{coins.size * 2} crypto assets (binx + binx_api)"
    
    # Link some assets to the extensions
    ext1.assets = Asset.where(ex_type: 'binx', value: ['BTC-USDT', 'ETH-USDT', 'SOL-USDT', 'DOGE-USDT'])
    ext2.assets = Asset.where(ex_type: 'binx_api', value: ['BTC-USDT', 'ETH-USDT', 'SOL-USDT', 'DOGE-USDT'])
    puts "✓ Linked sample assets to extensions: #{ext1.account} + #{ext2.account}"

    # Create sample positions
    puts "Creating sample positions..."
    Position.destroy_all # Clear existing sample positions
    
    ext1 = user1.extensions.first

    positions_data = [
      { symbol: 'BTC-USDT', side: 'long', amount: 0.05, status: 'open', info: { margin: 100, unrealizedPnl: 1.5, unrealizedPnlPercentage: 0.15 } },
      { symbol: 'ETH-USDT', side: 'short', amount: 1.2, status: 'open', info: { margin: 50, unrealizedPnl: -0.5, unrealizedPnlPercentage: -0.1 } },
      { symbol: 'SOL-USDT', side: 'long', amount: 25.0, status: 'open', info: { margin: 30, unrealizedPnl: 0.2, unrealizedPnlPercentage: 0.05 } },
      { symbol: 'XRP-USDT', side: 'long', amount: 1000.0, status: 'closed', realized_pnl: 12.5, realized_pnl_percentage: 1.25, closed_at: Time.now - 1.hour, info: { margin: 10 } },
      { symbol: 'ADA-USDT', side: 'short', amount: 500.0, status: 'closed', realized_pnl: -4.2, realized_pnl_percentage: -0.84, closed_at: Time.now - 5.hours, info: { margin: 5 } }
    ]

    positions_data.each_with_index do |data, i|
      asset = Asset.find_by(value: data[:symbol])
      next unless asset && ext1

      Position.create!(
        uuid: SecureRandom.uuid,
        asset_id: asset.id,
        extension_id: ext1.id,
        user_id: user1.id,
        amount: data[:amount],
        side: data[:side],
        status: data[:status] || 'open',
        realized_pnl: data[:realized_pnl] || 0,
        realized_pnl_percentage: data[:realized_pnl_percentage] || 0,
        info: data[:info],
        closed_at: data[:closed_at],
        last_activity_at: Time.now - (i * 60).seconds # Spaced by 1 minute
      )
    end
    puts "✓ Created 3 sample positions for the dashboard"
    
    puts "\nDatabase populated successfully!"
  end

  desc "Reset stats and positions"
  task :reset do
    require_relative 'libs/boot'

    puts "Resetting positions, equity snapshots, and AI actions..."
    Position.delete_all
    EquitySnapshot.delete_all
    AiAction.delete_all
    puts "✓ Reset complete."
  end

  desc "Seed global recommended strategies from docs/*.txt"
  task :seed_strategies do
    require_relative 'libs/boot'
    puts "Seeding global strategies..."
    seed_global_strategies!
    puts "✓ Seeding complete."
  end
end

namespace :user do
  desc "Create a new user and pre-populate with a strategy"
  task :create, [:email] do |t, args|
    require_relative 'libs/boot'
    require 'securerandom'

    email = args[:email]
    if email.nil? || email.empty?
      puts "Error: Please provide an email address. Usage: rake \"user:create[user@example.com]\""
      next
    end

    if User.exists?(email: email)
      puts "Error: User with email #{email} already exists."
      next
    end

    password = SecureRandom.hex(8)
    user = User.new(email: email)
    user.password = password

    if user.save
      puts "✓ User created: #{email}"
      puts "  Password: #{password} (Please save this now)"

    else
      puts "✗ Failed to create user: #{user.errors.full_messages.join(', ')}"
    end
  end
end

namespace :ai do
  desc "Open an interactive console to chat with the AI"
  task :chat do
    require_relative 'libs/boot'
    require_relative 'libs/ai'

    pastel = Pastel.new

    puts pastel.bold.cyan("🤖 AI Chat Console")
    puts pastel.dim("Type your messages. Press Ctrl+D (or type '\\send') to send. Type '\\exit', or '\\quit' to end.")
    puts pastel.dim("=" * 70)

    # Initialize conversation history in memory
    messages = []
    is_interactive = STDIN.tty?

    loop do
      print pastel.bold.green("\nYou: ")
      input_lines = []

      # Read multi-line input until EOF or /send command
      loop do
        line = $stdin.gets
        break if line.nil? # EOF

        line = line.chomp

        # Check for immediate exit commands
        if ['\exit', '\quit'].include?(line.downcase.strip)
          puts pastel.bold.yellow("\n👋 Goodbye!")
          exit 0
        end

        break if line.downcase.strip == '\send' # Send command

        input_lines << line
      end

      input = input_lines.join("\n").strip

      if input.strip.empty?
        next
      end

      # Add user message to history
      messages << { role: 'user', content: input }

      print pastel.bold.blue("AI: ")
      response = AI.chat(messages: messages)

      if response[:response].start_with?("[error]")
        puts pastel.red("❌ Error: #{response[:response]}")
      else
        puts pastel.cyan(response[:response])
      end

      # Add AI response to history
      messages << { role: 'assistant', content: response[:response] }

      # Display metadata
      puts pastel.dim("\n⏱️  [Duration: #{response[:duration_ms]}ms | Tokens: #{response[:tokens]}]")

      # In non-interactive mode (piped input), exit after one message
      break unless is_interactive
    end
  end
end
