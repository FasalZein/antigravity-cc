package cli

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/spf13/cobra"
)

var (
	installForce bool
)

func NewInstallCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "install",
		Short: "Install CLIProxyAPI service",
		Long: `Install and configure CLIProxyAPI from source.

This command:
1. Builds CLIProxyAPI from source
2. Installs the binary to the appropriate location
3. Sets up auto-start service (launchd/systemd/Task Scheduler)
4. Sets up auto-update (12-hour interval)
5. Creates default configuration if missing

This replaces the need for 'brew install' and always uses latest source.`,
		RunE: runInstall,
	}

	cmd.Flags().BoolVar(&installForce, "force", false, "Force reinstall even if already installed")

	return cmd
}

func runInstall(cmd *cobra.Command, args []string) error {
	cfg := detectConfig()

	log("=== CLIProxyAPI Installation ===")
	log("Platform: %s/%s", runtime.GOOS, runtime.GOARCH)

	// Check prerequisites
	log("Checking prerequisites...")
	if err := checkPrerequisites(); err != nil {
		return err
	}

	// Check if source exists
	if _, err := os.Stat(cfg.SourceDir); err != nil {
		logError("Source directory not found: %s", cfg.SourceDir)
		log("Please clone the CLIProxyAPI source repository first")
		return fmt.Errorf("source not found")
	}

	// Build from source
	log("Building CLIProxyAPI from source...")
	version := getSourceVersion(cfg.SourceDir)
	commit := getGitCommit(cfg.SourceDir)

	tempBinary := filepath.Join(cfg.SourceDir, GetBinaryName("cliproxyapi.new"))
	if err := buildBinary(cfg, tempBinary, version); err != nil {
		return fmt.Errorf("build failed: %w", err)
	}
	defer os.Remove(tempBinary)

	// Create bin directory
	os.MkdirAll(cfg.BinDir, 0755)

	// Install binary
	destBinary := filepath.Join(cfg.BinDir, GetBinaryName("cliproxyapi"))
	log("Installing binary to %s", destBinary)

	// Backup existing if present
	if _, err := os.Stat(destBinary); err == nil {
		backupPath := destBinary + ".bak"
		copyFile(destBinary, backupPath)
	}

	if err := copyFile(tempBinary, destBinary); err != nil {
		return fmt.Errorf("install failed: %w", err)
	}
	os.Chmod(destBinary, 0755)

	logSuccess("Binary installed: %s (%s, %s)", destBinary, version, commit)

	// Create log directory
	logDir := GetDefaultLogDir()
	os.MkdirAll(logDir, 0755)

	// Install service
	log("Installing service...")
	if err := installService(cfg); err != nil {
		logWarn("Service installation failed: %v", err)
		log("You may need to start manually: cliproxyctl start")
	} else {
		logSuccess("Service installed")
	}

	// Install auto-updater
	log("Installing auto-updater...")
	if err := installAutoUpdater(cfg); err != nil {
		logWarn("Auto-updater installation failed: %v", err)
	} else {
		logSuccess("Auto-updater installed (runs every 12 hours)")
	}

	// Add to PATH if not already
	if runtime.GOOS != "windows" {
		ensureInPath(cfg.BinDir)
	}

	log("")
	logSuccess("Installation complete!")
	log("")
	log("Next steps:")
	log("  1. Login to Antigravity: cliproxyapi --antigravity-login")
	log("  2. Start the service:    cliproxyctl start")
	log("  3. Check status:         cliproxyctl status")

	return nil
}

func checkPrerequisites() error {
	// Check Go
	if _, err := exec.LookPath("go"); err != nil {
		logError("Go is not installed")
		log("Install Go from: https://go.dev/dl/")
		return fmt.Errorf("go not found")
	}

	goVersion, _ := exec.Command("go", "version").Output()
	log("  Go: %s", strings.TrimSpace(string(goVersion)))

	// Check Git
	if _, err := exec.LookPath("git"); err != nil {
		logError("Git is not installed")
		return fmt.Errorf("git not found")
	}

	gitVersion, _ := exec.Command("git", "--version").Output()
	log("  Git: %s", strings.TrimSpace(string(gitVersion)))

	return nil
}

