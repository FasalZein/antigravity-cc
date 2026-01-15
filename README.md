# Antigravity Claude Code (anticc)

Use Claude Code with Antigravity models (Claude, Gemini, GPT) via CLIProxyAPI - no API keys needed, just your Google account.

## Architecture

```
Claude Code → CCR (3456) → CLIProxyAPI (8317) → Antigravity → Google AI
```

- **Free access** to Claude Opus 4.5, Sonnet 4.5, Gemini 3 Pro via Google OAuth
- **Multi-account rotation** - add multiple Google accounts to increase rate limits
- **Auto-updates** - built from source and updated every 12 hours with auto-rollback
- **Cross-platform** - macOS, Linux, Windows, and WSL support

## Quick Start

```bash
git clone https://github.com/YourUsername/antigravity-CC.git ~/antigravity-CC
cd ~/antigravity-CC
./setup.sh
```

**Windows:**
```powershell
git clone https://github.com/YourUsername/antigravity-CC.git $HOME\antigravity-CC
cd $HOME\antigravity-CC
.\setup-windows.ps1
```

### Requirements

| OS | Requirements |
|----|--------------|
| **macOS** | Go 1.24+, Node.js, Git |
| **Linux** | Go 1.24+, Node.js, Git |
| **Windows** | Go 1.24+, Git, PowerShell 5+ |

---

## Commands

After sourcing `anticc.sh` (or `anticc.ps1` on Windows):

### Profile (Shell-only)

| Command | Description |
|---------|-------------|
| `anticc-on` | Enable Antigravity mode (route through CCR) |
| `anticc-off` | Direct mode (bypass CCR) |

### Service Management

| Command | Description |
|---------|-------------|
| `anticc-start` | Start CLIProxyAPI service |
| `anticc-stop-service` | Stop CLIProxyAPI service |
| `anticc-restart-service` | Restart CLIProxyAPI service |
| `anticc-status` | Show service and profile status |
| `anticc-logs` | Follow service logs (Ctrl+C to stop) |
| `anticc-logs -n 50` | Show last 50 lines |

### Updates

| Command | Description |
|---------|-------------|
| `anticc-update` | Pull latest, build, deploy with health check |
| `anticc-rollback` | Rollback to previous version |
| `anticc-diagnose` | Run full diagnostics |
| `anticc-quota` | Check Antigravity quota |

### All Commands

```bash
anticc-help  # Show all available commands
```

---

## CLI Tool (cliproxyctl)

All shell commands delegate to `cliproxyctl`, a cross-platform Go binary in `tools/cliproxyctl/`.

```bash
# Direct usage (same as anticc-* commands)
cliproxyctl start
cliproxyctl stop
cliproxyctl restart
cliproxyctl status
cliproxyctl logs -f
cliproxyctl update
cliproxyctl rollback
cliproxyctl diagnose
cliproxyctl quota           # CLI quota check
cliproxyctl quota --web     # Web dashboard with Antigravity + Codex tabs
```

### Quota Dashboard

View your quota usage in a web browser:

```bash
cliproxyctl quota --web
```

This opens a dashboard showing:
- **Antigravity tab**: Per-account session/daily quota with visual progress rings
- **Codex tab**: Session (5h) and weekly quota for all Codex accounts

The dashboard reads auth tokens from:
- Antigravity: `~/.cli-proxy-api/antigravity-*.json`
- Codex: `~/.cli-proxy-api/codex-*.json`

See [tools/cliproxyctl/README.md](tools/cliproxyctl/README.md) for developer docs.

---

## Multi-Account Rotation

Add multiple Google accounts to increase rate limits:

```bash
~/.local/bin/cliproxyapi --antigravity-login  # Add account 1
~/.local/bin/cliproxyapi --antigravity-login  # Add account 2
```

CLIProxyAPI rotates through accounts automatically when one hits rate limits.

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

## Files

| File | Description |
|------|-------------|
| `config.yaml` | CLIProxyAPI configuration |
| `anticc.sh` / `anticc.ps1` | Shell commands (thin wrapper) |
| `cliproxy-source/` | CLIProxyAPI source repository |
| `tools/cliproxyctl/` | Cross-platform CLI tool (Go) |

### Binaries & Logs

| Platform | Binary | Logs |
|----------|--------|------|
| macOS/Linux | `~/.local/bin/cliproxyapi` | `~/.local/var/log/cliproxyapi.log` |
| Windows | `%LOCALAPPDATA%\Programs\CLIProxyAPI\cliproxyapi.exe` | `%LOCALAPPDATA%\CLIProxyAPI\logs\` |

### Service Files

| Platform | Service Manager | Files |
|----------|----------------|-------|
| macOS | launchd | `~/Library/LaunchAgents/com.cliproxy.api.plist` |
| Linux | systemd | `~/.config/systemd/user/cliproxyapi.service` |
| Windows | Task Scheduler | `CLIProxyAPI-Startup`, `CLIProxyAPI-AutoUpdate` |

---

## Auto-Update

CLIProxyAPI is built from source and auto-updated every 12 hours:

1. `git checkout main && git fetch --all`
2. `git reset --hard origin/main`
3. `go build` with version info
4. Backup current binary
5. Deploy new binary
6. Restart service
7. Health check (`/v1/models`)
8. Auto-rollback if health check fails

### Why Build from Source?

- Homebrew/npm releases lag behind
- Fast-moving project with frequent patches
- Immediate access to bug fixes

---

## Troubleshooting

### Quick Checks

```bash
anticc-status    # Service status
anticc-diagnose  # Full diagnostics
anticc-logs      # Follow logs
```

### Service Issues

```bash
anticc-restart-service  # Restart
anticc-logs -n 100      # Check recent logs
```

### Update Failed

```bash
anticc-rollback  # Restore previous version
```

### Rate Limits

Add more Google accounts:
```bash
~/.local/bin/cliproxyapi --antigravity-login
```

### Build Failures

Check Go version (requires 1.24+):
```bash
go version
```

---

## Migrating from Homebrew

```bash
# Stop and uninstall brew version
brew services stop cliproxyapi
brew uninstall cliproxyapi

# Run new setup
cd ~/antigravity-CC
git pull
./setup.sh
```

---

## Uninstalling

### macOS

```bash
anticc-stop-service
launchctl unload ~/Library/LaunchAgents/com.cliproxy.api.plist
launchctl unload ~/Library/LaunchAgents/com.cliproxy.updater.plist
rm ~/Library/LaunchAgents/com.cliproxy.*.plist
rm ~/.local/bin/cliproxyapi
rm -rf ~/antigravity-CC
# Remove 'source anticc.sh' from ~/.zshrc
```

### Linux

```bash
anticc-stop-service
systemctl --user disable cliproxyapi
crontab -l | grep -v cliproxy | crontab -
rm ~/.local/bin/cliproxyapi
rm -rf ~/antigravity-CC
# Remove 'source anticc.sh' from ~/.bashrc
```

### Windows

```powershell
.\setup-windows.ps1 -Uninstall
```

---

## Resources

- [CLIProxyAPI Docs](https://help.router-for.me/)
- [Antigravity Setup](https://help.router-for.me/configuration/provider/antigravity)
- [Claude Code Docs](https://docs.anthropic.com/claude-code)

## License

MIT
