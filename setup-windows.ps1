# ============================================================================
# setup-windows.ps1 - One-Click Windows Setup for Antigravity CLIProxyAPI
# ============================================================================
# This script sets up everything needed to run CLIProxyAPI on Windows:
#   1. Checks prerequisites (Git, Go)
#   2. Clones the CLIProxyAPI source repository
#   3. Builds the binary from source
#   4. Creates config from template
#   5. Sets up scheduled tasks for auto-update and startup
#   6. Adds anticc to PowerShell profile
#
# Usage:
#   .\setup-windows.ps1              # Full interactive setup
#   .\setup-windows.ps1 -Uninstall   # Remove everything
#   .\setup-windows.ps1 -Update      # Update only (skip initial setup)
# ============================================================================

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Update,
    [switch]$SkipProfile
)

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================
$script:REPO_URL = "https://github.com/router-for-me/CLIProxyAPIPlus.git"
$script:CLIPROXY_DIR = $PSScriptRoot
$script:SOURCE_DIR = Join-Path $script:CLIPROXY_DIR "cliproxy-source"
$script:BIN_DIR = Join-Path $env:LOCALAPPDATA "Programs\CLIProxyAPI"
$script:LOG_DIR = Join-Path $env:LOCALAPPDATA "CLIProxyAPI\logs"
$script:CONFIG_FILE = Join-Path $script:CLIPROXY_DIR "config.yaml"

# Colors
$script:ESC = [char]27
$script:C_GREEN = "$($script:ESC)[32m"
$script:C_YELLOW = "$($script:ESC)[33m"
$script:C_RED = "$($script:ESC)[31m"
$script:C_BOLD = "$($script:ESC)[1m"
$script:C_NC = "$($script:ESC)[0m"

# ============================================================================
# HELPERS
# ============================================================================
function Write-Step {
    param([string]$Message)
    Write-Host "$($script:C_GREEN)==>$($script:C_NC) $Message"
}

function Write-SubStep {
    param([string]$Message)
    Write-Host "    $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Host "$($script:C_YELLOW)Warning:$($script:C_NC) $Message"
}

function Write-Err {
    param([string]$Message)
    Write-Host "$($script:C_RED)Error:$($script:C_NC) $Message"
}

function Test-Command {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# ============================================================================
# UNINSTALL
# ============================================================================
function Invoke-Uninstall {
    Write-Host ""
    Write-Host "$($script:C_BOLD)Uninstalling Antigravity CLIProxyAPI...$($script:C_NC)"
    Write-Host ""

    # Stop service
    Write-Step "Stopping CLIProxyAPI..."
    Stop-Process -Name "cliproxyapi" -Force -ErrorAction SilentlyContinue

    # Remove scheduled tasks
    Write-Step "Removing scheduled tasks..."
    Unregister-ScheduledTask -TaskName "CLIProxyAPI-Startup" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "CLIProxyAPI-AutoUpdate" -Confirm:$false -ErrorAction SilentlyContinue

    # Remove binary directory
    Write-Step "Removing binaries..."
    if (Test-Path $script:BIN_DIR) {
        Remove-Item -Path $script:BIN_DIR -Recurse -Force
        Write-SubStep "Removed $($script:BIN_DIR)"
    }

    # Remove log directory
    Write-Step "Removing logs..."
    if (Test-Path $script:LOG_DIR) {
        Remove-Item -Path $script:LOG_DIR -Recurse -Force
        Write-SubStep "Removed $($script:LOG_DIR)"
    }

    # Remove source directory
    $confirmSource = Read-Host "Remove source directory ($($script:SOURCE_DIR))? [y/N]"
    if ($confirmSource -eq "y" -or $confirmSource -eq "Y") {
        if (Test-Path $script:SOURCE_DIR) {
            Remove-Item -Path $script:SOURCE_DIR -Recurse -Force
            Write-SubStep "Removed $($script:SOURCE_DIR)"
        }
    }

    Write-Host ""
    Write-Host "$($script:C_GREEN)Uninstall complete!$($script:C_NC)"
    Write-Host "Note: You may want to remove the anticc line from your PowerShell profile manually."
    Write-Host "Profile location: $PROFILE"
    exit 0
}

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================
function Test-Prerequisites {
    Write-Step "Checking prerequisites..."

    $missing = @()

    # Check Git
    if (Test-Command "git") {
        $gitVersion = git --version
        Write-SubStep "$($script:C_GREEN)✓$($script:C_NC) Git: $gitVersion"
    } else {
        Write-SubStep "$($script:C_RED)✗$($script:C_NC) Git: NOT FOUND"
        $missing += "Git"
    }

    # Check Go
    if (Test-Command "go") {
        $goVersion = go version
        Write-SubStep "$($script:C_GREEN)✓$($script:C_NC) $goVersion"
    } else {
        Write-SubStep "$($script:C_RED)✗$($script:C_NC) Go: NOT FOUND"
        $missing += "Go"
    }

    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 5) {
        Write-SubStep "$($script:C_GREEN)✓$($script:C_NC) PowerShell: $psVersion"
    } else {
        Write-Warn "PowerShell $psVersion detected. Some features work best with PowerShell 7+"
    }

    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Err "Missing prerequisites: $($missing -join ', ')"
        Write-Host ""
        Write-Host "Please install the missing tools:"
        if ($missing -contains "Git") {
            Write-Host "  Git: https://git-scm.com/download/win"
            Write-Host "       or: winget install Git.Git"
        }
        if ($missing -contains "Go") {
            Write-Host "  Go:  https://golang.org/dl/"
            Write-Host "       or: winget install GoLang.Go"
        }
        Write-Host ""
        exit 1
    }
}

