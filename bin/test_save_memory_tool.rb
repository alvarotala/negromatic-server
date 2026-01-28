require_relative '../app'

puts 'Setting up test data for Save Memory Tool...'

ActiveRecord::Base.transaction do
  user = User.create!(email: 'save_mem_test@example.com', password: 'password')
  assistant = Assistant.create!(name: 'MemBot', user: user)
  contact = Contact.create!(name: 'User1', assistant: assistant)
  channel = Channel.create!(
    assistant: assistant,
    provider: 'mock_provider',
    provider_uid: '123',
    active: true
  )

  tool = Negromatic::Tools::SaveMemory.new(assistant, contact, channel)
  
  puts "\n--- Test 1: Save a simple memory ---"
  content = "The user's favorite color is blue."
  result = tool.execute({ 'content' => content })
  
  puts "Result: #{result}"
  
  saved_memory = Memory.where(assistant_id: assistant.id, contact_id: contact.id).last
  
  if saved_memory && saved_memory.content == content
    puts "✓ Successfully saved memory: #{saved_memory.content}"
  else
    puts "❌ Failed to save memory."
    puts "Expected: #{content}"
    puts "Got: #{saved_memory&.content || 'nil'}"
    exit 1
  end

  puts "\n--- Test 2: Verify memory persists and is searchable ---"
  search_results = Memory.search('color blue', assistant_id: assistant.id, contact_id: contact.id)
  if search_results.any? && search_results.first.content == content
    puts "✓ Successfully found memory via search."
  else
    puts "❌ Memory not found via search."
    exit 1
  end

  raise ActiveRecord::Rollback
end

puts "\n✓ Save Memory Tool Verified Successfully!"
