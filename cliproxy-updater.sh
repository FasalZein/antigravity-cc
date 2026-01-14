#!/usr/bin/env bash
# ============================================================================
# cliproxy-updater.sh - Automatic CLIProxyAPI Build & Deploy
# ============================================================================
# Runs via launchd every 12 hours. Pulls latest, builds, health checks,
# and auto-rollbacks if something breaks.
# ============================================================================

set -euo pipefail

# Configuration
CLIPROXY_SOURCE_DIR="${CLIPROXY_SOURCE_DIR:-$HOME/Dev/Code Forge/CLIProxyAPI/cliproxy-source}"
CLIPROXY_BIN_DIR="${CLIPROXY_BIN_DIR:-$HOME/.local/bin}"
CLIPROXY_CONFIG="${CLIPROXY_CONFIG:-$HOME/Dev/Code Forge/CLIProxyAPI/config.yaml}"
CLIPROXY_PORT="${CLIPROXY_PORT:-8317}"
CLIPROXY_API_KEY="${CLIPROXY_API_KEY:-}"
LOG_FILE="${HOME}/.local/var/log/cliproxy-updater.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# Get current running version
get_running_version() {
    if pgrep -f "cliproxyapi" > /dev/null 2>&1; then
        curl -sf "http://127.0.0.1:${CLIPROXY_PORT}/" 2>/dev/null | grep -o 'v[0-9.]*' | head -1 || echo "unknown"
    else
        echo "not running"
    fi
}

# Get installed binary version
get_binary_version() {
    if [[ -x "${CLIPROXY_BIN_DIR}/cliproxyapi" ]]; then
        "${CLIPROXY_BIN_DIR}/cliproxyapi" 2>&1 | grep "Version:" | sed 's/.*Version: \([^,]*\).*/\1/' || echo "unknown"
    else
        echo "not installed"
    fi
}

# Get source version
get_source_version() {
    cd "$CLIPROXY_SOURCE_DIR" 2>/dev/null && git describe --tags --always 2>/dev/null || echo "unknown"
}

# Health check
health_check() {
    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "http://127.0.0.1:${CLIPROXY_PORT}/v1/models" -H "Authorization: Bearer ${CLIPROXY_API_KEY}" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        ((attempt++))
    done
    return 1
}

# Stop CLIProxyAPI
stop_cliproxy() {
    log "Stopping CLIProxyAPI..."
    pkill -f "cliproxyapi" 2>/dev/null || true
    sleep 2
}

# Start CLIProxyAPI
start_cliproxy() {
    log "Starting CLIProxyAPI..."
    nohup "${CLIPROXY_BIN_DIR}/cliproxyapi" --config "$CLIPROXY_CONFIG" >> "${HOME}/.local/var/log/cliproxyapi.log" 2>&1 &
    sleep 3
}

# Rollback to backup
rollback() {
    log_error "Rolling back to previous version..."
    if [[ -f "${CLIPROXY_BIN_DIR}/cliproxyapi.bak" ]]; then
        stop_cliproxy
        mv "${CLIPROXY_BIN_DIR}/cliproxyapi" "${CLIPROXY_BIN_DIR}/cliproxyapi.failed" 2>/dev/null || true
        mv "${CLIPROXY_BIN_DIR}/cliproxyapi.bak" "${CLIPROXY_BIN_DIR}/cliproxyapi"
        start_cliproxy
        if health_check; then
            log "Rollback successful"
            # Send notification (optional - uses terminal-notifier if available)
            command -v terminal-notifier >/dev/null && \
                terminal-notifier -title "CLIProxyAPI" -message "Rollback successful after failed update" -sound default 2>/dev/null || true
            return 0
        else
            log_error "Rollback failed - service not responding"
            return 1
        fi
    else
        log_error "No backup available for rollback"
        return 1
    fi
}

