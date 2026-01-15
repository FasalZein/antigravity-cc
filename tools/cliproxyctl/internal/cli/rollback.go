package cli

import (
	"fmt"
	"os"
	"time"

	"github.com/spf13/cobra"
)

func NewRollbackCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "rollback",
		Short: "Rollback to previous version",
		Long: `Rollback CLIProxyAPI to the previous version.

This restores the backup binary (.bak) and restarts the service.
Use this if an update causes issues.`,
		RunE: runRollback,
	}

	return cmd
}

func runRollback(cmd *cobra.Command, args []string) error {
	cfg := detectConfig()
	return doRollback(cfg)
}

func doRollback(cfg *Config) error {
	backupPath := cfg.BinPath + ".bak"

	// Check if backup exists
	if _, err := os.Stat(backupPath); os.IsNotExist(err) {
		return fmt.Errorf("no backup found at %s", backupPath)
	}

	backupVersion := getBinaryVersion(backupPath)
	currentVersion := getBinaryVersion(cfg.BinPath)

	log("Rolling back from %s to %s", currentVersion, backupVersion)

	// Stop service
	log("Stopping service...")
	stopService()

	// Poll for process stop
	for i := 0; i < 20; i++ {
		if !isProcessRunningCrossPlatform("cliproxyapi") {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	// Swap binaries
	log("Restoring backup...")

	// Move current to .failed
	failedPath := cfg.BinPath + ".failed"
	if err := os.Rename(cfg.BinPath, failedPath); err != nil {
		// Try copy if rename fails
		if err := copyFile(cfg.BinPath, failedPath); err != nil {
			logWarn("Could not save failed version: %v", err)
		}
	}

	// Move backup to current
	if err := os.Rename(backupPath, cfg.BinPath); err != nil {
		// Try copy if rename fails
		if err := copyFile(backupPath, cfg.BinPath); err != nil {
			return fmt.Errorf("failed to restore backup: %w", err)
		}
		os.Remove(backupPath)
	}

	os.Chmod(cfg.BinPath, 0755)

	// Start service
	log("Starting service...")
	if err := startService(cfg); err != nil {
		logWarn("Failed to start via service manager, trying direct start...")
		startServiceDirect(cfg)
	}

	// Poll for process start
	for i := 0; i < 10; i++ {
		if isProcessRunningCrossPlatform("cliproxyapi") {
			break
		}
		time.Sleep(200 * time.Millisecond)
	}

	// Health check
	log("Running health check...")
	if err := healthCheck(cfg, 10); err != nil {
		logError("Health check failed after rollback: %v", err)
		return fmt.Errorf("rollback completed but service not responding")
	}

	logSuccess("Rolled back to %s", backupVersion)

	// Clean up failed version
	os.Remove(failedPath)

	return nil
}
