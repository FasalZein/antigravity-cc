package cli

import (
	"fmt"
	"net/http"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

func NewStatusCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "status",
		Short: "Show service status",
		Long: `Show CLIProxyAPI service status including:
- Running service version
- Installed binary version
- Source code version
- CCR status
- Launchd/systemd service state`,
		RunE: runStatus,
	}

	return cmd
}

func runStatus(cmd *cobra.Command, args []string) error {
	cfg := detectConfig()

	fmt.Printf("%sServices:%s\n", colorBold, colorReset)

	// CLIProxyAPI status
	if isProcessRunning("cliproxyapi") {
		pid := getProcessPID("cliproxyapi")
		version := getBinaryVersion(cfg.BinPath)
		fmt.Printf("  CLIProxyAPI:  %srunning%s (PID: %s, %s) → :%d\n",
			colorGreen, colorReset, pid, version, cfg.Port)
	} else {
		fmt.Printf("  CLIProxyAPI:  %sstopped%s (use: cliproxyctl update)\n",
			colorRed, colorReset)
	}

	// CCR status
	if isProcessRunning("claude-code-router") {
		pid := getProcessPID("claude-code-router")
		fmt.Printf("  CCR:          %srunning%s (PID: %s) → :%d\n",
			colorGreen, colorReset, pid, cfg.CCRPort)
	} else {
		fmt.Printf("  CCR:          %sstopped%s (use: ccr start)\n",
			colorRed, colorReset)
	}

	fmt.Println()

	// Version info
	fmt.Printf("%sVersions:%s\n", colorBold, colorReset)

	// Running version (from API)
	runningVersion := getRunningVersion(cfg.Port)
	if runningVersion != "not running" {
		fmt.Printf("  Running: %s%s%s\n", colorGreen, runningVersion, colorReset)
	} else {
		fmt.Printf("  Running: %snot running%s\n", colorRed, colorReset)
	}

	// Binary version
	binaryVersion := getBinaryVersion(cfg.BinPath)
	if binaryVersion != "not installed" {
		fmt.Printf("  Binary:  %s\n", binaryVersion)
	} else {
		fmt.Printf("  Binary:  %snot installed%s\n", colorRed, colorReset)
	}

	// Source version
	sourceVersion := getSourceVersion(cfg.SourceDir)
	if sourceVersion != "unknown" {
		fmt.Printf("  Source:  %s\n", sourceVersion)

		// Check for remote updates
		remoteVersion := getRemoteVersion(cfg.SourceDir)
		if remoteVersion != "" && remoteVersion != sourceVersion {
			fmt.Printf("  Remote:  %s%s%s (update available!)\n",
				colorYellow, remoteVersion, colorReset)
		}
	} else {
		fmt.Printf("  Source:  %snot found%s\n", colorRed, colorReset)
	}

	// Backup version
	backupVersion := getBinaryVersion(cfg.BinPath + ".bak")
	if backupVersion != "not installed" && backupVersion != "unknown" {
		fmt.Printf("  Backup:  %s (for rollback)\n", backupVersion)
	}

	fmt.Println()

	// Launchd status (macOS only)
	if runtime.GOOS == "darwin" {
		fmt.Printf("%sLaunchd Services:%s\n", colorBold, colorReset)
		if isLaunchdServiceLoaded("com.cliproxy.api") {
			fmt.Printf("  com.cliproxy.api:     %sloaded%s\n", colorGreen, colorReset)
		} else {
			fmt.Printf("  com.cliproxy.api:     %snot loaded%s\n", colorYellow, colorReset)
		}
		if isLaunchdServiceLoaded("com.cliproxy.updater") {
			fmt.Printf("  com.cliproxy.updater: %sloaded%s (auto-update enabled)\n", colorGreen, colorReset)
		} else {
			fmt.Printf("  com.cliproxy.updater: %snot loaded%s\n", colorYellow, colorReset)
		}
		fmt.Println()
	}

	// Quick connectivity test
	fmt.Printf("%sConnectivity:%s\n", colorBold, colorReset)

	// Test CLIProxyAPI
	if testEndpoint(fmt.Sprintf("http://127.0.0.1:%d/v1/models", cfg.Port), cfg.APIKey) {
		fmt.Printf("  CLIProxyAPI (%d): %sresponding%s\n", cfg.Port, colorGreen, colorReset)
	} else {
		fmt.Printf("  CLIProxyAPI (%d): %snot responding%s\n", cfg.Port, colorRed, colorReset)
	}

	// Test CCR
	if testEndpoint(fmt.Sprintf("http://127.0.0.1:%d/health", cfg.CCRPort), "") {
		fmt.Printf("  CCR (%d):         %sresponding%s\n", cfg.CCRPort, colorGreen, colorReset)
	} else {
		fmt.Printf("  CCR (%d):         %snot responding%s\n", cfg.CCRPort, colorRed, colorReset)
	}

	return nil
}

func getRemoteVersion(sourceDir string) string {
	// Fetch latest from remote
	fetch := exec.Command("git", "fetch", "--tags", "--quiet")
	fetch.Dir = sourceDir
	fetch.Run()

	// Get remote version
	cmd := exec.Command("git", "describe", "--tags", "origin/main")
	cmd.Dir = sourceDir
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func testEndpoint(url, apiKey string) bool {
	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return false
	}
	if apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode == 200
}
