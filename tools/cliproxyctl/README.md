# cliproxyctl

Cross-platform CLI management tool for CLIProxyAPI. All `anticc-*` shell commands delegate to this binary.

## Build

```bash
cd tools/cliproxyctl
go build -o cliproxyctl .
```

## Commands

```bash
cliproxyctl start       # Start service
cliproxyctl stop        # Stop service
cliproxyctl restart     # Restart service (waits for port release)
cliproxyctl status      # Show status and versions
cliproxyctl logs        # Follow logs (default)
cliproxyctl logs -n 50  # Show last 50 lines
cliproxyctl logs --all  # Open in pager
cliproxyctl update      # Pull, build, deploy, health check
cliproxyctl rollback    # Restore previous version
cliproxyctl diagnose    # System diagnostics
cliproxyctl quota       # Check Antigravity quota
cliproxyctl install     # Full installation from source
```

## Platform Support

| Platform | Service Manager | Auto-Start | Auto-Update |
|----------|----------------|------------|-------------|
| macOS | launchd | ✅ | ✅ |
| Linux | systemd | ✅ | ✅ |
| Windows | Task Scheduler | ✅ | ✅ |
| WSL1 | direct process | manual | cron |
| WSL2 | systemd/direct | ✅ (if systemd) | ✅ |

## Configuration

Auto-detects from:
1. `CLIPROXY_DIR` environment variable
2. Relative to executable location
3. Common paths: `~/Dev/Code Forge/CLIProxyAPI`, `~/CLIProxyAPI`

## Development

### Adding Commands

1. Create `internal/cli/mycommand.go`
2. Implement `NewMyCmd() *cobra.Command`
3. Add to `main.go`: `rootCmd.AddCommand(cli.NewMyCmd())`

### Cross-compilation

```bash
GOOS=linux GOARCH=amd64 go build -o cliproxyctl-linux .
GOOS=windows GOARCH=amd64 go build -o cliproxyctl.exe .
GOOS=darwin GOARCH=arm64 go build -o cliproxyctl-darwin .
```

### Key Files

```
main.go                     # Entry point, registers commands
internal/cli/
├── common.go               # Config detection, WSL detection, logging
├── platform.go             # Cross-platform process/port/service management
├── service.go              # start, stop, restart commands
├── status.go               # status command
├── logs.go                 # logs command
├── updater.go              # update, rollback commands
├── diagnose.go             # diagnose command
├── quota.go                # quota command
└── install.go              # install command
```
