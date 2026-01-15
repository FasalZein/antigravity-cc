# ============================================================================
# anticc.ps1 - Antigravity Claude Code CLI (Profile Manager) for Windows
# ============================================================================
# Usage: . "$env:USERPROFILE\path\to\anticc.ps1"
#   Or add to your PowerShell profile: $PROFILE
#
# Commands:
#   anticc-on         Enable Antigravity mode (set env vars)
#   anticc-off        Disable Antigravity mode (unset env vars)
#
# Delegated to cliproxyctl:
#   anticc-status, anticc-version, anticc-update, anticc-rollback, anticc-diagnose,
#   anticc-quota, anticc-start, anticc-stop-service, anticc-restart-service, anticc-logs
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
$script:CLIPROXY_CTL = Join-Path $script:ANTICC_DIR "tools\cliproxyctl\cliproxyctl.exe"

# API key - hardcoded "dummy" for local-only services
$env:CLIPROXY_API_KEY = "dummy"

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

# Ensure cliproxyctl is built
function Ensure-Cliproxyctl {
    if (-not (Test-Path $script:CLIPROXY_CTL)) {
        $toolDir = Join-Path $script:ANTICC_DIR "tools\cliproxyctl"
        $mainGo = Join-Path $toolDir "main.go"
        if (Test-Path $mainGo) {
            Write-Log "Building cliproxyctl..."
            if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
                Write-Warn "Go not installed. Please install Go first."
                return $false
            }
            Push-Location $toolDir
            try {
                go build -o cliproxyctl.exe .
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "Failed to build cliproxyctl"
                    return $false
                }
            } finally {
                Pop-Location
            }
        } else {
            Write-Warn "cliproxyctl source not found at $toolDir"
            return $false
        }
    }
    return $true
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
    Show service and profile status (delegated to cliproxyctl)
    #>
    if (Ensure-Cliproxyctl) {
        & $script:CLIPROXY_CTL status
    }

    # Add shell-specific profile status
    Write-Host ""
    Write-Host "$($script:C_BOLD)Profile:$($script:C_NC)"
    switch ($env:ANTICC_ENABLED) {
        "true" { Write-Host "  Anticc: $($script:C_GREEN)enabled$($script:C_NC) -> $env:ANTHROPIC_BASE_URL" }
        default { Write-Host "  Anticc: $($script:C_YELLOW)disabled$($script:C_NC)" }
    }
}

# ============================================================================
# SERVICE MANAGEMENT (delegated to cliproxyctl)
# ============================================================================

function anticc-start {
    <#
    .SYNOPSIS
    Start CLIProxyAPI service (delegated to cliproxyctl)
    #>
    if (Ensure-Cliproxyctl) {
        & $script:CLIPROXY_CTL start
    }
}

function anticc-stop-service {
    <#
    .SYNOPSIS
    Stop CLIProxyAPI service (delegated to cliproxyctl)
    #>
    if (Ensure-Cliproxyctl) {
        & $script:CLIPROXY_CTL stop
    }
}

function anticc-restart-service {
    <#
    .SYNOPSIS
    Restart CLIProxyAPI service (delegated to cliproxyctl)
    #>
    if (Ensure-Cliproxyctl) {
        & $script:CLIPROXY_CTL restart
    }
}

# ============================================================================
# UPDATE MANAGEMENT
# ============================================================================

function anticc-version {
    <#
    .SYNOPSIS
    Show version info (delegated to cliproxyctl)
    #>
    if (Ensure-Cliproxyctl) {
        & $script:CLIPROXY_CTL status
    }
}

function anticc-update {
    <#
    .SYNOPSIS
    Pull latest and rebuild CLIProxyAPI (delegated to cliproxyctl)
    #>
    if (Ensure-Cliproxyctl) {
        & $script:CLIPROXY_CTL update @args
    }
}

