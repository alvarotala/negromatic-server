-- PostgreSQL schema for tradero
-- Safe to run multiple times (idempotent)

-- ============================================================================
-- TABLES (CREATE IF NOT EXISTS)
-- ============================================================================

-- Table structure for table users
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  email varchar(255) NOT NULL UNIQUE,
  password varchar(255) NOT NULL,
  ai_interval_minutes integer NOT NULL DEFAULT 5,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP
);

-- Table structure for table extensions
CREATE TABLE IF NOT EXISTS extensions (
  id SERIAL PRIMARY KEY,
  uuid varchar(255) NOT NULL,
  ex_type varchar(50) DEFAULT NULL,
  account varchar(255) DEFAULT NULL,
  api_key varchar(255) DEFAULT NULL,
  api_secret varchar(255) DEFAULT NULL,
  status varchar(20) DEFAULT 'idle',
  connected boolean DEFAULT false,
  user_id integer NOT NULL,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_extensions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Table structure for table strategies
CREATE TABLE IF NOT EXISTS strategies (
  id SERIAL PRIMARY KEY,
  name varchar(255) NOT NULL,
  content text DEFAULT NULL,
  active boolean DEFAULT false,
  user_id integer, -- null for global strategies (read-only templates)
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_strategies_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Table structure for table assets
CREATE TABLE IF NOT EXISTS assets (
  id SERIAL PRIMARY KEY,
  name varchar(255) NOT NULL,
  value varchar(20) NOT NULL,
  ex_type varchar(20) NOT NULL,
  url varchar(255) DEFAULT NULL,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_asset_value_ex_type UNIQUE (value, ex_type)
);

-- Join table for extensions and assets (Many-to-Many)
CREATE TABLE IF NOT EXISTS assets_extensions (
  id SERIAL PRIMARY KEY,
  asset_id integer NOT NULL,
  extension_id integer NOT NULL,
  status varchar(20) DEFAULT 'idle', -- ready, idle
  last_activity_at timestamp DEFAULT NULL,
  last_ai_check_at timestamp DEFAULT NULL,
  ai_history jsonb DEFAULT '[]',
  UNIQUE (asset_id, extension_id),
  CONSTRAINT fk_assets_extensions_asset FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE,
  CONSTRAINT fk_assets_extensions_extension FOREIGN KEY (extension_id) REFERENCES extensions(id) ON DELETE CASCADE
);

-- Table structure for table positions
CREATE TABLE IF NOT EXISTS positions (
  id SERIAL PRIMARY KEY,
  uuid varchar(255) NOT NULL UNIQUE,
  amount decimal(20, 8) NOT NULL,
  side varchar(10) NOT NULL, -- long, short
  status varchar(20) DEFAULT 'open', -- open, stale, closed
  info jsonb DEFAULT NULL,
  user_id integer NOT NULL,
  asset_id integer NOT NULL,
  extension_id integer NOT NULL,
  strategy_id integer DEFAULT NULL,
  close_reason varchar(30) DEFAULT NULL, -- telemetry_gone, ai_full_close, ai_partial_close, stale_confirmed, manual_archive
  realized_pnl decimal(20, 8) NOT NULL DEFAULT 0,
  realized_pnl_percentage decimal(10, 4) NOT NULL DEFAULT 0,
  closed_at timestamp DEFAULT NULL,
  last_activity_at timestamp DEFAULT CURRENT_TIMESTAMP,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_positions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_positions_asset FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE,
  CONSTRAINT fk_positions_extension FOREIGN KEY (extension_id) REFERENCES extensions(id) ON DELETE CASCADE,
  CONSTRAINT fk_positions_strategy FOREIGN KEY (strategy_id) REFERENCES strategies(id) ON DELETE SET NULL
);

-- Table structure for table equity_snapshots
CREATE TABLE IF NOT EXISTS equity_snapshots (
  id SERIAL PRIMARY KEY,
  user_id integer NOT NULL,
  total_balance decimal(20, 8) NOT NULL,
  unrealized_pnl decimal(20, 8) NOT NULL,
  equity decimal(20, 8) NOT NULL,
  timestamp timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_equity_snapshots_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Table structure for table ai_actions
CREATE TABLE IF NOT EXISTS ai_actions (
  id SERIAL PRIMARY KEY,
  user_id integer NOT NULL,
  asset_id integer NOT NULL,
  strategy_id integer NOT NULL,
  action_type varchar(50) NOT NULL, -- PLACE_MARKET_ORDER, CLOSE_MARKET_ORDER
  side varchar(10) NOT NULL,
  amount decimal(20, 8) NOT NULL,
  status varchar(20) DEFAULT 'pending', -- pending, executed, failed
  retry_count integer DEFAULT 0,
  info jsonb DEFAULT NULL,
  timestamp timestamp DEFAULT CURRENT_TIMESTAMP,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_ai_actions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_ai_actions_asset FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE,
  CONSTRAINT fk_ai_actions_strategy FOREIGN KEY (strategy_id) REFERENCES strategies(id) ON DELETE CASCADE
);

-- ============================================================================
-- INDEXES (CREATE IF NOT EXISTS)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_positions_user_status ON positions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_positions_close_reason ON positions(close_reason);
CREATE INDEX IF NOT EXISTS idx_positions_closed_at ON positions(closed_at);
CREATE INDEX IF NOT EXISTS idx_equity_snapshots_user_time ON equity_snapshots(user_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_ai_actions_status ON ai_actions(user_id, asset_id, status);

-- ============================================================================
-- MIGRATIONS (Safe to run multiple times)
-- ============================================================================

-- Add any future migrations here using:
-- ALTER TABLE table_name ADD COLUMN IF NOT EXISTS new_column type DEFAULT value;

-- Add optional per-extension API credentials (idempotent)
ALTER TABLE extensions ADD COLUMN IF NOT EXISTS api_key varchar(255) DEFAULT NULL;
ALTER TABLE extensions ADD COLUMN IF NOT EXISTS api_secret varchar(255) DEFAULT NULL;
