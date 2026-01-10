# Antigravity Claude Code (anticc)

Use Claude Code with Antigravity models (Claude, Gemini, GPT) via CLIProxyAPI - no API keys needed, just your Google account.

## Architecture

```
Claude Code → CCR (3456) → CLIProxyAPI (8317) → Antigravity → Google AI
```

- **Free access** to Claude Opus 4.5, Sonnet 4.5, Gemini 3 Pro, GPT-OSS via Google OAuth
- **Multi-account rotation** - add multiple Google accounts to increase rate limits
- **Auto-updates** - CLIProxyAPI is built from source and updated every 12 hours
- **Auto-rollback** - if an update breaks, it automatically rolls back to the previous version
- **MCP server support** - CCR handles model routing and schema normalization

## Quick Start

```bash
git clone https://github.com/YourUsername/antigravity-CC.git ~/antigravity-CC
cd ~/antigravity-CC
./setup.sh
```

The setup script will:
1. Check prerequisites (Go, Node.js, Git)
2. Clone CLIProxyAPI source and build from source
3. Install CCR (Claude Code Router) via npm
4. Generate an API key and create config files
5. Set up auto-start service (launchd on macOS, systemd on Linux)
6. Set up 12-hour auto-update (launchd timer on macOS, cron on Linux)
7. Add shell configuration to your terminal
8. Prompt you to login to Antigravity

### Requirements

| OS | Requirements |
|----|--------------|
| **macOS** | Go 1.24+, Node.js, Git (Homebrew recommended) |
| **Linux** | Go 1.24+, Node.js, Git, systemd (optional for auto-start) |
| **Windows** | Go 1.24+, Git, PowerShell 5+ (no Node.js needed!) |

---

## Windows Setup

Native Windows support is now available! No WSL required.

### Quick Start (Windows)

```powershell
# Clone the repo
git clone https://github.com/YourUsername/antigravity-CC.git $HOME\antigravity-CC
cd $HOME\antigravity-CC

# Run setup (as Administrator recommended for Task Scheduler)
.\setup-windows.ps1
```

The setup script will:
1. Check prerequisites (Go, Git)
2. Clone CLIProxyAPI source and build from source
3. Create config files and .env
4. Set up Task Scheduler for auto-start and 12-hour auto-update
5. Add anticc to your PowerShell profile
6. Start CLIProxyAPI

### Manual Setup (Windows)

```powershell
# 1. Install prerequisites
winget install Git.Git
winget install GoLang.Go

# 2. Clone this repo
git clone https://github.com/YourUsername/antigravity-CC.git $HOME\antigravity-CC
cd $HOME\antigravity-CC

# 3. Clone and build CLIProxyAPI
git clone https://github.com/router-for-me/CLIProxyAPIPlus.git cliproxy-source
cd cliproxy-source
$VERSION = git describe --tags --always
$COMMIT = git rev-parse --short HEAD
$env:CGO_ENABLED = "0"
go build -ldflags "-X main.Version=$VERSION -X main.Commit=$COMMIT" -o "$env:LOCALAPPDATA\Programs\CLIProxyAPI\cliproxyapi.exe" ./cmd/server
cd ..

# 4. Create config
Copy-Item config.example.yaml config.yaml
# Edit config.yaml with your settings

# 5. Create .env file
$API_KEY = "sk-" + -join ((48..57) + (97..122) | Get-Random -Count 48 | % {[char]$_})
"CLIPROXY_API_KEY=`"$API_KEY`"" | Out-File -FilePath .env -Encoding UTF8

# 6. Add to PowerShell profile
Add-Content -Path $PROFILE -Value '. "$HOME\antigravity-CC\anticc.ps1"'

