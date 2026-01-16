package cli

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

var (
	updateForce bool
	updateDry   bool
)

func NewUpdateCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "update",
		Short: "Self-update CLIProxyAPI",
		Long: `Pull latest source, build, deploy, health check, and auto-rollback on failure.

This command:
1. Pulls latest changes from origin/main
2. Builds with version info embedded
3. Backs up current binary
4. Deploys new binary
5. Restarts the service
6. Runs health check
7. Auto-rollbacks if health check fails`,
		RunE: runUpdate,
	}

	cmd.Flags().BoolVar(&updateForce, "force", false, "Force update even if already at latest")
	cmd.Flags().BoolVar(&updateDry, "dry-run", false, "Show what would be done without executing")

	return cmd
}

func runUpdate(cmd *cobra.Command, args []string) error {
	cfg := detectConfig()

	log("=== CLIProxyAPI Update ===")

	// Check if source directory exists
	if _, err := os.Stat(cfg.SourceDir); os.IsNotExist(err) {
		return fmt.Errorf("source directory not found: %s", cfg.SourceDir)
	}

	// Get current versions
	oldVersion := getSourceVersion(cfg.SourceDir)
	binaryVersion := getBinaryVersion(cfg.BinPath)

	log("Current source version: %s", oldVersion)
	log("Current binary version: %s", binaryVersion)

	// Pull latest
	log("Pulling latest changes...")
	if !updateDry {
		if err := gitPull(cfg.SourceDir); err != nil {
			return fmt.Errorf("git pull failed: %w", err)
		}
	}

	newVersion := getSourceVersion(cfg.SourceDir)
	log("Latest source version: %s", newVersion)

	// Check if update needed
	if newVersion == binaryVersion && !updateForce {
		logSuccess("Already at latest version: %s", newVersion)
		return nil
	}

	log("Update available: %s → %s", binaryVersion, newVersion)

	if updateDry {
		log("[dry-run] Would build and deploy version %s", newVersion)
		return nil
	}

	// Build new version
	log("Building %s...", newVersion)
	newBinaryPath := filepath.Join(cfg.SourceDir, "cliproxyapi.new")
	if err := buildBinary(cfg, newBinaryPath, newVersion); err != nil {
		return fmt.Errorf("build failed: %w", err)
	}
	defer os.Remove(newBinaryPath)

	// Backup current binary
	backupPath := cfg.BinPath + ".bak"
	if _, err := os.Stat(cfg.BinPath); err == nil {
		log("Backing up current binary...")
		if err := copyFile(cfg.BinPath, backupPath); err != nil {
			return fmt.Errorf("backup failed: %w", err)
		}
	}

	// Deploy new binary
	log("Deploying new binary...")
	if err := copyFile(newBinaryPath, cfg.BinPath); err != nil {
		return fmt.Errorf("deploy failed: %w", err)
	}
	os.Chmod(cfg.BinPath, 0755)

	// Restart service
	log("Restarting service...")
	stopService()

	// Poll for process stop
	for i := 0; i < 20; i++ {
		if !isProcessRunningCrossPlatform("cliproxyapi") {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	if err := startService(cfg); err != nil {
		logWarn("Failed to start via service manager, trying direct start...")
		startServiceDirect(cfg)
	}

	// Health check with faster polling
	log("Running health check...")
	if err := healthCheck(cfg, 30); err != nil {
		logError("Health check failed: %v", err)
		logWarn("Rolling back...")
		if rollbackErr := doRollback(cfg); rollbackErr != nil {
			return fmt.Errorf("rollback also failed: %w", rollbackErr)
		}
		return fmt.Errorf("update failed, rolled back to previous version")
	}

	// Restart CCR if available
	restartCCR()

	// Send notification
	sendNotification("CLIProxyAPI", fmt.Sprintf("Updated to %s", newVersion))

	logSuccess("Update successful: %s", newVersion)
	return nil
}

func buildBinary(cfg *Config, outputPath, version string) error {
	commit := getGitCommit(cfg.SourceDir)
	buildDate := time.Now().UTC().Format(time.RFC3339)

	ldflags := fmt.Sprintf(
		"-X 'main.Version=%s' -X 'main.Commit=%s' -X 'main.BuildDate=%s' -X 'main.DefaultConfigPath=%s'",
		version, commit, buildDate, cfg.ConfigPath,
	)

	cmd := exec.Command("go", "build", "-ldflags", ldflags, "-o", outputPath, "./cmd/server")
	cmd.Dir = cfg.SourceDir
	cmd.Env = append(os.Environ(), "CGO_ENABLED=0")

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%w: %s", err, stderr.String())
	}

	return nil
}

func gitPull(dir string) error {
	// Ensure we're on main branch
	checkout := exec.Command("git", "checkout", "main", "--quiet")
	checkout.Dir = dir
	checkout.Run() // Ignore error if already on main

	// Fetch all (tags and branches)
	fetch := exec.Command("git", "fetch", "--all", "--tags", "--quiet")
	fetch.Dir = dir
	if err := fetch.Run(); err != nil {
		return fmt.Errorf("git fetch failed: %w", err)
	}

	// Reset to origin/main (always build from main branch)
	reset := exec.Command("git", "reset", "--hard", "origin/main")
	reset.Dir = dir
	var stderr bytes.Buffer
	reset.Stderr = &stderr
	if err := reset.Run(); err != nil {
		return fmt.Errorf("git reset failed: %s", stderr.String())
	}

	return nil
}

func getGitCommit(dir string) string {
	cmd := exec.Command("git", "rev-parse", "--short", "HEAD")
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}

func stopService() {
	switch runtime.GOOS {
	case "darwin":
		exec.Command("launchctl", "stop", "com.cliproxy.api").Run()
		killProcessCrossPlatform("cliproxyapi")
	case "linux":
		if !isWSL() || hasSystemd() {
			exec.Command("systemctl", "--user", "stop", "cliproxyapi").Run()
		}
		killProcessCrossPlatform("cliproxyapi")
	case "windows":
		killProcessCrossPlatform("cliproxyapi")
	default:
		killProcessCrossPlatform("cliproxyapi")
	}
}

func startService(cfg *Config) error {
	sm := NewServiceManager(cfg)
	return sm.StartService()
}

func startServiceDirect(cfg *Config) error {
	logDir := GetDefaultLogDir()
	os.MkdirAll(logDir, 0755)

	logFile := filepath.Join(logDir, "cliproxyapi.log")
	f, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}

	cmd := exec.Command(cfg.BinPath, "--config", cfg.ConfigPath)
	cmd.Stdout = f
	cmd.Stderr = f
	return cmd.Start()
}

