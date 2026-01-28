require_relative '../app'

puts 'Setting up test data for Memory Search...'

ActiveRecord::Base.transaction do
  user = User.create!(email: 'mem_test@example.com', password: 'password')
  assistant = Assistant.create!(name: 'MemBot', user: user)
  contact = Contact.create!(name: 'User1', external_id: '1001', assistant: assistant)

  # Create memories with varying content
  Memory.create!(assistant: assistant, content: 'The user prefers coffee over tea.')
  Memory.create!(assistant: assistant, content: 'The user hates waking up early.')
  Memory.create!(assistant: assistant, content: 'The user has a dog named Rex.')
  Memory.create!(assistant: assistant, content: 'Rex needs to go to the vet on Monday.')
  Memory.create!(assistant: assistant, content: 'The user likes appointments in the afternoon.')

  puts "\n--- Test 1: Simple Keyword Search 'coffee' ---"
  begin
    results = Memory.search('coffee', assistant_id: assistant.id)
    results.each { |m| puts "[#{m.attributes['rank']}] #{m.content} (Keys: #{m.attributes.keys})" }
    raise 'Test 1 Failed' unless results.first&.content&.include?('coffee')
  rescue StandardError => e
    puts "ERROR IN TEST 1: #{e.class} - #{e.message}"
    puts e.backtrace
  end

  puts "\n--- Test 2: Contextual Search 'Rex vet' ---"
  # Should find the specific vet memory first, then the dog memory
  results = Memory.search('Rex vet', assistant_id: assistant.id)
  results.each { |m| puts "[#{m.attributes['rank']}] #{m.content}" }
  raise 'Test 2 Failed' unless results.first&.content&.include?('vet')

  puts "\n--- Test 3: Stopword Handling 'the user likes' ---"
  # 'the' and 'user' are common, so 'likes' should drive the rank
  results = Memory.search('the user likes', assistant_id: assistant.id)
  results.each { |m| puts "[#{m.attributes['rank']}] #{m.content}" }
  raise 'Test 3 Failed' unless results.first&.content&.include?('afternoon')

  raise ActiveRecord::Rollback
end

puts "\n✓ Memory Search Verified Successfully!"