# 7. Reload and start
. .\anticc.ps1
anticc-start
& "$env:LOCALAPPDATA\Programs\CLIProxyAPI\cliproxyapi.exe" --antigravity-login
```

### Windows Commands

All the same commands work in PowerShell:

```powershell
anticc-on              # Enable Antigravity mode (set env vars)
anticc-off             # Disable Antigravity mode (unset env vars)
anticc-status          # Show status
anticc-login           # Login to Antigravity (add Google account)
anticc-update          # Update to latest version
anticc-diagnose        # Full diagnostics
anticc-help            # Show all commands
```

### Windows Startup Commands

```powershell
anticc-enable-startup    # Start CLIProxyAPI on Windows login
anticc-disable-startup   # Disable startup on login
```

**Note:** Windows connects directly to CLIProxyAPI (no CCR required). The architecture is simpler:
```
Claude Code -> CLIProxyAPI (8317) -> Antigravity -> Google AI
```

### Windows Files

| File | Location |
|------|----------|
| Binary | `%LOCALAPPDATA%\Programs\CLIProxyAPI\cliproxyapi.exe` |
| Source | `<repo>\cliproxy-source\` |
| Config | `<repo>\config.yaml` |
| Logs | `%LOCALAPPDATA%\CLIProxyAPI\logs\` |
| Updater | `<repo>\cliproxy-updater.ps1` |

### Windows Task Scheduler

| Task | Description |
|------|-------------|
| `CLIProxyAPI-Startup` | Starts CLIProxyAPI on login |
| `CLIProxyAPI-AutoUpdate` | Auto-updates every 12 hours |

### Uninstalling (Windows)

```powershell
.\setup-windows.ps1 -Uninstall
```

Or manually:

```powershell
# Stop service
Stop-Process -Name cliproxyapi -Force

# Remove scheduled tasks
Unregister-ScheduledTask -TaskName "CLIProxyAPI-Startup" -Confirm:$false
Unregister-ScheduledTask -TaskName "CLIProxyAPI-AutoUpdate" -Confirm:$false

# Remove files
Remove-Item "$env:LOCALAPPDATA\Programs\CLIProxyAPI" -Recurse -Force
Remove-Item "$env:LOCALAPPDATA\CLIProxyAPI" -Recurse -Force

# Remove from PowerShell profile (edit $PROFILE manually)
```

---

## Migrating from Homebrew

If you previously installed CLIProxyAPI via Homebrew, follow these steps to migrate to the source-based setup:

### Step 1: Stop and Uninstall Brew Version

```bash
# Stop the brew service
brew services stop cliproxyapi

# Unload from launchd
launchctl unload ~/Library/LaunchAgents/homebrew.mxcl.cliproxyapi.plist 2>/dev/null

# Uninstall the brew package
brew uninstall cliproxyapi
```

### Step 2: Run the New Setup

```bash
cd ~/antigravity-CC  # or wherever you cloned this repo
git pull             # get latest changes
./setup.sh           # run the new setup
```

### Step 3: Verify Migration

```bash
source ~/.zshrc      # or ~/.bashrc
anticc-status        # should show services running
anticc-version       # should show source-built version
```

### What Changes After Migration

| Before (Brew) | After (Source) |
|---------------|----------------|
| Binary: `/opt/homebrew/bin/cliproxyapi` | Binary: `~/.local/bin/cliproxyapi` |
| Config: `/opt/homebrew/etc/cliproxyapi.conf` | Config: `~/antigravity-CC/config.yaml` |
| Service: `brew services start cliproxyapi` | Service: `anticc-start` |
| Updates: Wait for brew formula update | Updates: Auto every 12h or `anticc-update` |

---

## Manual Setup

### macOS

```bash
# 1. Install prerequisites
brew install go node git

# 2. Clone this repo
git clone https://github.com/YourUsername/antigravity-CC.git ~/antigravity-CC
cd ~/antigravity-CC

# 3. Clone and build CLIProxyAPI
git clone https://github.com/router-for-me/CLIProxyAPI.git cliproxy-source
cd cliproxy-source
VERSION=$(git describe --tags --always)
go build -ldflags "-X main.Version=$VERSION" -o ~/.local/bin/cliproxyapi ./cmd/server
cd ..

# 4. Install CCR
npm install -g @musistudio/claude-code-router

# 5. Create config
cp config.example.yaml config.yaml
API_KEY="sk-$(openssl rand -hex 24)"
sed -i '' "s/sk-your-api-key-here/$API_KEY/" config.yaml
echo "CLIPROXY_API_KEY=\"$API_KEY\"" > .env

