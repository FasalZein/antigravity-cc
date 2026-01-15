package cli

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// Platform-specific implementations for cross-platform support

// ============================================================================
// PROCESS MANAGEMENT
// ============================================================================

// isProcessRunningCrossPlatform checks if a process is running (cross-platform)
func isProcessRunningCrossPlatform(name string) bool {
	switch runtime.GOOS {
	case "windows":
		cmd := exec.Command("tasklist", "/FI", fmt.Sprintf("IMAGENAME eq %s.exe", name), "/NH")
		out, err := cmd.Output()
		if err != nil {
			return false
		}
		return strings.Contains(string(out), name)
	default: // macOS, Linux
		cmd := exec.Command("pgrep", "-f", name)
		return cmd.Run() == nil
	}
}

// getProcessPIDCrossPlatform returns the PID of a running process (cross-platform)
func getProcessPIDCrossPlatform(name string) string {
	switch runtime.GOOS {
	case "windows":
		// Use PowerShell for reliable PID retrieval on Windows
		cmd := exec.Command("powershell", "-NoProfile", "-Command",
			fmt.Sprintf("(Get-Process -Name '%s' -ErrorAction SilentlyContinue | Select-Object -First 1).Id", name))
		out, err := cmd.Output()
		if err != nil {
			return ""
		}
		return strings.TrimSpace(string(out))
	default:
		cmd := exec.Command("pgrep", "-f", name)
		out, err := cmd.Output()
		if err != nil {
			return ""
		}
		lines := strings.Split(strings.TrimSpace(string(out)), "\n")
		if len(lines) > 0 {
			return lines[0]
		}
		return ""
	}
}

// killProcessCrossPlatform kills a process by name (cross-platform)
func killProcessCrossPlatform(name string) error {
	switch runtime.GOOS {
	case "windows":
		cmd := exec.Command("taskkill", "/F", "/IM", name+".exe")
		return cmd.Run()
	default:
		cmd := exec.Command("pkill", "-f", name)
		return cmd.Run()
	}
}

// killProcessForceCrossPlatform force kills a process (cross-platform)
func killProcessForceCrossPlatform(name string) error {
	switch runtime.GOOS {
	case "windows":
		cmd := exec.Command("taskkill", "/F", "/IM", name+".exe")
		return cmd.Run()
	default:
		cmd := exec.Command("pkill", "-9", "-f", name)
		return cmd.Run()
	}
}

// ============================================================================
// PORT MANAGEMENT
// ============================================================================

// isPortInUseCrossPlatform checks if a port is in use (cross-platform)
func isPortInUseCrossPlatform(port int) bool {
	switch runtime.GOOS {
	case "windows":
		cmd := exec.Command("powershell", "-NoProfile", "-Command",
			fmt.Sprintf("Get-NetTCPConnection -LocalPort %d -ErrorAction SilentlyContinue", port))
		return cmd.Run() == nil
	default:
		cmd := exec.Command("lsof", "-i", fmt.Sprintf(":%d", port))
		return cmd.Run() == nil
	}
}

// getPortProcessCrossPlatform returns info about what's using a port (cross-platform)
func getPortProcessCrossPlatform(port int) string {
	switch runtime.GOOS {
	case "windows":
		cmd := exec.Command("powershell", "-NoProfile", "-Command",
			fmt.Sprintf(`$conn = Get-NetTCPConnection -LocalPort %d -ErrorAction SilentlyContinue | Select-Object -First 1; if($conn) { $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue; if($proc) { "$($proc.Name) (PID: $($proc.Id))" } }`, port))
		out, err := cmd.Output()
		if err != nil {
			return ""
		}
		return strings.TrimSpace(string(out))
	default:
		cmd := exec.Command("lsof", "-i", fmt.Sprintf(":%d", port))
		out, err := cmd.Output()
		if err != nil {
			return ""
		}
		lines := strings.Split(string(out), "\n")
		if len(lines) > 1 {
			fields := strings.Fields(lines[1])
			if len(fields) >= 2 {
				return fmt.Sprintf("%s (PID: %s)", fields[0], fields[1])
			}
		}
		return ""
	}
}

