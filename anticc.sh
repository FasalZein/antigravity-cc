#!/usr/bin/env bash
# ============================================================================
# anticc - Antigravity Claude Code CLI (Profile Manager)
# ============================================================================
# Usage: source "/path/to/anticc.sh"
#
# Commands:
#   anticc-on         Enable Antigravity mode (set env vars)
#   anticc-off        Disable Antigravity mode (unset env vars)
#   anticc-status     Check current profile status
#   anticc-update     Pull latest source and rebuild CLIProxyAPI
#   anticc-rollback   Rollback to previous version if update fails
#   anticc-version    Show version info (running, binary, source)
#   anticc-quota      Check quota for all accounts (CLI)
#   anticc-quota-web  Open quota dashboard in browser
#
# CLIProxyAPI is built from source and auto-updated every 12 hours.
# Services are managed via launchd (not brew).
# ============================================================================

# Detect script directory
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    ANTICC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "$ZSH_VERSION" ]]; then
    eval 'ANTICC_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"'
fi

# ============================================================================
# CONFIGURATION
# ============================================================================
ANTICC_CLIPROXY_PORT=8317
ANTICC_CCR_PORT=3456

export CLIPROXY_DIR="${CLIPROXY_DIR:-$ANTICC_DIR}"

# Source-based installation paths
CLIPROXY_BIN_DIR="${HOME}/.local/bin"
CLIPROXY_SOURCE_DIR="${ANTICC_DIR}/cliproxy-source"
CLIPROXY_UPDATER="${ANTICC_DIR}/cliproxy-updater.sh"

# Load API key from .env if not set
[[ -z "$CLIPROXY_API_KEY" && -f "$CLIPROXY_DIR/.env" ]] && source "$CLIPROXY_DIR/.env"
export CLIPROXY_API_KEY="${CLIPROXY_API_KEY:-}"

# Internal settings (exported when anticc-on is called)
# Using CCR (Claude Code Router) on port 3456
_ANTICC_BASE_URL="http://127.0.0.1:${ANTICC_CCR_PORT}"
_ANTICC_API_KEY="$CLIPROXY_API_KEY"

# Model configuration
_ANTICC_OPUS_MODEL="gemini-claude-opus-4-5-thinking"
_ANTICC_SONNET_MODEL="gemini-claude-sonnet-4-5-thinking"
_ANTICC_HAIKU_MODEL="gemini-3-flash-preview"

# Track state
ANTICC_ENABLED="${ANTICC_ENABLED:-false}"

# Auto-enable on source (for IDE plugins like Claude Code)
# Default: true (like old script behavior)
# Set ANTICC_AUTO_ENABLE=false in your .zshrc before sourcing to disable
ANTICC_AUTO_ENABLE="${ANTICC_AUTO_ENABLE:-true}"

# ============================================================================
# COLORS
# ============================================================================
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null) -ge 8 ]]; then
    _C_GREEN=$(tput setaf 2); _C_YELLOW=$(tput setaf 3)
    _C_RED=$(tput setaf 1); _C_BOLD=$(tput bold); _C_NC=$(tput sgr0)
else
    _C_GREEN=''; _C_YELLOW=''; _C_RED=''; _C_BOLD=''; _C_NC=''
fi

_log() { echo -e "${_C_GREEN}[anticc]${_C_NC} $*"; }
_warn() { echo -e "${_C_YELLOW}[anticc]${_C_NC} $*" >&2; }

# ============================================================================
# UTILITIES (for status display only)
# ============================================================================
_is_running() { pgrep -f "$1" >/dev/null 2>&1; }
_get_pid() { pgrep -f "$1" 2>/dev/null | head -1; }

# ============================================================================
# PROFILE COMMANDS (Environment Variables Only)
# ============================================================================

# Enable Antigravity mode (set environment variables)
anticc-on() {
    export ANTHROPIC_BASE_URL="$_ANTICC_BASE_URL"
    export ANTHROPIC_API_KEY="$_ANTICC_API_KEY"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$_ANTICC_OPUS_MODEL"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$_ANTICC_SONNET_MODEL"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$_ANTICC_HAIKU_MODEL"
    export ANTICC_ENABLED="true"
    _log "Antigravity mode ${_C_GREEN}enabled${_C_NC} → CCR (:${ANTICC_CCR_PORT})"
}

