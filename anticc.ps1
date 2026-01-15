# ============================================================================
# anticc.ps1 - Antigravity Claude Code CLI (Profile Manager) for Windows
# ============================================================================
# Usage: . "$env:USERPROFILE\path\to\anticc.ps1"
#   Or add to your PowerShell profile: $PROFILE
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
# CLIProxyAPI is built from source and auto-updated via Task Scheduler.
# Windows version connects directly to CLIProxyAPI (no CCR needed).
# ============================================================================

# Detect script directory
$script:ANTICC_DIR = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# ============================================================================
# CONFIGURATION
# ============================================================================
$script:ANTICC_CLIPROXY_PORT = 8317

# Set CLIPROXY_DIR if not already set
if (-not $env:CLIPROXY_DIR) {
    $env:CLIPROXY_DIR = $script:ANTICC_DIR
}

# Paths
$script:CLIPROXY_BIN_DIR = Join-Path $env:LOCALAPPDATA "Programs\CLIProxyAPI"
$script:CLIPROXY_SOURCE_DIR = Join-Path $script:ANTICC_DIR "cliproxy-source"
$script:CLIPROXY_UPDATER = Join-Path $script:ANTICC_DIR "cliproxy-updater.ps1"
$script:CLIPROXY_LOG_DIR = Join-Path $env:LOCALAPPDATA "CLIProxyAPI\logs"

# Load API key from .env if not set
$envFile = Join-Path $env:CLIPROXY_DIR ".env"
if (-not $env:CLIPROXY_API_KEY -and (Test-Path $envFile)) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match "^\s*([^#][^=]+)\s*=\s*(.+)\s*$") {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"').Trim("'")
            Set-Item -Path "env:$name" -Value $value
        }
    }
}

# Internal settings - connects directly to CLIProxyAPI
$script:_ANTICC_BASE_URL = "http://127.0.0.1:$($script:ANTICC_CLIPROXY_PORT)"
$script:_ANTICC_API_KEY = $env:CLIPROXY_API_KEY

# Model configuration
$script:_ANTICC_OPUS_MODEL = "gemini-claude-opus-4-5-thinking"
$script:_ANTICC_SONNET_MODEL = "gemini-claude-sonnet-4-5-thinking"
$script:_ANTICC_HAIKU_MODEL = "gemini-3-flash-preview"

# Track state
if (-not $env:ANTICC_ENABLED) { $env:ANTICC_ENABLED = "false" }

# Auto-enable setting
if (-not $env:ANTICC_AUTO_ENABLE) { $env:ANTICC_AUTO_ENABLE = "true" }

# ============================================================================
# COLORS (using ANSI escape codes for Windows Terminal / PowerShell 7+)
# ============================================================================
$script:ESC = [char]27
$script:C_GREEN = "$($script:ESC)[32m"
$script:C_YELLOW = "$($script:ESC)[33m"
$script:C_RED = "$($script:ESC)[31m"
$script:C_BOLD = "$($script:ESC)[1m"
$script:C_NC = "$($script:ESC)[0m"

function Write-Log { param([string]$Message) Write-Host "$($script:C_GREEN)[anticc]$($script:C_NC) $Message" }
function Write-Warn { param([string]$Message) Write-Host "$($script:C_YELLOW)[anticc]$($script:C_NC) $Message" -ForegroundColor Yellow }

# ============================================================================
# UTILITIES
# ============================================================================
function Test-ProcessRunning {
    param([string]$ProcessName)
    $null -ne (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
}

function Get-ProcessId {
    param([string]$ProcessName)
    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) { return $proc.Id }
    return $null
}

# ============================================================================
# PROFILE COMMANDS
# ============================================================================

function anticc-on {
    <#
    .SYNOPSIS
    Enable Antigravity mode (set environment variables for CLIProxyAPI)
    #>
    $env:ANTHROPIC_BASE_URL = $script:_ANTICC_BASE_URL
    $env:ANTHROPIC_API_KEY = $script:_ANTICC_API_KEY
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL = $script:_ANTICC_OPUS_MODEL
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $script:_ANTICC_SONNET_MODEL
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $script:_ANTICC_HAIKU_MODEL
    $env:ANTICC_ENABLED = "true"
    Write-Log "Antigravity mode $($script:C_GREEN)enabled$($script:C_NC) -> CLIProxyAPI (:$($script:ANTICC_CLIPROXY_PORT))"
}