// ============================================================================
// PATHS
// ============================================================================

// GetDefaultBinDir returns the default binary installation directory
func GetDefaultBinDir() string {
	home, _ := os.UserHomeDir()
	switch runtime.GOOS {
	case "windows":
		return filepath.Join(os.Getenv("LOCALAPPDATA"), "Programs", "CLIProxyAPI")
	default:
		return filepath.Join(home, ".local", "bin")
	}
}

// GetDefaultLogDir returns the default log directory
func GetDefaultLogDir() string {
	home, _ := os.UserHomeDir()
	switch runtime.GOOS {
	case "windows":
		return filepath.Join(os.Getenv("LOCALAPPDATA"), "CLIProxyAPI", "logs")
	default:
		return filepath.Join(home, ".local", "var", "log")
	}
}

// GetBinaryName returns the binary name with platform extension
func GetBinaryName(name string) string {
	if runtime.GOOS == "windows" {
		return name + ".exe"
	}
	return name
}

// ============================================================================
// SERVICE MANAGEMENT
// ============================================================================

// ServiceManager handles platform-specific service operations
type ServiceManager struct {
	cfg *Config
}

// NewServiceManager creates a new service manager
func NewServiceManager(cfg *Config) *ServiceManager {
	return &ServiceManager{cfg: cfg}
}

// IsServiceInstalled checks if the service is installed
func (sm *ServiceManager) IsServiceInstalled() bool {
	switch runtime.GOOS {
	case "darwin":
		plist := filepath.Join(os.Getenv("HOME"), "Library/LaunchAgents/com.cliproxy.api.plist")
		_, err := os.Stat(plist)
		return err == nil
	case "linux":
		// Check systemd user service
		service := filepath.Join(os.Getenv("HOME"), ".config/systemd/user/cliproxyapi.service")
		_, err := os.Stat(service)
		return err == nil
	case "windows":
		// Check if scheduled task exists
		cmd := exec.Command("schtasks", "/Query", "/TN", "CLIProxyAPI-Startup")
		return cmd.Run() == nil
	default:
		return false
	}
}

// StartService starts the service
func (sm *ServiceManager) StartService() error {
	switch runtime.GOOS {
	case "darwin":
		return sm.startServiceMacOS()
	case "linux":
		return sm.startServiceLinux()
	case "windows":
		return sm.startServiceWindows()
	default:
		return fmt.Errorf("unsupported platform: %s", runtime.GOOS)
	}
}

// StopService stops the service
func (sm *ServiceManager) StopService() error {
	switch runtime.GOOS {
	case "darwin":
		exec.Command("launchctl", "stop", "com.cliproxy.api").Run()
	case "linux":
		exec.Command("systemctl", "--user", "stop", "cliproxyapi").Run()
	case "windows":
		// Just kill the process on Windows
	}
	// Also kill any running process
	killProcessCrossPlatform("cliproxyapi")
	return nil
}

// RestartService restarts the service
func (sm *ServiceManager) RestartService() error {
	sm.StopService()
	return sm.StartService()
}

func (sm *ServiceManager) startServiceMacOS() error {
	plist := filepath.Join(os.Getenv("HOME"), "Library/LaunchAgents/com.cliproxy.api.plist")
	if _, err := os.Stat(plist); err != nil {
		// No plist, use direct start
		return sm.startServiceDirect()
	}

	// Direct start is much faster than launchctl for restarts
	// launchctl kickstart -k can take 10+ seconds
	// We use direct start and let launchd's KeepAlive handle future restarts
	return sm.startServiceDirect()
}

func (sm *ServiceManager) startServiceLinux() error {
	// Check if running in WSL without systemd
	if isWSL() && !hasSystemd() {
		log("WSL detected without systemd, using direct process management")
		return sm.startServiceDirect()
	}

	// Try systemd first
	cmd := exec.Command("systemctl", "--user", "start", "cliproxyapi")
	if err := cmd.Run(); err != nil {
		return sm.startServiceDirect()
	}
	return nil
}

