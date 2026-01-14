# ============================================================================
# cliproxy-updater.ps1 - Automatic CLIProxyAPI Build & Deploy for Windows
# ============================================================================
# Runs via Windows Task Scheduler every 12 hours. Pulls latest, builds,
# health checks, and auto-rollbacks if something breaks.
#
# Usage:
#   .\cliproxy-updater.ps1 -Action update    # Pull, build, deploy (default)
#   .\cliproxy-updater.ps1 -Action status    # Show version info
#   .\cliproxy-updater.ps1 -Action rollback  # Rollback to previous version
#   .\cliproxy-updater.ps1 -Action build-only # Build without deploy
# ============================================================================

[CmdletBinding()]
param(
    [ValidateSet("update", "status", "rollback", "build-only")]
    [string]$Action = "update"
)

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================
$script:CLIPROXY_SOURCE_DIR = if ($env:CLIPROXY_SOURCE_DIR) {
    $env:CLIPROXY_SOURCE_DIR
} else {
    Join-Path $PSScriptRoot "cliproxy-source"
}

$script:CLIPROXY_BIN_DIR = if ($env:CLIPROXY_BIN_DIR) {
    $env:CLIPROXY_BIN_DIR
} else {
    Join-Path $env:LOCALAPPDATA "Programs\CLIProxyAPI"
}

$script:CLIPROXY_CONFIG = if ($env:CLIPROXY_CONFIG) {
    $env:CLIPROXY_CONFIG
} else {
    Join-Path $PSScriptRoot "config.yaml"
}

$script:CLIPROXY_PORT = if ($env:CLIPROXY_PORT) { $env:CLIPROXY_PORT } else { 8317 }
$script:CLIPROXY_API_KEY = $env:CLIPROXY_API_KEY

$script:LOG_DIR = Join-Path $env:LOCALAPPDATA "CLIProxyAPI\logs"
$script:LOG_FILE = Join-Path $script:LOG_DIR "cliproxy-updater.log"

# Ensure directories exist
if (-not (Test-Path $script:LOG_DIR)) {
    New-Item -ItemType Directory -Path $script:LOG_DIR -Force | Out-Null
}

if (-not (Test-Path $script:CLIPROXY_BIN_DIR)) {
    New-Item -ItemType Directory -Path $script:CLIPROXY_BIN_DIR -Force | Out-Null
}

# ============================================================================
# LOGGING
# ============================================================================
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    Add-Content -Path $script:LOG_FILE -Value $logMessage -ErrorAction SilentlyContinue
}

function Write-LogError {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] ERROR: $Message"
    Write-Host $logMessage -ForegroundColor Red
    Add-Content -Path $script:LOG_FILE -Value $logMessage -ErrorAction SilentlyContinue
}

# ============================================================================
# VERSION HELPERS
# ============================================================================
function Get-RunningVersion {
    $proc = Get-Process -Name "cliproxyapi" -ErrorAction SilentlyContinue
    if ($proc) {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:CLIPROXY_PORT)/" -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($response.Content -match 'v[\d.]+') {
                return $matches[0]
            }
        } catch {}
        return "unknown"
    }
    return "not running"
}

function Get-BinaryVersion {
    $binary = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.exe"
    if (Test-Path $binary) {
        $output = & $binary 2>&1 | Select-String "Version:" | Select-Object -First 1
        if ($output -match 'Version:\s*([^,]+)') {
            return $matches[1]
        }
        return "unknown"
    }
    return "not installed"
}

function Get-SourceVersion {
    if (Test-Path $script:CLIPROXY_SOURCE_DIR) {
        Push-Location $script:CLIPROXY_SOURCE_DIR
        $version = git describe --tags --always 2>$null
        Pop-Location
        return $version
    }
    return "unknown"
}