function anticc-off {
    <#
    .SYNOPSIS
    Disable Antigravity mode (unset environment variables)
    #>
    Remove-Item Env:ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:ANTHROPIC_DEFAULT_OPUS_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
    $env:ANTICC_ENABLED = "false"
    Write-Log "Antigravity mode $($script:C_YELLOW)disabled$($script:C_NC) (using default Anthropic API)"
}

# ============================================================================
# STATUS
# ============================================================================

function anticc-status {
    <#
    .SYNOPSIS
    Show service and profile status
    #>
    Write-Host "$($script:C_BOLD)Services:$($script:C_NC)"

    # CLIProxyAPI status
    if (Test-ProcessRunning "cliproxyapi") {
        $pid = Get-ProcessId "cliproxyapi"
        try {
            $response = Invoke-RestMethod -Uri "http://127.0.0.1:$($script:ANTICC_CLIPROXY_PORT)/" -TimeoutSec 2 -ErrorAction SilentlyContinue
            $version = if ($response -match 'v[\d.]+') { $matches[0] } else { "?" }
        } catch { $version = "?" }
        Write-Host "  CLIProxyAPI:  $($script:C_GREEN)running$($script:C_NC) (PID: $pid, $version) -> :$($script:ANTICC_CLIPROXY_PORT)"
    } else {
        Write-Host "  CLIProxyAPI:  $($script:C_RED)stopped$($script:C_NC) (use: anticc-start)"
    }

    Write-Host ""
    Write-Host "$($script:C_BOLD)Profile:$($script:C_NC)"
    switch ($env:ANTICC_ENABLED) {
        "true" { Write-Host "  Anticc: $($script:C_GREEN)enabled$($script:C_NC) -> $env:ANTHROPIC_BASE_URL" }
        default { Write-Host "  Anticc: $($script:C_YELLOW)disabled$($script:C_NC)" }
    }

    Write-Host ""
    Write-Host "$($script:C_BOLD)Updates:$($script:C_NC)"
    $task = Get-ScheduledTask -TaskName "CLIProxyAPI-AutoUpdate" -ErrorAction SilentlyContinue
    if ($task) {
        Write-Host "  Auto-update: $($script:C_GREEN)enabled$($script:C_NC) (every 12h)"
    } else {
        Write-Host "  Auto-update: $($script:C_YELLOW)disabled$($script:C_NC) (run: anticc-enable-autoupdate)"
    }
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================

function anticc-start {
    <#
    .SYNOPSIS
    Start CLIProxyAPI service
    #>
    if (Test-ProcessRunning "cliproxyapi") {
        Write-Log "CLIProxyAPI already running"
        return
    }

    $binary = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.exe"
    if (-not (Test-Path $binary)) {
        Write-Warn "CLIProxyAPI not found at $binary"
        Write-Warn "Run: anticc-update to build from source"
        return
    }

    $config = Join-Path $env:CLIPROXY_DIR "config.yaml"
    if (-not (Test-Path $config)) {
        Write-Warn "Config not found at $config"
        return
    }

    # Ensure log directory exists
    if (-not (Test-Path $script:CLIPROXY_LOG_DIR)) {
        New-Item -ItemType Directory -Path $script:CLIPROXY_LOG_DIR -Force | Out-Null
    }

    Write-Log "Starting CLIProxyAPI..."
    $logFile = Join-Path $script:CLIPROXY_LOG_DIR "cliproxyapi.log"

    # Start as background job
    Start-Process -FilePath $binary -ArgumentList "--config", "`"$config`"" `
        -WindowStyle Hidden -RedirectStandardOutput $logFile -RedirectStandardError $logFile

    Start-Sleep -Seconds 2

    if (Test-ProcessRunning "cliproxyapi") {
        $pid = Get-ProcessId "cliproxyapi"
        Write-Log "CLIProxyAPI started (PID: $pid)"
    } else {
        Write-Warn "Failed to start. Check: $logFile"
    }
}

function anticc-stop-service {
    <#
    .SYNOPSIS
    Stop CLIProxyAPI service
    #>
    Write-Log "Stopping CLIProxyAPI..."
    Stop-Process -Name "cliproxyapi" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    if (-not (Test-ProcessRunning "cliproxyapi")) {
        Write-Log "CLIProxyAPI stopped"
    } else {
        Write-Warn "CLIProxyAPI still running, force killing..."
        Stop-Process -Name "cliproxyapi" -Force -ErrorAction SilentlyContinue
    }
}

function anticc-restart-service {
    <#
    .SYNOPSIS
    Restart CLIProxyAPI service
    #>
    anticc-stop-service
    Start-Sleep -Seconds 1
    anticc-start
}

# ============================================================================
# UPDATE MANAGEMENT
# ============================================================================

function anticc-version {
    <#
    .SYNOPSIS
    Show version info (running, binary, source, remote)
    #>
    Write-Host "$($script:C_BOLD)CLIProxyAPI Versions:$($script:C_NC)"

    # Running version
    if (Test-ProcessRunning "cliproxyapi") {
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:ANTICC_CLIPROXY_PORT)/" -TimeoutSec 2 -ErrorAction SilentlyContinue
            $running = if ($response.Content -match 'v[\d.]+') { $matches[0] } else { "unknown" }
        } catch { $running = "unknown" }
        Write-Host "  Running: $($script:C_GREEN)$running$($script:C_NC)"
    } else {
        Write-Host "  Running: $($script:C_RED)not running$($script:C_NC)"
    }

    # Binary version
    $binary = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.exe"
    if (Test-Path $binary) {
        $output = & $binary 2>&1 | Select-String "Version:" | Select-Object -First 1
        $binaryVer = if ($output -match 'Version:\s*([^,]+)') { $matches[1] } else { "unknown" }
        Write-Host "  Binary:  $binaryVer"
    } else {
        Write-Host "  Binary:  $($script:C_RED)not installed$($script:C_NC)"
    }

    # Source version
    if (Test-Path $script:CLIPROXY_SOURCE_DIR) {
        Push-Location $script:CLIPROXY_SOURCE_DIR
        $sourceVer = git describe --tags --always 2>$null
        Write-Host "  Source:  $sourceVer"

        # Check for updates
        git fetch --tags --quiet 2>$null
        $remoteVer = git describe --tags origin/main 2>$null
        if ($remoteVer -and $sourceVer -ne $remoteVer) {
            Write-Host "  Remote:  $($script:C_YELLOW)$remoteVer$($script:C_NC) (update available!)"
        }
        Pop-Location
    } else {
        Write-Host "  Source:  $($script:C_RED)not found$($script:C_NC)"
    }

    # Backup version
    $backup = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.bak.exe"
    if (Test-Path $backup) {
        $output = & $backup 2>&1 | Select-String "Version:" | Select-Object -First 1
        $backupVer = if ($output -match 'Version:\s*([^,]+)') { $matches[1] } else { "unknown" }
        Write-Host "  Backup:  $backupVer (for rollback)"
    }
}

