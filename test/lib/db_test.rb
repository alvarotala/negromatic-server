require_relative '../test_helper'

class DatabaseConnectionTest < Minitest::Test
  def test_database_is_test
    db_name = ActiveRecord::Base.connection.current_database
    assert_match(/test/, db_name, "Database name should contain 'test', but was '#{db_name}'")
    refute_equal 'tradero', db_name, "Database should not be the production database 'tradero'"
  end
end
