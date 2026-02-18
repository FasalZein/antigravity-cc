#!/usr/bin/env bash
# ============================================================================
# anticc - Antigravity Claude Code CLI (Thin Wrapper)
# ============================================================================
# Usage: source "/path/to/anticc.sh"
#
# This script is a thin wrapper around cliproxyctl for most commands.
# It handles shell-specific functionality (environment variables, sourcing)
# that can't be done in a compiled binary.
#
# Commands delegated to cliproxyctl:
#   anticc-status, anticc-version, anticc-update, anticc-rollback, anticc-diagnose,
#   anticc-quota, anticc-start, anticc-stop-service, anticc-restart-service, anticc-logs
#
# Commands handled by shell (require shell integration):
#   anticc-ccr-on, anticc-ccr-off, anticc-ccr-status (persistent CCR toggle)
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

# Paths
CLIPROXY_BIN_DIR="${HOME}/.local/bin"
CLIPROXY_CTL="${ANTICC_DIR}/tools/cliproxyctl/cliproxyctl"
ANTICC_STATE_FILE="${HOME}/.cli-proxy-api/anticc-state"

# API key - .env file takes precedence, then env var, then "dummy" default
if [[ -f "${ANTICC_DIR}/.env" ]]; then
    _env_key=$(grep -E '^CLIPROXY_API_KEY=' "${ANTICC_DIR}/.env" 2>/dev/null | cut -d= -f2- | tr -d '"'"'")
    if [[ -n "$_env_key" ]]; then
        export CLIPROXY_API_KEY="$_env_key"
    fi
fi
export CLIPROXY_API_KEY="${CLIPROXY_API_KEY:-dummy}"

# Load persistent CCR state (default: enabled)
# State file contains either "ccr" or "direct"
_ANTICC_CCR_MODE="ccr"
if [[ -f "$ANTICC_STATE_FILE" ]]; then
    _saved_mode=$(cat "$ANTICC_STATE_FILE" 2>/dev/null)
    if [[ "$_saved_mode" == "direct" ]]; then
        _ANTICC_CCR_MODE="direct"
    fi
fi

# Internal settings - depends on CCR mode
_ANTICC_API_KEY="$CLIPROXY_API_KEY"
if [[ "$_ANTICC_CCR_MODE" == "direct" ]]; then
    _ANTICC_BASE_URL="http://127.0.0.1:${ANTICC_CLIPROXY_PORT}"
else
    _ANTICC_BASE_URL="http://127.0.0.1:${ANTICC_CCR_PORT}"
fi

# Model configuration
_ANTICC_OPUS_MODEL="claude-opus-4-6-thinking"
_ANTICC_SONNET_MODEL="claude-sonnet-4-6"
_ANTICC_HAIKU_MODEL="gemini-3-flash-preview"

# Track state
ANTICC_ENABLED="${ANTICC_ENABLED:-false}"

# Auto-enable on source
ANTICC_AUTO_ENABLE="${ANTICC_AUTO_ENABLE:-true}"

# ============================================================================
# COLORS & LOGGING
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
# CLIPROXYCTL WRAPPER
# ============================================================================

# Ensure cliproxyctl is built
_ensure_cliproxyctl() {
    if [[ ! -x "$CLIPROXY_CTL" ]]; then
        local tool_dir="${ANTICC_DIR}/tools/cliproxyctl"
        if [[ -f "$tool_dir/main.go" ]]; then
            _log "Building cliproxyctl..."
            if ! command -v go &>/dev/null; then
                _warn "Go not installed. Please install Go first."
                return 1
            fi
            (cd "$tool_dir" && go build -o cliproxyctl .) || {
                _warn "Failed to build cliproxyctl"
                return 1
            }
        else
            _warn "cliproxyctl source not found at $tool_dir"
            return 1
        fi
    fi
    return 0
}

# ============================================================================
# UTILITIES
# ============================================================================
_is_running() { pgrep -f "$1" >/dev/null 2>&1; }
_get_pid() { pgrep -f "$1" 2>/dev/null | head -1; }