function anticc-update {
    <#
    .SYNOPSIS
    Pull latest and rebuild CLIProxyAPI
    #>
    if (-not (Test-Path $script:CLIPROXY_UPDATER)) {
        Write-Warn "Updater script not found at $($script:CLIPROXY_UPDATER)"
        return
    }

    Write-Log "Running CLIProxyAPI update..."
    & $script:CLIPROXY_UPDATER -Action update
}

function anticc-rollback {
    <#
    .SYNOPSIS
    Rollback to previous version
    #>
    if (-not (Test-Path $script:CLIPROXY_UPDATER)) {
        Write-Warn "Updater script not found"
        return
    }

    Write-Warn "Rolling back to previous version..."
    & $script:CLIPROXY_UPDATER -Action rollback
}

# ============================================================================
# AUTO-UPDATE MANAGEMENT (Windows Task Scheduler)
# ============================================================================

function anticc-enable-autoupdate {
    <#
    .SYNOPSIS
    Enable auto-update via Windows Task Scheduler (runs every 12 hours)
    #>
    $taskName = "CLIProxyAPI-AutoUpdate"
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($existingTask) {
        Write-Log "Auto-update task already exists"
        return
    }

    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -WindowStyle Hidden -File `"$($script:CLIPROXY_UPDATER)`" -Action update"

    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) `
        -RepetitionInterval (New-TimeSpan -Hours 12) -RepetitionDuration (New-TimeSpan -Days 365)

    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -RunOnlyIfNetworkAvailable

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Description "Auto-update CLIProxyAPI every 12 hours" | Out-Null

    Write-Log "Auto-update enabled (runs every 12 hours)"
}

function anticc-disable-autoupdate {
    <#
    .SYNOPSIS
    Disable auto-update
    #>
    $taskName = "CLIProxyAPI-AutoUpdate"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Log "Auto-update disabled"
}

# ============================================================================
# STARTUP MANAGEMENT
# ============================================================================

function anticc-enable-startup {
    <#
    .SYNOPSIS
    Enable CLIProxyAPI to start on Windows login
    #>
    $taskName = "CLIProxyAPI-Startup"
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($existingTask) {
        Write-Log "Startup task already exists"
        return
    }

    $binary = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.exe"
    $config = Join-Path $env:CLIPROXY_DIR "config.yaml"

    $action = New-ScheduledTaskAction -Execute $binary -Argument "--config `"$config`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Description "Start CLIProxyAPI on login" | Out-Null

    Write-Log "CLIProxyAPI will start on login"
}

