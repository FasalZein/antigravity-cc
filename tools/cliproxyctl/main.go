// cliproxyctl - CLI management tool for CLIProxyAPI
//
// This tool consolidates shell script functionality into a single Go binary.
// Shell scripts become thin wrappers that just call cliproxyctl commands.
//
// Commands:
//   - cliproxyctl install    Install/setup CLIProxyAPI from source
//   - cliproxyctl update     Self-update: git pull, go build, deploy, health check
//   - cliproxyctl start      Start the CLIProxyAPI service
//   - cliproxyctl stop       Stop the CLIProxyAPI service
//   - cliproxyctl restart    Restart the CLIProxyAPI service
//   - cliproxyctl status     Show service status
//   - cliproxyctl logs       View service logs
//   - cliproxyctl quota      Check Antigravity quota
//   - cliproxyctl rollback   Rollback to previous version
//   - cliproxyctl diagnose   Run diagnostics
package main

import (
	"fmt"
	"os"

	"cliproxyctl/internal/cli"

	"github.com/spf13/cobra"
)

var (
	Version   = "dev"
	Commit    = "unknown"
	BuildDate = "unknown"
)

func main() {
	rootCmd := &cobra.Command{
		Use:   "cliproxyctl",
		Short: "CLI management tool for CLIProxyAPI",
		Long: `cliproxyctl consolidates CLIProxyAPI management into a single binary.

This tool replaces the need for 'brew install' - it always builds from source
to ensure you have the latest version.

Service Commands:
  install    Install CLIProxyAPI from source (first-time setup)
  start      Start the CLIProxyAPI service
  stop       Stop the CLIProxyAPI service
  restart    Restart the CLIProxyAPI service
  status     Show service and version status
  logs       View service logs

Update Commands:
  update     Self-update: git pull, build, deploy, health check, auto-rollback
  rollback   Rollback to previous version

Utility Commands:
  quota      Check Antigravity quota (CLI or web dashboard)
  diagnose   Run system diagnostics`,
		Version: fmt.Sprintf("%s (commit: %s, built: %s)", Version, Commit, BuildDate),
	}

	// Service commands
	rootCmd.AddCommand(cli.NewInstallCmd())
	rootCmd.AddCommand(cli.NewStartCmd())
	rootCmd.AddCommand(cli.NewStopCmd())
	rootCmd.AddCommand(cli.NewRestartCmd())
	rootCmd.AddCommand(cli.NewStatusCmd())
	rootCmd.AddCommand(cli.NewLogsCmd())

	// Update commands
	rootCmd.AddCommand(cli.NewUpdateCmd())
	rootCmd.AddCommand(cli.NewRollbackCmd())

	// Utility commands
	rootCmd.AddCommand(cli.NewQuotaCmd())
	rootCmd.AddCommand(cli.NewDiagnoseCmd())

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