# 6. Add to shell
echo 'source "$HOME/antigravity-CC/anticc.sh"' >> ~/.zshrc
source ~/.zshrc

# 7. Start and login
anticc-start
~/.local/bin/cliproxyapi --antigravity-login
ccr start
```

### Linux (Ubuntu/Debian)

```bash
# 1. Install prerequisites
sudo apt update
sudo apt install -y golang-go nodejs npm git curl

# 2. Clone this repo
git clone https://github.com/YourUsername/antigravity-CC.git ~/antigravity-CC
cd ~/antigravity-CC

# 3. Clone and build CLIProxyAPI
git clone https://github.com/router-for-me/CLIProxyAPI.git cliproxy-source
cd cliproxy-source
VERSION=$(git describe --tags --always)
go build -ldflags "-X main.Version=$VERSION" -o ~/.local/bin/cliproxyapi ./cmd/server
cd ..

# 4. Install CCR
sudo npm install -g @musistudio/claude-code-router

# 5. Create config
cp config.example.yaml config.yaml
API_KEY="sk-$(openssl rand -hex 24)"
sed -i "s/sk-your-api-key-here/$API_KEY/" config.yaml
echo "CLIPROXY_API_KEY=\"$API_KEY\"" > .env

# 6. Add to shell
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
echo 'source "$HOME/antigravity-CC/anticc.sh"' >> ~/.bashrc
source ~/.bashrc

# 7. Start and login
anticc-start
~/.local/bin/cliproxyapi --antigravity-login
ccr start
```

### Linux (Fedora/RHEL)

```bash
# 1. Install prerequisites
sudo dnf install -y golang nodejs npm git

# Then follow Ubuntu steps 2-7
```

### Linux (Arch)

```bash
# 1. Install prerequisites
sudo pacman -S go nodejs npm git

