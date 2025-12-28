#!/bin/bash
# =============================================================================
# CLIProxyAPI + Antigravity Setup Script
# =============================================================================
# This script sets up everything needed to use Claude Code with Antigravity:
# 1. Installs CLIProxyAPI (via Homebrew on macOS, direct download on Linux)
# 2. Installs CCR (Claude Code Router) via npm
# 3. Creates config files from examples
# 4. Generates an API key
# 5. Adds shell configuration to your terminal
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
error() { echo -e "${RED}[error]${NC} $*"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$SCRIPT_DIR"

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)    echo "macos" ;;
        Linux*)     echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)          echo "unknown" ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)   echo "amd64" ;;
        arm64|aarch64)  echo "arm64" ;;
        armv7l)         echo "arm" ;;
        *)              echo "unknown" ;;
    esac
}

# Detect Linux distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "$ID"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)
ARCH=$(detect_arch)
DISTRO=""
[[ "$OS" == "linux" ]] && DISTRO=$(detect_distro)

echo ""
echo "=============================================="
echo "  CLIProxyAPI + Antigravity Setup"
echo "=============================================="
echo "  OS: $OS, Arch: $ARCH${DISTRO:+, Distro: $DISTRO}"
echo "=============================================="
echo ""

# =============================================================================
# Helper: Install Node.js if needed
# =============================================================================
install_nodejs() {
    if command -v node &>/dev/null && command -v npm &>/dev/null; then
        log "Node.js already installed: $(node --version)"
        return 0
    fi
    
    log "Installing Node.js..."
    
    case "$OS" in
        macos)
            if command -v brew &>/dev/null; then
                brew install node
            else
                error "Homebrew not found. Please install Node.js manually:"
                echo "  brew install node"
                echo "  Or download from: https://nodejs.org/"
                return 1
            fi
            ;;
        linux)
            case "$DISTRO" in
                ubuntu|debian|pop|linuxmint|elementary)
                    log "Installing Node.js via apt..."
                    # Use NodeSource for latest LTS
                    if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
                        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
                    fi
                    sudo apt-get install -y nodejs
                    ;;
                fedora|rhel|centos|rocky|almalinux)
                    log "Installing Node.js via dnf..."
                    sudo dnf install -y nodejs npm
                    ;;
                arch|manjaro|endeavouros)
                    log "Installing Node.js via pacman..."
                    sudo pacman -S --noconfirm nodejs npm
                    ;;
                opensuse*|suse*)
                    log "Installing Node.js via zypper..."
                    sudo zypper install -y nodejs npm
                    ;;
                alpine)
                    log "Installing Node.js via apk..."
                    sudo apk add --no-cache nodejs npm
                    ;;
                *)
                    warn "Unknown Linux distribution: $DISTRO"
                    warn "Trying to install Node.js via nvm..."
                    
                    # Install nvm as fallback
                    if [[ ! -d "$HOME/.nvm" ]]; then
                        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
                        export NVM_DIR="$HOME/.nvm"
                        # shellcheck disable=SC1091
                        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
                    fi
                    
                    if command -v nvm &>/dev/null; then
                        nvm install --lts
                        nvm use --lts
                    else
                        error "Could not install Node.js. Please install manually:"
                        echo "  https://nodejs.org/en/download/"
                        return 1
                    fi
                    ;;
            esac
            ;;
        *)
            error "Unsupported OS for Node.js installation: $OS"
            return 1
            ;;
    esac
    
    # Verify installation
    if command -v node &>/dev/null && command -v npm &>/dev/null; then
        log "Node.js installed: $(node --version)"
        return 0
    else
        error "Node.js installation failed"
        return 1
    fi
}

# =============================================================================
# Step 1: Check/Install CLIProxyAPI
# =============================================================================
log "Checking CLIProxyAPI..."

