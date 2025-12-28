#!/bin/bash
# =============================================================================
# Antigravity Claude Code Setup Script
# =============================================================================
# This script sets up everything needed to use Claude Code with Antigravity:
# 1. Installs CLIProxyAPI (via Homebrew on macOS)
# 2. Installs CCR (Claude Code Router) via npm
# 3. Creates config files
# 4. Generates an API key
# 5. Adds shell configuration to your terminal
# 6. Starts services
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
        *)          echo "unknown" ;;
    esac
}

OS=$(detect_os)

echo ""
echo "=============================================="
echo "  Antigravity Claude Code Setup"
echo "=============================================="
echo "  OS: $OS"
echo "=============================================="
echo ""

# =============================================================================
# macOS Setup
# =============================================================================
if [[ "$OS" == "macos" ]]; then
    
    # Check for Homebrew
    if ! command -v brew &>/dev/null; then
        error "Homebrew not found. Please install Homebrew first:"
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    
    # Step 1: Install CLIProxyAPI
    log "Step 1: Installing CLIProxyAPI..."
    if command -v cliproxyapi &>/dev/null; then
        log "CLIProxyAPI already installed"
    else
        brew install router-for-me/tap/cliproxyapi
        log "CLIProxyAPI installed"
    fi
    
    # Step 2: Install Node.js (for CCR)
    log "Step 2: Checking Node.js..."
    if ! command -v node &>/dev/null; then
        log "Installing Node.js..."
        brew install node
    fi
    log "Node.js: $(node --version)"
    
    # Step 3: Install CCR
    log "Step 3: Installing CCR (Claude Code Router)..."
    if command -v ccr &>/dev/null; then
        log "CCR already installed"
    else
        npm install -g @musistudio/claude-code-router
        log "CCR installed"
    fi
    
    # Step 4: Generate API key and create config
    log "Step 4: Setting up configuration..."
    
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        log ".env already exists"
        source "$SCRIPT_DIR/.env"
    else
        API_KEY="sk-$(openssl rand -hex 24)"
        echo "CLIPROXY_API_KEY=\"$API_KEY\"" > "$SCRIPT_DIR/.env"
        log "Generated new API key"
        CLIPROXY_API_KEY="$API_KEY"
    fi
    
    # Create config.yaml in project directory
    if [[ -f "$SCRIPT_DIR/config.yaml" ]]; then
        log "config.yaml already exists"
    else
        if [[ -f "$SCRIPT_DIR/config.example.yaml" ]]; then
            cp "$SCRIPT_DIR/config.example.yaml" "$SCRIPT_DIR/config.yaml"
            sed -i '' "s/sk-your-api-key-here/$CLIPROXY_API_KEY/g" "$SCRIPT_DIR/config.yaml"
            log "Created config.yaml"
        else
            error "config.example.yaml not found!"
            exit 1
        fi
    fi
    
    # Symlink our config to Homebrew's config location
    # CLIProxyAPI brew service uses config at /opt/homebrew/etc/cliproxyapi.conf
    BREW_CONFIG_DIR="/opt/homebrew/etc"
    [[ ! -d "$BREW_CONFIG_DIR" ]] && BREW_CONFIG_DIR="/usr/local/etc"
    BREW_CONFIG_FILE="$BREW_CONFIG_DIR/cliproxyapi.conf"
    
    if [[ -d "$BREW_CONFIG_DIR" ]]; then
        # Check if already symlinked to our config
        if [[ -L "$BREW_CONFIG_FILE" ]] && [[ "$(readlink "$BREW_CONFIG_FILE")" == "$SCRIPT_DIR/config.yaml" ]]; then
            log "Homebrew config already symlinked to our config"
        else
            # Backup existing config if it's a regular file
            if [[ -f "$BREW_CONFIG_FILE" && ! -L "$BREW_CONFIG_FILE" ]]; then
                mv "$BREW_CONFIG_FILE" "$BREW_CONFIG_FILE.backup"
                log "Backed up existing config to $BREW_CONFIG_FILE.backup"
            fi
            
            # Remove existing symlink if it points elsewhere
            [[ -L "$BREW_CONFIG_FILE" ]] && rm "$BREW_CONFIG_FILE"
            
            # Create symlink
            ln -sf "$SCRIPT_DIR/config.yaml" "$BREW_CONFIG_FILE"
            log "Symlinked $BREW_CONFIG_FILE → $SCRIPT_DIR/config.yaml"
        fi
    else
        warn "Homebrew etc directory not found. CLIProxyAPI may need manual config."
    fi
    
    # Step 5: Create CCR config
    log "Step 5: Setting up CCR config..."
    CCR_CONFIG_DIR="$HOME/.config/ccr"
    CCR_CONFIG_FILE="$CCR_CONFIG_DIR/config.json"
    
    if [[ -f "$CCR_CONFIG_FILE" ]]; then
        log "CCR config already exists"
    else
        mkdir -p "$CCR_CONFIG_DIR"
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
        log "Created CCR config"
    fi
    
    # Step 6: Add to shell config
    log "Step 6: Setting up shell configuration..."
    
    SHELL_NAME=$(basename "$SHELL")
    case "$SHELL_NAME" in
        zsh)  SHELL_RC="$HOME/.zshrc" ;;
        bash) SHELL_RC="$HOME/.bashrc" ;;
        *)    SHELL_RC="$HOME/.${SHELL_NAME}rc" ;;
    esac
    
    SOURCE_LINE="source \"$SCRIPT_DIR/anticc.sh\""
    MARKER="# Antigravity Claude Code (anticc)"
    
    if [[ -f "$SHELL_RC" ]] && grep -q "anticc.sh" "$SHELL_RC"; then
        log "Shell config already set up"
    else
        echo "" >> "$SHELL_RC"
        echo "$MARKER" >> "$SHELL_RC"
        echo "$SOURCE_LINE" >> "$SHELL_RC"
        log "Added to $SHELL_RC"
    fi
    
    # Step 7: Start services
    log "Step 7: Starting services..."
    
    # Start CLIProxyAPI via brew services
    if brew services list 2>/dev/null | grep -q "cliproxyapi.*started"; then
        log "CLIProxyAPI already running"
    else
        brew services start cliproxyapi
        log "CLIProxyAPI started"
    fi
    
    # Start CCR
    if pgrep -f "claude-code-router" >/dev/null 2>&1; then
        log "CCR already running"
    else
        ccr start 2>/dev/null || warn "CCR may need manual start: ccr start"
    fi
    
    # Done!
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
    echo "3. Verify services are running:"
    echo "   ${BLUE}anticc-status${NC}"
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
        cliproxyapi --antigravity-login
    fi

