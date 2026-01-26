# ⚡ Tradero: The AI-First Trading Infrastructure

Tradero isn't just another trading bot. It's a **Bot Creator Platform** that bridges the gap between your trading intuition and machine-speed execution. Define your own logic in plain English, and let specialized LLMs (like Grok-4) act as your disciplined 24/7 executor.

---

## 🚀 Why Tradero?

- **🧠 Your Logic, AI-Executed**: Stop fighting with rigid code. Describe your strategy (leverage, risk rules, entry conditions) in plain text. The AI reads it, analyzes the market, and follows your rules strictly.
- **🛡️ Built-in Risk Guardrails**: Designed with a "risk-first" mindset. Keep your margin ratios tight (e.g., ~2%) and let the bot handle the complex math of position sizing and averaging.
- **🌐 Multi-Exchange Roadmap**: 
  - ✅ **BingX Futures** (Currently Supported via Chrome Extension)
  - ✅ **BingX Futures (API)** (Supported via `binx_api` extension type)
  - 🔜 **Binance Futures** (Coming Soon)
  - 🗺️ **Spot, Stocks, & Forex** (On the horizon)
- **💬 Sentiment Aware**: Integrate real-time X (Twitter) and news sentiment to adjust aggression. Doubling down when the hype is high or cooling off during red flags.

---

## 🛠️ How it Works

1. **Link the Bridge**: Use our Chrome Extension to link your exchange session to the Tradero server.
   - Alternatively, link a `binx_api` extension to connect via BingX API keys (server-side polling + action execution).
2. **Define the Playbook**: Write your strategy in the Dashboard. No Python or PineScript required.
3. **Select Your Assets**: Choose which symbols the bot should watch.
4. **Execute**: The server periodically polls your account status and asks the AI: *"Based on these rules and this market, what's the next move?"*

---

## ⚙️ Getting Started

### Prerequisites

- **Ruby**: 3.1+
- **PostgreSQL**
- **Docker & Docker Compose** (Recommended)

### Quick Setup (Docker)

The fastest way to get Tradero running:

1. **Environment**:
   ```bash
   cp .env.example .env
   # Add your GROK_API_KEY and other credentials
   ```

2. **Launch**:
   ```bash
   docker-compose up --build
   ```

3. **Initialize**:
   ```bash
   # In a new terminal
   docker-compose exec web bundle exec rake db:migrate
   docker-compose exec web bundle exec rake db:populate
   ```

4. **Go!**: Open [http://localhost:3010](http://localhost:3010)

### Useful Docker commands

# Follow logs
docker compose logs -f web
# Or all services:
docker compose logs -f

# Open a shell in the web container
docker compose exec web bash
# If bash is not available:
docker compose exec web sh

---

## 📂 Project Structure

- `app.rb`: Main Sinatra application core.
- `libs/ai.rb`: The brain. Handles LLM prompting and advice parsing.
- `libs/routes.rb`: Web and API endpoint definitions.
- `views/`: Modern, dark-themed ERB templates powered by Bootstrap 5.
- `docs/`: Strategy role templates and documentation.

---

## ⚠️ Disclaimer

Not financial advice. Tradero is a tool for automation. Futures trading involves significant risk of loss. Always test your strategies with small amounts first and never trade money you cannot afford to lose.

---

Built for traders who want to automate their intuition. ⚡
