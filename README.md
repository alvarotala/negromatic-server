# 🤖 Negromatic: The AI Virtual Assistant Orchestrator

Negromatic is a powerful platform designed to create, manage, and monitor autonomous virtual assistants. It bridges the gap between AI intelligence and real-world social interaction, allowing you to deploy specialized agents across multiple platforms like WhatsApp, Instagram, and Telegram.

Published at: [https://negromatic.contentor.io](https://negromatic.contentor.io)

---

## 🌟 The Vision

Negromatic isn't just a chatbot; it's a **Virtual Assistant Administrator**. It allows supervisors to orchestrate a fleet of AI agents, each with its own:

- **Identity**: Unique personality, tone of voice, and expertise (e.g., Jennifer, the Dental Clinic Assistant). Powered by **Grok-4**.
- **Memory**: 
  - **Contact Memory**: Personalized history for every person the assistant interacts with.
  - **Global Memory**: Knowledge base for the assistant's own identity and continuous learning.
  - *Note: Memory is currently implemented via PostgreSQL Full-Text Search as Grok does not natively provide an embeddings API yet.*
- **Tools**: Modular integrations with social networks and communication platforms.
- **Supervision**: Every assistant has a human supervisor who can be reached for confirmations, reporting, and monitoring.

### Example Use Case: Jennifer
Jennifer is a virtual assistant for a dental clinic. She:
1. Receives messages from Instagram or WhatsApp.
2. Identifies the user and creates/updates their contact profile.
3. Handles appointment scheduling autonomously.
4. Escalates to her supervisor via Telegram if she needs confirmation or encounters a complex request.

---

## 🛠️ Core Features

- **Multi-Platform Modular Design**: Abstracted integrations for WhatsApp, Instagram, Telegram, and more.
- **Supervisor Loop**: Assistants can "call home" to their supervisor for guidance or reporting.
- **Autonomous Content Creation**: Assistants can be tasked with posting images, creating promotional videos, or managing social media presence.
- **Real-time Monitoring**: Supervisors can view all active interactions and intervene when necessary.
- **MCP-Ready Architecture**: We leverage Model Context Protocol (MCP) to expose new tools and capabilities to our assistants dynamically.

---

## 🏗️ Project Roadmap

### Phase 1: Foundation (Completed)
- [x] Define Core Domain Models (Assistant, Supervisor, Contact, Interaction).
- [x] Implement the Supervisor Notification System.
- [x] Establish the Modular "Channel" Interface for social networks.

### Phase 2: Memory & Identity (Completed)
- [x] Implement Searchable Contact Memory (PostgreSQL-based).
- [x] Implement Global Identity Knowledge Base.
- [x] Develop the Identity Editor for supervisors.

### Phase 3: Social Integration (Completed)
- [x] Created an **MCP Server** (`bin/negromatic-mcp`) to expose social tools to AI agents.
- [x] Implemented **WhatsApp Module** using WAHA (WhatsApp HTTP API).
- [x] Implemented **Telegram Module** with Supervisor Notification support.
- [x] Implemented **Instagram Module** for DM automation.
- [x] Modular Channel Architecture established in `libs/channels/`.

### Phase 4: Media & Automation (Verified)
- [x] Integrated **Grok-2-image-gen** for automated image creation.
- [x] Implemented **Scheduled Tasks** system (`scheduled_tasks` table).
- [x] Added `generate_image` and `schedule_task` tools to the **MCP Server**.
- [x] Refactored **Background Scheduler** to handle automated social posts and follow-ups.

## ✅ Verification
We have established a suite of verification scripts to ensure system stability:
- `bin/test_ai_flow.rb`: Verifies core Assistant logic and tool use.
- `bin/test_memory_search.rb`: Verifies PostgreSQL Full-Text Search ranking.
- `bin/test_scheduler.rb`: Verifies automated task execution and media generation.
- `bin/test_channels.rb`: Verifies integration with Telegram, WhatsApp, and Instagram APIs.

For a detailed log of the implementation and verification process, see [docs/WALKTHROUGH.md](docs/WALKTHROUGH.md).

---

## ⚙️ Development

Negromatic is built with **Ruby & Sinatra**, running on **Docker**.

### Prerequisites
- Ruby 3.1+
- PostgreSQL
- Docker & Docker Compose

### Quick Start
1. **Setup Environment**:
   ```bash
   cp .env.example .env
   # Add your API keys and configuration
   ```
2. **Launch Services**:
   ```bash
   docker-compose up --build
   ```
3. **Initialize Database**:
   ```bash
   docker-compose exec web bundle exec rake db:migrate
   ```

---

## 📂 Architecture Note

The project is designed to be highly modular. Social networks are treated as "Channels" that can be plugged in or out. Business logic is separated from the transport layer, ensuring that adding a new social network is as simple as implementing a standard interface or adding a new MCP tool.

---

Built for those who want to scale human-like interaction with AI precision. ⚡
