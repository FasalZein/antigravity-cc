package cli

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/spf13/cobra"
)

func NewStartCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "start",
		Short: "Start CLIProxyAPI service",
		Long: `Start the CLIProxyAPI service.

Uses platform-specific service management:
- macOS: launchctl
- Linux: systemd user service
- Windows: background process`,
		RunE: runStart,
	}

	return cmd
}

func NewStopCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "stop",
		Short: "Stop CLIProxyAPI service",
		RunE:  runStop,
	}

	return cmd
}

func NewRestartCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "restart",
		Short: "Restart CLIProxyAPI service",
		RunE:  runRestart,
	}

	return cmd
}

func runStart(cmd *cobra.Command, args []string) error {
	startTime := time.Now()
	cfg := detectConfig()
	sm := NewServiceManager(cfg)

	if isProcessRunningCrossPlatform("cliproxyapi") {
		pid := getProcessPIDCrossPlatform("cliproxyapi")
		logSuccess("CLIProxyAPI already running (PID: %s)", pid)
		return nil
	}

	// Check binary exists
	binary := filepath.Join(cfg.BinDir, GetBinaryName("cliproxyapi"))
	if _, err := os.Stat(binary); err != nil {
		logError("CLIProxyAPI not found at %s", binary)
		log("Run 'cliproxyctl update' to build from source")
		return fmt.Errorf("binary not found")
	}

	// Check config exists
	if _, err := os.Stat(cfg.ConfigPath); err != nil {
		logError("Config not found at %s", cfg.ConfigPath)
		return fmt.Errorf("config not found")
	}

	log("Starting CLIProxyAPI...")
	serviceStart := time.Now()
	if err := sm.StartService(); err != nil {
		logWarn("Service start failed: %v", err)
		return err
	}
	log("Service manager completed (%dms)", time.Since(serviceStart).Milliseconds())

	// Poll for process start (instead of fixed sleep)
	processStart := time.Now()
	for i := 0; i < 10; i++ {
		if isProcessRunningCrossPlatform("cliproxyapi") {
			break
		}
		time.Sleep(200 * time.Millisecond)
	}

	if isProcessRunningCrossPlatform("cliproxyapi") {
		pid := getProcessPIDCrossPlatform("cliproxyapi")
		log("Process detected (%dms)", time.Since(processStart).Milliseconds())
		logSuccess("CLIProxyAPI started (PID: %s)", pid)

		// Quick health check - poll with short intervals
		healthStart := time.Now()
		if err := quickHealthCheck(cfg, 30); err == nil {
			log("Service responding on port %d (%dms)", cfg.Port, time.Since(healthStart).Milliseconds())
		} else {
			logWarn("Health check timed out (%dms)", time.Since(healthStart).Milliseconds())
		}
	} else {
		logError("Failed to start CLIProxyAPI")
		logDir := GetDefaultLogDir()
		log("Check logs: cliproxyctl logs")
		log("Log file: %s", filepath.Join(logDir, "cliproxyapi.log"))
		return fmt.Errorf("failed to start")
	}

	log("Total start time: %dms", time.Since(startTime).Milliseconds())
	return nil
}

func runStop(cmd *cobra.Command, args []string) error {
	startTime := time.Now()
	cfg := detectConfig()
	sm := NewServiceManager(cfg)

	if !isProcessRunningCrossPlatform("cliproxyapi") {
		log("CLIProxyAPI is not running")
		return nil
	}

	log("Stopping CLIProxyAPI...")
	stopStart := time.Now()
	if err := sm.StopService(); err != nil {
		logWarn("Service stop had issues: %v", err)
	}
	log("Service manager completed (%dms)", time.Since(stopStart).Milliseconds())

	// Poll for process stop (instead of fixed sleep)
	pollStart := time.Now()
	for i := 0; i < 10; i++ {
		if !isProcessRunningCrossPlatform("cliproxyapi") {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	if isProcessRunningCrossPlatform("cliproxyapi") {
		logWarn("Still running (%dms), force killing...", time.Since(pollStart).Milliseconds())
		killProcessForceCrossPlatform("cliproxyapi")
		// Brief wait for force kill
		for i := 0; i < 5; i++ {
			if !isProcessRunningCrossPlatform("cliproxyapi") {
				break
			}
			time.Sleep(100 * time.Millisecond)
		}
	}

	if !isProcessRunningCrossPlatform("cliproxyapi") {
		logSuccess("CLIProxyAPI stopped (%dms)", time.Since(startTime).Milliseconds())
	} else {
		logError("Failed to stop CLIProxyAPI")
		return fmt.Errorf("failed to stop")
	}

	return nil
}

func runRestart(cmd *cobra.Command, args []string) error {
	if err := runStop(cmd, args); err != nil {
		// Continue even if stop fails
	}
	// No fixed sleep - stop already confirmed process is gone
	return runStart(cmd, args)
}

// quickHealthCheck polls the service with short intervals for fast startup detection
func quickHealthCheck(cfg *Config, maxAttempts int) error {
	client := &http.Client{Timeout: 1 * time.Second}
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

		time.Sleep(300 * time.Millisecond)
	}

	return fmt.Errorf("service not responding after %d attempts", maxAttempts)
}
