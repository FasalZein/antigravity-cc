#!/bin/bash
# =============================================================================
# Antigravity Claude Code Setup Script
# =============================================================================
# This script sets up everything needed to use Claude Code with Antigravity:
# 1. Checks prerequisites (Go, Node.js, Git)
# 2. Clones CLIProxyAPI source and builds from source
# 3. Installs CCR (Claude Code Router) via npm
# 4. Creates config files and generates API key
# 5. Sets up auto-start service (launchd on macOS, systemd on Linux)
# 6. Sets up 12-hour auto-update (launchd timer on macOS, cron on Linux)
# 7. Adds shell configuration to your terminal
# 8. Prompts you to login to Antigravity
#
# Supports: macOS, Linux (Ubuntu/Debian, Fedora, Arch)
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
error() { echo -e "${RED}[error]${NC} $*"; exit 1; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$SCRIPT_DIR"

# Paths
CLIPROXY_SOURCE_DIR="$SCRIPT_DIR/cliproxy-source"
CLIPROXY_BIN_DIR="$HOME/.local/bin"
CLIPROXY_BIN="$CLIPROXY_BIN_DIR/cliproxyapi"
CLIPROXY_LOG_DIR="$HOME/.local/var/log"
LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

# Detect OS and distro
detect_os() {
    case "$(uname -s)" in
        Darwin*)    echo "macos" ;;
        Linux*)     echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*)  echo "windows" ;;
        *)          echo "unknown" ;;
    esac
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# Detect if running in WSL
detect_wsl() {
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
    elif [[ -n "$WSL_DISTRO_NAME" ]]; then
        echo "wsl"
    else
        echo ""
    fi
}

OS=$(detect_os)
ARCH=$(uname -m)
DISTRO=""
WSL=""
[[ "$OS" == "linux" ]] && DISTRO=$(detect_distro)
[[ "$OS" == "linux" ]] && WSL=$(detect_wsl)

echo ""
echo "=============================================="
echo "  Antigravity Claude Code Setup"
echo "=============================================="
echo "  OS: $OS ($ARCH)"
[[ -n "$DISTRO" ]] && echo "  Distro: $DISTRO"
[[ -n "$WSL" ]] && echo "  Environment: WSL (Windows Subsystem for Linux)"
echo "=============================================="
echo ""

# =============================================================================
# Windows Check - Redirect to PowerShell script
# =============================================================================

if [[ "$OS" == "windows" ]]; then
    echo ""
    warn "Detected Windows (Git Bash/MSYS/Cygwin)"
    warn "Please use the PowerShell setup script instead:"
    echo ""
    echo "  powershell -ExecutionPolicy Bypass -File setup-windows.ps1"
    echo ""
    echo "Or if using WSL, this script will work natively."
    exit 0
fi

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."

    # Check for Git
    if ! command -v git &>/dev/null; then
        if [[ "$OS" == "macos" ]]; then
            error "Git not found. Install Xcode Command Line Tools: xcode-select --install"
        else
            error "Git not found. Install with your package manager."
        fi
    fi
    log "Git: $(git --version | head -1)"

    # Check for Go
    if ! command -v go &>/dev/null; then
        if [[ "$OS" == "macos" ]]; then
            if command -v brew &>/dev/null; then
                warn "Go not found. Installing via Homebrew..."
                brew install go
            else
                error "Go not found. Install Homebrew first, then run: brew install go"
            fi
        else
            case "$DISTRO" in
                ubuntu|debian|pop)
                    warn "Go not found. Installing..."
                    sudo apt update && sudo apt install -y golang-go
                    ;;
                fedora|rhel|centos)
                    warn "Go not found. Installing..."
                    sudo dnf install -y golang
                    ;;
                arch|manjaro)
                    warn "Go not found. Installing..."
                    sudo pacman -S --noconfirm go
                    ;;
                *)
                    error "Go not found. Please install Go 1.24+ manually from https://go.dev/dl/"
                    ;;
            esac
        fi
    fi

    # Verify Go version
    if command -v go &>/dev/null; then
        GO_VERSION=$(go version | grep -oE 'go[0-9]+\.[0-9]+' | sed 's/go//')
        log "Go: $GO_VERSION"
    fi

    # Check for Node.js
    if ! command -v node &>/dev/null; then
        if [[ "$OS" == "macos" ]]; then
            if command -v brew &>/dev/null; then
                warn "Node.js not found. Installing via Homebrew..."
                brew install node
            else
                error "Node.js not found. Install Homebrew first, then run: brew install node"
            fi
        else
            case "$DISTRO" in
                ubuntu|debian|pop)
                    warn "Node.js not found. Installing..."
                    sudo apt update && sudo apt install -y nodejs npm
                    ;;
                fedora|rhel|centos)
                    warn "Node.js not found. Installing..."
                    sudo dnf install -y nodejs npm
                    ;;
                arch|manjaro)
                    warn "Node.js not found. Installing..."
                    sudo pacman -S --noconfirm nodejs npm
                    ;;
                *)
                    error "Node.js not found. Please install Node.js manually from https://nodejs.org/"
                    ;;
            esac
        fi
    fi
    log "Node.js: $(node --version 2>/dev/null || echo 'installing...')"

    # Create directories
    mkdir -p "$CLIPROXY_BIN_DIR"
    mkdir -p "$CLIPROXY_LOG_DIR"
    [[ "$OS" == "macos" ]] && mkdir -p "$LAUNCHAGENTS_DIR"
    [[ "$OS" == "linux" ]] && mkdir -p "$SYSTEMD_USER_DIR"

    log "Prerequisites OK"
    echo ""
}