# Then follow Ubuntu steps 2-7
```

---

## Available Commands

After sourcing `anticc.sh`:

### Profile Commands

| Command | Description |
|---------|-------------|
| `anticc-on` | Enable Antigravity mode (route through CCR) |
| `anticc-off` | Direct mode (bypass CCR, connect to CLIProxyAPI) |
| `anticc-status` | Show service and profile status |
| `anticc-help` | Show all commands |

### Service Commands

| Command | Description |
|---------|-------------|
| `anticc-start` | Start CLIProxyAPI service |
| `anticc-stop-service` | Stop CLIProxyAPI service |
| `anticc-restart-service` | Restart CLIProxyAPI service |

### Update Commands

| Command | Description |
|---------|-------------|
| `anticc-version` | Show version info (running, binary, source, remote) |
| `anticc-update` | Pull latest source and rebuild immediately |
| `anticc-rollback` | Rollback to previous version if update fails |
| `anticc-enable-autoupdate` | Enable 12-hour auto-update |
| `anticc-disable-autoupdate` | Disable auto-update |

### Diagnostics

| Command | Description |
|---------|-------------|
| `anticc-diagnose` | Run full diagnostics |

---

## Auto-Update System

CLIProxyAPI is built from source and auto-updated every 12 hours:

```
┌─────────────────────────────────────────────────────────────┐
│  Scheduler (launchd/cron - every 12h)                       │
│  └── cliproxy-updater.sh                                    │
│      ├── git pull (fetch latest)                            │
│      ├── go build (compile)                                 │
│      ├── backup current binary                              │
│      ├── deploy new binary                                  │
│      ├── restart service                                    │
│      ├── health check                                       │
│      └── auto-rollback if health check fails                │
└─────────────────────────────────────────────────────────────┘
```

### Platform-Specific Implementation

| Platform | Auto-Start | Auto-Update |
|----------|------------|-------------|
| **macOS** | launchd (`com.cliproxy.api.plist`) | launchd timer (`com.cliproxy.updater.plist`) |
| **Linux** | systemd (`cliproxy.service`) or manual | cron job (every 12h) |
| **Windows** | Task Scheduler (`CLIProxyAPI-Startup`) | Task Scheduler (`CLIProxyAPI-AutoUpdate`) |

### Why Build from Source?

- Homebrew releases lag behind by hours/days
- Fast-moving project with frequent patches (400+ releases)
- Immediate access to bug fixes and new features

---

## Available Models

| Model | Best For |
|-------|----------|
| `gemini-claude-opus-4-5-thinking` | Complex reasoning, architecture |
| `gemini-claude-sonnet-4-5-thinking` | General coding with thinking |
| `gemini-claude-sonnet-4-5` | Fast coding tasks |
| `gemini-3-flash-preview` | Quick responses (Haiku replacement) |
| `gemini-3-pro-preview` | Large context (1M tokens) |

---

## Multi-Account Rotation

Add multiple Google accounts to increase rate limits:

**macOS/Linux:**
```bash
~/.local/bin/cliproxyapi --antigravity-login  # Add account 1
~/.local/bin/cliproxyapi --antigravity-login  # Add account 2
~/.local/bin/cliproxyapi --antigravity-login  # Add account 3
```

**Windows:**
```powershell
anticc-login  # Add account 1
anticc-login  # Add account 2
anticc-login  # Add account 3
```

CLIProxyAPI rotates through accounts automatically when one hits rate limits.

---

## MCP Servers

MCP servers work with Antigravity/Gemini backends. On macOS/Linux, CCR handles model routing. On Windows, CLIProxyAPI handles this directly.

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

---

## CCR Configuration

CCR (Claude Code Router) config is stored at `~/.claude-code-router/config.json`.

The setup script creates this automatically with your API key and detects your Claude CLI path.

### Manual CCR Config

If you need to manually create or edit the config:

```json
{
  "LOG": true,
  "LOG_LEVEL": "debug",
  "CLAUDE_PATH": "/opt/homebrew/bin/claude",
  "HOST": "127.0.0.1",
  "PORT": 3456,
  "APIKEY": "sk-your-api-key",
  "API_TIMEOUT_MS": "600000",
  "Providers": [
    {
      "Name": "cpa",
      "Type": "openai",
      "Model": "",
      "BaseURL": "http://127.0.0.1:8317/v1",
      "APIKEY": "sk-your-api-key"
    }
  ],
  "Router": {
    "Model": {
      "opus": "gemini-claude-opus-4-5-thinking",
      "sonnet": "gemini-claude-sonnet-4-5-thinking",
      "haiku": "gemini-3-flash-preview"
    },
    "Provider": {
      "opus": "cpa",
      "sonnet": "cpa",
      "haiku": "cpa"
    }
  }
}
```

Find your Claude path with: `which claude`

---

## Environment Variables

The `anticc.sh` script sets these automatically:

```bash
export ANTHROPIC_BASE_URL="http://127.0.0.1:3456"  # CCR port
export ANTHROPIC_API_KEY="sk-your-api-key"
export ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
export ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-claude-sonnet-4-5-thinking"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-3-flash-preview"
```

---

## Files

| File | Description |
|------|-------------|
| `config.yaml` | CLIProxyAPI configuration |
| `anticc.sh` | Shell commands and environment setup |
| `cliproxy-updater.sh` | Auto-update script (pull, build, deploy, rollback) |
| `cliproxy-source/` | CLIProxyAPI source repository |
| `setup.sh` | One-command setup script (macOS/Linux) |
| `setup-windows.ps1` | One-command setup script (Windows) |
| `anticc.ps1` | PowerShell commands and environment setup (Windows) |
| `cliproxy-updater.ps1` | Auto-update script for Windows |
| `~/.claude-code-router/config.json` | CCR configuration (created by setup) |

### macOS: Launchd Plists

| File | Description |
|------|-------------|
| `~/Library/LaunchAgents/com.cliproxy.api.plist` | CLIProxyAPI service (auto-start) |
| `~/Library/LaunchAgents/com.cliproxy.updater.plist` | 12-hour auto-update timer |

### Linux: Systemd & Cron

| File | Description |
|------|-------------|
| `~/.config/systemd/user/cliproxy.service` | CLIProxyAPI service (optional) |
| Cron: `0 */12 * * *` | 12-hour auto-update |

### Logs

| Platform | Log Location |
|----------|--------------|
| **macOS/Linux** | `~/.local/var/log/cliproxyapi.log` |
| **macOS/Linux** | `~/.local/var/log/cliproxy-updater.log` |
| **Windows** | `%LOCALAPPDATA%\CLIProxyAPI\logs\cliproxyapi.log` |
| **Windows** | `%LOCALAPPDATA%\CLIProxyAPI\logs\cliproxy-updater.log` |

---

## Troubleshooting

### Check service status

**All platforms:**
```bash
anticc-status   # Shows CLIProxyAPI and profile status
anticc-diagnose # Full diagnostics
anticc-version  # Compare running vs source versions
```

### Update failed / service not responding

```bash
anticc-rollback  # Rollback to previous version
anticc-start     # Restart service
```

### Rate limit errors

Add more Google accounts:

**macOS/Linux:**
```bash
~/.local/bin/cliproxyapi --antigravity-login
```

**Windows:**
```powershell
anticc-login
```

### Model not found

Make sure you're using Antigravity model names (with `gemini-` prefix for Claude models).

### Build failures

Check Go version (requires 1.24+):

```bash
go version
```

### Check logs

**macOS/Linux:**
```bash
tail -50 ~/.local/var/log/cliproxyapi.log
tail -50 ~/.local/var/log/cliproxy-updater.log
```

**Windows (PowerShell):**
```powershell
Get-Content "$env:LOCALAPPDATA\CLIProxyAPI\logs\cliproxyapi.log" -Tail 50
Get-Content "$env:LOCALAPPDATA\CLIProxyAPI\logs\cliproxy-updater.log" -Tail 50
```

### Windows: Task Scheduler issues

If scheduled tasks aren't working, re-run setup as Administrator:

```powershell
# Run PowerShell as Administrator
.\setup-windows.ps1