# Bypass CCR mode (connect directly to CLIProxyAPI, skipping CCR)
anticc-off() {
    export ANTHROPIC_BASE_URL="http://127.0.0.1:${ANTICC_CLIPROXY_PORT}"
    export ANTHROPIC_API_KEY="$_ANTICC_API_KEY"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$_ANTICC_OPUS_MODEL"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$_ANTICC_SONNET_MODEL"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$_ANTICC_HAIKU_MODEL"
    export ANTICC_ENABLED="direct"
    _log "Direct mode ${_C_YELLOW}enabled${_C_NC} → CLIProxyAPI (:${ANTICC_CLIPROXY_PORT}) [bypassing CCR]"
}

# ============================================================================
# STATUS (read-only, does not modify services)
# ============================================================================

# Show status
anticc-status() {
    echo "${_C_BOLD}Services:${_C_NC}"

    # CLIProxyAPI status
    if _is_running "cliproxyapi"; then
        local version=$("${CLIPROXY_BIN_DIR}/cliproxyapi" 2>&1 | grep "Version:" | sed 's/.*Version: \([^,]*\).*/\1/' || echo "?")
        echo "  CLIProxyAPI:  ${_C_GREEN}running${_C_NC} (PID: $(_get_pid 'cliproxyapi'), $version) → :${ANTICC_CLIPROXY_PORT}"
    else
        echo "  CLIProxyAPI:  ${_C_RED}stopped${_C_NC} (use: anticc-start)"
    fi

    # CCR status
    if _is_running "claude-code-router"; then
        echo "  CCR:          ${_C_GREEN}running${_C_NC} (PID: $(_get_pid 'claude-code-router')) → :${ANTICC_CCR_PORT}"
    else
        echo "  CCR:          ${_C_RED}stopped${_C_NC} (use: ccr start)"
    fi

    echo ""
    echo "${_C_BOLD}Profile:${_C_NC}"
    if [[ "$ANTICC_ENABLED" == "true" ]]; then
        echo "  Anticc: ${_C_GREEN}enabled${_C_NC} → $ANTHROPIC_BASE_URL"
    elif [[ "$ANTICC_ENABLED" == "direct" ]]; then
        echo "  Anticc: ${_C_YELLOW}direct${_C_NC} → $ANTHROPIC_BASE_URL"
    else
        echo "  Anticc: ${_C_YELLOW}disabled${_C_NC}"
    fi

    # Show update status
    echo ""
    echo "${_C_BOLD}Updates:${_C_NC}"
    if launchctl list com.cliproxy.updater &>/dev/null; then
        echo "  Auto-update: ${_C_GREEN}enabled${_C_NC} (every 12h)"
    else
        echo "  Auto-update: ${_C_YELLOW}disabled${_C_NC} (run: anticc-enable-autoupdate)"
    fi
}

# ============================================================================
# SERVICE MANAGEMENT (launchd-based)
# ============================================================================

# Start CLIProxyAPI via launchd
anticc-start() {
    if _is_running "cliproxyapi"; then
        _log "CLIProxyAPI already running"
        return 0
    fi

    if [[ ! -x "${CLIPROXY_BIN_DIR}/cliproxyapi" ]]; then
        _warn "CLIProxyAPI not found at ${CLIPROXY_BIN_DIR}/cliproxyapi"
        _warn "Run: anticc-update to build from source"
        return 1
    fi

    local config="$CLIPROXY_DIR/config.yaml"
    if [[ ! -f "$config" ]]; then
        _warn "Config not found at $config"
        return 1
    fi

    _log "Starting CLIProxyAPI..."
    launchctl load ~/Library/LaunchAgents/com.cliproxy.api.plist 2>/dev/null || true
    launchctl start com.cliproxy.api 2>/dev/null || true
    sleep 2

    if _is_running "cliproxyapi"; then
        _log "CLIProxyAPI started (PID: $(_get_pid 'cliproxyapi'))"
    else
        _warn "Failed via launchd, trying direct start..."
        nohup "${CLIPROXY_BIN_DIR}/cliproxyapi" --config "$config" >> ~/.local/var/log/cliproxyapi.log 2>&1 &
        sleep 2
        if _is_running "cliproxyapi"; then
            _log "CLIProxyAPI started directly (PID: $!)"
        else
            _warn "Failed to start. Check: tail ~/.local/var/log/cliproxyapi.log"
            return 1
        fi
    fi
}

