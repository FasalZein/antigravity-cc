#!/usr/bin/env bash
# ============================================================================
# cliproxy-updater.sh - Thin wrapper for cliproxyctl update
# ============================================================================
# This script delegates to cliproxyctl for the actual update logic.
# Kept for backwards compatibility with existing launchd/cron jobs.
# ============================================================================

set -euo pipefail

# Detect script directory
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# PATH Setup for cron/systemd environments
export PATH="$HOME/go/bin:$HOME/.local/bin:/usr/local/go/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
export GOPATH="${GOPATH:-$HOME/go}"

# cliproxyctl location
CLIPROXYCTL="${SCRIPT_DIR}/tools/cliproxyctl/cliproxyctl"

# Ensure cliproxyctl is built
ensure_cliproxyctl() {
    if [[ ! -x "$CLIPROXYCTL" ]]; then
        local tool_dir="${SCRIPT_DIR}/tools/cliproxyctl"
        if [[ -f "$tool_dir/main.go" ]]; then
            echo "[cliproxy-updater] Building cliproxyctl..."
            if command -v go &>/dev/null; then
                (cd "$tool_dir" && go build -o cliproxyctl .) || {
                    echo "[cliproxy-updater] Failed to build cliproxyctl"
                    exit 1
                }
            else
                echo "[cliproxy-updater] Go not installed"
                exit 1
            fi
        else
            echo "[cliproxy-updater] cliproxyctl source not found"
            exit 1
        fi
    fi
}

# Main
ensure_cliproxyctl

case "${1:-update}" in
    update)
        exec "$CLIPROXYCTL" update
        ;;
    status)
        exec "$CLIPROXYCTL" status
        ;;
    rollback)
        exec "$CLIPROXYCTL" rollback
        ;;
    *)
        echo "Usage: $0 {update|status|rollback}"
        echo "This is a thin wrapper around cliproxyctl."
        echo "For full functionality, use: cliproxyctl --help"
        exit 1
        ;;
esac