# ============================================================================
# CLONE SOURCE
# ============================================================================
function Initialize-Source {
    Write-Step "Setting up source repository..."

    if (Test-Path $script:SOURCE_DIR) {
        Write-SubStep "Source directory exists, updating..."
        Push-Location $script:SOURCE_DIR
        git fetch --tags --quiet
        git reset --hard origin/main --quiet
        Pop-Location
    } else {
        Write-SubStep "Cloning from $($script:REPO_URL)..."
        git clone --depth 1 $script:REPO_URL $script:SOURCE_DIR
    }

    Push-Location $script:SOURCE_DIR
    $version = git describe --tags --always 2>$null
    Pop-Location
    Write-SubStep "Source version: $version"
}

# ============================================================================
# BUILD BINARY
# ============================================================================
function Build-Binary {
    Write-Step "Building CLIProxyAPI..."

    # Ensure bin directory exists
    if (-not (Test-Path $script:BIN_DIR)) {
        New-Item -ItemType Directory -Path $script:BIN_DIR -Force | Out-Null
    }

    Push-Location $script:SOURCE_DIR

    $VERSION = git describe --tags --always
    $COMMIT = git rev-parse --short HEAD
    $BUILD_DATE = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    Write-SubStep "Version: $VERSION"
    Write-SubStep "Commit: $COMMIT"

    $ldflags = "-s -w -X main.Version=$VERSION -X main.Commit=$COMMIT -X main.BuildDate=$BUILD_DATE"

    $env:CGO_ENABLED = "0"
    $env:GOOS = "windows"
    $env:GOARCH = "amd64"

    try {
        go build -ldflags $ldflags -o "cliproxyapi.exe" ./cmd/server
        if (-not (Test-Path "cliproxyapi.exe")) {
            throw "Build output not found"
        }
        Move-Item -Path "cliproxyapi.exe" -Destination (Join-Path $script:BIN_DIR "cliproxyapi.exe") -Force
        Write-SubStep "$($script:C_GREEN)✓$($script:C_NC) Built successfully"
    } catch {
        Write-Err "Build failed: $_"
        Pop-Location
        exit 1
    }

    Pop-Location
}