# ============================================================================
# CCR TOGGLE COMMANDS (persistent - survives terminal restarts)
# ============================================================================

# Enable CCR (persistent - saved to file)
anticc-ccr-on() {
    mkdir -p "$(dirname "$ANTICC_STATE_FILE")"
    echo "ccr" > "$ANTICC_STATE_FILE"
    _ANTICC_CCR_MODE="ccr"
    _ANTICC_BASE_URL="http://127.0.0.1:${ANTICC_CCR_PORT}"
    export ANTHROPIC_BASE_URL="$_ANTICC_BASE_URL"
    export ANTHROPIC_API_KEY="$_ANTICC_API_KEY"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$_ANTICC_OPUS_MODEL"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$_ANTICC_SONNET_MODEL"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$_ANTICC_HAIKU_MODEL"
    export ANTICC_ENABLED="true"
    _log "CCR mode ${_C_GREEN}enabled${_C_NC} → CCR (:${ANTICC_CCR_PORT}) [persistent]"
    _log "Setting saved. New terminals will use CCR."
}

# Disable CCR (persistent - saved to file)
anticc-ccr-off() {
    mkdir -p "$(dirname "$ANTICC_STATE_FILE")"
    echo "direct" > "$ANTICC_STATE_FILE"
    _ANTICC_CCR_MODE="direct"
    _ANTICC_BASE_URL="http://127.0.0.1:${ANTICC_CLIPROXY_PORT}"
    export ANTHROPIC_BASE_URL="$_ANTICC_BASE_URL"
    export ANTHROPIC_API_KEY="$_ANTICC_API_KEY"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$_ANTICC_OPUS_MODEL"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$_ANTICC_SONNET_MODEL"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$_ANTICC_HAIKU_MODEL"
    export ANTICC_ENABLED="direct"
    _log "Direct mode ${_C_YELLOW}enabled${_C_NC} → CLIProxyAPI (:${ANTICC_CLIPROXY_PORT}) [persistent]"
    _log "Setting saved. New terminals will bypass CCR."
}

# Show current CCR mode
anticc-ccr-status() {
    echo "${_C_BOLD}CCR Mode:${_C_NC}"
    if [[ "$_ANTICC_CCR_MODE" == "direct" ]]; then
        echo "  Persistent: ${_C_YELLOW}direct${_C_NC} (bypassing CCR)"
        echo "  Endpoint:   http://127.0.0.1:${ANTICC_CLIPROXY_PORT}"
    else
        echo "  Persistent: ${_C_GREEN}ccr${_C_NC} (via CCR)"
        echo "  Endpoint:   http://127.0.0.1:${ANTICC_CCR_PORT}"
    fi
    echo "  State file: $ANTICC_STATE_FILE"
    echo ""
    echo "${_C_BOLD}Current Session:${_C_NC}"
    echo "  ANTHROPIC_BASE_URL: ${ANTHROPIC_BASE_URL:-not set}"
}

# ============================================================================
# DELEGATED TO CLIPROXYCTL
# ============================================================================

anticc-status() {
    _ensure_cliproxyctl && "$CLIPROXY_CTL" status

    # Add shell-specific profile status
    echo ""
    echo "${_C_BOLD}Profile:${_C_NC}"
    if [[ "$ANTICC_ENABLED" == "true" ]]; then
        echo "  Anticc: ${_C_GREEN}enabled${_C_NC} → $ANTHROPIC_BASE_URL"
    elif [[ "$ANTICC_ENABLED" == "direct" ]]; then
        echo "  Anticc: ${_C_YELLOW}direct${_C_NC} → $ANTHROPIC_BASE_URL"
    else
        echo "  Anticc: ${_C_YELLOW}disabled${_C_NC}"
    fi
}

anticc-version() {
    _ensure_cliproxyctl && "$CLIPROXY_CTL" status
}

