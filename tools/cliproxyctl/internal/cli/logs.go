package cli

import (
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/spf13/cobra"
)

var (
	logsFollow bool
	logsLines  int
	logsAll    bool
)

func NewLogsCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "logs",
		Short: "View CLIProxyAPI logs",
		Long: `View CLIProxyAPI service logs.

Examples:
  cliproxyctl logs           # Show last 50 lines
  cliproxyctl logs -n 100    # Show last 100 lines
  cliproxyctl logs -f        # Follow logs (like tail -f)
  cliproxyctl logs --all     # Open full log in pager`,
		RunE: runLogs,
	}

	cmd.Flags().BoolVarP(&logsFollow, "follow", "f", false, "Follow log output")
	cmd.Flags().IntVarP(&logsLines, "lines", "n", 50, "Number of lines to show")
	cmd.Flags().BoolVar(&logsAll, "all", false, "Open full log in pager")

	return cmd
}

func runLogs(cmd *cobra.Command, args []string) error {
	logDir := GetDefaultLogDir()
	logFile := filepath.Join(logDir, "cliproxyapi.log")

	if _, err := os.Stat(logFile); err != nil {
		logError("Log file not found at %s", logFile)
		return fmt.Errorf("log file not found")
	}

	if logsFollow {
		log("Following logs at %s (Ctrl+C to stop)...", logFile)

		followCmd := FollowFile(logFile)
		followCmd.Stdout = os.Stdout
		followCmd.Stderr = os.Stderr

		// Handle interrupt
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

		go func() {
			<-sigChan
			if followCmd.Process != nil {
				followCmd.Process.Kill()
			}
		}()

		return followCmd.Run()
	}

	if logsAll {
		// Open in pager
		return openInPager(logFile)
	}

	// Show last N lines
	lines, err := ReadLastLines(logFile, logsLines)
	if err != nil {
		logError("Failed to read log file: %v", err)
		return err
	}

	for _, line := range lines {
		fmt.Println(line)
	}

	return nil
}

func openInPager(filePath string) error {
	// Try common pagers
	pagers := []string{"less", "more"}
	if p := os.Getenv("PAGER"); p != "" {
		pagers = []string{p}
	}

	for _, pager := range pagers {
		cmd := exec.Command(pager, "+G", filePath)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err == nil {
			return nil
		}
	}

	// Fallback: just read the file
	content, err := os.ReadFile(filePath)
	if err != nil {
		return err
	}
	fmt.Print(string(content))
	return nil
}
