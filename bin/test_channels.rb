
require_relative '../app'
# require 'webmock' # We might not have webmock in the gemfile, but let's see. 
# If not, we can manually mock HTTParty. Let's start with manual mocking to avoid dependency hell.

puts "Setting up test data for Channels..."

# --- MANUAL MOCKING OF HTTPARTY ---
module MockHTTParty
  class << self
    attr_accessor :last_request
  end

  def post(url, options = {})
    puts "  -> [MOCK HTTP POST] URL: #{url}"
    puts "  -> [MOCK HTTP POST] Body: #{options[:body]}"
    MockHTTParty.last_request = { url: url, options: options }
    OpenStruct.new(success?: true, body: '{}')
  end
end

# Patch HTTParty globally
module HTTParty
  class << self
    def post(url, options = {})
      puts "  -> [MOCK HTTP POST] URL: #{url}"
      puts "  -> [MOCK HTTP POST] Body: #{options[:body]}"
      MockHTTParty.last_request = { url: url, options: options }
      OpenStruct.new(success?: true, body: '{}')
    end
  end
end

ActiveRecord::Base.transaction do
  user = User.create!(email: 'channel_test@example.com', password: 'password')
  assistant = Assistant.create!(name: 'ChannelBot', user: user)

  # --- TEST 1: TELEGRAM ---
  puts "\n--- Test 1: Telegram Channel ---"
  tg_channel = Channel.create!(
    assistant: assistant,
    provider: 'telegram',
    provider_uid: 'TG_BOT_1',
    config: { 'token' => '123:ABC', 'supervisor_chat_id' => '999' },
    active: true
  )
  
  contact_tg = Contact.create!(name: 'TG User', external_id: '1001', assistant: assistant)
  
  # Outbound Message
  puts "Testing send_message..."
  client = Negromatic::Channels::Telegram.new(tg_channel)
  client.send_message(contact_tg, "Hello Telegram")
  
  req = MockHTTParty.last_request
  raise "TG URL Mismatch" unless req[:url].include?('api.telegram.org/bot123:ABC/sendMessage')
  raise "TG Body ChatID Mismatch" unless req[:options][:body][:chat_id] == '1001'
  raise "TG Body Text Mismatch" unless req[:options][:body][:text] == 'Hello Telegram'
  puts "✓ Telegram Send Verified"

  # Supervisor Notification
  puts "Testing notify_supervisor..."
  client.notify_supervisor("Something fatal happened")
  
  req = MockHTTParty.last_request
  raise "TG Supervisor ChatID Mismatch" unless req[:options][:body][:chat_id] == '999'
  raise "TG Supervisor Text Mismatch" unless req[:options][:body][:text].include?('SUPERVISOR NOTIFICATION')
  puts "✓ Telegram Supervisor Verified"


  # --- TEST 2: WHATSAPP (WAHA) ---
  puts "\n--- Test 2: WhatsApp Channel ---"
  wa_channel = Channel.create!(
    assistant: assistant,
    provider: 'whatsapp',
    provider_uid: 'WA_BOT_1',
    config: { 'session' => 'mysession', 'supervisor_phone' => '15550001' },
    active: true
  )
  
  contact_wa = Contact.create!(name: 'WA User', external_id: '12345', assistant: assistant)
  
  # Outbound Message
  puts "Testing send_message..."
  client = Negromatic::Channels::Whatsapp.new(wa_channel)
  client.send_message(contact_wa, "Hello WhatsApp")
  
  req = MockHTTParty.last_request
  # Verify URL - we can't be sure of ENV but defaults to localhost
  raise "WA Body ChatID Mismatch" unless req[:options][:body].include?('12345@c.us')
  raise "WA Body Text Mismatch" unless req[:options][:body].include?('Hello WhatsApp')
  puts "✓ WhatsApp Send Verified"

  # Supervisor Notification
  puts "Testing notify_supervisor..."
  client.notify_supervisor("Escalation needed")
  
  req = MockHTTParty.last_request
  raise "WA Supervisor Phone Mismatch" unless req[:options][:body].include?('15550001@c.us')
  raise "WA Supervisor Text Mismatch" unless req[:options][:body].include?('SUPERVISOR NOTIFICATION')
  puts "✓ WhatsApp Supervisor Verified"


  # --- TEST 3: INSTAGRAM ---
  puts "\n--- Test 3: Instagram Channel ---"
  ig_channel = Channel.create!(
    assistant: assistant,
    provider: 'instagram',
    provider_uid: 'IG_PAGE_1',
    config: { 'access_token' => 'IG_TOKEN', 'page_id' => 'PAGE_1' },
    active: true
  )
  
  contact_ig = Contact.create!(name: 'IG User', external_id: 'IG_USER_1', assistant: assistant)
  
  # Outbound Message
  puts "Testing send_message..."
  client = Negromatic::Channels::Instagram.new(ig_channel)
  client.send_message(contact_ig, "Hello Instagram")
  
  req = MockHTTParty.last_request
  raise "IG Param AccessToken Mismatch" unless req[:options][:query][:access_token] == 'IG_TOKEN'
  raise "IG Body Recipient Mismatch" unless req[:options][:body][:recipient][:id] == 'IG_USER_1'
  puts "✓ Instagram Send Verified"


  # --- TEST 4: ASSISTANT NOTIFY SUPERVISOR (Generic) ---
  puts "\n--- Test 4: Assistant#notify_supervisor Logic ---"
  # This usually picks the FIRST channel that supports supervisor notification?
  # Or is it hardcoded to Telegram?
  # Let's check Assistant model code (reading it mentally from memory/previous cats)
  # It usually iterates or picks specific one.
  # Let's assume we want it to use the configured Telegram channel since it's the most common supervisor channel.
  
  # Create a scenario where only TG is active
  assistant.channels.destroy_all
  Channel.create!(
    assistant: assistant,
    provider: 'telegram',
    provider_uid: 'TG_BOT_2',
    config: { 'token' => 'XXX', 'supervisor_chat_id' => 'THE_BOSS' },
    active: true
  )
  
  assistant.notify_supervisor("Global Alert")
  
  req = MockHTTParty.last_request
  raise "Assistant Supervisor Routing Mismatch" unless req[:options][:body][:chat_id] == 'THE_BOSS'
  puts "✓ Assistant Generic Notification Verified"

  raise ActiveRecord::Rollback
end

puts "\n✓ All Channel Tests Passed!"
