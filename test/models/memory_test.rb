require_relative '../test_helper'

class MemoryTest < Minitest::Test
  def setup
    super
    @user = User.create!(email: 'mem_test@example.com', password: 'password')
    @assistant = Assistant.create!(name: 'MemBot', user: @user)
    @contact = Contact.resolve(@assistant, 'mock', '1001', name: 'User1')

    Memory.create!(assistant: @assistant, content: 'The user prefers coffee over tea.')
    Memory.create!(assistant: @assistant, content: 'The user hates waking up early.')
    Memory.create!(assistant: @assistant, content: 'The user has a dog named Rex.')
    Memory.create!(assistant: @assistant, content: 'Rex needs to go to the vet on Monday.')
    Memory.create!(assistant: @assistant, content: 'The user likes appointments in the afternoon.')
  end

  def test_keyword_search
    results = Memory.search('coffee', assistant_id: @assistant.id)
    assert results.any? { |m| m.content.include?('coffee') }, "Should find memory with keyword 'coffee'"
  end

  def test_contextual_search
    results = Memory.search('Rex vet', assistant_id: @assistant.id)
    # The search should return the memory about Rex and vet, and potentially the one about Rex.
    # We check if the most relevant one is there.
    assert results.any? { |m| m.content.include?('vet') }, "Should find memory with context 'Rex vet'"
  end

  def test_stopword_handling
    results = Memory.search('the user likes', assistant_id: @assistant.id)
    # This checks if it handles common words and focuses on 'likes'
    assert results.any? { |m| m.content.include?('afternoon') }, "Should find memory regarding 'likes' (appointments)"
  end
end