# Or manually create tasks
anticc-enable-startup
anticc-enable-autoupdate
```

### Linux: Manually start on boot

If systemd setup failed, add to your `~/.bashrc` or `~/.profile`:

```bash
# Auto-start CLIProxyAPI if not running
pgrep -f cliproxyapi >/dev/null || ~/.local/bin/cliproxyapi --config ~/antigravity-CC/config.yaml &
```

### Linux: Manually setup cron for auto-update

```bash
# Edit crontab
crontab -e

# Add this line (runs every 12 hours at minute 0)
0 */12 * * * ~/antigravity-CC/cliproxy-updater.sh update >> ~/.local/var/log/cliproxy-updater-cron.log 2>&1
```

---

## Uninstalling

### macOS

```bash
# Stop services
anticc-stop-service
launchctl unload ~/Library/LaunchAgents/com.cliproxy.api.plist
launchctl unload ~/Library/LaunchAgents/com.cliproxy.updater.plist

# Remove files
rm ~/Library/LaunchAgents/com.cliproxy.api.plist
rm ~/Library/LaunchAgents/com.cliproxy.updater.plist
rm ~/.local/bin/cliproxyapi
rm -rf ~/antigravity-CC

# Remove from shell config (edit ~/.zshrc manually)
```

### Linux

```bash
# Stop services
anticc-stop-service
systemctl --user stop cliproxy 2>/dev/null
systemctl --user disable cliproxy 2>/dev/null

# Remove cron job
crontab -l | grep -v cliproxy-updater | crontab -

# Remove files
rm ~/.config/systemd/user/cliproxy.service 2>/dev/null
rm ~/.local/bin/cliproxyapi
rm -rf ~/antigravity-CC

# Remove from shell config (edit ~/.bashrc manually)
```

---

## Resources

- [CLIProxyAPI Docs](https://help.router-for.me/)
- [Antigravity Setup](https://help.router-for.me/configuration/provider/antigravity)
- [Claude Code Docs](https://docs.anthropic.com/claude-code)
- [CCR Package](https://www.npmjs.com/package/@musistudio/claude-code-router)

## License

MIT