anticc-update() {
    _ensure_cliproxyctl && "$CLIPROXY_CTL" update "$@"
}

anticc-rollback() {
    _ensure_cliproxyctl && "$CLIPROXY_CTL" rollback "$@"
}

anticc-diagnose() {
    _ensure_cliproxyctl && "$CLIPROXY_CTL" diagnose "$@"
}

anticc-quota() {
    _ensure_cliproxyctl && "$CLIPROXY_CTL" quota "$@"
}

anticc-quota-web() {
    local port="${1:-8318}"
    _log "Starting quota dashboard on http://127.0.0.1:$port"
    _ensure_cliproxyctl && "$CLIPROXY_CTL" quota --web --port "$port"
}

# ============================================================================
# SERVICE MANAGEMENT (delegated to cliproxyctl)
# ============================================================================

anticc-start() {
    _ensure_cliproxyctl && "$CLIPROXY_CTL" start
}

anticc-stop-service() {
    _ensure_cliproxyctl && "$CLIPROXY_CTL" stop
}

anticc-restart-service() {
    _ensure_cliproxyctl && "$CLIPROXY_CTL" restart
}

# ============================================================================
# AUTO-UPDATE MANAGEMENT
# ============================================================================

anticc-enable-autoupdate() {
    local plist="$HOME/Library/LaunchAgents/com.cliproxy.updater.plist"
    if [[ ! -f "$plist" ]]; then
        _warn "Updater plist not found at $plist"
        return 1
    fi
    launchctl load "$plist" 2>/dev/null
    _log "Auto-update enabled (runs every 12 hours)"
}

anticc-disable-autoupdate() {
    launchctl unload ~/Library/LaunchAgents/com.cliproxy.updater.plist 2>/dev/null
    _log "Auto-update disabled"
}

# ============================================================================
# LOG VIEWING (delegated to cliproxyctl)
# ============================================================================

CLIPROXY_LOG_FILE="$HOME/.local/var/log/cliproxyapi.log"
CLIPROXY_UPDATER_LOG="$HOME/.local/var/log/cliproxy-updater.log"

anticc-logs() {
    local arg="${1:-}"

    case "$arg" in
        -n|--lines)
            # Show last N lines (non-following)
            local lines="${2:-50}"
            _ensure_cliproxyctl && "$CLIPROXY_CTL" logs -n "$lines"
            ;;
        -a|--all|all)
            _ensure_cliproxyctl && "$CLIPROXY_CTL" logs --all
            ;;
        ""|--follow|-f|follow)
            # Default: follow logs (most common use case)
            _ensure_cliproxyctl && "$CLIPROXY_CTL" logs -f
            ;;
        *)
            # Number passed directly: show last N lines
            if [[ "$arg" =~ ^[0-9]+$ ]]; then
                _ensure_cliproxyctl && "$CLIPROXY_CTL" logs -n "$arg"
            else
                _warn "Unknown option: $arg"
                _log "Usage: anticc-logs [-f|--follow] [-n N|--lines N] [-a|--all] [N]"
                return 1
            fi
            ;;
    esac
}

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

anticc-logs-clear() {
    if [[ ! -f "$CLIPROXY_LOG_FILE" ]]; then
        _warn "Log file not found"
        return 1
    fi

    local size=$(du -h "$CLIPROXY_LOG_FILE" | cut -f1)
    _log "Current log size: $size"

    local backup="${CLIPROXY_LOG_FILE}.$(date +%Y%m%d_%H%M%S)"
    mv "$CLIPROXY_LOG_FILE" "$backup"
    touch "$CLIPROXY_LOG_FILE"

    gzip "$backup" 2>/dev/null &

    _log "Log cleared. Old log backed up to ${backup}.gz"
    _log "Restarting service to apply..."
    anticc-restart-service
}

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

    local backups=$(ls -1 "${CLIPROXY_LOG_FILE}"*.gz 2>/dev/null | wc -l)
    if [[ $backups -gt 0 ]]; then
        echo "  Backups: $backups compressed log files"
    fi
}

