require_relative '../libs/boot'

# Explicitly connect to the default DB (likely 'negromatic' or 'tradero' or user's default)
# We need to connect to a DB to create another DB. Usually 'postgres' is safe, or the one in .env.
config = ActiveRecord::Base.connection_db_config.configuration_hash

# We want to create this db
test_db_name = 'negromatic_test'

puts 'Connecting to maintenance database...'
# Connect to 'postgres' to create databases if possible, or stay connected to current if it allows creating
begin
  ActiveRecord::Base.establish_connection(config.merge(database: 'postgres'))
  ActiveRecord::Base.connection
rescue StandardError
  ActiveRecord::Base.establish_connection(config)
end

puts "Dropping #{test_db_name} if exists..."
begin
  ActiveRecord::Base.connection.drop_database(test_db_name)
rescue ActiveRecord::NoDatabaseError
  # ignore
rescue StandardError => e
  puts "Warning dropping db: #{e.message}"
end

puts "Creating #{test_db_name}..."
ActiveRecord::Base.connection.create_database(test_db_name)

puts "Connecting to #{test_db_name}..."
ActiveRecord::Base.establish_connection(config.merge(database: test_db_name))

puts 'Loading Schema...'
sql_content = File.read('schema.sql')
statements = sql_content.split(';')

ActiveRecord::Base.transaction do
  statements.each do |stmt|
    executable_content = stmt.gsub(/--.*$/, '').strip
    next if executable_content.empty?

    ActiveRecord::Base.connection.execute(stmt)
  end
end

puts 'Test database setup complete.'