# ============================================================================
# HEALTH CHECK
# ============================================================================
function Test-Health {
    $maxAttempts = 30
    $attempt = 1

    while ($attempt -le $maxAttempts) {
        try {
            $headers = @{ "Authorization" = "Bearer $($script:CLIPROXY_API_KEY)" }
            $null = Invoke-RestMethod -Uri "http://127.0.0.1:$($script:CLIPROXY_PORT)/v1/models" `
                -Headers $headers -TimeoutSec 2 -ErrorAction Stop
            return $true
        } catch {
            Start-Sleep -Seconds 1
            $attempt++
        }
    }
    return $false
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================
function Stop-CLIProxyAPI {
    Write-Log "Stopping CLIProxyAPI..."
    Stop-Process -Name "cliproxyapi" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Start-CLIProxyAPI {
    Write-Log "Starting CLIProxyAPI..."
    $binary = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.exe"
    $logFile = Join-Path $script:LOG_DIR "cliproxyapi.log"

    Start-Process -FilePath $binary -ArgumentList "--config", "`"$($script:CLIPROXY_CONFIG)`"" `
        -WindowStyle Hidden -RedirectStandardOutput $logFile -RedirectStandardError $logFile

    Start-Sleep -Seconds 3
}

# ============================================================================
# ROLLBACK
# ============================================================================
function Invoke-Rollback {
    Write-LogError "Rolling back to previous version..."
    $backup = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.bak.exe"
    $current = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.exe"
    $failed = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.failed.exe"

    if (Test-Path $backup) {
        Stop-CLIProxyAPI

        if (Test-Path $current) {
            Move-Item -Path $current -Destination $failed -Force -ErrorAction SilentlyContinue
        }
        Move-Item -Path $backup -Destination $current -Force

        Start-CLIProxyAPI

        if (Test-Health) {
            Write-Log "Rollback successful"
            # Windows toast notification (if BurntToast module available)
            if (Get-Module -ListAvailable -Name BurntToast) {
                Import-Module BurntToast
                New-BurntToastNotification -Text "CLIProxyAPI", "Rollback successful after failed update"
            }
            return $true
        } else {
            Write-LogError "Rollback failed - service not responding"
            return $false
        }
    } else {
        Write-LogError "No backup available for rollback"
        return $false
    }
}

# ============================================================================
# UPDATE
# ============================================================================
function Invoke-Update {
    Write-Log "=== CLIProxyAPI Auto-Update Started ==="

    # Load API key from .env if not set
    $envFile = Join-Path $PSScriptRoot ".env"
    if (-not $script:CLIPROXY_API_KEY -and (Test-Path $envFile)) {
        Get-Content $envFile | ForEach-Object {
            if ($_ -match "^\s*([^#][^=]+)\s*=\s*(.+)\s*$") {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim().Trim('"').Trim("'")
                if ($name -eq "CLIPROXY_API_KEY") {
                    $script:CLIPROXY_API_KEY = $value
                }
            }
        }
    }

    # Check if source directory exists
    if (-not (Test-Path $script:CLIPROXY_SOURCE_DIR)) {
        Write-LogError "Source directory not found: $($script:CLIPROXY_SOURCE_DIR)"
        Write-Log "Run setup-windows.ps1 to clone the repository first"
        return $false
    }

    $oldVersion = Get-SourceVersion

    # Pull latest
    Write-Log "Pulling latest changes..."
    Push-Location $script:CLIPROXY_SOURCE_DIR
    try {
        git fetch --tags --quiet 2>$null
        git reset --hard origin/main --quiet 2>$null
    } catch {
        Write-LogError "Git pull failed: $_"
        Pop-Location
        return $false
    }

    $newVersion = Get-SourceVersion
    $currentBinaryVersion = Get-BinaryVersion

    # Check if update needed
    if ($newVersion -eq $currentBinaryVersion) {
        Write-Log "Already at latest version: $newVersion"
        Pop-Location
        return $true
    }

    Write-Log "Update available: $currentBinaryVersion -> $newVersion"

    # Check if Go is installed
    try {
        $null = Get-Command go -ErrorAction Stop
    } catch {
        Write-LogError "Go is not installed. Please install Go from https://golang.org/dl/"
        Pop-Location
        return $false
    }

    # Build new version
    Write-Log "Building $newVersion..."
    $VERSION = git describe --tags --always
    $COMMIT = git rev-parse --short HEAD
    $BUILD_DATE = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $DEFAULT_CONFIG = $script:CLIPROXY_CONFIG

    $ldflags = "-X 'main.Version=$VERSION' -X 'main.Commit=$COMMIT' -X 'main.BuildDate=$BUILD_DATE' -X 'main.DefaultConfigPath=$DEFAULT_CONFIG'"

    try {
        $env:CGO_ENABLED = "0"
        go build -ldflags "$ldflags" -o "cliproxyapi.new.exe" ./cmd/server 2>&1 | Tee-Object -FilePath $script:LOG_FILE -Append
        if (-not (Test-Path "cliproxyapi.new.exe")) {
            throw "Build output not found"
        }
    } catch {
        Write-LogError "Build failed: $_"
        Remove-Item "cliproxyapi.new.exe" -Force -ErrorAction SilentlyContinue
        Pop-Location
        return $false
    }

    # Backup current binary
    $currentBinary = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.exe"
    $backupBinary = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.bak.exe"
    if (Test-Path $currentBinary) {
        Copy-Item -Path $currentBinary -Destination $backupBinary -Force
    }

    # Deploy new binary
    Write-Log "Deploying new binary..."
    Move-Item -Path "cliproxyapi.new.exe" -Destination $currentBinary -Force

    Pop-Location

    # Restart service
    Stop-CLIProxyAPI
    Start-CLIProxyAPI

    # Health check
    Write-Log "Running health check..."
    if (Test-Health) {
        Write-Log "Update successful: $newVersion"
        $failed = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.failed.exe"
        Remove-Item $failed -Force -ErrorAction SilentlyContinue

        # Windows toast notification
        if (Get-Module -ListAvailable -Name BurntToast) {
            Import-Module BurntToast
            New-BurntToastNotification -Text "CLIProxyAPI", "Updated to $newVersion"
        }
        return $true
    } else {
        Write-LogError "Health check failed after update"
        Invoke-Rollback
        return $false
    }
}

# ============================================================================
# STATUS
# ============================================================================
function Show-Status {
    Write-Host "CLIProxyAPI Status:"
    Write-Host "  Running:   $(Get-RunningVersion)"
    Write-Host "  Binary:    $(Get-BinaryVersion)"
    Write-Host "  Source:    $(Get-SourceVersion)"
    Write-Host "  Config:    $($script:CLIPROXY_CONFIG)"
    Write-Host "  Log:       $($script:LOG_FILE)"
}

# ============================================================================
# BUILD ONLY
# ============================================================================
function Invoke-BuildOnly {
    Write-Log "Building without deploy..."

    if (-not (Test-Path $script:CLIPROXY_SOURCE_DIR)) {
        Write-LogError "Source directory not found: $($script:CLIPROXY_SOURCE_DIR)"
        return $false
    }

    Push-Location $script:CLIPROXY_SOURCE_DIR

    git fetch --tags --quiet 2>$null
    git reset --hard origin/main --quiet 2>$null

    $VERSION = git describe --tags --always
    $COMMIT = git rev-parse --short HEAD
    $BUILD_DATE = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $DEFAULT_CONFIG = $script:CLIPROXY_CONFIG

    $ldflags = "-X 'main.Version=$VERSION' -X 'main.Commit=$COMMIT' -X 'main.BuildDate=$BUILD_DATE' -X 'main.DefaultConfigPath=$DEFAULT_CONFIG'"

    try {
        $env:CGO_ENABLED = "0"
        go build -ldflags "$ldflags" -o "cliproxyapi.exe" ./cmd/server
        Write-Log "Built $VERSION"
    } catch {
        Write-LogError "Build failed: $_"
        Pop-Location
        return $false
    }

    Pop-Location
    return $true
}

# ============================================================================
# MAIN
# ============================================================================
switch ($Action) {
    "update" { Invoke-Update }
    "status" { Show-Status }
    "rollback" { Invoke-Rollback }
    "build-only" { Invoke-BuildOnly }
}