func installService(cfg *Config) error {
	switch runtime.GOOS {
	case "darwin":
		return installServiceMacOS(cfg)
	case "linux":
		return installServiceLinux(cfg)
	case "windows":
		return installServiceWindows(cfg)
	default:
		return fmt.Errorf("unsupported platform: %s", runtime.GOOS)
	}
}

func installServiceMacOS(cfg *Config) error {
	plistDir := filepath.Join(os.Getenv("HOME"), "Library/LaunchAgents")
	os.MkdirAll(plistDir, 0755)

	plistPath := filepath.Join(plistDir, "com.cliproxy.api.plist")
	binary := filepath.Join(cfg.BinDir, "cliproxyapi")
	logFile := filepath.Join(GetDefaultLogDir(), "cliproxyapi.log")

	plistContent := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cliproxy.api</string>
    <key>ProgramArguments</key>
    <array>
        <string>%s</string>
        <string>--config</string>
        <string>%s</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>%s</string>
    <key>StandardErrorPath</key>
    <string>%s</string>
    <key>WorkingDirectory</key>
    <string>%s</string>
</dict>
</plist>`, binary, cfg.ConfigPath, logFile, logFile, cfg.BaseDir)

	if err := os.WriteFile(plistPath, []byte(plistContent), 0644); err != nil {
		return err
	}

	// Load the service
	exec.Command("launchctl", "bootout", fmt.Sprintf("gui/%d/com.cliproxy.api", os.Getuid())).Run()
	return exec.Command("launchctl", "bootstrap", fmt.Sprintf("gui/%d", os.Getuid()), plistPath).Run()
}

func installServiceLinux(cfg *Config) error {
	// Check if running in WSL without systemd
	if isWSL() && !hasSystemd() {
		log("WSL detected without systemd - skipping service installation")
		log("To start CLIProxyAPI in WSL, use: cliproxyctl start")
		log("Consider adding 'cliproxyctl start' to your .bashrc/.zshrc")
		return nil
	}

	serviceDir := filepath.Join(os.Getenv("HOME"), ".config/systemd/user")
	os.MkdirAll(serviceDir, 0755)

	servicePath := filepath.Join(serviceDir, "cliproxyapi.service")
	binary := filepath.Join(cfg.BinDir, "cliproxyapi")

	serviceContent := fmt.Sprintf(`[Unit]
Description=CLIProxyAPI - Local API Proxy
After=network.target

[Service]
Type=simple
ExecStart=%s --config %s
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
`, binary, cfg.ConfigPath)

	if err := os.WriteFile(servicePath, []byte(serviceContent), 0644); err != nil {
		return err
	}

	// Reload and enable
	exec.Command("systemctl", "--user", "daemon-reload").Run()
	return exec.Command("systemctl", "--user", "enable", "cliproxyapi").Run()
}

func installServiceWindows(cfg *Config) error {
	binary := filepath.Join(cfg.BinDir, "cliproxyapi.exe")
	taskName := "CLIProxyAPI-Startup"

	// Delete existing task
	exec.Command("schtasks", "/Delete", "/TN", taskName, "/F").Run()

	// Create new task
	cmd := exec.Command("schtasks", "/Create",
		"/TN", taskName,
		"/TR", fmt.Sprintf(`"%s" --config "%s"`, binary, cfg.ConfigPath),
		"/SC", "ONLOGON",
		"/RL", "LIMITED",
		"/F")
	return cmd.Run()
}

func installAutoUpdater(cfg *Config) error {
	switch runtime.GOOS {
	case "darwin":
		return installAutoUpdaterMacOS(cfg)
	case "linux":
		return installAutoUpdaterLinux(cfg)
	case "windows":
		return installAutoUpdaterWindows(cfg)
	default:
		return fmt.Errorf("unsupported platform")
	}
}

func installAutoUpdaterMacOS(cfg *Config) error {
	plistDir := filepath.Join(os.Getenv("HOME"), "Library/LaunchAgents")
	plistPath := filepath.Join(plistDir, "com.cliproxy.updater.plist")

	// Use cliproxyctl for updates
	cliproxyctl := filepath.Join(cfg.BaseDir, "tools/cliproxyctl/cliproxyctl")
	logFile := filepath.Join(GetDefaultLogDir(), "cliproxy-updater.log")

	plistContent := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cliproxy.updater</string>
    <key>ProgramArguments</key>
    <array>
        <string>%s</string>
        <string>update</string>
    </array>
    <key>StartInterval</key>
    <integer>43200</integer>
    <key>StandardOutPath</key>
    <string>%s</string>
    <key>StandardErrorPath</key>
    <string>%s</string>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>`, cliproxyctl, logFile, logFile)

	if err := os.WriteFile(plistPath, []byte(plistContent), 0644); err != nil {
		return err
	}

	exec.Command("launchctl", "bootout", fmt.Sprintf("gui/%d/com.cliproxy.updater", os.Getuid())).Run()
	return exec.Command("launchctl", "bootstrap", fmt.Sprintf("gui/%d", os.Getuid()), plistPath).Run()
}