# ============================================================================
# SETUP CONFIG
# ============================================================================
function Initialize-Config {
    Write-Step "Setting up configuration..."

    if (Test-Path $script:CONFIG_FILE) {
        Write-SubStep "Config already exists at $($script:CONFIG_FILE)"
        return
    }

    $templateFile = Join-Path $script:SOURCE_DIR "config.example.yaml"
    if (Test-Path $templateFile) {
        Copy-Item -Path $templateFile -Destination $script:CONFIG_FILE
        Write-SubStep "Created config from template"
        Write-SubStep "$($script:C_YELLOW)!$($script:C_NC) Please edit $($script:CONFIG_FILE) and add your API keys"
    } else {
        Write-Warn "No config template found. You'll need to create config.yaml manually."
    }

    # Create .env file if it doesn't exist
    $envFile = Join-Path $script:CLIPROXY_DIR ".env"
    if (-not (Test-Path $envFile)) {
        @"
# CLIProxyAPI Environment Variables
# Add your API key here
CLIPROXY_API_KEY=your-api-key-here
"@ | Out-File -FilePath $envFile -Encoding UTF8
        Write-SubStep "Created .env file - please add your CLIPROXY_API_KEY"
    }
}

# ============================================================================
# SETUP LOG DIRECTORY
# ============================================================================
function Initialize-Logs {
    Write-Step "Setting up log directory..."

    if (-not (Test-Path $script:LOG_DIR)) {
        New-Item -ItemType Directory -Path $script:LOG_DIR -Force | Out-Null
    }
    Write-SubStep "Logs: $($script:LOG_DIR)"
}

# ============================================================================
# SETUP SCHEDULED TASKS
# ============================================================================
function Initialize-ScheduledTasks {
    Write-Step "Setting up scheduled tasks..."

    # Auto-update task
    $updateTaskName = "CLIProxyAPI-AutoUpdate"
    $existingUpdate = Get-ScheduledTask -TaskName $updateTaskName -ErrorAction SilentlyContinue

    if (-not $existingUpdate) {
        $updaterScript = Join-Path $script:CLIPROXY_DIR "cliproxy-updater.ps1"

        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -WindowStyle Hidden -File `"$updaterScript`" -Action update"

        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) `
            -RepetitionInterval (New-TimeSpan -Hours 12) -RepetitionDuration (New-TimeSpan -Days 365)

        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -StartWhenAvailable -RunOnlyIfNetworkAvailable

        Register-ScheduledTask -TaskName $updateTaskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Description "Auto-update CLIProxyAPI every 12 hours" | Out-Null

        Write-SubStep "$($script:C_GREEN)✓$($script:C_NC) Auto-update task created (runs every 12 hours)"
    } else {
        Write-SubStep "Auto-update task already exists"
    }

    # Startup task
    $startupTaskName = "CLIProxyAPI-Startup"
    $existingStartup = Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue

    if (-not $existingStartup) {
        $binary = Join-Path $script:BIN_DIR "cliproxyapi.exe"

        $action = New-ScheduledTaskAction -Execute $binary `
            -Argument "--config `"$($script:CONFIG_FILE)`""

        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

        Register-ScheduledTask -TaskName $startupTaskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Description "Start CLIProxyAPI on login" | Out-Null

        Write-SubStep "$($script:C_GREEN)✓$($script:C_NC) Startup task created (runs on login)"
    } else {
        Write-SubStep "Startup task already exists"
    }
}

# ============================================================================
# SETUP POWERSHELL PROFILE
# ============================================================================
function Initialize-Profile {
    Write-Step "Setting up PowerShell profile..."

    if ($SkipProfile) {
        Write-SubStep "Skipped (use -SkipProfile)"
        return
    }

    $profileDir = Split-Path $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    if (-not (Test-Path $PROFILE)) {
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    }

    $anticcScript = Join-Path $script:CLIPROXY_DIR "anticc.ps1"
    $sourceLine = ". `"$anticcScript`""

    $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue

    if ($profileContent -and $profileContent.Contains("anticc.ps1")) {
        Write-SubStep "anticc already in profile"
    } else {
        Add-Content -Path $PROFILE -Value ""
        Add-Content -Path $PROFILE -Value "# Antigravity CLIProxyAPI"
        Add-Content -Path $PROFILE -Value $sourceLine
        Write-SubStep "$($script:C_GREEN)✓$($script:C_NC) Added anticc to PowerShell profile"
    }
}

