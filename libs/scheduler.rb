require 'rufus-scheduler'

require_relative './extensions/binx_api'

scheduler = Rufus::Scheduler.new

# Task to check for expired extensions every minute
scheduler.every '1m' do
  ActiveRecord::Base.connection_pool.with_connection do
    begin
      # Find extensions that haven't been updated
      threshold = 2.minute.ago
      
      expired_extensions = Extension.where('updated_at < ?', threshold)
                                    .where(connected: true)
      
      if expired_extensions.any?
        count = expired_extensions.count
        expired_extensions.update_all(status: 'idle', connected: false, updated_at: Time.now)
        puts "[Scheduler] Set #{count} expired extensions to idle"
      end
    rescue => e
      puts "[Scheduler] Error: #{e.message}"
    end
  end
end

# BINX API extension (server-side polling + action execution)
#
# For `ex_type: binx_api` we:
# - poll BingX for balance/positions/price
# - feed the data into the same ingest pipeline as `/api/ticker`
# - execute any pending AI actions directly via the BingX API
scheduler.every '1m' do
  ActiveRecord::Base.connection_pool.with_connection do
    BinxApi::Runner.tick_all!
  rescue => e
    puts "[Scheduler] binx_api error: #{e.message}"
  end
end

# Task to check for expired assets every 1 minute
scheduler.every '1m' do
  ActiveRecord::Base.connection_pool.with_connection do
    begin
      # Find assets_extensions that haven't been updated
      threshold = 2.minutes.ago
      
      expired_assets = AssetsExtension.where('last_activity_at < ?', threshold)
                                      .where(status: 'ready')
      
      if expired_assets.any?
        count = expired_assets.count
        expired_assets.update_all(status: 'idle')
        puts "[Scheduler] Set #{count} expired assets to idle"
      end
    rescue => e
      puts "[Scheduler] Assets Error: #{e.message}"
    end
  end
end