function anticc-rollback {
    <#
    .SYNOPSIS
    Rollback to previous version (delegated to cliproxyctl)
    #>
    if (Ensure-Cliproxyctl) {
        & $script:CLIPROXY_CTL rollback @args
    }
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
# LOG VIEWING (delegated to cliproxyctl)
# ============================================================================

function anticc-logs {
    <#
    .SYNOPSIS
    View CLIProxyAPI logs (delegated to cliproxyctl)
    .PARAMETER Follow
    Follow log output (like tail -f)
    .PARAMETER Lines
    Number of lines to show (default: 50)
    .PARAMETER All
    Open full log in pager
    #>
    param(
        [Alias("f")]
        [switch]$Follow,
        [Alias("n")]
        [int]$Lines = 50,
        [switch]$All
    )

    if (-not (Ensure-Cliproxyctl)) { return }

    if ($Follow) {
        & $script:CLIPROXY_CTL logs -f
    } elseif ($All) {
        & $script:CLIPROXY_CTL logs --all
    } else {
        & $script:CLIPROXY_CTL logs -n $Lines
    }
}

# ============================================================================
# DIAGNOSTICS
# ============================================================================

function anticc-diagnose {
    <#
    .SYNOPSIS
    Run full diagnostics (delegated to cliproxyctl)
    #>
    if (Ensure-Cliproxyctl) {
        & $script:CLIPROXY_CTL diagnose @args
    }
}

# ============================================================================
# QUOTA TOOLS
# ============================================================================

function anticc-quota {
    <#
    .SYNOPSIS
    Check Antigravity quota for all accounts (delegated to cliproxyctl)
    .PARAMETER Web
    Start web server with dashboard
    .PARAMETER Port
    Port for web server (default: 8318)
    #>
    param(
        [switch]$Web,
        [int]$Port = 8318
    )

    if (-not (Ensure-Cliproxyctl)) { return }

    if ($Web) {
        Write-Log "Starting quota dashboard on http://127.0.0.1:$Port"
        & $script:CLIPROXY_CTL quota --web --port $Port
    } else {
        & $script:CLIPROXY_CTL quota
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
anticc - Antigravity Claude Code CLI (Windows - Thin Wrapper)

Architecture:
  Claude Code -> CLIProxyAPI (8317) -> Antigravity -> Google AI

Profile Commands (shell-based - modifies environment):
  anticc-on              Enable Antigravity mode (set env vars)
  anticc-off             Disable Antigravity mode (unset env vars)
  anticc-login           Login to Antigravity (add Google account)

Delegated to cliproxyctl:
  anticc-status          Show service and profile status
  anticc-version         Show version info (running, binary, source, remote)
  anticc-start           Start CLIProxyAPI service
  anticc-stop-service    Stop CLIProxyAPI service
  anticc-restart-service Restart CLIProxyAPI service
  anticc-update          Pull latest and rebuild CLIProxyAPI
  anticc-rollback        Rollback to previous version if update fails
  anticc-diagnose        Run full diagnostics
  anticc-quota           Check Antigravity quota for all accounts (CLI)
  anticc-quota -Web      Open quota dashboard in browser
  anticc-logs [-f|-n N|--all]  View CLIProxyAPI logs

Auto-Update:
  anticc-enable-autoupdate   Enable 12-hour auto-update via Task Scheduler
  anticc-disable-autoupdate  Disable auto-update

Startup:
  anticc-enable-startup      Start CLIProxyAPI on Windows login
  anticc-disable-startup     Disable startup on login

Other:
  anticc-help            Show this help

Files:
  Binary:    `$env:LOCALAPPDATA\Programs\CLIProxyAPI\cliproxyapi.exe
  CLI Tool:  tools\cliproxyctl\cliproxyctl.exe
  Config:    config.yaml
  Logs:      `$env:LOCALAPPDATA\CLIProxyAPI\logs\cliproxyapi.log

API Key: "dummy" (hardcoded for local-only services)

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