# =============================================================================
# Step 1: Clone CLIProxyAPI Source
# =============================================================================

clone_source() {
    log "Step 1: Cloning CLIProxyAPI source..."

    if [[ -d "$CLIPROXY_SOURCE_DIR/.git" ]]; then
        log "Source already cloned, pulling latest..."
        cd "$CLIPROXY_SOURCE_DIR"
        git fetch --tags --quiet
        git reset --hard origin/main --quiet
    else
        log "Cloning from GitHub..."
        rm -rf "$CLIPROXY_SOURCE_DIR"
        git clone https://github.com/router-for-me/CLIProxyAPI.git "$CLIPROXY_SOURCE_DIR"
        cd "$CLIPROXY_SOURCE_DIR"
        git fetch --tags --quiet
    fi

    VERSION=$(git describe --tags --always 2>/dev/null || echo "unknown")
    log "Source version: $VERSION"
    cd "$SCRIPT_DIR"
    echo ""
}

# =============================================================================
# Step 2: Build CLIProxyAPI
# =============================================================================

build_cliproxy() {
    log "Step 2: Building CLIProxyAPI from source..."

    cd "$CLIPROXY_SOURCE_DIR"

    VERSION=$(git describe --tags --always)
    COMMIT=$(git rev-parse --short HEAD)
    BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    DEFAULT_CONFIG="$SCRIPT_DIR/config.yaml"

    log "Building $VERSION ($COMMIT)..."

    go build \
        -ldflags "-X main.Version=$VERSION -X main.Commit=$COMMIT -X main.BuildDate=$BUILD_DATE -X main.DefaultConfigPath=$DEFAULT_CONFIG" \
        -o "$CLIPROXY_BIN" \
        ./cmd/server

    chmod +x "$CLIPROXY_BIN"

    # Verify build
    if [[ -x "$CLIPROXY_BIN" ]]; then
        BUILT_VERSION=$("$CLIPROXY_BIN" 2>&1 | grep "Version:" | sed 's/.*Version: \([^,]*\).*/\1/')
        log "Built successfully: $BUILT_VERSION"
    else
        error "Build failed!"
    fi

    # Build cliproxyctl (quota dashboard tool)
    log "Building cliproxyctl..."
    cd "$CLIPROXY_SOURCE_DIR/tools/cliproxyctl"
    go build -o "$CLIPROXY_BIN_DIR/cliproxyctl" .
    chmod +x "$CLIPROXY_BIN_DIR/cliproxyctl"
    if [[ -x "$CLIPROXY_BIN_DIR/cliproxyctl" ]]; then
        log "cliproxyctl built successfully"
    else
        warn "cliproxyctl build failed (non-critical)"
    fi

    cd "$SCRIPT_DIR"
    echo ""
}

# =============================================================================
# Step 3: Install CCR
# =============================================================================

install_ccr() {
    log "Step 3: Installing CCR (Claude Code Router)..."

    if command -v ccr &>/dev/null; then
        log "CCR already installed: $(ccr --version 2>/dev/null || echo 'unknown')"
    else
        if [[ "$OS" == "linux" ]]; then
            sudo npm install -g @musistudio/claude-code-router
        else
            npm install -g @musistudio/claude-code-router
        fi
        log "CCR installed"
    fi
    echo ""
}

# =============================================================================
# Step 4: Generate API Key and Create Configs
# =============================================================================

