package cli

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// Config holds runtime configuration
type Config struct {
	BaseDir    string // Base CLIProxyAPI directory
	SourceDir  string // cliproxy-source directory
	BinDir     string // Binary directory (~/.local/bin)
	BinPath    string // Full path to cliproxyapi binary
	ConfigPath string // config.yaml path
	Port       int    // CLIProxyAPI port
	CCRPort    int    // CCR port
	APIKey     string // API key from env
	LogDir     string // Log directory
}

// detectConfig auto-detects configuration paths
func detectConfig() *Config {
	home, _ := os.UserHomeDir()
	if home == "" {
		home = os.Getenv("HOME")
	}
	// Windows fallback
	if home == "" && runtime.GOOS == "windows" {
		home = os.Getenv("USERPROFILE")
	}

	// Try to find base directory
	baseDir := os.Getenv("CLIPROXY_DIR")
	if baseDir == "" {
		// Try relative to executable
		exe, _ := os.Executable()
		if exe != "" {
			// If running from tools/cliproxyctl, go up two levels
			dir := filepath.Dir(exe)
			if filepath.Base(filepath.Dir(dir)) == "tools" {
				baseDir = filepath.Dir(filepath.Dir(dir))
			}
		}
	}
	if baseDir == "" {
		// Default fallback - common locations (platform-specific)
		var candidates []string
		if runtime.GOOS == "windows" {
			candidates = []string{
				filepath.Join(home, "Dev", "Code Forge", "CLIProxyAPI"),
				filepath.Join(home, "Developer", "CLIProxyAPI"),
				filepath.Join(home, "CLIProxyAPI"),
				filepath.Join(os.Getenv("USERPROFILE"), "CLIProxyAPI"),
			}
		} else {
			candidates = []string{
				filepath.Join(home, "Dev/Code Forge/CLIProxyAPI"),
				filepath.Join(home, "Developer/CLIProxyAPI"),
				filepath.Join(home, "CLIProxyAPI"),
			}
		}
		for _, c := range candidates {
			if _, err := os.Stat(c); err == nil {
				baseDir = c
				break
			}
		}
	}

	// Use platform-specific directories
	binDir := GetDefaultBinDir()
	logDir := GetDefaultLogDir()

	cfg := &Config{
		BaseDir:    baseDir,
		SourceDir:  filepath.Join(baseDir, "cliproxy-source"),
		BinDir:     binDir,
		BinPath:    filepath.Join(binDir, GetBinaryName("cliproxyapi")),
		ConfigPath: filepath.Join(baseDir, "config.yaml"),
		Port:       8317,
		CCRPort:    3456,
		LogDir:     logDir,
	}

	// Get API key - .env file takes precedence over environment variable
	// Default to "dummy" if neither is set
	envFile := filepath.Join(baseDir, ".env")
	if data, err := os.ReadFile(envFile); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			if strings.HasPrefix(line, "CLIPROXY_API_KEY=") {
				cfg.APIKey = strings.TrimPrefix(line, "CLIPROXY_API_KEY=")
				cfg.APIKey = strings.Trim(cfg.APIKey, "\"'")
				break
			}
		}
	}
	// Fall back to environment variable if not in .env
	if cfg.APIKey == "" {
		cfg.APIKey = os.Getenv("CLIPROXY_API_KEY")
	}
	// Final fallback to "dummy"
	if cfg.APIKey == "" {
		cfg.APIKey = "dummy"
	}

	return cfg
}

// getSourceVersion returns the git tag/commit for the source
func getSourceVersion(sourceDir string) string {
	cmd := exec.Command("git", "describe", "--tags", "--always")
	cmd.Dir = sourceDir
	out, err := cmd.Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}

// getBinaryVersion returns the version of the installed binary
// Uses a 5-second timeout to prevent hanging if the binary doesn't respond
func getBinaryVersion(binPath string) string {
	if _, err := os.Stat(binPath); err != nil {
		return "not installed"
	}

	// Create context with 5-second timeout to prevent hanging
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Use --version flag to get version info without starting the server
	cmd := exec.CommandContext(ctx, binPath, "--version")
	out, err := cmd.CombinedOutput()

	// Check if timeout occurred
	if ctx.Err() == context.DeadlineExceeded {
		return "timeout"
	}
	if err != nil {
		// If --version flag is not supported, try without args (legacy)
		ctx2, cancel2 := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel2()
		cmd2 := exec.CommandContext(ctx2, binPath)
		out, _ = cmd2.CombinedOutput()
		if ctx2.Err() == context.DeadlineExceeded {
			return "timeout"
		}
	}

	for _, line := range strings.Split(string(out), "\n") {
		if strings.Contains(line, "Version:") {
			// Extract version: "Version: v1.2.3," -> "v1.2.3"
			parts := strings.Split(line, "Version:")
			if len(parts) > 1 {
				version := strings.TrimSpace(parts[1])
				version = strings.TrimSuffix(version, ",")
				return version
			}
		}
	}
	return "unknown"
}

