# cliproxyctl

Cross-platform CLI management tool for CLIProxyAPI. Consolidates shell script functionality into a single Go binary.

## Features

- **Cross-platform**: macOS, Linux, Windows, and WSL support
- **Always from source**: Builds CLIProxyAPI from the main branch
- **Auto-update**: Configurable auto-update with health checks and rollback
- **Service management**: Platform-native service integration (launchd/systemd/Task Scheduler)
- **Zero external dependencies**: No curl, no shell commands for core functionality

## Installation

### Build from source

```bash
cd tools/cliproxyctl
go build -o cliproxyctl .
```

### First-time setup

```bash
./cliproxyctl install
```

This will:
1. Build CLIProxyAPI from source
2. Install the binary to the appropriate location
3. Set up auto-start service
4. Configure auto-update (every 12 hours)

## Commands

### Service Management

```bash
cliproxyctl start      # Start CLIProxyAPI service
cliproxyctl stop       # Stop CLIProxyAPI service
cliproxyctl restart    # Restart CLIProxyAPI service
cliproxyctl status     # Show service status and versions
cliproxyctl logs       # View service logs
cliproxyctl logs -f    # Follow logs (like tail -f)
cliproxyctl logs -n 100  # Show last 100 lines
```

### Update Management

```bash
cliproxyctl update           # Pull latest, build, deploy, health check
cliproxyctl update --force   # Force update even if at latest version
cliproxyctl update --dry-run # Show what would be done
cliproxyctl rollback         # Rollback to previous version
```

### Utilities

```bash
cliproxyctl quota            # Check Antigravity quota (CLI)
cliproxyctl quota --web      # Start web dashboard
cliproxyctl diagnose         # Run system diagnostics
cliproxyctl install          # Full installation from source
```

## Platform Support

| Platform | Service Manager | Auto-Start | Auto-Update |
|----------|----------------|------------|-------------|
| macOS | launchd | ✅ | ✅ launchd timer |
| Linux | systemd | ✅ | ✅ systemd timer |
| Windows | Task Scheduler | ✅ | ✅ schtasks |
| WSL1 | direct process | manual | cron (manual) |
| WSL2 | systemd/direct | ✅ (if systemd) | ✅ (if systemd) |

### WSL Notes

- **WSL1**: No systemd, uses direct process management. Add `cliproxyctl start` to `.bashrc`
- **WSL2**: Can enable systemd in `/etc/wsl.conf`. If enabled, full service support works
- Run `cliproxyctl diagnose` to see WSL detection and systemd status

## Directory Structure

### macOS/Linux
```
~/.local/bin/cliproxyapi          # Binary
~/.local/var/log/cliproxyapi.log  # Logs
~/Library/LaunchAgents/           # macOS services
~/.config/systemd/user/           # Linux services
```

### Windows
```
%LOCALAPPDATA%\Programs\CLIProxyAPI\cliproxyapi.exe  # Binary
%LOCALAPPDATA%\CLIProxyAPI\logs\cliproxyapi.log     # Logs
```

## Update Flow

The update process is designed to be safe with automatic rollback:

```
1. git checkout main && git fetch --all
2. git reset --hard origin/main
3. go build with version info
4. Backup current binary → .bak
5. Deploy new binary
6. Restart service
7. Health check (polls /v1/models)
8. If health check fails → automatic rollback
9. Notify on success
```

## Configuration

cliproxyctl auto-detects configuration from:

1. `CLIPROXY_DIR` environment variable
2. Relative to executable location
3. Common paths: `~/Dev/Code Forge/CLIProxyAPI`, `~/Developer/CLIProxyAPI`, `~/CLIProxyAPI`

### Required Files

- `config.yaml` - CLIProxyAPI configuration
- `cliproxy-source/` - Source code directory (for building)

## Shell Integration

The shell scripts (`anticc.sh`, `anticc.ps1`) are thin wrappers that delegate to cliproxyctl:

```bash
# Source the shell script
source /path/to/anticc.sh

# Profile commands (shell-only, modifies environment)
anticc-on              # Enable Antigravity mode
anticc-off             # Direct mode (bypass CCR)

# All other commands delegate to cliproxyctl
anticc-start           # → cliproxyctl start
anticc-stop-service    # → cliproxyctl stop
anticc-update          # → cliproxyctl update
anticc-logs            # → cliproxyctl logs
# etc.
```

## Development

### Cross-compilation

```bash
# Linux
GOOS=linux GOARCH=amd64 go build -o cliproxyctl-linux .

# Windows
GOOS=windows GOARCH=amd64 go build -o cliproxyctl.exe .

# macOS ARM
GOOS=darwin GOARCH=arm64 go build -o cliproxyctl-darwin .
```

### Adding New Commands

1. Create a new file in `internal/cli/`
2. Implement `NewXxxCmd() *cobra.Command`
3. Add to `main.go`: `rootCmd.AddCommand(cli.NewXxxCmd())`

### Testing

```bash
# Build and run diagnostics
go build -o cliproxyctl . && ./cliproxyctl diagnose

# Test update (dry run)
./cliproxyctl update --dry-run
```

## Troubleshooting

### Service won't start

```bash
cliproxyctl diagnose          # Full diagnostics
cliproxyctl logs -n 50        # Check recent logs
```

### Update failed

```bash
cliproxyctl rollback          # Restore previous version
cliproxyctl logs              # Check what went wrong
```

### WSL issues

```bash
cliproxyctl diagnose          # Shows WSL version and systemd status
```

If systemd isn't available:
- Add `cliproxyctl start` to `~/.bashrc` or `~/.zshrc`
- Use cron for auto-updates: `0 */12 * * * /path/to/cliproxyctl update`

## License

Part of CLIProxyAPI. See main repository for license information.
