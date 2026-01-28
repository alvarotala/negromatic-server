require_relative '../app'

puts "Recreating database schema (Clean Unified Contacts)..."

# Drop tables to start fresh
ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS scheduled_tasks CASCADE")
ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS interactions CASCADE")
ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS memories CASCADE")
ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS contact_identities CASCADE")
ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS contacts CASCADE")
ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS channels CASCADE")
ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS assistants CASCADE")
ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS users CASCADE")

# Run schema.sql
sql = File.read('schema.sql')
ActiveRecord::Base.connection.execute(sql)

puts "Database Reset Complete."
