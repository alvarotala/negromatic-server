# frozen_string_literal: true

class Memory < ActiveRecord::Base
  belongs_to :assistant
  belongs_to :contact, optional: true

  validates :content, presence: true

  # Simple text-based search (fallback since Grok doesn't have embeddings yet)
  def self.search(query, assistant_id:, contact_id: nil, limit: 5)
    memories = where(assistant_id: assistant_id)
    memories = memories.where(contact_id: contact_id) if contact_id
    
    # Using PostgreSQL full-text search if available, otherwise LIKE
    # For now, let's use a simple ILIKE search as a reliable fallback
    memories.where("content ILIKE ?", "%#{query}%")
            .order(created_at: :desc)
            .limit(limit)
  end
end