setup_config() {
    log "Step 4: Setting up configuration..."

    # API key defaults to "dummy" for local-only services
    # User can change this in .env if needed
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        log ".env exists, loading..."
        source "$SCRIPT_DIR/.env"
    else
        CLIPROXY_API_KEY="dummy"
        echo "CLIPROXY_API_KEY=\"$CLIPROXY_API_KEY\"" > "$SCRIPT_DIR/.env"
        log "Created .env with default API key"
    fi

    # Create config.yaml
    if [[ -f "$SCRIPT_DIR/config.yaml" ]]; then
        log "config.yaml already exists"
    else
        if [[ -f "$SCRIPT_DIR/config.example.yaml" ]]; then
            cp "$SCRIPT_DIR/config.example.yaml" "$SCRIPT_DIR/config.yaml"
            if [[ "$OS" == "macos" ]]; then
                sed -i '' "s/sk-your-api-key-here/$CLIPROXY_API_KEY/g" "$SCRIPT_DIR/config.yaml"
            else
                sed -i "s/sk-your-api-key-here/$CLIPROXY_API_KEY/g" "$SCRIPT_DIR/config.yaml"
            fi
            log "Created config.yaml"
        else
            error "config.example.yaml not found!"
        fi
    fi

    # Create CCR config
    CCR_CONFIG_DIR="$HOME/.claude-code-router"
    CCR_CONFIG_FILE="$CCR_CONFIG_DIR/config.json"

    # Find Claude CLI path
    CLAUDE_PATH=$(which claude 2>/dev/null || echo "/opt/homebrew/bin/claude")
    if [[ ! -x "$CLAUDE_PATH" ]]; then
        # Try common locations
        for path in /opt/homebrew/bin/claude /usr/local/bin/claude "$HOME/.local/bin/claude" "$HOME/.npm-global/bin/claude"; do
            if [[ -x "$path" ]]; then
                CLAUDE_PATH="$path"
                break
            fi
        done
    fi

    if [[ -f "$CCR_CONFIG_FILE" ]]; then
        log "CCR config already exists at $CCR_CONFIG_FILE"
    else
        mkdir -p "$CCR_CONFIG_DIR"
        cat > "$CCR_CONFIG_FILE" << EOF
{
  "LOG": true,
  "LOG_LEVEL": "debug",
  "CLAUDE_PATH": "${CLAUDE_PATH}",
  "HOST": "127.0.0.1",
  "PORT": 3456,
  "APIKEY": "${CLIPROXY_API_KEY}",
  "API_TIMEOUT_MS": "600000",
  "Providers": [
    {
      "Name": "cpa",
      "Type": "openai",
      "Model": "",
      "BaseURL": "http://127.0.0.1:8317/v1",
      "APIKEY": "${CLIPROXY_API_KEY}"
    }
  ],
  "Router": {
    "Model": {
      "opus": "gemini-claude-opus-4-5-thinking",
      "sonnet": "gemini-claude-sonnet-4-5-thinking",
      "haiku": "gemini-3-flash-preview"
    },
    "Provider": {
      "opus": "cpa",
      "sonnet": "cpa",
      "haiku": "cpa"
    }
  }
}
EOF
        log "Created CCR config at $CCR_CONFIG_FILE"
        log "Claude path: $CLAUDE_PATH"
    fi
    echo ""
}

# =============================================================================
# Step 5: Setup Auto-Start Service
# =============================================================================

setup_service() {
    log "Step 5: Setting up auto-start service..."

    if [[ "$OS" == "macos" ]]; then
        setup_launchd_service
    else
        setup_systemd_service
    fi
    echo ""
}

setup_launchd_service() {
    # Unload old brew service if exists
    launchctl unload ~/Library/LaunchAgents/homebrew.mxcl.cliproxyapi.plist 2>/dev/null || true
    brew services stop cliproxyapi 2>/dev/null || true

    # CLIProxyAPI service plist
    cat > "$LAUNCHAGENTS_DIR/com.cliproxy.api.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cliproxy.api</string>

    <key>ProgramArguments</key>
    <array>
        <string>$CLIPROXY_BIN</string>
        <string>--config</string>
        <string>$SCRIPT_DIR/config.yaml</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>$CLIPROXY_LOG_DIR/cliproxyapi.log</string>

    <key>StandardErrorPath</key>
    <string>$CLIPROXY_LOG_DIR/cliproxyapi.log</string>

    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>
</dict>
</plist>
EOF
    log "Created launchd service plist"
}