func installAutoUpdaterLinux(cfg *Config) error {
	// Check if running in WSL without systemd
	if isWSL() && !hasSystemd() {
		log("WSL detected without systemd - skipping auto-updater installation")
		log("To update CLIProxyAPI in WSL, use: cliproxyctl update")
		log("Consider adding a cron job for automatic updates")
		return nil
	}

	// Use systemd timer
	timerDir := filepath.Join(os.Getenv("HOME"), ".config/systemd/user")

	cliproxyctl := filepath.Join(cfg.BaseDir, "tools/cliproxyctl/cliproxyctl")

	// Service file
	servicePath := filepath.Join(timerDir, "cliproxyapi-updater.service")
	serviceContent := fmt.Sprintf(`[Unit]
Description=CLIProxyAPI Auto-Updater

[Service]
Type=oneshot
ExecStart=%s update
`, cliproxyctl)

	if err := os.WriteFile(servicePath, []byte(serviceContent), 0644); err != nil {
		return err
	}

	// Timer file
	timerPath := filepath.Join(timerDir, "cliproxyapi-updater.timer")
	timerContent := `[Unit]
Description=CLIProxyAPI Auto-Update Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=12h
Persistent=true

[Install]
WantedBy=timers.target
`
	if err := os.WriteFile(timerPath, []byte(timerContent), 0644); err != nil {
		return err
	}

	exec.Command("systemctl", "--user", "daemon-reload").Run()
	return exec.Command("systemctl", "--user", "enable", "--now", "cliproxyapi-updater.timer").Run()
}

func installAutoUpdaterWindows(cfg *Config) error {
	cliproxyctl := filepath.Join(cfg.BaseDir, "tools", "cliproxyctl", "cliproxyctl.exe")
	taskName := "CLIProxyAPI-AutoUpdate"

	// Delete existing
	exec.Command("schtasks", "/Delete", "/TN", taskName, "/F").Run()

	// Create task that runs every 12 hours
	cmd := exec.Command("schtasks", "/Create",
		"/TN", taskName,
		"/TR", fmt.Sprintf(`"%s" update`, cliproxyctl),
		"/SC", "HOURLY",
		"/MO", "12",
		"/F")
	return cmd.Run()
}

func ensureInPath(binDir string) {
	// Check if already in PATH
	pathEnv := os.Getenv("PATH")
	if strings.Contains(pathEnv, binDir) {
		return
	}

	log("")
	logWarn("Binary directory is not in PATH")
	log("Add to your shell profile (~/.zshrc or ~/.bashrc):")
	log("")
	log("  export PATH=\"%s:$PATH\"", binDir)
	log("")
}