function anticc-disable-startup {
    <#
    .SYNOPSIS
    Disable CLIProxyAPI startup on login
    #>
    $taskName = "CLIProxyAPI-Startup"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Log "Startup disabled"
}

# ============================================================================
# DIAGNOSTICS
# ============================================================================

function anticc-diagnose {
    <#
    .SYNOPSIS
    Run full diagnostics
    #>
    Write-Host "$($script:C_BOLD)=== Antigravity Diagnostics (Windows) ===$($script:C_NC)"
    Write-Host ""

    # Check CLIProxyAPI installation
    Write-Host "$($script:C_BOLD)1. CLIProxyAPI Installation:$($script:C_NC)"
    $binary = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.exe"
    if (Test-Path $binary) {
        Write-Host "   Binary: $binary"
        $output = & $binary 2>&1 | Select-String "Version:" | Select-Object -First 1
        Write-Host "   $output"
    } else {
        Write-Host "   $($script:C_RED)NOT INSTALLED$($script:C_NC) - run: anticc-update"
    }
    Write-Host ""

    # Check source repo
    Write-Host "$($script:C_BOLD)2. Source Repository:$($script:C_NC)"
    if (Test-Path $script:CLIPROXY_SOURCE_DIR) {
        Write-Host "   Path: $($script:CLIPROXY_SOURCE_DIR)"
        Push-Location $script:CLIPROXY_SOURCE_DIR
        $ver = git describe --tags --always 2>$null
        $branch = git branch --show-current 2>$null
        Write-Host "   Version: $ver"
        Write-Host "   Branch: $branch"
        Pop-Location
    } else {
        Write-Host "   $($script:C_RED)NOT FOUND$($script:C_NC) at $($script:CLIPROXY_SOURCE_DIR)"
    }
    Write-Host ""

    # Check config
    Write-Host "$($script:C_BOLD)3. Configuration:$($script:C_NC)"
    $config = Join-Path $env:CLIPROXY_DIR "config.yaml"
    if (Test-Path $config) {
        Write-Host "   Config: $config"
    } else {
        Write-Host "   Config: $($script:C_RED)NOT FOUND$($script:C_NC)"
    }
    Write-Host ""

    # Check API key
    Write-Host "$($script:C_BOLD)4. API Key:$($script:C_NC)"
    if ($env:CLIPROXY_API_KEY) {
        Write-Host "   CLIPROXY_API_KEY: $($script:C_GREEN)set$($script:C_NC) ($($env:CLIPROXY_API_KEY.Length) chars)"
    } else {
        Write-Host "   CLIPROXY_API_KEY: $($script:C_RED)NOT SET$($script:C_NC)"
    }
    Write-Host ""

    # Check ports
    Write-Host "$($script:C_BOLD)5. Ports:$($script:C_NC)"
    $cliproxyPort = Get-NetTCPConnection -LocalPort $script:ANTICC_CLIPROXY_PORT -ErrorAction SilentlyContinue
    if ($cliproxyPort) {
        Write-Host "   Port $($script:ANTICC_CLIPROXY_PORT): $($script:C_GREEN)in use$($script:C_NC) (PID: $($cliproxyPort.OwningProcess | Select-Object -First 1))"
    } else {
        Write-Host "   Port $($script:ANTICC_CLIPROXY_PORT): $($script:C_YELLOW)free$($script:C_NC)"
    }
    Write-Host ""

    # Check scheduled tasks
    Write-Host "$($script:C_BOLD)6. Scheduled Tasks:$($script:C_NC)"
    $startupTask = Get-ScheduledTask -TaskName "CLIProxyAPI-Startup" -ErrorAction SilentlyContinue
    if ($startupTask) {
        Write-Host "   CLIProxyAPI-Startup: $($script:C_GREEN)registered$($script:C_NC)"
    } else {
        Write-Host "   CLIProxyAPI-Startup: $($script:C_YELLOW)not registered$($script:C_NC)"
    }

    $updateTask = Get-ScheduledTask -TaskName "CLIProxyAPI-AutoUpdate" -ErrorAction SilentlyContinue
    if ($updateTask) {
        Write-Host "   CLIProxyAPI-AutoUpdate: $($script:C_GREEN)registered$($script:C_NC)"
    } else {
        Write-Host "   CLIProxyAPI-AutoUpdate: $($script:C_YELLOW)not registered$($script:C_NC)"
    }
    Write-Host ""

    # Check logs
    Write-Host "$($script:C_BOLD)7. Recent Logs:$($script:C_NC)"
    $logFile = Join-Path $script:CLIPROXY_LOG_DIR "cliproxyapi.log"
    if (Test-Path $logFile) {
        Write-Host "   Last 3 lines of $logFile :"
        Get-Content $logFile -Tail 3 | ForEach-Object { Write-Host "   $_" }
    } else {
        Write-Host "   No log file at $logFile"
    }
    Write-Host ""

    # Connectivity test
    Write-Host "$($script:C_BOLD)7. Connectivity Test:$($script:C_NC)"
    try {
        $headers = @{ "Authorization" = "Bearer $($env:CLIPROXY_API_KEY)" }
        $null = Invoke-RestMethod -Uri "http://127.0.0.1:$($script:ANTICC_CLIPROXY_PORT)/v1/models" -Headers $headers -TimeoutSec 2
        Write-Host "   CLIProxyAPI ($($script:ANTICC_CLIPROXY_PORT)): $($script:C_GREEN)responding$($script:C_NC)"
    } catch {
        Write-Host "   CLIProxyAPI ($($script:ANTICC_CLIPROXY_PORT)): $($script:C_RED)not responding$($script:C_NC)"
    }
    Write-Host ""

    Write-Host "$($script:C_BOLD)=== End Diagnostics ===$($script:C_NC)"
}