# Main update function
update() {
    log "=== CLIProxyAPI Auto-Update Started ==="

    # Load API key from .env if not set
    if [[ -z "$CLIPROXY_API_KEY" && -f "$HOME/Dev/Code Forge/CLIProxyAPI/.env" ]]; then
        source "$HOME/Dev/Code Forge/CLIProxyAPI/.env"
    fi

    local old_version=$(get_source_version)

    # Pull latest
    log "Pulling latest changes..."
    cd "$CLIPROXY_SOURCE_DIR"
    git fetch --tags --quiet
    git reset --hard origin/main --quiet

    local new_version=$(get_source_version)

    # Check if update needed
    local current_binary_version=$(get_binary_version)
    if [[ "$new_version" == "$current_binary_version" ]]; then
        log "Already at latest version: $new_version"
        return 0
    fi

    log "Update available: $current_binary_version → $new_version"

    # Build new version
    log "Building $new_version..."
    local VERSION=$(git describe --tags --always)
    local COMMIT=$(git rev-parse --short HEAD)
    local BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local DEFAULT_CONFIG="$CLIPROXY_CONFIG"

    if ! go build -ldflags "-X 'main.Version=$VERSION' -X 'main.Commit=$COMMIT' -X 'main.BuildDate=$BUILD_DATE' -X 'main.DefaultConfigPath=$DEFAULT_CONFIG'" -o cliproxyapi.new ./cmd/server 2>>"$LOG_FILE"; then
        log_error "Build failed"
        rm -f cliproxyapi.new
        return 1
    fi

    # Backup current binary
    if [[ -f "${CLIPROXY_BIN_DIR}/cliproxyapi" ]]; then
        cp "${CLIPROXY_BIN_DIR}/cliproxyapi" "${CLIPROXY_BIN_DIR}/cliproxyapi.bak"
    fi

    # Deploy new binary
    log "Deploying new binary..."
    mv cliproxyapi.new "${CLIPROXY_BIN_DIR}/cliproxyapi"
    chmod +x "${CLIPROXY_BIN_DIR}/cliproxyapi"

    # Restart service
    stop_cliproxy
    start_cliproxy

    # Health check
    log "Running health check..."
    if health_check; then
        log "Update successful: $new_version"
        rm -f "${CLIPROXY_BIN_DIR}/cliproxyapi.failed"
        # Send success notification
        command -v terminal-notifier >/dev/null && \
            terminal-notifier -title "CLIProxyAPI" -message "Updated to $new_version" -sound default 2>/dev/null || true
        return 0
    else
        log_error "Health check failed after update"
        rollback
        return 1
    fi
}

# Status command
status() {
    echo "CLIProxyAPI Status:"
    echo "  Running:   $(get_running_version)"
    echo "  Binary:    $(get_binary_version)"
    echo "  Source:    $(get_source_version)"
    echo "  Config:    $CLIPROXY_CONFIG"
    echo "  Log:       $LOG_FILE"
}

# Manual rollback command
manual_rollback() {
    if [[ -f "${CLIPROXY_BIN_DIR}/cliproxyapi.bak" ]]; then
        rollback
    else
        echo "No backup available"
        exit 1
    fi
}

# Parse command
case "${1:-update}" in
    update)
        update
        ;;
    status)
        status
        ;;
    rollback)
        manual_rollback
        ;;
    build-only)
        log "Building without deploy..."
        cd "$CLIPROXY_SOURCE_DIR"
        git fetch --tags --quiet
        git reset --hard origin/main --quiet
        VERSION=$(git describe --tags --always)
        COMMIT=$(git rev-parse --short HEAD)
        BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        DEFAULT_CONFIG="$CLIPROXY_CONFIG"
        go build -ldflags "-X 'main.Version=$VERSION' -X 'main.Commit=$COMMIT' -X 'main.BuildDate=$BUILD_DATE' -X 'main.DefaultConfigPath=$DEFAULT_CONFIG'" -o cliproxyapi ./cmd/server
        log "Built $VERSION"
        ;;
    *)
        echo "Usage: $0 {update|status|rollback|build-only}"
        exit 1
        ;;
esac
