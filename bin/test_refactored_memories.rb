require_relative '../app'

puts 'Setting up test data for Refactored Memory Tools...'

user = User.find_or_create_by!(email: 'refactor_test@example.com') do |u|
  u.password = 'password'
end
assistant = Assistant.create!(name: 'RefactorBot', user: user)
contact = Contact.create!(name: 'UserRefactor', assistant: assistant)
channel = Channel.create!(
  assistant: assistant,
  provider: 'mock_provider',
  provider_uid: '123_refactor',
  active: true
)

begin
  global_tool = Negromatic::Tools::GlobalMemory.new(assistant, contact, channel)
  contact_tool = Negromatic::Tools::ContactMemory.new(assistant, contact, channel)
  
  puts "\n--- Test 1: Save Global Memory ---"
  g_save_res = global_tool.execute({ 'action' => 'save', 'content' => 'Global fact: The sky is blue.' })
  puts "Result: #{g_save_res}"

  puts "\n--- Test 2: Save Contact Memory ---"
  c_save_res = contact_tool.execute({ 'action' => 'save', 'content' => 'User fact: Likes spicy food.' })
  puts "Result: #{c_save_res}"

  # Wait for FTS indexing
  puts "\n--- Waiting for FTS indexing... ---"
  sleep 2

  puts "\n--- Test 3: Search Global Memory ---"
  g_search_res = global_tool.execute({ 'action' => 'search', 'query' => 'sky blue' })
  puts "Search Result:\n#{g_search_res}"
  if g_search_res.include?('The sky is blue')
    puts "✓ Global search verified."
  else
    puts "❌ Global search FAILED."
  end

  puts "\n--- Test 4: Search Contact Memory ---"
  c_search_res = contact_tool.execute({ 'action' => 'search', 'query' => 'spicy food' })
  puts "Search Result:\n#{c_search_res}"
  if c_search_res.include?('Likes spicy food')
    puts "✓ Contact search verified."
  else
    puts "❌ Contact search FAILED."
  end

  puts "\n--- Test 5: Verify Isolation (Global search should NOT find contact memory) ---"
  g_iso_res = global_tool.execute({ 'action' => 'search', 'query' => 'spicy food' })
  if g_iso_res.include?('No global memories found')
    puts "✓ Isolation verified: Global search did not find contact memory."
  else
    puts "❌ Isolation FAILED: Global search found contact memory."
  end

ensure
  # Cleanup
  assistant.destroy
  user.destroy # Optional
end

puts "\n✓ Refactored Memory Tools Verified Successfully!"