# ============================================================================
# QUOTA TOOLS
# ============================================================================

function anticc-quota {
    <#
    .SYNOPSIS
    Check Antigravity quota for all accounts (CLI mode by default)
    .PARAMETER Web
    Start web server with dashboard
    .PARAMETER Port
    Port for web server (default: 8318)
    #>
    param(
        [switch]$Web,
        [int]$Port = 8318
    )

    $toolDir = Join-Path $script:ANTICC_DIR "tools\check-quota"
    $binary = Join-Path $toolDir "check-quota.exe"
    $sourceFile = Join-Path $toolDir "main.go"

    # Build if not exists or source is newer
    $needsBuild = $false
    if (-not (Test-Path $binary)) {
        $needsBuild = $true
    } elseif ((Test-Path $sourceFile) -and ((Get-Item $sourceFile).LastWriteTime -gt (Get-Item $binary).LastWriteTime)) {
        $needsBuild = $true
    }

    if ($needsBuild) {
        Write-Log "Building check-quota tool..."
        if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
            Write-Warn "Go not installed. Install Go to use this feature."
            return
        }
        Push-Location $toolDir
        try {
            go build -o check-quota.exe .
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "Failed to build check-quota tool"
                return
            }
        } finally {
            Pop-Location
        }
    }

    if ($Web) {
        Write-Log "Starting quota dashboard on http://127.0.0.1:$Port"
        & $binary --web --port $Port
    } else {
        & $binary
    }
}