# ============================================================================
# LEGACY COMMANDS (Backward Compatibility)
# ============================================================================

anticc-up() {
    _warn "anticc-up is deprecated. Use: anticc-start && anticc-ccr-on"
    anticc-start
    anticc-ccr-on
}

anticc-down() {
    _warn "anticc-down is deprecated. Use: anticc-ccr-off"
    anticc-ccr-off
}

# Old anticc-on/anticc-off now redirect to persistent versions
anticc-on() {
    _warn "anticc-on is deprecated. Use: anticc-ccr-on (persistent)"
    anticc-ccr-on
}

anticc-off() {
    _warn "anticc-off is deprecated. Use: anticc-ccr-off (persistent)"
    anticc-ccr-off
}

anticc-stop() {
    _warn "anticc-stop is deprecated. Use: anticc-stop-service"
    anticc-stop-service
}

anticc-restart() {
    anticc-restart-service
}

anticc-start-cliproxy() {
    anticc-start
}

# ============================================================================
# HELP
# ============================================================================

anticc-help() {
    cat << 'EOF'
anticc - Antigravity Claude Code CLI (Thin Wrapper)

Architecture:
  Claude Code → CCR (3456) → CLIProxyAPI (8317) → Antigravity
  Or direct:   Claude Code → CLIProxyAPI (8317) → Antigravity

CCR Toggle (persistent - survives terminal restarts):
  anticc-ccr-on          Enable CCR mode (via CCR port 3456)
  anticc-ccr-off         Disable CCR, connect directly to CLIProxyAPI (port 8317)
  anticc-ccr-status      Show current CCR mode

Service Commands:
  anticc-status          Show service and profile status
  anticc-start           Start CLIProxyAPI service
  anticc-stop-service    Stop CLIProxyAPI service
  anticc-restart-service Restart CLIProxyAPI service

Update Commands:
  anticc-update          Pull latest and rebuild CLIProxyAPI
  anticc-rollback        Rollback to previous version if update fails
  anticc-version         Show version info

Quota & Diagnostics:
  anticc-quota           Check Antigravity quota for all accounts (CLI)
  anticc-quota-web [port] Open quota dashboard in browser (default: 8318)
  anticc-diagnose        Run full diagnostics

Auto-Update:
  anticc-enable-autoupdate   Enable 12-hour auto-update via launchd
  anticc-disable-autoupdate  Disable auto-update

Log Commands:
  anticc-logs [-n N|-a]  View CLIProxyAPI logs (default: follow, -n N lines, -a all)
  anticc-logs-updater    View auto-updater logs
  anticc-logs-clear      Clear logs (backup + restart service)
  anticc-logs-info       Show log file sizes and info

Other:
  anticc-help            Show this help

Files:
  Binary:      ~/.local/bin/cliproxyapi
  CLI Tool:    tools/cliproxyctl/cliproxyctl
  Config:      config.yaml
  Logs:        ~/.local/var/log/cliproxyapi.log
  CCR State:   ~/.cli-proxy-api/anticc-state

Environment variables are auto-exported when sourced (for IDE plugins).
To disable: export ANTICC_AUTO_ENABLE=false before sourcing.
EOF
}

# ============================================================================
# AUTO-ENABLE ON SOURCE (for IDE plugins)
# ============================================================================
if [[ "$ANTICC_AUTO_ENABLE" == "true" ]]; then
    export ANTHROPIC_BASE_URL="$_ANTICC_BASE_URL"
    export ANTHROPIC_API_KEY="$_ANTICC_API_KEY"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$_ANTICC_OPUS_MODEL"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$_ANTICC_SONNET_MODEL"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$_ANTICC_HAIKU_MODEL"
    # Set ANTICC_ENABLED based on CCR mode
    if [[ "$_ANTICC_CCR_MODE" == "direct" ]]; then
        export ANTICC_ENABLED="direct"
    else
        export ANTICC_ENABLED="true"
    fi
fi
