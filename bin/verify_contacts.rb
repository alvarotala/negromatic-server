require_relative '../app'

puts "\n--- Verifying Unified Contact Logic (Refaction) ---\n"

ActiveRecord::Base.transaction do
  # Setup
  user = User.create!(email: 'verify@example.com', password: 'password')
  assistant = Assistant.create!(
    name: 'Verifier',
    identity: 'You are a test assistant.', 
    user: user
  )

  puts "1. Receiving message from WhatsApp (user: phone_123)"
  contact_a = Contact.resolve(assistant, 'whatsapp', 'phone_123', { name: "John WA" })
  contact_a.interactions.create!(
    assistant: assistant, 
    channel: Channel.create!(assistant: assistant, provider: 'whatsapp', provider_uid: 'bot_wa'),
    direction: 'inbound', 
    content: "Hello from WhatsApp" 
  )
  puts "   -> Contact A Created: ID=#{contact_a.id}, Name=#{contact_a.name}"
  puts "   -> Identities: #{contact_a.identities.map { |i| "#{i.provider}:#{i.external_id}" }.join(', ')}"

  puts "\n2. Receiving message from Instagram (user: insta_john)"
  contact_b = Contact.resolve(assistant, 'instagram', 'insta_john', { name: "John Insta" })
  contact_b.interactions.create!(
    assistant: assistant, 
    channel: Channel.create!(assistant: assistant, provider: 'instagram', provider_uid: 'bot_insta'), 
    direction: 'inbound', 
    content: "Hello from Instagram" 
  )
  puts "   -> Contact B Created: ID=#{contact_b.id}, Name=#{contact_b.name}"
  puts "   -> Identities: #{contact_b.identities.map { |i| "#{i.provider}:#{i.external_id}" }.join(', ')}"

  puts "\n3. Checking they are different"
  if contact_a.id != contact_b.id
    puts "   -> OK: Contacts are separate currently."
  else
    puts "   -> ERROR: Contacts are already same?"
  end

  puts "\n4. Linking Identity 'insta_john' (Instagram) to Contact A"
  # Simulating the tool usage
  tool = Negromatic::Tools::ManageContact.new(assistant, contact_a, nil)
  result = tool.execute({
    'action' => 'link_identity',
    'provider' => 'instagram',
    'external_id' => 'insta_john'
  })
  puts "   -> Tool Result: #{result}"

  puts "\n5. Verifying Merge"
  contact_a.reload
  puts "   -> Contact A Identities: #{contact_a.identities.map { |i| "#{i.provider}:#{i.external_id}" }.join(', ')}"
  
  # Check if Contact B is gone
  b_exists = Contact.exists?(contact_b.id)
  puts "   -> Contact B deleted? #{!b_exists}"

  # Check Interactions
  interaction_count = contact_a.interactions.count
  puts "   -> Contact A interactions: #{interaction_count} (Expected 2)"
  
  interactions = contact_a.interactions.order(:id).map { |i| "[#{i.direction}] #{i.content}" }
  puts "   -> History: #{interactions}"

  if interaction_count == 2 && !b_exists && contact_a.identities.count == 2
    puts "\n✅ SUCCESS: Contacts merged successfully with new schema."
  else
    puts "\n❌ FAILURE: Verification failed."
  end

  raise ActiveRecord::Rollback
end
