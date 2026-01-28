require_relative 'libs/boot'
require 'securerandom'

desc "Show help and examples for all available commands"
task :help do
  puts "\nNegromatic Server - Available Commands"
  puts "======================================"
  puts "\nGeneral:"
  puts "  rake start                 - Start the app in development mode"
  puts "  rake build                 - Full build: migrate, populate, and start"
  puts "  rake help                  - Show this help message"
  puts "\nDatabase (db namespace):"
  puts "  rake db:migrate            - Run the schema from schema.sql"
  puts "  rake db:populate           - Fill the database with sample data (assistants, channels, contacts)"
  puts "  rake db:reset              - Clear all interactions, contacts, and memories"
  puts "\nUser (user namespace):"
  puts "  rake \"user:create[email]\"  - Create a new supervisor user"
  puts "\nAI (ai namespace):"
  puts "  rake ai:chat               - Open an interactive console to chat with Grok"
  puts "\nExamples:"
  puts "  rake start port=3020"
  puts ""
end

task default: :help

desc "Start the app in development mode with Sinatra reloading"
task :start do
  ENV['APP_ENV'] = 'development'
  port = ENV['port'] || 3010
  puts "Starting Negromatic Server on port #{port} in development mode..."
  sh "bundle exec ruby app.rb"
end

desc "Build environment: migrate, populate, start"
task build: ['db:migrate', 'db:populate', :start]

namespace :db do
  desc "Execute schema.sql to update the database schema"
  task :migrate do
    db_config = ActiveRecord::Base.connection_db_config.configuration_hash

    puts "Connecting to #{db_config[:database]} using #{db_config[:adapter]}..."
    
    begin
      sql_content = File.read('schema.sql')
      statements = sql_content.split(';')
      
      ActiveRecord::Base.transaction do
        statements.each do |stmt|
          executable_content = stmt.gsub(/--.*$/, '').strip
          next if executable_content.empty?
          
          begin
            puts "Executing: #{executable_content.truncate(50)}..."
            ActiveRecord::Base.connection.execute(stmt)
          rescue => e
            puts "Error: Statement failed: #{e.message.truncate(200)}"
            # Don't raise here if it's "already exists" to keep it idempotent
            # raise e unless e.message.include?('already exists')
          end
        end
      end
      
      puts "Database migration task completed."
    rescue => e
      puts "Failed to connect or migrate: #{e.message}"
    end
  end

  desc "Populate database with sample data: assistants, channels, and contacts"
  task :populate do
    require_relative 'libs/boot'
    
    puts "Populating database with sample data..."
    
    # Create Supervisor
    user = User.find_or_initialize_by(email: 'admin@negromatic.io')
    user.password = 'alqp10'
    user.save
    puts "✓ Supervisor created: admin@negromatic.io"
    
    # Create Assistant: Jennifer
    jennifer = user.assistants.find_or_initialize_by(name: 'Jennifer')
    jennifer.identity = <<~TEXT
      You are Jennifer, a highly professional and friendly virtual assistant for 'Smile Bright Dental Clinic'.
      Your tone is empathetic, efficient, and welcoming. 
      You help patients schedule appointments, answer common questions about services (cleanings, whitening, braces), 
      and escalate complex medical questions to your supervisor.
    TEXT
    jennifer.global_memory = <<~TEXT
      Clinic Name: Smile Bright Dental
      Hours: Mon-Fri 9am-6pm, Sat 10am-2pm.
      Services: General Dentistry, Orthodontics, Cosmetic Whitening.
      Emergency: Call 555-0199 after hours.
    TEXT
    jennifer.save
    puts "✓ Assistant created: Jennifer"

    # Create Channels
    whatsapp = jennifer.channels.find_or_initialize_by(provider: 'whatsapp')
    whatsapp.provider_uid = '1234567890'
    whatsapp.config = { session: 'default' }
    whatsapp.save
    
    telegram = jennifer.channels.find_or_initialize_by(provider: 'telegram')
    telegram.provider_uid = 'bot_token_sample'
    telegram.config = { supervisor_chat_id: '987654321' }
    telegram.save
    puts "✓ Channels created: WhatsApp & Telegram"
    
    # Create sample contacts
    # Create sample contacts
    contact1 = Contact.resolve(jennifer, 'whatsapp', '555-1234', { 
      name: 'John Doe', 
      memory: 'Has a mild fear of dentists. Prefers morning appointments. Interested in whitening.' 
    })
    
    contact2 = Contact.resolve(jennifer, 'whatsapp', '555-9876', { 
      name: 'Alice Smith', 
      memory: 'Existing patient. Son (Leo) has braces.' 
    })
    puts "✓ Sample contacts created"
    
    # Create some sample interactions
    Interaction.create!(
      assistant: jennifer,
      contact: contact1,
      channel: whatsapp,
      direction: 'inbound',
      content: 'Hi, do you have any openings for a cleaning next Tuesday?'
    )
    Interaction.create!(
      assistant: jennifer,
      contact: contact1,
      channel: whatsapp,
      direction: 'outbound',
      content: 'Hello John! Yes, I have an opening at 10:00 AM. Would that work for you?'
    )
    puts "✓ Sample interactions logged"
    
    puts "\nNegromatic database populated successfully!"
  end

  desc "Reset interactions, contacts, and memories"
  task :reset do
    require_relative 'libs/boot'

    puts "Resetting interactions, contacts, memories, and scheduled tasks..."
    Interaction.delete_all
    Contact.delete_all
    Memory.delete_all
    ScheduledTask.delete_all
    puts "✓ Reset complete."
  end
