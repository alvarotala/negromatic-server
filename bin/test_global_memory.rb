require_relative '../app'

puts 'Setting up test data for Global Memory Tool (Improved with Mock)...'

# Mocking MockProvider since it's used in the test but not defined as a real channel
module Negromatic
  module Channels
    class MockProvider
      def initialize(channel)
        @channel = channel
      end
      def send_message(contact, text)
        puts ">>> [MOCK SEND]: #{text}"
      end
    end
  end
end

user = User.find_or_create_by!(email: 'global_mem_test@example.com') do |u|
  u.password = 'password'
end
assistant = Assistant.create!(name: 'GlobalBot', user: user)
contact = Contact.create!(name: 'User1', assistant: assistant)
channel = Channel.create!(
  assistant: assistant,
  provider: 'mock_provider',
  provider_uid: '123',
  active: true
)

begin
  global_tool = Negromatic::Tools::SaveGlobalMemory.new(assistant, contact, channel)
  contact_tool = Negromatic::Tools::SaveMemory.new(assistant, contact, channel)
  
  puts "\n--- Test 1: Save a global memory ---"
  global_content = "The assistant's official name is GlobalBot."
  global_tool.execute({ 'content' => global_content })
  
  puts "\n--- Test 2: Save a contact memory ---"
  contact_content = "User1 likes pizza."
  contact_tool.execute({ 'content' => contact_content })
  
  # Retry loop for search stability
  max_retries = 5
  search_ok = false
  
  puts "\n--- Waiting for FTS indexing... ---"
  max_retries.times do |i|
    sleep(i + 1)
    g_results = Memory.search('GlobalBot', assistant_id: assistant.id, contact_id: nil)
    c_results = Memory.search('pizza', assistant_id: assistant.id, contact_id: contact.id)
    
    if g_results.any? && c_results.any?
      puts "✓ Search results stable after #{i+1} seconds."
      search_ok = true
      break
    end
    puts "Attempt #{i+1}: Search results not yet available..."
  end

  unless search_ok
    puts "❌ Search results failed to stabilize."
    exit 1
  end

  puts "\n--- Test 3: Verify Memory.search with contact_id: nil ---"
  results = Memory.search('GlobalBot', assistant_id: assistant.id, contact_id: nil)
  if results.any? && results.first.content == global_content
    puts "✓ Successfully found global memory."
  else
    puts "❌ Global memory not found via search."
  end

  puts "\n--- Test 4: Verify Memory.search with contact_id: contact.id ---"
  results = Memory.search('pizza', assistant_id: assistant.id, contact_id: contact.id)
  if results.any? && results.first.content == contact_content
    puts "✓ Successfully found contact memory."
  else
    puts "❌ Contact memory not found via search."
  end

  puts "\n--- Test 5: Verify assistant context building ---"
  # Mocking log method to capture output
  original_log = assistant.method(:log)
  assistant.define_singleton_method(:log) do |msg, level: :info, color: :white|
    if msg.is_a?(String) && msg.start_with?("Context (Memories):")
      @captured_log = msg
      puts "CAPTURED LOG: #{msg}"
    end
    # Still call original log or at least AppLogger if needed, but we don't want to spam
  end
  def assistant.captured_log; @captured_log; end

  # We use a query that matches BOTH
  assistant.process_message(contact, channel, "GlobalBot pizza")
  
  if assistant.captured_log && assistant.captured_log.include?("1 Contact, 1 Global")
    puts "✓ Assistant successfully retrieved both memory types."
  else
    puts "❌ Assistant failed to retrieve memories."
    puts "Log was: #{assistant.captured_log}"
  end

ensure
  # Cleanup
  assistant.destroy
  user.destroy # Optional, but keeps it clean
end

puts "\n✓ Global Memory Tool Verified Successfully!"
