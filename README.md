# Antigravity Claude Code (anticc)

Use Claude Code with Antigravity models (Claude, Gemini, GPT) via CLIProxyAPI - no API keys needed, just your Google account.

## Architecture

```
Claude Code → CCR (3456) → CLIProxyAPI (8317) → Antigravity → Google AI
```

- **Free access** to Claude Opus 4.5, Sonnet 4.5, Gemini 3 Pro, GPT-OSS via Google OAuth
- **Multi-account rotation** - add multiple Google accounts to increase rate limits
- **MCP server support** - CCR handles model routing and schema normalization
- **Works with Claude Code** - seamless integration via environment variables

## Quick Start (One Command)

```bash
git clone https://github.com/YourUsername/antigravity-CC.git ~/antigravity-CC
cd ~/antigravity-CC
./setup.sh
```

The setup script will:
1. Install CLIProxyAPI (via Homebrew on macOS, direct download on Linux)
2. Install CCR (Claude Code Router) via npm
3. Generate an API key
4. Create config files
5. Add shell configuration to your terminal
6. Prompt you to login to Antigravity

### Requirements

- **macOS** or **Linux** (Windows via WSL)
- **Homebrew** (macOS) - for installing CLIProxyAPI
- **Node.js** - for CCR (auto-installed if missing)

## Manual Setup

If you prefer to set up manually:

### 1. Install CLIProxyAPI

**macOS (Homebrew):**
```bash
brew install router-for-me/tap/cliproxyapi
```

**Linux (Direct Download):**
```bash
VERSION=$(curl -sL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
curl -sL "https://github.com/router-for-me/CLIProxyAPI/releases/download/${VERSION}/CLIProxyAPI_Linux_${ARCH}.tar.gz" | tar xz
mkdir -p ~/.local/bin
mv CLIProxyAPI ~/.local/bin/cliproxyapi
chmod +x ~/.local/bin/cliproxyapi
export PATH="$HOME/.local/bin:$PATH"
```

### 2. Install CCR (Claude Code Router)

```bash
npm install -g @musistudio/claude-code-router
```

### 3. Create Config Files

```bash
cp config.example.yaml config.yaml
cp .env.example .env

# Generate API key
API_KEY=$(openssl rand -hex 24 | sed 's/^/sk-/')
echo "CLIPROXY_API_KEY=\"$API_KEY\"" > .env

# Update config.yaml with your key
sed -i '' "s/sk-your-api-key-here/$API_KEY/" config.yaml  # macOS
# sed -i "s/sk-your-api-key-here/$API_KEY/" config.yaml   # Linux
```

### 4. Add Shell Config

Add to `~/.zshrc` or `~/.bashrc`:

```bash
# Antigravity Claude Code (anticc)
source "$HOME/antigravity-CC/anticc.sh"
```

### 5. Login & Start

```bash
source ~/.zshrc
cliproxyapi --antigravity-login   # Opens browser for Google OAuth
brew services start cliproxyapi   # Start CLIProxyAPI (macOS)
ccr start                         # Start CCR
claude                            # Use Claude Code
```

## Available Commands

After sourcing `anticc.sh`:

| Command | Description |
|---------|-------------|
| `anticc-on` | Enable Antigravity mode (set env vars) |
| `anticc-off` | Disable Antigravity mode (unset env vars) |
| `anticc-status` | Check profile and service status |
| `anticc-help` | Show all commands |

### Service Management (External)

| Command | Description |
|---------|-------------|
| `brew services start cliproxyapi` | Start CLIProxyAPI (macOS) |
| `brew services stop cliproxyapi` | Stop CLIProxyAPI (macOS) |
| `ccr start` | Start CCR |
| `ccr stop` | Stop CCR |

## Available Models

| Model | Best For |
|-------|----------|
| `gemini-claude-opus-4-5-thinking` | Complex reasoning, architecture |
| `gemini-claude-sonnet-4-5-thinking` | General coding with thinking |
| `gemini-claude-sonnet-4-5` | Fast coding tasks |
| `gemini-3-pro-preview` | Large context (1M tokens) |
| `gemini-2.5-flash` | Quick responses |

## Multi-Account Rotation

Add multiple Google accounts to increase rate limits:

```bash
cliproxyapi --antigravity-login  # Add account 1
cliproxyapi --antigravity-login  # Add account 2
cliproxyapi --antigravity-login  # Add account 3
```

CLIProxyAPI rotates through accounts automatically when one hits rate limits.

## MCP Servers

CCR handles model routing so MCP servers work with Antigravity/Gemini backends.

### Supported MCP Servers

- **Firecrawl** - Web scraping
- **Context7** - Documentation lookup
- **Exa** - Web search

### Configure MCP Servers

Create `.mcp.json` in your project directory:

```json
{
  "mcpServers": {
    "firecrawl-mcp": {
      "command": "npx",
      "args": ["-y", "firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "your-firecrawl-key"
      }
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@context7/mcp"]
    }
  }
}
```

## Environment Variables

The `anticc.sh` script sets these automatically:

```bash
export ANTHROPIC_BASE_URL="http://127.0.0.1:3456"  # CCR port
export ANTHROPIC_API_KEY="sk-your-api-key"
export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-claude-sonnet-4-5-thinking"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-claude-sonnet-4-5"
```

## Files

| File | Description |
|------|-------------|
| `config.yaml` | CLIProxyAPI configuration |
| `anticc.sh` | Shell commands and environment setup |
| `setup.sh` | One-command setup script |

## Troubleshooting

### Check service status

```bash
anticc-status  # Shows CLIProxyAPI, CCR, and profile status
```

### Rate limit errors

Add more Google accounts:

```bash
cliproxyapi --antigravity-login
```

### Model not found

Make sure you're using Antigravity model names (with `gemini-` prefix for Claude models).

### CCR not starting

Check if Node.js is installed:

```bash
node --version
npm --version
```

## Resources

- [CLIProxyAPI Docs](https://help.router-for.me/)
- [Antigravity Setup](https://help.router-for.me/configuration/provider/antigravity)
- [Claude Code Docs](https://docs.anthropic.com/claude-code)
- [CCR Package](https://www.npmjs.com/package/@musistudio/claude-code-router)

## License

MIT