end

namespace :user do
  desc "Create a new supervisor user"
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
      puts "✓ Supervisor created: #{email}"
      puts "  Password: #{password} (Please save this now)"
    else
      puts "✗ Failed to create user: #{user.errors.full_messages.join(', ')}"
    end
  end
end

namespace :ai do
  desc "Open an interactive console to chat with Grok"
  task :chat do
    require_relative 'libs/boot'
    require_relative 'libs/ai'

    pastel = Pastel.new

    puts pastel.bold.cyan("🤖 Grok Chat Console (Negromatic)")
    puts pastel.dim("Type your messages. Press Ctrl+D (or type '\\send') to send. Type '\\exit', or '\\quit' to end.")
    puts pastel.dim("=" * 70)

    messages = []
    is_interactive = STDIN.tty?

    loop do
      print pastel.bold.green("\nYou: ")
      input_lines = []

      loop do
        line = $stdin.gets
        break if line.nil?
        line = line.chomp
        if ['\exit', '\quit'].include?(line.downcase.strip)
          puts pastel.bold.yellow("\n👋 Goodbye!")
          exit 0
        end
        break if line.downcase.strip == '\send'
        input_lines << line
      end

      input = input_lines.join("\n").strip
      next if input.strip.empty?

      messages << { role: 'user', content: input }
      print pastel.bold.blue("Grok: ")
      
      # Using the existing AI.chat method which defaults to Grok
      response = AI.chat(messages: messages)

      if response[:response].start_with?("[error]")
        puts pastel.red("❌ Error: #{response[:response]}")
      else
        puts pastel.cyan(response[:response])
      end

      messages << { role: 'assistant', content: response[:response] }
      puts pastel.dim("\n⏱️  [Duration: #{response[:duration_ms]}ms | Tokens: #{response[:tokens]}]")
      break unless is_interactive
    end
  end
end

namespace :channel do
  desc "Chat with an assistant via CLI using an existing Channel UID. Usage: rake \"channel:cli[custom-uid]\""
  task :cli, [:uid] do |t, args|
    require_relative 'libs/boot'
    require_relative 'libs/ai'
    
    uid = args[:uid]
    
    if uid.nil? || uid.empty?
      puts "❌ Error: Please provide a Channel UID. \nUsage: rake \"channel:cli[my-cli-uid]\""
      exit 1
    end

    # Find existing Channel by UID (must be 'cli' provider)
    channel = Channel.find_by(provider: 'cli', provider_uid: uid)
    
    unless channel
      puts "❌ Channel with UID '#{uid}' not found."
      puts "   Please create a CLI channel for your assistant first via the web dashboard."
      exit 1
    end

    assistant = channel.assistant
    
    pastel = Pastel.new
    puts pastel.bold.cyan("\n🤖 Entering CLI Chat Mode with #{assistant.name} (UID: #{uid})")
    puts pastel.dim("Type your message and press Enter. Type '\\exit' to quit.")
    puts pastel.dim("--------------------------------------------------")
    
    # Simple REPL
    loop do
      print pastel.bold.yellow("You: ")
      input = $stdin.gets&.chomp
      
      break if input.nil? || ['\exit', '\quit', 'exit', 'quit'].include?(input.downcase.strip)
      next if input.strip.empty?
      
      # Process message
      # 1. Receive (this logs inbound)
      cli_client = Negromatic::Channels::Cli.new(channel)
      contact = cli_client.receive_message(
        'text' => input,
        'sender_id' => 'cli-user',
        'sender_name' => 'Developer'
      )
      
      # 2. Process (Assistant logic)
      assistant.process_message(contact, channel, input)
    end
    
    puts pastel.bold.cyan("\n👋 Goodbye!")
  end
end