// getRunningVersion returns the version from the running service
func getRunningVersion(port int) string {
	if !isProcessRunning("cliproxyapi") {
		return "not running"
	}

	// Try to fetch from API
	cmd := exec.Command("curl", "-sf", fmt.Sprintf("http://127.0.0.1:%d/", port))
	out, err := cmd.Output()
	if err != nil {
		return "unknown"
	}

	// Look for version in response
	content := string(out)
	for _, line := range strings.Split(content, "\n") {
		if idx := strings.Index(line, "v"); idx >= 0 {
			// Extract something like v1.2.3
			rest := line[idx:]
			for i, c := range rest {
				if i > 0 && !isVersionChar(c) {
					return rest[:i]
				}
			}
		}
	}
	return "unknown"
}

func isVersionChar(c rune) bool {
	return (c >= '0' && c <= '9') || c == '.' || c == 'v' || c == '-'
}

// isProcessRunning checks if a process with the given name is running (uses cross-platform version)
func isProcessRunning(name string) bool {
	return isProcessRunningCrossPlatform(name)
}

// getProcessPID returns the PID of a running process (uses cross-platform version)
func getProcessPID(name string) string {
	return getProcessPIDCrossPlatform(name)
}

// Color helpers
var (
	colorReset  = "\033[0m"
	colorRed    = "\033[31m"
	colorGreen  = "\033[32m"
	colorYellow = "\033[33m"
	colorBold   = "\033[1m"
)

func init() {
	// Disable colors if not a terminal
	if !isTerminal() {
		colorReset = ""
		colorRed = ""
		colorGreen = ""
		colorYellow = ""
		colorBold = ""
	}
}

func isTerminal() bool {
	fi, _ := os.Stdout.Stat()
	return (fi.Mode() & os.ModeCharDevice) != 0
}

func log(format string, args ...interface{}) {
	fmt.Printf(colorGreen+"[cliproxyctl]"+colorReset+" "+format+"\n", args...)
}

func logWarn(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, colorYellow+"[cliproxyctl]"+colorReset+" "+format+"\n", args...)
}

func logError(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, colorRed+"[cliproxyctl]"+colorReset+" ERROR: "+format+"\n", args...)
}

func logSuccess(format string, args ...interface{}) {
	fmt.Printf(colorGreen+"[cliproxyctl] ✓"+colorReset+" "+format+"\n", args...)
}

// isPortInUse checks if a port is in use (uses cross-platform version)
func isPortInUse(port int) bool {
	return isPortInUseCrossPlatform(port)
}

// getPortProcess returns info about what's using a port (uses cross-platform version)
func getPortProcess(port int) string {
	return getPortProcessCrossPlatform(port)
}

// checkConnectivity tests if a URL is reachable (uses native Go http, no curl dependency)
func checkConnectivity(url string, apiKey string) bool {
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
	defer resp.Body.Close()
	return resp.StatusCode < 500
}

// isWSL detects if running in Windows Subsystem for Linux
func isWSL() bool {
	if runtime.GOOS != "linux" {
		return false
	}
	// Check for WSL indicators
	// Method 1: Check /proc/version for Microsoft/WSL
	if data, err := os.ReadFile("/proc/version"); err == nil {
		content := strings.ToLower(string(data))
		if strings.Contains(content, "microsoft") || strings.Contains(content, "wsl") {
			return true
		}
	}
	// Method 2: Check for WSL environment variable
	if os.Getenv("WSL_DISTRO_NAME") != "" {
		return true
	}
	// Method 3: Check for WSL interop
	if _, err := os.Stat("/proc/sys/fs/binfmt_misc/WSLInterop"); err == nil {
		return true
	}
	return false
}

// isWSL2 detects if running in WSL2 specifically (has better systemd support)
func isWSL2() bool {
	if !isWSL() {
		return false
	}
	// WSL2 has a different kernel version pattern
	if data, err := os.ReadFile("/proc/version"); err == nil {
		content := strings.ToLower(string(data))
		// WSL2 uses a real Linux kernel, WSL1 shows "microsoft" differently
		return strings.Contains(content, "wsl2") || strings.Contains(content, "microsoft-standard")
	}
	return false
}

// hasSystemd checks if systemd is available (important for WSL)
func hasSystemd() bool {
	if runtime.GOOS != "linux" {
		return false
	}
	// Check if systemd is PID 1
	if data, err := os.ReadFile("/proc/1/comm"); err == nil {
		return strings.TrimSpace(string(data)) == "systemd"
	}
	// Fallback: check if systemctl is available and working
	cmd := exec.Command("systemctl", "--user", "is-system-running")
	return cmd.Run() == nil
}

// isLaunchdServiceLoaded checks if a launchd service is loaded
func isLaunchdServiceLoaded(service string) bool {
	if runtime.GOOS != "darwin" {
		return false
	}
	cmd := exec.Command("launchctl", "list", service)
	return cmd.Run() == nil
}