func healthCheck(cfg *Config, maxAttempts int) error {
	client := &http.Client{Timeout: 2 * time.Second}
	url := fmt.Sprintf("http://127.0.0.1:%d/v1/models", cfg.Port)

	for i := 0; i < maxAttempts; i++ {
		req, _ := http.NewRequest("GET", url, nil)
		if cfg.APIKey != "" {
			req.Header.Set("Authorization", "Bearer "+cfg.APIKey)
		}

		resp, err := client.Do(req)
		if err == nil && resp.StatusCode == 200 {
			resp.Body.Close()
			return nil
		}
		if resp != nil {
			resp.Body.Close()
		}

		// Use shorter intervals for faster detection
		time.Sleep(300 * time.Millisecond)
	}

	return fmt.Errorf("service not responding after %d attempts", maxAttempts)
}

func restartCCR() {
	// Check if ccr command exists
	ccrBin := "ccr"
	if runtime.GOOS == "windows" {
		ccrBin = "ccr.exe"
	}
	if _, err := exec.LookPath(ccrBin); err != nil {
		return
	}

	log("Restarting CCR...")
	killProcessCrossPlatform("claude-code-router")
	time.Sleep(1 * time.Second)

	// Use context with timeout to prevent hanging
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, ccrBin, "start")
	cmd.Start()

	// Wait up to 3 seconds for CCR to start
	for i := 0; i < 6; i++ {
		time.Sleep(500 * time.Millisecond)
		if isProcessRunningCrossPlatform("claude-code-router") {
			log("CCR restarted")
			return
		}
	}

	logWarn("CCR failed to start (may need manual: ccr start)")
}

func sendNotification(title, message string) {
	SendNotificationCrossPlatform(title, message)
}

func copyFile(src, dst string) error {
	sourceFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer sourceFile.Close()

	destFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer destFile.Close()

	_, err = io.Copy(destFile, sourceFile)
	return err
}