func (sm *ServiceManager) startServiceWindows() error {
	binary := filepath.Join(sm.cfg.BinDir, GetBinaryName("cliproxyapi"))
	if _, err := os.Stat(binary); err != nil {
		return fmt.Errorf("binary not found: %s", binary)
	}

	logDir := GetDefaultLogDir()
	os.MkdirAll(logDir, 0755)
	logFile := filepath.Join(logDir, "cliproxyapi.log")

	// Start as detached process on Windows
	cmd := exec.Command("cmd", "/C", "start", "/B", binary, "--config", sm.cfg.ConfigPath)
	cmd.Dir = filepath.Dir(binary)

	// Redirect to log file
	f, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err == nil {
		cmd.Stdout = f
		cmd.Stderr = f
	}

	return cmd.Start()
}

func (sm *ServiceManager) startServiceDirect() error {
	binary := filepath.Join(sm.cfg.BinDir, GetBinaryName("cliproxyapi"))
	if _, err := os.Stat(binary); err != nil {
		return fmt.Errorf("binary not found: %s", binary)
	}

	logDir := GetDefaultLogDir()
	os.MkdirAll(logDir, 0755)
	logFile := filepath.Join(logDir, "cliproxyapi.log")

	f, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}

	cmd := exec.Command(binary, "--config", sm.cfg.ConfigPath)
	cmd.Stdout = f
	cmd.Stderr = f

	return cmd.Start()
}

// ============================================================================
// NOTIFICATIONS
// ============================================================================

// SendNotificationCrossPlatform sends a desktop notification (cross-platform)
func SendNotificationCrossPlatform(title, message string) {
	switch runtime.GOOS {
	case "darwin":
		exec.Command("terminal-notifier", "-title", title, "-message", message, "-sound", "default").Run()
	case "linux":
		exec.Command("notify-send", title, message).Run()
	case "windows":
		// Use PowerShell for Windows notifications
		script := fmt.Sprintf(`
			[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
			$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
			$textNodes = $template.GetElementsByTagName("text")
			$textNodes.Item(0).AppendChild($template.CreateTextNode("%s")) | Out-Null
			$textNodes.Item(1).AppendChild($template.CreateTextNode("%s")) | Out-Null
			$toast = [Windows.UI.Notifications.ToastNotification]::new($template)
			[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("CLIProxyAPI").Show($toast)
		`, title, message)
		exec.Command("powershell", "-NoProfile", "-Command", script).Run()
	}
}

// ============================================================================
// FILE OPERATIONS
// ============================================================================

// ReadLastLines reads the last N lines from a file (cross-platform)
func ReadLastLines(filePath string, n int) ([]string, error) {
	switch runtime.GOOS {
	case "windows":
		cmd := exec.Command("powershell", "-NoProfile", "-Command",
			fmt.Sprintf("Get-Content '%s' -Tail %d", filePath, n))
		out, err := cmd.Output()
		if err != nil {
			return nil, err
		}
		lines := strings.Split(strings.TrimSpace(string(out)), "\n")
		return lines, nil
	default:
		cmd := exec.Command("tail", "-n", fmt.Sprintf("%d", n), filePath)
		out, err := cmd.Output()
		if err != nil {
			return nil, err
		}
		lines := strings.Split(strings.TrimSpace(string(out)), "\n")
		return lines, nil
	}
}

// FollowFile follows a file like tail -f (returns a command that can be waited on)
func FollowFile(filePath string) *exec.Cmd {
	switch runtime.GOOS {
	case "windows":
		return exec.Command("powershell", "-NoProfile", "-Command",
			fmt.Sprintf("Get-Content '%s' -Wait -Tail 50", filePath))
	default:
		return exec.Command("tail", "-F", filePath)
	}
}
