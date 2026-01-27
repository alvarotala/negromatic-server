-- Negromatic Schema
-- ============================================================================

-- Table structure for table users (Supervisors)
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  email varchar(255) NOT NULL UNIQUE,
  password varchar(255) NOT NULL,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP
);

-- Table structure for table assistants
CREATE TABLE IF NOT EXISTS assistants (
  id SERIAL PRIMARY KEY,
  name varchar(255) NOT NULL,
  identity text DEFAULT NULL, -- The "Who am I" prompt
  global_memory text DEFAULT NULL, -- Long-term learning/knowledge
  user_id integer NOT NULL, -- The supervisor
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_assistants_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Table structure for table channels
-- Represents a social network integration for an assistant (WhatsApp, Telegram, etc.)
CREATE TABLE IF NOT EXISTS channels (
  id SERIAL PRIMARY KEY,
  assistant_id integer NOT NULL,
  provider varchar(50) NOT NULL, -- 'whatsapp', 'telegram', 'instagram'
  provider_uid varchar(255) NOT NULL, -- Unique ID in the provider (e.g., phone number, bot token)
  config jsonb DEFAULT '{}', -- Provider-specific configuration
  active boolean DEFAULT true,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_channels_assistant FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
  UNIQUE (assistant_id, provider)
);

-- Table structure for table contacts
-- Represents a person interacting with an assistant
CREATE TABLE IF NOT EXISTS contacts (
  id SERIAL PRIMARY KEY,
  external_id varchar(255) NOT NULL, -- ID from the social network (e.g., phone number)
  name varchar(255) DEFAULT NULL,
  profile_data jsonb DEFAULT '{}', -- Additional info scraped or gathered
  memory text DEFAULT NULL, -- Memory specific to this contact
  assistant_id integer NOT NULL,
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_contacts_assistant FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
  UNIQUE (assistant_id, external_id)
);

-- Table structure for table memories (Vector-based memory)
CREATE TABLE IF NOT EXISTS memories (
  id SERIAL PRIMARY KEY,
  content text NOT NULL,
  embedding jsonb DEFAULT NULL, -- Array of floats
  assistant_id integer NOT NULL,
  contact_id integer DEFAULT NULL, -- NULL for global assistant memory
  created_at timestamp DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_memories_assistant FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
  CONSTRAINT fk_memories_contact FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_memories_assistant_contact ON memories(assistant_id, contact_id);

-- Table structure for table interactions
-- Log of messages exchanged
CREATE TABLE IF NOT EXISTS interactions (
  id SERIAL PRIMARY KEY,
  contact_id integer NOT NULL,
  assistant_id integer NOT NULL,
  channel_id integer NOT NULL,
  direction varchar(10) NOT NULL, -- 'inbound', 'outbound'
  content text NOT NULL,
  metadata jsonb DEFAULT '{}', -- e.g., message type, platform-specific IDs
  timestamp timestamp DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_interactions_contact FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  CONSTRAINT fk_interactions_assistant FOREIGN KEY (assistant_id) REFERENCES assistants(id) ON DELETE CASCADE,
  CONSTRAINT fk_interactions_channel FOREIGN KEY (channel_id) REFERENCES channels(id) ON DELETE CASCADE
);