# Stop CLIProxyAPI
anticc-stop-service() {
    _log "Stopping CLIProxyAPI..."
    launchctl stop com.cliproxy.api 2>/dev/null || true
    pkill -f "cliproxyapi" 2>/dev/null || true
    sleep 1
    if ! _is_running "cliproxyapi"; then
        _log "CLIProxyAPI stopped"
    else
        _warn "CLIProxyAPI still running, force killing..."
        pkill -9 -f "cliproxyapi" 2>/dev/null || true
    fi
}

# Restart CLIProxyAPI
anticc-restart-service() {
    anticc-stop-service
    sleep 1
    anticc-start
}

# ============================================================================
# UPDATE MANAGEMENT (source-based)
# ============================================================================

# Show version info
anticc-version() {
    echo "${_C_BOLD}CLIProxyAPI Versions:${_C_NC}"

    # Running version
    if _is_running "cliproxyapi"; then
        local running=$(curl -sf "http://127.0.0.1:${ANTICC_CLIPROXY_PORT}/" 2>/dev/null | grep -o 'v[0-9.]*' | head -1 || echo "unknown")
        echo "  Running: ${_C_GREEN}${running}${_C_NC}"
    else
        echo "  Running: ${_C_RED}not running${_C_NC}"
    fi

    # Binary version
    if [[ -x "${CLIPROXY_BIN_DIR}/cliproxyapi" ]]; then
        local binary=$("${CLIPROXY_BIN_DIR}/cliproxyapi" 2>&1 | grep "Version:" | sed 's/.*Version: \([^,]*\).*/\1/')
        echo "  Binary:  ${binary}"
    else
        echo "  Binary:  ${_C_RED}not installed${_C_NC}"
    fi

    # Source version
    if [[ -d "$CLIPROXY_SOURCE_DIR" ]]; then
        local source=$(cd "$CLIPROXY_SOURCE_DIR" && git describe --tags --always 2>/dev/null)
        echo "  Source:  ${source}"

        # Check for updates
        cd "$CLIPROXY_SOURCE_DIR"
        git fetch --tags --quiet 2>/dev/null
        local remote=$(git describe --tags origin/main 2>/dev/null || echo "unknown")
        if [[ "$source" != "$remote" ]]; then
            echo "  Remote:  ${_C_YELLOW}${remote}${_C_NC} (update available!)"
        fi
    else
        echo "  Source:  ${_C_RED}not found${_C_NC}"
    fi

    # Backup version
    if [[ -f "${CLIPROXY_BIN_DIR}/cliproxyapi.bak" ]]; then
        local backup=$("${CLIPROXY_BIN_DIR}/cliproxyapi.bak" 2>&1 | grep "Version:" | sed 's/.*Version: \([^,]*\).*/\1/')
        echo "  Backup:  ${backup} (for rollback)"
    fi
}

# Trigger update
anticc-update() {
    if [[ ! -x "$CLIPROXY_UPDATER" ]]; then
        _warn "Updater script not found at $CLIPROXY_UPDATER"
        return 1
    fi

    _log "Running CLIProxyAPI update..."
    "$CLIPROXY_UPDATER" update
}

# Rollback to previous version
anticc-rollback() {
    if [[ ! -x "$CLIPROXY_UPDATER" ]]; then
        _warn "Updater script not found"
        return 1
    fi

    _warn "Rolling back to previous version..."
    "$CLIPROXY_UPDATER" rollback
}

# Enable auto-update via launchd
anticc-enable-autoupdate() {
    local plist="$HOME/Library/LaunchAgents/com.cliproxy.updater.plist"
    if [[ ! -f "$plist" ]]; then
        _warn "Updater plist not found at $plist"
        return 1
    fi

    launchctl load "$plist" 2>/dev/null
    _log "Auto-update enabled (runs every 12 hours)"
}

# Disable auto-update
anticc-disable-autoupdate() {
    launchctl unload ~/Library/LaunchAgents/com.cliproxy.updater.plist 2>/dev/null
    _log "Auto-update disabled"
}

# ============================================================================
# LEGACY COMMANDS (Backward Compatibility)
# ============================================================================

anticc-up() {
    _warn "anticc-up is deprecated. Use: anticc-start"
    anticc-start
    anticc-on
}

anticc-down() {
    anticc-off
}

anticc-stop() {
    _warn "anticc-stop is deprecated. Use: anticc-stop-service"
    anticc-stop-service
}

anticc-restart() {
    anticc-restart-service
}

# Keep old name as alias
anticc-start-cliproxy() {
    anticc-start
}

# ============================================================================
# DIAGNOSTICS
# ============================================================================