# ============================================================================
# ADD TO PATH
# ============================================================================
function Add-ToPath {
    Write-Step "Adding to PATH..."

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($currentPath -notlike "*$($script:BIN_DIR)*") {
        $newPath = "$currentPath;$($script:BIN_DIR)"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$env:Path;$($script:BIN_DIR)"
        Write-SubStep "$($script:C_GREEN)✓$($script:C_NC) Added $($script:BIN_DIR) to PATH"
    } else {
        Write-SubStep "Already in PATH"
    }
}

# ============================================================================
# START SERVICE
# ============================================================================
function Start-Service {
    Write-Step "Starting CLIProxyAPI..."

    $binary = Join-Path $script:BIN_DIR "cliproxyapi.exe"
    $logFile = Join-Path $script:LOG_DIR "cliproxyapi.log"

    if (-not (Test-Path $script:CONFIG_FILE)) {
        Write-Warn "Config file not found. Please create $($script:CONFIG_FILE) first."
        return
    }

    # Check if already running
    $proc = Get-Process -Name "cliproxyapi" -ErrorAction SilentlyContinue
    if ($proc) {
        Write-SubStep "CLIProxyAPI already running (PID: $($proc.Id))"
        return
    }

    Start-Process -FilePath $binary -ArgumentList "--config", "`"$($script:CONFIG_FILE)`"" `
        -WindowStyle Hidden -RedirectStandardOutput $logFile -RedirectStandardError $logFile

    Start-Sleep -Seconds 2

    $proc = Get-Process -Name "cliproxyapi" -ErrorAction SilentlyContinue
    if ($proc) {
        Write-SubStep "$($script:C_GREEN)✓$($script:C_NC) CLIProxyAPI started (PID: $($proc.Id))"
    } else {
        Write-Warn "Failed to start. Check logs at $logFile"
    }
}

# ============================================================================
# SHOW SUMMARY
# ============================================================================
function Show-Summary {
    Write-Host ""
    Write-Host "$($script:C_BOLD)═══════════════════════════════════════════════════════════$($script:C_NC)"
    Write-Host "$($script:C_GREEN)Setup Complete!$($script:C_NC)"
    Write-Host "$($script:C_BOLD)═══════════════════════════════════════════════════════════$($script:C_NC)"
    Write-Host ""
    Write-Host "Files:"
    Write-Host "  Binary:  $($script:BIN_DIR)\cliproxyapi.exe"
    Write-Host "  Source:  $($script:SOURCE_DIR)"
    Write-Host "  Config:  $($script:CONFIG_FILE)"
    Write-Host "  Logs:    $($script:LOG_DIR)"
    Write-Host ""
    Write-Host "Next Steps:"
    Write-Host "  1. Edit $($script:CONFIG_FILE) with your settings"
    Write-Host "  2. Add your API key to .env file"
    Write-Host "  3. Restart PowerShell or run: . `"$(Join-Path $script:CLIPROXY_DIR 'anticc.ps1')`""
    Write-Host "  4. Run 'anticc-status' to check status"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  anticc-on       Enable Antigravity mode"
    Write-Host "  anticc-off      Direct mode (bypass CCR)"
    Write-Host "  anticc-status   Show status"
    Write-Host "  anticc-update   Update to latest version"
    Write-Host "  anticc-help     Show all commands"
    Write-Host ""
}

# ============================================================================
# MAIN
# ============================================================================
Write-Host ""
Write-Host "$($script:C_BOLD)═══════════════════════════════════════════════════════════$($script:C_NC)"
Write-Host "$($script:C_BOLD)  Antigravity CLIProxyAPI - Windows Setup$($script:C_NC)"
Write-Host "$($script:C_BOLD)═══════════════════════════════════════════════════════════$($script:C_NC)"
Write-Host ""

if ($Uninstall) {
    Invoke-Uninstall
    exit 0
}

Test-Prerequisites

if ($Update) {
    Initialize-Source
    Build-Binary
    Write-Host ""
    Write-Host "$($script:C_GREEN)Update complete!$($script:C_NC)"
    exit 0
}

Initialize-Source
Build-Binary
Initialize-Config
Initialize-Logs
Initialize-ScheduledTasks
Initialize-Profile
Add-ToPath
Start-Service
Show-Summary