setup_systemd_service() {
    # Check if systemd is available
    if ! command -v systemctl &>/dev/null; then
        warn "systemd not available. Skipping auto-start service setup."
        warn "You'll need to start CLIProxyAPI manually or add to ~/.bashrc"
        return
    fi

    # Create systemd user service
    cat > "$SYSTEMD_USER_DIR/cliproxy.service" << EOF
[Unit]
Description=CLIProxyAPI - Antigravity Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=$CLIPROXY_BIN --config $SCRIPT_DIR/config.yaml
Restart=always
RestartSec=5
StandardOutput=append:$CLIPROXY_LOG_DIR/cliproxyapi.log
StandardError=append:$CLIPROXY_LOG_DIR/cliproxyapi.log
Environment=HOME=$HOME

[Install]
WantedBy=default.target
EOF

    # Reload systemd and enable service
    systemctl --user daemon-reload
    systemctl --user enable cliproxy.service 2>/dev/null || true
    log "Created systemd user service"
}

# =============================================================================
# Step 6: Setup Auto-Update
# =============================================================================

setup_autoupdate() {
    log "Step 6: Setting up auto-update (every 12 hours)..."

    if [[ "$OS" == "macos" ]]; then
        setup_launchd_updater
    else
        setup_cron_updater
    fi
    echo ""
}

setup_launchd_updater() {
    # Auto-updater plist (every 12 hours = 43200 seconds)
    cat > "$LAUNCHAGENTS_DIR/com.cliproxy.updater.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cliproxy.updater</string>

    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/cliproxy-updater.sh</string>
        <string>update</string>
    </array>

    <key>StartInterval</key>
    <integer>43200</integer>

    <key>RunAtLoad</key>
    <false/>

    <key>StandardOutPath</key>
    <string>$CLIPROXY_LOG_DIR/cliproxy-updater-launchd.log</string>

    <key>StandardErrorPath</key>
    <string>$CLIPROXY_LOG_DIR/cliproxy-updater-launchd.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>$HOME</string>
        <key>GOPATH</key>
        <string>$HOME/go</string>
    </dict>
</dict>
</plist>
EOF
    log "Created launchd updater plist (12-hour interval)"
}

setup_cron_updater() {
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "cliproxy-updater"; then
        log "Cron job already exists"
        return
    fi

    # Add cron job for every 12 hours (at minute 0 of hours 0 and 12)
    CRON_CMD="0 */12 * * * $SCRIPT_DIR/cliproxy-updater.sh update >> $CLIPROXY_LOG_DIR/cliproxy-updater-cron.log 2>&1"

    # Add to crontab
    (crontab -l 2>/dev/null || true; echo "$CRON_CMD") | crontab -
    log "Added cron job for auto-update (every 12 hours)"
}

# =============================================================================
# Step 7: Setup Shell Configuration
# =============================================================================

setup_shell() {
    log "Step 7: Setting up shell configuration..."

    SHELL_NAME=$(basename "$SHELL")
    case "$SHELL_NAME" in
        zsh)  SHELL_RC="$HOME/.zshrc" ;;
        bash) SHELL_RC="$HOME/.bashrc" ;;
        fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
        *)    SHELL_RC="$HOME/.${SHELL_NAME}rc" ;;
    esac

    # Ensure shell rc file exists
    touch "$SHELL_RC"

    MARKER="# Antigravity Claude Code (anticc)"
    PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
    SOURCE_LINE="source \"$SCRIPT_DIR/anticc.sh\""

    if grep -q "anticc.sh" "$SHELL_RC" 2>/dev/null; then
        log "Shell config already set up in $SHELL_RC"
    else
        {
            echo ""
            echo "$MARKER"
            echo "$PATH_LINE"
            echo "$SOURCE_LINE"
        } >> "$SHELL_RC"
        log "Added to $SHELL_RC"
    fi
    echo ""
}

# =============================================================================
# Step 8: Start Services
# =============================================================================

start_services() {
    log "Step 8: Starting services..."

    # Source .env for API key
    source "$SCRIPT_DIR/.env" 2>/dev/null || true

    # Health check function
    check_cliproxy_running() {
        curl -sf "http://127.0.0.1:8317/v1/models" -H "Authorization: Bearer $CLIPROXY_API_KEY" >/dev/null 2>&1
    }

    # Kill any existing cliproxy processes
    pkill -f "cliproxyapi" 2>/dev/null || true
    sleep 1

    if [[ "$OS" == "macos" ]]; then
        start_macos_services
    else
        start_linux_services
    fi

    # Start CCR
    if pgrep -f "claude-code-router" >/dev/null 2>&1; then
        log "CCR already running"
    else
        # Run ccr start in background with timeout to prevent hanging
        timeout 5 ccr start >/dev/null 2>&1 &
        sleep 2
        if pgrep -f "claude-code-router" >/dev/null 2>&1; then
            log "CCR started"
        else
            warn "CCR may need manual start: ccr start"
        fi
    fi

    echo ""
}