function anticc-quota-web {
    <#
    .SYNOPSIS
    Open quota dashboard in browser (web UI mode)
    .PARAMETER Port
    Port for web server (default: 8318)
    #>
    param(
        [int]$Port = 8318
    )
    anticc-quota -Web -Port $Port
}

# ============================================================================
# HELP
# ============================================================================

function anticc-login {
    <#
    .SYNOPSIS
    Login to Antigravity (add Google account)
    #>
    $binary = Join-Path $script:CLIPROXY_BIN_DIR "cliproxyapi.exe"
    if (-not (Test-Path $binary)) {
        Write-Warn "CLIProxyAPI not installed. Run: anticc-update"
        return
    }
    Write-Log "Opening Antigravity login..."
    & $binary --antigravity-login
}

function anticc-help {
    <#
    .SYNOPSIS
    Show anticc help
    #>
    Write-Host @"
anticc - Antigravity Claude Code CLI (Windows)

Architecture:
  Claude Code -> CLIProxyAPI (8317) -> Antigravity -> Google AI

Profile Commands:
  anticc-on              Enable Antigravity mode (set env vars)
  anticc-off             Disable Antigravity mode (unset env vars)
  anticc-status          Show service and profile status
  anticc-login           Login to Antigravity (add Google account)

Service Commands:
  anticc-start           Start CLIProxyAPI service
  anticc-stop-service    Stop CLIProxyAPI service
  anticc-restart-service Restart CLIProxyAPI service

Update Commands:
  anticc-version         Show version info (running, binary, source, remote)
  anticc-update          Pull latest and rebuild CLIProxyAPI
  anticc-rollback        Rollback to previous version if update fails

Auto-Update:
  anticc-enable-autoupdate   Enable 12-hour auto-update via Task Scheduler
  anticc-disable-autoupdate  Disable auto-update

Startup:
  anticc-enable-startup      Start CLIProxyAPI on Windows login
  anticc-disable-startup     Disable startup on login

Quota Commands:
  anticc-quota           Check Antigravity quota for all accounts (CLI)
  anticc-quota -Web      Open quota dashboard in browser
  anticc-quota-web [port] Open quota dashboard (default port: 8318)

Diagnostics:
  anticc-diagnose        Run full diagnostics
  anticc-help            Show this help

Files:
  Binary:   `$env:LOCALAPPDATA\Programs\CLIProxyAPI\cliproxyapi.exe
  Source:   $($script:CLIPROXY_SOURCE_DIR)
  Config:   `$env:CLIPROXY_DIR\config.yaml
  Logs:     `$env:LOCALAPPDATA\CLIProxyAPI\logs\cliproxyapi.log
  Updater:  $($script:CLIPROXY_UPDATER)

Environment variables are auto-exported when sourced (for IDE plugins).
To disable: `$env:ANTICC_AUTO_ENABLE = "false" before sourcing.
"@
}

# ============================================================================
# AUTO-ENABLE ON SOURCE (for IDE plugins)
# ============================================================================
if ($env:ANTICC_AUTO_ENABLE -eq "true") {
    $env:ANTHROPIC_BASE_URL = $script:_ANTICC_BASE_URL
    $env:ANTHROPIC_API_KEY = $script:_ANTICC_API_KEY
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL = $script:_ANTICC_OPUS_MODEL
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $script:_ANTICC_SONNET_MODEL
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $script:_ANTICC_HAIKU_MODEL
    $env:ANTICC_ENABLED = "true"
}

# Export functions for use in the session
Export-ModuleMember -Function anticc-* -ErrorAction SilentlyContinue
