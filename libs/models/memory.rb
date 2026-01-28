# frozen_string_literal: true

class Memory < ActiveRecord::Base
  belongs_to :assistant
  belongs_to :contact, optional: true

  validates :content, presence: true

  # Full-Text Search using PostgreSQL tsvector
  def self.search(query, assistant_id:, contact_id: nil, limit: 5)
    return [] if query.strip.empty?

    # Prepare the base scope
    scope = where(assistant_id: assistant_id)
    scope = scope.where(contact_id: contact_id) if contact_id

    # Sanitize query for websearch_to_tsquery (handles quotes, or, -negation)
    # We construct the function call string safely
    tsquery_func = "websearch_to_tsquery('english', #{connection.quote(query)})"

    # Perform the search
    # We iterate directly since binding a function call via ? sometimes quotes it as a string literal
    scope
      .where("search_vector @@ #{tsquery_func}")
      .order(Arel.sql("ts_rank(search_vector, #{tsquery_func}) DESC, created_at DESC"))
      .limit(limit)
  end
end