anticc-diagnose() {
    echo "${_C_BOLD}=== Antigravity Diagnostics ===${_C_NC}"
    echo ""

    # Check CLIProxyAPI installation
    echo "${_C_BOLD}1. CLIProxyAPI Installation:${_C_NC}"
    if [[ -x "${CLIPROXY_BIN_DIR}/cliproxyapi" ]]; then
        echo "   Binary: ${CLIPROXY_BIN_DIR}/cliproxyapi"
        echo "   Version: $("${CLIPROXY_BIN_DIR}/cliproxyapi" 2>&1 | grep 'Version:' | head -1)"
    else
        echo "   ${_C_RED}NOT INSTALLED${_C_NC} - run: anticc-update"
    fi
    echo ""

    # Check source repo
    echo "${_C_BOLD}2. Source Repository:${_C_NC}"
    if [[ -d "$CLIPROXY_SOURCE_DIR" ]]; then
        echo "   Path: $CLIPROXY_SOURCE_DIR"
        echo "   Version: $(cd "$CLIPROXY_SOURCE_DIR" && git describe --tags --always 2>/dev/null)"
        echo "   Branch: $(cd "$CLIPROXY_SOURCE_DIR" && git branch --show-current 2>/dev/null)"
    else
        echo "   ${_C_RED}NOT FOUND${_C_NC} at $CLIPROXY_SOURCE_DIR"
    fi
    echo ""

    # Check config
    echo "${_C_BOLD}3. Configuration:${_C_NC}"
    local config="$CLIPROXY_DIR/config.yaml"
    if [[ -f "$config" ]]; then
        echo "   Config: $config"
    else
        echo "   Config: ${_C_RED}NOT FOUND${_C_NC}"
    fi
    echo ""

    # Check API key
    echo "${_C_BOLD}4. API Key:${_C_NC}"
    if [[ -n "$CLIPROXY_API_KEY" ]]; then
        echo "   CLIPROXY_API_KEY: ${_C_GREEN}set${_C_NC} (${#CLIPROXY_API_KEY} chars)"
    else
        echo "   CLIPROXY_API_KEY: ${_C_RED}NOT SET${_C_NC}"
    fi
    echo ""

    # Check ports
    echo "${_C_BOLD}5. Ports:${_C_NC}"
    if lsof -i :${ANTICC_CLIPROXY_PORT} &>/dev/null; then
        echo "   Port ${ANTICC_CLIPROXY_PORT}: ${_C_GREEN}in use${_C_NC}"
        lsof -i :${ANTICC_CLIPROXY_PORT} 2>/dev/null | head -2 | tail -1 | awk '{print "   Process: " $1 " (PID: " $2 ")"}'
    else
        echo "   Port ${ANTICC_CLIPROXY_PORT}: ${_C_YELLOW}free${_C_NC}"
    fi

    if lsof -i :${ANTICC_CCR_PORT} &>/dev/null; then
        echo "   Port ${ANTICC_CCR_PORT}: ${_C_GREEN}in use${_C_NC}"
        lsof -i :${ANTICC_CCR_PORT} 2>/dev/null | head -2 | tail -1 | awk '{print "   Process: " $1 " (PID: " $2 ")"}'
    else
        echo "   Port ${ANTICC_CCR_PORT}: ${_C_YELLOW}free${_C_NC}"
    fi
    echo ""

    # Check launchd services
    echo "${_C_BOLD}6. Launchd Services:${_C_NC}"
    if launchctl list com.cliproxy.api &>/dev/null; then
        echo "   com.cliproxy.api: ${_C_GREEN}loaded${_C_NC}"
    else
        echo "   com.cliproxy.api: ${_C_YELLOW}not loaded${_C_NC}"
    fi
    if launchctl list com.cliproxy.updater &>/dev/null; then
        echo "   com.cliproxy.updater: ${_C_GREEN}loaded${_C_NC} (auto-update enabled)"
    else
        echo "   com.cliproxy.updater: ${_C_YELLOW}not loaded${_C_NC}"
    fi
    echo ""

    # Check logs
    echo "${_C_BOLD}7. Recent Logs:${_C_NC}"
    local log_file="$HOME/.local/var/log/cliproxyapi.log"
    if [[ -f "$log_file" ]]; then
        echo "   Last 3 lines of $log_file:"
        tail -3 "$log_file" 2>/dev/null | sed 's/^/   /'
    else
        echo "   No log file at $log_file"
    fi
    echo ""

    # Quick connectivity test
    echo "${_C_BOLD}8. Connectivity Test:${_C_NC}"
    if curl -sf "http://127.0.0.1:${ANTICC_CLIPROXY_PORT}/v1/models" -H "Authorization: Bearer $CLIPROXY_API_KEY" &>/dev/null; then
        echo "   CLIProxyAPI (${ANTICC_CLIPROXY_PORT}): ${_C_GREEN}responding${_C_NC}"
    else
        echo "   CLIProxyAPI (${ANTICC_CLIPROXY_PORT}): ${_C_RED}not responding${_C_NC}"
    fi

    if curl -sf "http://127.0.0.1:${ANTICC_CCR_PORT}/health" &>/dev/null; then
        echo "   CCR (${ANTICC_CCR_PORT}): ${_C_GREEN}responding${_C_NC}"
    else
        echo "   CCR (${ANTICC_CCR_PORT}): ${_C_RED}not responding${_C_NC}"
    fi
    echo ""

    echo "${_C_BOLD}=== End Diagnostics ===${_C_NC}"
}

