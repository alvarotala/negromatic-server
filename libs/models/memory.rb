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
    sanitized_query_sql = Arel.sql("websearch_to_tsquery('english', #{connection.quote(query)})")

    # Perform the search
    # We select the content and rank
    scope
      .where('search_vector @@ ?', sanitized_query_sql)
      #.select("memories.*, ts_rank(search_vector, #{sanitized_query_sql.to_sql}) AS search_rank")
      .order(Arel.sql("ts_rank(search_vector, #{sanitized_query_sql}) DESC, created_at DESC"))
      #.order('created_at DESC')
      .limit(limit)
  end
end
