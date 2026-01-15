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

func NewDiagnoseCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "diagnose",
		Short: "Run system diagnostics",
		Long: `Run comprehensive diagnostics for CLIProxyAPI including:
- Installation verification
- Source repository status
- Configuration validation
- API key status
- Port availability
- Service status
- Log analysis
- Connectivity tests`,
		RunE: runDiagnose,
	}

	return cmd
}

func runDiagnose(cmd *cobra.Command, args []string) error {
	cfg := detectConfig()

	fmt.Printf("%s=== CLIProxyAPI Diagnostics ===%s\n\n", colorBold, colorReset)

	// 0. Platform Info
	fmt.Printf("%s0. Platform:%s\n", colorBold, colorReset)
	fmt.Printf("   OS: %s/%s\n", runtime.GOOS, runtime.GOARCH)
	if isWSL() {
		if isWSL2() {
			fmt.Printf("   Environment: %sWSL2%s\n", colorGreen, colorReset)
		} else {
			fmt.Printf("   Environment: %sWSL1%s\n", colorYellow, colorReset)
		}
		if hasSystemd() {
			fmt.Printf("   Systemd: %savailable%s\n", colorGreen, colorReset)
		} else {
			fmt.Printf("   Systemd: %snot available%s (direct process management)\n", colorYellow, colorReset)
		}
	}
	fmt.Println()

	// 1. CLIProxyAPI Installation
	fmt.Printf("%s1. CLIProxyAPI Installation:%s\n", colorBold, colorReset)
	if _, err := os.Stat(cfg.BinPath); err == nil {
		fmt.Printf("   Binary: %s\n", cfg.BinPath)
		version := getBinaryVersion(cfg.BinPath)
		fmt.Printf("   Version: %s\n", version)
	} else {
		fmt.Printf("   %sNOT INSTALLED%s - run: cliproxyctl update\n", colorRed, colorReset)
	}
	fmt.Println()

	// 2. Source Repository
	fmt.Printf("%s2. Source Repository:%s\n", colorBold, colorReset)
	if _, err := os.Stat(cfg.SourceDir); err == nil {
		fmt.Printf("   Path: %s\n", cfg.SourceDir)
		fmt.Printf("   Version: %s\n", getSourceVersion(cfg.SourceDir))
		fmt.Printf("   Branch: %s\n", getGitBranch(cfg.SourceDir))

		// Check for uncommitted changes
		if hasUncommittedChanges(cfg.SourceDir) {
			fmt.Printf("   Status: %shas uncommitted changes%s\n", colorYellow, colorReset)
		} else {
			fmt.Printf("   Status: %sclean%s\n", colorGreen, colorReset)
		}
	} else {
		fmt.Printf("   %sNOT FOUND%s at %s\n", colorRed, colorReset, cfg.SourceDir)
	}
	fmt.Println()

	// 3. Go Installation
	fmt.Printf("%s3. Go Installation:%s\n", colorBold, colorReset)
	if goVersion, err := getGoVersion(); err == nil {
		fmt.Printf("   Go: %s\n", goVersion)
	} else {
		fmt.Printf("   Go: %sNOT FOUND%s\n", colorRed, colorReset)
	}
	fmt.Println()

	// 4. Configuration
	fmt.Printf("%s4. Configuration:%s\n", colorBold, colorReset)
	if _, err := os.Stat(cfg.ConfigPath); err == nil {
		fmt.Printf("   Config: %s\n", cfg.ConfigPath)
	} else {
		fmt.Printf("   Config: %sNOT FOUND%s at %s\n", colorRed, colorReset, cfg.ConfigPath)
	}
	fmt.Println()

	// 5. API Key
	fmt.Printf("%s5. API Key:%s\n", colorBold, colorReset)
	if cfg.APIKey != "" {
		fmt.Printf("   CLIPROXY_API_KEY: %sset%s (%d chars)\n", colorGreen, colorReset, len(cfg.APIKey))
	} else {
		fmt.Printf("   CLIPROXY_API_KEY: %sNOT SET%s\n", colorRed, colorReset)
	}
	fmt.Println()

	// 6. Ports
	fmt.Printf("%s6. Ports:%s\n", colorBold, colorReset)
	if isPortInUse(cfg.Port) {
		process := getPortProcess(cfg.Port)
		fmt.Printf("   Port %d: %sin use%s - %s\n", cfg.Port, colorGreen, colorReset, process)
	} else {
		fmt.Printf("   Port %d: %sfree%s\n", cfg.Port, colorYellow, colorReset)
	}
	if isPortInUse(cfg.CCRPort) {
		process := getPortProcess(cfg.CCRPort)
		fmt.Printf("   Port %d: %sin use%s - %s\n", cfg.CCRPort, colorGreen, colorReset, process)
	} else {
		fmt.Printf("   Port %d: %sfree%s\n", cfg.CCRPort, colorYellow, colorReset)
	}
	fmt.Println()

	// 7. Service Management
	fmt.Printf("%s7. Service Management:%s\n", colorBold, colorReset)
	switch runtime.GOOS {
	case "darwin":
		services := []string{"com.cliproxy.api", "com.cliproxy.updater"}
		for _, svc := range services {
			if isLaunchdServiceLoaded(svc) {
				fmt.Printf("   %s: %sloaded%s\n", svc, colorGreen, colorReset)
			} else {
				fmt.Printf("   %s: %snot loaded%s\n", svc, colorYellow, colorReset)
			}
		}
	case "linux":
		if isWSL() && !hasSystemd() {
			fmt.Printf("   WSL without systemd - using direct process management\n")
		} else {
			// Check systemd service status
			cmd := exec.Command("systemctl", "--user", "is-active", "cliproxyapi")
			out, _ := cmd.Output()
			status := strings.TrimSpace(string(out))
			if status == "active" {
				fmt.Printf("   cliproxyapi.service: %sactive%s\n", colorGreen, colorReset)
			} else {
				fmt.Printf("   cliproxyapi.service: %s%s%s\n", colorYellow, status, colorReset)
			}
		}
	case "windows":
		// Check scheduled task
		cmd := exec.Command("schtasks", "/Query", "/TN", "CLIProxyAPI-Startup")
		if cmd.Run() == nil {
			fmt.Printf("   CLIProxyAPI-Startup task: %sexists%s\n", colorGreen, colorReset)
		} else {
			fmt.Printf("   CLIProxyAPI-Startup task: %snot found%s\n", colorYellow, colorReset)
		}
	}
	fmt.Println()

	// 8. Recent Logs
	fmt.Printf("%s8. Recent Logs:%s\n", colorBold, colorReset)
	logFile := filepath.Join(cfg.LogDir, "cliproxyapi.log")
	if _, err := os.Stat(logFile); err == nil {
		fmt.Printf("   Log file: %s\n", logFile)
		showRecentLogErrors(logFile, 3)
	} else {
		fmt.Printf("   No log file at %s\n", logFile)
	}
	fmt.Println()

	// 9. Connectivity Test
	fmt.Printf("%s9. Connectivity Test:%s\n", colorBold, colorReset)

	// Test CLIProxyAPI
	url := fmt.Sprintf("http://127.0.0.1:%d/v1/models", cfg.Port)
	if checkConnectivity(url, cfg.APIKey) {
		fmt.Printf("   CLIProxyAPI (%d): %sresponding%s\n", cfg.Port, colorGreen, colorReset)
	} else {
		fmt.Printf("   CLIProxyAPI (%d): %snot responding%s\n", cfg.Port, colorRed, colorReset)
	}

	// Test CCR
	ccrURL := fmt.Sprintf("http://127.0.0.1:%d/health", cfg.CCRPort)
	if checkConnectivity(ccrURL, "") {
		fmt.Printf("   CCR (%d): %sresponding%s\n", cfg.CCRPort, colorGreen, colorReset)
	} else {
		fmt.Printf("   CCR (%d): %snot responding%s\n", cfg.CCRPort, colorRed, colorReset)
	}
	fmt.Println()

	// 10. Auth Files
	fmt.Printf("%s10. Antigravity Auth Files:%s\n", colorBold, colorReset)
	authDir := filepath.Join(os.Getenv("HOME"), ".cli-proxy-api")
	files, err := os.ReadDir(authDir)
	if err == nil {
		count := 0
		for _, f := range files {
			if strings.HasPrefix(f.Name(), "antigravity-") && strings.HasSuffix(f.Name(), ".json") {
				count++
			}
		}
		if count > 0 {
			fmt.Printf("   Found %d auth file(s) in %s\n", count, authDir)
		} else {
			fmt.Printf("   %sNo auth files found%s in %s\n", colorYellow, colorReset, authDir)
		}
	} else {
		fmt.Printf("   Auth directory not found: %s\n", authDir)
	}
	fmt.Println()

	fmt.Printf("%s=== End Diagnostics ===%s\n", colorBold, colorReset)

	return nil
}

func getGitBranch(dir string) string {
	cmd := exec.Command("git", "branch", "--show-current")
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}

func hasUncommittedChanges(dir string) bool {
	cmd := exec.Command("git", "status", "--porcelain")
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		return false
	}
	return len(strings.TrimSpace(string(out))) > 0
}

func getGoVersion() (string, error) {
	cmd := exec.Command("go", "version")
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func showRecentLogErrors(logFile string, lines int) {
	// Use cross-platform ReadLastLines
	logLines, err := ReadLastLines(logFile, lines)
	if err != nil {
		fmt.Printf("   Unable to read log file: %v\n", err)
		return
	}

	if len(logLines) == 0 || (len(logLines) == 1 && logLines[0] == "") {
		fmt.Printf("   No recent log entries\n")
		return
	}

	fmt.Printf("   Last %d lines:\n", lines)
	for _, line := range logLines {
		if len(line) > 70 {
			line = line[:67] + "..."
		}
		fmt.Printf("   │ %s\n", line)
	}
}