# ============================================================================
# QUOTA TOOLS
# ============================================================================

# Check Antigravity quota for all accounts (CLI mode)
anticc-quota() {
    local tool_dir="$ANTICC_DIR/tools/check-quota"
    local binary="$tool_dir/check-quota"
    
    # Build if not exists or source is newer
    if [[ ! -x "$binary" ]] || [[ "$tool_dir/main.go" -nt "$binary" ]]; then
        _log "Building check-quota tool..."
        if ! command -v go &>/dev/null; then
            _warn "Go not installed. Install Go to use this feature."
            return 1
        fi
        (cd "$tool_dir" && go build -o check-quota .) || {
            _warn "Failed to build check-quota tool"
            return 1
        }
    fi
    
    "$binary" "$@"
}

# Open quota dashboard in browser (web UI mode)
anticc-quota-web() {
    local port="${1:-8318}"
    _log "Starting quota dashboard on http://127.0.0.1:$port"
    anticc-quota --web --port "$port"
}

# ============================================================================
# LOG VIEWING
# ============================================================================

# Log file paths
CLIPROXY_LOG_FILE="$HOME/.local/var/log/cliproxyapi.log"
CLIPROXY_UPDATER_LOG="$HOME/.local/var/log/cliproxy-updater.log"

# View CLIProxyAPI logs (like brew services log)
anticc-logs() {
    local arg="${1:-50}"
    
    if [[ ! -f "$CLIPROXY_LOG_FILE" ]]; then
        _warn "Log file not found at $CLIPROXY_LOG_FILE"
        return 1
    fi
    
    case "$arg" in
        -f|--follow|follow)
            _log "Following logs at $CLIPROXY_LOG_FILE (Ctrl+C to stop)..."
            exec tail -F "$CLIPROXY_LOG_FILE"
            ;;
        -a|--all|all)
            less +G "$CLIPROXY_LOG_FILE"
            ;;
        *)
            tail -n "$arg" "$CLIPROXY_LOG_FILE"
            ;;
    esac
}

# View updater logs
anticc-logs-updater() {
    local arg="${1:-50}"
    
    if [[ ! -f "$CLIPROXY_UPDATER_LOG" ]]; then
        _warn "Updater log file not found at $CLIPROXY_UPDATER_LOG"
        return 1
    fi
    
    case "$arg" in
        -f|--follow|follow)
            _log "Following updater logs (Ctrl+C to stop)..."
            exec tail -F "$CLIPROXY_UPDATER_LOG"
            ;;
        -a|--all|all)
            less +G "$CLIPROXY_UPDATER_LOG"
            ;;
        *)
            tail -n "$arg" "$CLIPROXY_UPDATER_LOG"
            ;;
    esac
}

# Clear/rotate log files
anticc-logs-clear() {
    local log_file="$CLIPROXY_LOG_FILE"
    
    if [[ ! -f "$log_file" ]]; then
        _warn "Log file not found"
        return 1
    fi
    
    local size=$(du -h "$log_file" | cut -f1)
    _log "Current log size: $size"
    
    # Backup old log with timestamp
    local backup="${log_file}.$(date +%Y%m%d_%H%M%S)"
    mv "$log_file" "$backup"
    touch "$log_file"
    
    # Compress the backup
    gzip "$backup" 2>/dev/null &
    
    _log "Log cleared. Old log backed up to ${backup}.gz"
    _log "Restarting service to apply..."
    anticc-restart-service
}

