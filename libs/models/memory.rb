# frozen_string_literal: true

class Memory < ActiveRecord::Base
  belongs_to :assistant
  belongs_to :contact, optional: true

  validates :content, presence: true

  # Full-Text Search using PostgreSQL tsvector
  # contact_id: Integer (specific contact), Nil (global only), :any (all memories for assistant)
  def self.search(query, assistant_id:, contact_id: :any, limit: 5)
    return [] if query.strip.empty?

    # Prepare the base scope
    scope = where(assistant_id: assistant_id)
    
    if contact_id == :any
      # No additional filtering, search all memories for this assistant
    elsif contact_id.nil?
      scope = scope.where(contact_id: nil)
    else
      scope = scope.where(contact_id: contact_id)
    end

    # Sanitize query for websearch_to_tsquery (handles quotes, or, -negation)
    tsquery_func = "websearch_to_tsquery('english', #{connection.quote(query)})"

    # Perform the search
    scope
      .where("search_vector @@ #{tsquery_func}")
      .order(Arel.sql("ts_rank(search_vector, #{tsquery_func}) DESC, created_at DESC"))
      .limit(limit)
  end
end