start_macos_services() {
    # Load and start via launchd
    launchctl unload "$LAUNCHAGENTS_DIR/com.cliproxy.api.plist" 2>/dev/null || true
    launchctl load "$LAUNCHAGENTS_DIR/com.cliproxy.api.plist"
    launchctl start com.cliproxy.api 2>/dev/null || true
    sleep 3

    if check_cliproxy_running; then
        log "CLIProxyAPI started via launchd"
    else
        warn "Launchd start may have failed, trying direct start..."
        nohup "$CLIPROXY_BIN" --config "$SCRIPT_DIR/config.yaml" >> "$CLIPROXY_LOG_DIR/cliproxyapi.log" 2>&1 &
        sleep 2
        if check_cliproxy_running; then
            log "CLIProxyAPI started directly"
        else
            warn "CLIProxyAPI may not be running. Check: tail $CLIPROXY_LOG_DIR/cliproxyapi.log"
        fi
    fi

    # Enable auto-updater
    launchctl unload "$LAUNCHAGENTS_DIR/com.cliproxy.updater.plist" 2>/dev/null || true
    launchctl load "$LAUNCHAGENTS_DIR/com.cliproxy.updater.plist" 2>/dev/null || true
    log "Auto-updater enabled (every 12 hours)"
}

start_linux_services() {
    # Try systemd first
    if command -v systemctl &>/dev/null; then
        systemctl --user start cliproxy.service 2>/dev/null || true
        sleep 2

        if check_cliproxy_running; then
            log "CLIProxyAPI started via systemd"
            return
        fi
    fi

    # Fallback to direct start
    nohup "$CLIPROXY_BIN" --config "$SCRIPT_DIR/config.yaml" >> "$CLIPROXY_LOG_DIR/cliproxyapi.log" 2>&1 &
    sleep 2

    if check_cliproxy_running; then
        log "CLIProxyAPI started directly"
    else
        warn "CLIProxyAPI may not be running. Check: tail $CLIPROXY_LOG_DIR/cliproxyapi.log"
    fi

    log "Auto-update cron job enabled (every 12 hours)"
}

# =============================================================================
# Final Instructions
# =============================================================================

print_success() {
    SHELL_NAME=$(basename "$SHELL")
    case "$SHELL_NAME" in
        zsh)  SHELL_RC="$HOME/.zshrc" ;;
        bash) SHELL_RC="$HOME/.bashrc" ;;
        *)    SHELL_RC="$HOME/.${SHELL_NAME}rc" ;;
    esac

    echo ""
    log "Setup complete!"
    echo ""
    echo "=============================================="
    echo -e "  ${BOLD}Next Steps${NC}"
    echo "=============================================="
    echo ""
    echo "1. Reload your shell:"
    echo -e "   ${BLUE}source $SHELL_RC${NC}"
    echo ""
    echo "2. Login to Antigravity (opens browser):"
    echo -e "   ${BLUE}$CLIPROXY_BIN --antigravity-login${NC}"
    echo ""
    echo "3. Verify services are running:"
    echo -e "   ${BLUE}anticc-status${NC}"
    echo ""
    echo "4. Use Claude Code:"
    echo -e "   ${BLUE}claude${NC}"
    echo ""
    echo "Optional: Add more Google accounts for higher rate limits:"
    echo -e "   ${BLUE}$CLIPROXY_BIN --antigravity-login${NC}  (repeat for each account)"
    echo ""
    echo "=============================================="
    echo -e "  ${BOLD}Useful Commands${NC}"
    echo "=============================================="
    echo ""
    echo -e "  ${BLUE}anticc-status${NC}    - Show service status"
    echo -e "  ${BLUE}anticc-version${NC}   - Show version info"
    echo -e "  ${BLUE}anticc-update${NC}    - Update CLIProxyAPI now"
    echo -e "  ${BLUE}anticc-diagnose${NC}  - Run diagnostics"
    echo -e "  ${BLUE}anticc-help${NC}      - Show all commands"
    echo ""
    echo "=============================================="
    echo ""

    # Ask if they want to login now
    read -r -p "Would you like to login to Antigravity now? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        "$CLIPROXY_BIN" --antigravity-login
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    check_prerequisites
    clone_source
    build_cliproxy
    install_ccr
    setup_config
    setup_service
    setup_autoupdate
    setup_shell
    start_services
    print_success
}

# Handle unsupported OS
if [[ "$OS" == "unknown" ]]; then
    error "Unsupported OS. Please use macOS or Linux."
fi

# Run
main