# Show log file info
anticc-logs-info() {
    echo "${_C_BOLD}Log Files:${_C_NC}"
    
    if [[ -f "$CLIPROXY_LOG_FILE" ]]; then
        local size=$(du -h "$CLIPROXY_LOG_FILE" | cut -f1)
        local lines=$(wc -l < "$CLIPROXY_LOG_FILE")
        local modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$CLIPROXY_LOG_FILE" 2>/dev/null || stat -c "%y" "$CLIPROXY_LOG_FILE" 2>/dev/null | cut -d. -f1)
        echo "  CLIProxyAPI: $CLIPROXY_LOG_FILE"
        echo "    Size: $size, Lines: $lines, Modified: $modified"
    else
        echo "  CLIProxyAPI: ${_C_RED}not found${_C_NC}"
    fi
    
    if [[ -f "$CLIPROXY_UPDATER_LOG" ]]; then
        local size=$(du -h "$CLIPROXY_UPDATER_LOG" | cut -f1)
        local lines=$(wc -l < "$CLIPROXY_UPDATER_LOG")
        echo "  Updater: $CLIPROXY_UPDATER_LOG"
        echo "    Size: $size, Lines: $lines"
    fi
    
    # Show backups
    local backups=$(ls -1 "${CLIPROXY_LOG_FILE}"*.gz 2>/dev/null | wc -l)
    if [[ $backups -gt 0 ]]; then
        echo "  Backups: $backups compressed log files"
    fi
}

# ============================================================================
# HELP
# ============================================================================

anticc-help() {
    cat << EOF
anticc - Antigravity Claude Code CLI

Architecture:
  Claude Code → CCR (3456) → CLIProxyAPI (8317) → Antigravity

Profile Commands:
  anticc-on              Enable Antigravity mode (set env vars via CCR)
  anticc-off             Direct mode (bypass CCR, connect to CLIProxyAPI)
  anticc-status          Show service and profile status

Service Commands:
  anticc-start           Start CLIProxyAPI service
  anticc-stop-service    Stop CLIProxyAPI service
  anticc-restart-service Restart CLIProxyAPI service

Update Commands:
  anticc-version         Show version info (running, binary, source, remote)
  anticc-update          Pull latest and rebuild CLIProxyAPI
  anticc-rollback        Rollback to previous version if update fails

Auto-Update:
  anticc-enable-autoupdate   Enable 12-hour auto-update via launchd
  anticc-disable-autoupdate  Disable auto-update

Quota Commands:
  anticc-quota           Check Antigravity quota for all accounts (CLI)
  anticc-quota-web [port] Open quota dashboard in browser (default: 8318)

Log Commands:
  anticc-logs [N|-f|-a]  View CLIProxyAPI logs (N lines, -f follow, -a all)
  anticc-logs-updater    View auto-updater logs
  anticc-logs-clear      Clear logs (backup + restart service)
  anticc-logs-info       Show log file sizes and info

Diagnostics:
  anticc-diagnose        Run full diagnostics
  anticc-help            Show this help

Files:
  Binary:   ~/.local/bin/cliproxyapi
  Source:   $ANTICC_DIR/cliproxy-source
  Config:   $ANTICC_DIR/config.yaml
  Logs:     ~/.local/var/log/cliproxyapi.log
  Updater:  $ANTICC_DIR/cliproxy-updater.sh

Examples:
  anticc-logs            Show last 50 lines of logs
  anticc-logs 100        Show last 100 lines
  anticc-logs -f         Follow logs in real-time (like tail -f)
  anticc-logs -a         Open full log in less

Environment variables are auto-exported when sourced (for IDE plugins).
To disable: export ANTICC_AUTO_ENABLE=false before sourcing.
EOF
}

# ============================================================================
# AUTO-ENABLE ON SOURCE (for IDE plugins)
# ============================================================================
# When sourced in .zshrc/.bashrc, auto-exports env vars for IDE plugins
# Default: enabled (like old script behavior)
# To disable: export ANTICC_AUTO_ENABLE=false before sourcing
# ============================================================================
if [[ "$ANTICC_AUTO_ENABLE" == "true" ]]; then
    # Silently export env vars (no log message during shell init)
    export ANTHROPIC_BASE_URL="$_ANTICC_BASE_URL"
    export ANTHROPIC_API_KEY="$_ANTICC_API_KEY"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$_ANTICC_OPUS_MODEL"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$_ANTICC_SONNET_MODEL"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$_ANTICC_HAIKU_MODEL"
    export ANTICC_ENABLED="true"
fi
