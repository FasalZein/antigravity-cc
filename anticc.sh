#!/usr/bin/env bash
# ============================================================================
# anticc - Antigravity Claude Code CLI (Profile Manager)
# ============================================================================
# Usage: source "/path/to/anticc.sh"
#
# Commands:
#   anticc-on     Enable Antigravity mode (set env vars)
#   anticc-off    Disable Antigravity mode (unset env vars)
#   anticc-status Check current profile status
#
# This script ONLY manages environment variables for Claude Code.
# CLIProxyAPI and CCR services are managed separately via brew services.
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
_ANTICC_HAIKU_MODEL="gemini-claude-sonnet-4-5"

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

# Disable Antigravity mode (unset environment variables)
anticc-off() {
    unset ANTHROPIC_BASE_URL ANTHROPIC_API_KEY
    unset ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
    export ANTICC_ENABLED="false"
    _log "Antigravity mode ${_C_YELLOW}disabled${_C_NC} - using default/other provider"
}

# ============================================================================
# STATUS (read-only, does not modify services)
# ============================================================================

# Show status
anticc-status() {
    echo "${_C_BOLD}Services (read-only):${_C_NC}"
    
    # CLIProxyAPI status
    if _is_running "CLIProxyAPI" || _is_running "cliproxyapi"; then
        echo "  CLIProxyAPI:  ${_C_GREEN}running${_C_NC} (PID: $(_get_pid 'CLIProxyAPI' || _get_pid 'cliproxyapi')) → :${ANTICC_CLIPROXY_PORT}"
    else
        echo "  CLIProxyAPI:  ${_C_RED}stopped${_C_NC} (use: brew services start cliproxyapi)"
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
    else
        echo "  Anticc: ${_C_YELLOW}disabled${_C_NC}"
    fi
}

# ============================================================================
# LEGACY COMMANDS (Backward Compatibility - profile only)
# ============================================================================

anticc-up() {
    _warn "anticc-up is deprecated. Services are managed via brew services."
    _warn "Use: brew services start cliproxyapi && ccr start"
    anticc-on
}

anticc-down() {
    anticc-off
}

anticc-stop() { 
    _warn "anticc-stop is deprecated. Use anticc-off to disable profile."
    _warn "To stop services: brew services stop cliproxyapi && ccr stop"
    anticc-off
}

anticc-restart() { 
    _warn "anticc-restart is deprecated. Services are managed via brew services."
    _warn "Use: brew services restart cliproxyapi"
    anticc-off
    anticc-on
}

# ============================================================================
# HELP
# ============================================================================

anticc-help() {
    cat << 'EOF'
anticc - Antigravity Claude Code Profile Manager

Architecture:
  Claude Code → CCR (3456) → CLIProxyAPI (8317) → Antigravity

Profile Commands (environment variables only):
  anticc-on       Enable Antigravity mode (set env vars)
  anticc-off      Disable Antigravity mode (unset env vars)
  anticc-status   Check current profile and service status (read-only)

Service Management (external):
  brew services start cliproxyapi   Start CLIProxyAPI
  brew services stop cliproxyapi    Stop CLIProxyAPI
  brew services restart cliproxyapi Restart CLIProxyAPI
  ccr start                         Start CCR
  ccr stop                          Stop CCR

Note: This script does NOT start/stop/restart services.
      Services are managed externally via brew services and ccr.

Environment variables are auto-exported when sourced (for IDE plugins).
To disable auto-export: export ANTICC_AUTO_ENABLE=false before sourcing.
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