# Check for either command name (CLIProxyAPI or cliproxyapi)
CLIPROXY_CMD=""
if command -v CLIProxyAPI &>/dev/null; then
    CLIPROXY_CMD="CLIProxyAPI"
elif command -v cliproxyapi &>/dev/null; then
    CLIPROXY_CMD="cliproxyapi"
fi

if [[ -n "$CLIPROXY_CMD" ]]; then
    log "CLIProxyAPI already installed: $($CLIPROXY_CMD --help 2>&1 | head -1 || echo 'unknown version')"
else
    case "$OS" in
        macos)
            if command -v brew &>/dev/null; then
                log "Installing CLIProxyAPI via Homebrew..."
                brew install router-for-me/tap/cliproxyapi
                CLIPROXY_CMD="cliproxyapi"
            else
                error "Homebrew not found. Please install CLIProxyAPI manually:"
                echo "  brew install router-for-me/tap/cliproxyapi"
                echo "  Or download from: https://github.com/router-for-me/CLIProxyAPI/releases"
                exit 1
            fi
            ;;
        linux)
            log "Installing CLIProxyAPI for Linux..."
            
            # Determine download URL based on architecture
            DOWNLOAD_ARCH="$ARCH"
            if [[ "$ARCH" == "amd64" ]]; then
                DOWNLOAD_ARCH="amd64"
            elif [[ "$ARCH" == "arm64" ]]; then
                DOWNLOAD_ARCH="arm64"
            else
                error "Unsupported architecture: $ARCH"
                echo "  Please download manually from: https://github.com/router-for-me/CLIProxyAPI/releases"
                exit 1
            fi
            
            # Get latest release version
            log "Fetching latest release..."
            LATEST_VERSION=$(curl -sL "https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || echo "")
            
            if [[ -z "$LATEST_VERSION" ]]; then
                warn "Could not determine latest version, using v6.6.60"
                LATEST_VERSION="v6.6.60"
            fi
            
            log "Latest version: $LATEST_VERSION"
            
            # Download URL
            DOWNLOAD_URL="https://github.com/router-for-me/CLIProxyAPI/releases/download/${LATEST_VERSION}/CLIProxyAPI_Linux_${DOWNLOAD_ARCH}.tar.gz"
            
            # Create temp directory
            TEMP_DIR=$(mktemp -d)
            trap "rm -rf $TEMP_DIR" EXIT
            
            log "Downloading from: $DOWNLOAD_URL"
            if curl -sL "$DOWNLOAD_URL" -o "$TEMP_DIR/cliproxyapi.tar.gz"; then
                log "Extracting..."
                tar -xzf "$TEMP_DIR/cliproxyapi.tar.gz" -C "$TEMP_DIR"
                
                # Find the binary
                BINARY_PATH=$(find "$TEMP_DIR" -name "CLIProxyAPI" -o -name "cliproxyapi" 2>/dev/null | head -1)
                
                if [[ -z "$BINARY_PATH" ]]; then
                    # Try looking for any executable
                    BINARY_PATH=$(find "$TEMP_DIR" -type f -executable 2>/dev/null | head -1)
                fi
                
                if [[ -n "$BINARY_PATH" && -f "$BINARY_PATH" ]]; then
                    # Install to /usr/local/bin or ~/.local/bin
                    if [[ -w "/usr/local/bin" ]]; then
                        INSTALL_DIR="/usr/local/bin"
                    else
                        INSTALL_DIR="$HOME/.local/bin"
                        mkdir -p "$INSTALL_DIR"
                    fi
                    
                    cp "$BINARY_PATH" "$INSTALL_DIR/cliproxyapi"
                    chmod +x "$INSTALL_DIR/cliproxyapi"
                    
                    # Also create CLIProxyAPI symlink for compatibility
                    ln -sf "$INSTALL_DIR/cliproxyapi" "$INSTALL_DIR/CLIProxyAPI" 2>/dev/null || true
                    
                    log "Installed to: $INSTALL_DIR/cliproxyapi"
                    
                    # Add to PATH if needed
                    if [[ "$INSTALL_DIR" == "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
                        warn "Please add ~/.local/bin to your PATH:"
                        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
                        export PATH="$HOME/.local/bin:$PATH"
                    fi
                    
                    CLIPROXY_CMD="cliproxyapi"
                else
                    error "Could not find CLIProxyAPI binary in downloaded archive"
                    exit 1
                fi
            else
                error "Failed to download CLIProxyAPI"
                echo "  Please download manually from: https://github.com/router-for-me/CLIProxyAPI/releases"
                exit 1
            fi
            ;;
        *)
            error "Unsupported OS: $OS"
            echo "  Please download CLIProxyAPI manually from: https://github.com/router-for-me/CLIProxyAPI/releases"
            exit 1
            ;;
    esac
fi

# Export the command name for use in anticc.sh
export CLIPROXY_CMD

# =============================================================================
# Step 2: Install CCR (Claude Code Router)
# =============================================================================
log "Checking CCR (Claude Code Router)..."

if command -v ccr &>/dev/null; then
    log "CCR already installed: $(ccr --version 2>&1 || echo 'installed')"
else
    log "Installing CCR..."
    
    # Ensure Node.js is installed
    if ! install_nodejs; then
        error "Node.js is required for CCR. Please install Node.js and re-run setup."
        exit 1
    fi
    
    # Install CCR globally
    log "Installing @musistudio/claude-code-router..."
    npm install -g @musistudio/claude-code-router
    
    if command -v ccr &>/dev/null; then
        log "CCR installed successfully"
    else
        warn "CCR installed but 'ccr' command not found in PATH"
        warn "You may need to add npm global bin to your PATH:"
        echo "  export PATH=\"\$(npm config get prefix)/bin:\$PATH\""
    fi
fi

# =============================================================================
# Step 3: Create Config Files
# =============================================================================
log "Setting up configuration..."

# Generate API key if needed
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    log ".env already exists"
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
else
    API_KEY="sk-$(openssl rand -hex 24)"
    echo "CLIPROXY_API_KEY=\"$API_KEY\"" > "$SCRIPT_DIR/.env"
    log "Generated new API key in .env"
    CLIPROXY_API_KEY="$API_KEY"
fi

# Create config.yaml from example
if [[ -f "$SCRIPT_DIR/config.yaml" ]]; then
    log "config.yaml already exists"
else
    if [[ -f "$SCRIPT_DIR/config.example.yaml" ]]; then
        cp "$SCRIPT_DIR/config.example.yaml" "$SCRIPT_DIR/config.yaml"
        # Replace placeholder with actual key
        if [[ -n "$CLIPROXY_API_KEY" ]]; then
            # Use different sed syntax for macOS vs Linux
            if [[ "$OS" == "macos" ]]; then
                sed -i '' "s/sk-your-api-key-here/$CLIPROXY_API_KEY/g" "$SCRIPT_DIR/config.yaml"
            else
                sed -i "s/sk-your-api-key-here/$CLIPROXY_API_KEY/g" "$SCRIPT_DIR/config.yaml"
            fi
        fi
        log "Created config.yaml from example"
    else
        error "config.example.yaml not found!"
        exit 1
    fi
fi

# =============================================================================
# Step 4: Create CCR config if needed
# =============================================================================
CCR_CONFIG_DIR="$HOME/.config/ccr"
CCR_CONFIG_FILE="$CCR_CONFIG_DIR/config.json"

if [[ -f "$CCR_CONFIG_FILE" ]]; then
    log "CCR config already exists at $CCR_CONFIG_FILE"
else
    log "Creating CCR config..."
    mkdir -p "$CCR_CONFIG_DIR"
    
    # Create CCR config pointing to CLIProxyAPI
    cat > "$CCR_CONFIG_FILE" << EOF
{
  "port": 3456,
  "providers": {
    "default": {
      "baseUrl": "http://127.0.0.1:8317/v1",
      "apiKey": "${CLIPROXY_API_KEY}"
    }
  },
  "modelRouting": {
    "claude-sonnet-4-20250514": "gemini-claude-sonnet-4-5-thinking",
    "claude-3-5-sonnet-20241022": "gemini-claude-sonnet-4-5-thinking",
    "claude-3-5-haiku-20241022": "gemini-claude-sonnet-4-5",
    "claude-opus-4-20250514": "gemini-claude-opus-4-5-thinking"
  }
}
EOF
    log "Created CCR config at $CCR_CONFIG_FILE"
fi

# =============================================================================
# Step 5: Add to Shell Configuration
# =============================================================================
log "Setting up shell configuration..."

# Detect shell
SHELL_NAME=$(basename "$SHELL")
case "$SHELL_NAME" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bashrc" ;;
    *)    SHELL_RC="$HOME/.${SHELL_NAME}rc" ;;
esac

# Source line to add
SOURCE_LINE="source \"$SCRIPT_DIR/anticc.sh\""
MARKER="# Antigravity Claude Code (anticc)"

# Check if already added
if [[ -f "$SHELL_RC" ]] && grep -q "anticc.sh" "$SHELL_RC"; then
    log "Shell config already set up in $SHELL_RC"
else
    echo "" >> "$SHELL_RC"
    echo "$MARKER" >> "$SHELL_RC"
    echo "$SOURCE_LINE" >> "$SHELL_RC"
    log "Added to $SHELL_RC"
fi

# =============================================================================
# Step 6: Setup Services (macOS only - using brew services)
# =============================================================================
if [[ "$OS" == "macos" ]]; then
    log "Setting up CLIProxyAPI as a brew service..."
    
    # Check if service is already running
    if brew services list 2>/dev/null | grep -q "cliproxyapi.*started"; then
        log "CLIProxyAPI service already running"
    else
        log "Starting CLIProxyAPI service..."
        brew services start cliproxyapi 2>/dev/null || warn "Could not start brew service (may need manual start)"
    fi
fi

# =============================================================================
# Step 7: Login to Antigravity
# =============================================================================
echo ""
log "Setup complete!"
echo ""
echo "=============================================="
echo "  Next Steps"
echo "=============================================="
echo ""
echo "1. Reload your shell:"
echo "   ${BLUE}source $SHELL_RC${NC}"
echo ""
echo "2. Login to Antigravity (opens browser):"
echo "   ${BLUE}cliproxyapi --antigravity-login${NC}"
echo ""
echo "3. Start the services:"
if [[ "$OS" == "macos" ]]; then
echo "   ${BLUE}brew services start cliproxyapi${NC}  (if not already running)"
else
echo "   ${BLUE}cliproxyapi --config $SCRIPT_DIR/config.yaml &${NC}"
fi
echo "   ${BLUE}ccr start${NC}"
echo ""
echo "4. Use Claude Code:"
echo "   ${BLUE}claude${NC}"
echo ""
echo "Optional: Add more Google accounts for higher rate limits:"
echo "   ${BLUE}cliproxyapi --antigravity-login${NC}  (repeat for each account)"
echo ""
echo "=============================================="
echo ""

# Ask if they want to login now
read -r -p "Would you like to login to Antigravity now? [y/N] " response
if [[ "$response" =~ ^[Yy]$ ]]; then
    # Source the script first
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/anticc.sh"
    # Use the detected command name
    if [[ -n "$CLIPROXY_CMD" ]]; then
        "$CLIPROXY_CMD" --antigravity-login
    elif command -v cliproxyapi &>/dev/null; then
        cliproxyapi --antigravity-login
    elif command -v CLIProxyAPI &>/dev/null; then
        CLIProxyAPI --antigravity-login
    else
        error "CLIProxyAPI command not found!"
        exit 1
    fi
fi