# =============================================================================
# Linux Setup (basic support)
# =============================================================================
elif [[ "$OS" == "linux" ]]; then
    warn "Linux support is experimental. Some steps may require manual intervention."
    
    # Detect architecture
    ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
    
    # Step 1: Install CLIProxyAPI
    log "Step 1: Installing CLIProxyAPI..."
    if command -v cliproxyapi &>/dev/null; then
        log "CLIProxyAPI already installed"
    else
        VERSION=$(curl -sL "https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v6.6.60")
        DOWNLOAD_URL="https://github.com/router-for-me/CLIProxyAPI/releases/download/${VERSION}/CLIProxyAPI_Linux_${ARCH}.tar.gz"
        
        TEMP_DIR=$(mktemp -d)
        trap "rm -rf $TEMP_DIR" EXIT
        
        log "Downloading CLIProxyAPI $VERSION..."
        curl -sL "$DOWNLOAD_URL" -o "$TEMP_DIR/cliproxyapi.tar.gz"
        tar -xzf "$TEMP_DIR/cliproxyapi.tar.gz" -C "$TEMP_DIR"
        
        INSTALL_DIR="$HOME/.local/bin"
        mkdir -p "$INSTALL_DIR"
        
        BINARY=$(find "$TEMP_DIR" -type f -executable | head -1)
        cp "$BINARY" "$INSTALL_DIR/cliproxyapi"
        chmod +x "$INSTALL_DIR/cliproxyapi"
        
        export PATH="$HOME/.local/bin:$PATH"
        log "CLIProxyAPI installed to $INSTALL_DIR"
    fi
    
    # Step 2: Install Node.js
    log "Step 2: Checking Node.js..."
    if ! command -v node &>/dev/null; then
        warn "Node.js not found. Please install Node.js manually:"
        echo "  Ubuntu/Debian: sudo apt install nodejs npm"
        echo "  Fedora: sudo dnf install nodejs npm"
        echo "  Arch: sudo pacman -S nodejs npm"
        exit 1
    fi
    log "Node.js: $(node --version)"
    
    # Step 3: Install CCR
    log "Step 3: Installing CCR..."
    if command -v ccr &>/dev/null; then
        log "CCR already installed"
    else
        npm install -g @musistudio/claude-code-router
        log "CCR installed"
    fi
    
    # Step 4-6: Same as macOS
    log "Step 4: Setting up configuration..."
    
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        source "$SCRIPT_DIR/.env"
    else
        API_KEY="sk-$(openssl rand -hex 24)"
        echo "CLIPROXY_API_KEY=\"$API_KEY\"" > "$SCRIPT_DIR/.env"
        CLIPROXY_API_KEY="$API_KEY"
    fi
    
    if [[ ! -f "$SCRIPT_DIR/config.yaml" ]] && [[ -f "$SCRIPT_DIR/config.example.yaml" ]]; then
        cp "$SCRIPT_DIR/config.example.yaml" "$SCRIPT_DIR/config.yaml"
        sed -i "s/sk-your-api-key-here/$CLIPROXY_API_KEY/g" "$SCRIPT_DIR/config.yaml"
    fi
    
    # CCR config
    CCR_CONFIG_DIR="$HOME/.config/ccr"
    CCR_CONFIG_FILE="$CCR_CONFIG_DIR/config.json"
    if [[ ! -f "$CCR_CONFIG_FILE" ]]; then
        mkdir -p "$CCR_CONFIG_DIR"
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
    fi
    
    # Shell config
    SHELL_RC="$HOME/.bashrc"
    [[ "$SHELL" == *"zsh"* ]] && SHELL_RC="$HOME/.zshrc"
    
    if ! grep -q "anticc.sh" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# Antigravity Claude Code (anticc)" >> "$SHELL_RC"
        echo "source \"$SCRIPT_DIR/anticc.sh\"" >> "$SHELL_RC"
    fi
    
    echo ""
    log "Setup complete!"
    echo ""
    echo "=============================================="
    echo "  Next Steps (Linux)"
    echo "=============================================="
    echo ""
    echo "1. Reload your shell:"
    echo "   ${BLUE}source $SHELL_RC${NC}"
    echo ""
    echo "2. Login to Antigravity:"
    echo "   ${BLUE}cliproxyapi --antigravity-login${NC}"
    echo ""
    echo "3. Start services manually:"
    echo "   ${BLUE}cliproxyapi --config $SCRIPT_DIR/config.yaml &${NC}"
    echo "   ${BLUE}ccr start${NC}"
    echo ""
    echo "4. Use Claude Code:"
    echo "   ${BLUE}claude${NC}"
    echo ""
    echo "=============================================="

else
    error "Unsupported OS: $OS"
    echo "Please use macOS or Linux."
    exit 1
fi
