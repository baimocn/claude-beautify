# ═══════════════════════════════════════════════════════
#  Claude Code Terminal Beautify - All-in-One Installer
#  Usage: powershell -ExecutionPolicy Bypass -File install.ps1
# ═══════════════════════════════════════════════════════

$ErrorActionPreference = "Stop"

function Write-Step  { param($msg) Write-Host "  > $msg" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Fail  { param($msg) Write-Host "  [ERR] $msg" -ForegroundColor Red }
function Write-Warn  { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  +====================================================+" -ForegroundColor DarkCyan
Write-Host "  |   Claude Code Terminal Beautify - Installer v1.0.0    |" -ForegroundColor DarkCyan
Write-Host "  +====================================================+" -ForegroundColor DarkCyan
Write-Host ""

# Check choco
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Fail "Chocolatey not found. Install it first:"
    Write-Host "  Set-ExecutionPolicy Bypass -Scope Process; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))" -ForegroundColor DarkGray
    exit 1
}
Write-OK "Chocolatey found"

# ───────────────────────────────────────────────────────
# 1. Install Oh My Posh
# ───────────────────────────────────────────────────────
Write-Step "Installing Oh My Posh..."
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    Write-OK "Oh My Posh already installed"
} else {
    choco install oh-my-posh -y 2>&1 | Out-Null
    Write-OK "Oh My Posh installed"
}

# Ensure oh-my-posh is in PATH (choco sometimes doesn't update PATH)
$ompBin = "C:\Program Files (x86)\oh-my-posh\bin"
if (Test-Path $ompBin) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$ompBin*") {
        [Environment]::SetEnvironmentVariable('Path', "$userPath;$ompBin", 'User')
        Write-OK "Added Oh My Posh to PATH"
    }
    $env:Path = "$env:Path;$ompBin"
}

# ───────────────────────────────────────────────────────
# 2. Install Nerd Font
# ───────────────────────────────────────────────────────
Write-Step "Installing Cascadia Code Nerd Font..."
$fontInstalled = (Get-ChildItem "C:\Windows\Fonts" -Filter "*Caskaydia*" -ErrorAction SilentlyContinue).Count -gt 0
if ($fontInstalled) {
    Write-OK "Cascadia Code Nerd Font already installed"
} else {
    choco install cascadia-code-nerd-font -y 2>&1 | Out-Null
    Write-OK "Cascadia Code Nerd Font installed"
}

# ───────────────────────────────────────────────────────
# 3. Install Windows Terminal (if not present)
# ───────────────────────────────────────────────────────
Write-Step "Checking Windows Terminal..."
$wtPath = Get-Command wt -ErrorAction SilentlyContinue
if ($wtPath) {
    Write-OK "Windows Terminal already installed"
} else {
    Write-Step "Installing Windows Terminal..."
    choco install microsoft-windows-terminal -y 2>&1 | Out-Null
    Write-OK "Windows Terminal installed"
}

# ───────────────────────────────────────────────────────
# 4. Configure Windows Terminal
# ───────────────────────────────────────────────────────
Write-Step "Configuring Windows Terminal..."

$wtSettingsDir = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
if (Test-Path $wtSettingsDir) {
    $wtSettingsPath = Join-Path $wtSettingsDir "settings.json"
    $srcWtSettings = Join-Path $PSScriptRoot "terminal-settings.json"
    if (Test-Path $srcWtSettings) {
        Copy-Item $srcWtSettings $wtSettingsPath -Force
        Write-OK "Windows Terminal settings applied"
    } else {
        Write-Warn "terminal-settings.json not found, skipping WT config"
    }
} else {
    Write-Warn "Windows Terminal not launched yet, skip config (run WT once, then re-run installer)"
}

# ───────────────────────────────────────────────────────
# 5. Configure PowerShell Profile (PS 7 + PS 5.1)
# ───────────────────────────────────────────────────────
Write-Step "Configuring PowerShell profiles..."

$profileTemplate = Join-Path $PSScriptRoot "profile.ps1"
if (-not (Test-Path $profileTemplate)) {
    Write-Fail "profile.ps1 not found in project folder"
    exit 1
}

# PowerShell 7
$ps7Dir = Join-Path $env:USERPROFILE "Documents\PowerShell"
$ps7Profile = Join-Path $ps7Dir "Microsoft.PowerShell_profile.ps1"
if (-not (Test-Path $ps7Dir)) { New-Item -Path $ps7Dir -ItemType Directory -Force | Out-Null }
Copy-Item $profileTemplate $ps7Profile -Force
Write-OK "PS7 profile: $ps7Profile"

# PowerShell 5.1
$ps5Dir = Join-Path $env:USERPROFILE "Documents\WindowsPowerShell"
$ps5Profile = Join-Path $ps5Dir "Microsoft.PowerShell_profile.ps1"
if (-not (Test-Path $ps5Dir)) { New-Item -Path $ps5Dir -ItemType Directory -Force | Out-Null }
Copy-Item $profileTemplate $ps5Profile -Force
Write-OK "PS5 profile: $ps5Profile"

# ───────────────────────────────────────────────────────
# 6. Install Claude Code Status Bar
# ───────────────────────────────────────────────────────
Write-Step "Installing Claude Code status bar..."

$claudeDir = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $claudeDir)) { New-Item -Path $claudeDir -ItemType Directory -Force | Out-Null }

$srcScript = Join-Path $PSScriptRoot "statusline.sh"
$dstScript = Join-Path $claudeDir "statusline-command.sh"
if (Test-Path $srcScript) {
    Copy-Item $srcScript $dstScript -Force
    Write-OK "Status bar script: $dstScript"
} else {
    Write-Fail "statusline.sh not found"
    exit 1
}

# Update settings.json
$settingsPath = Join-Path $claudeDir "settings.json"
if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    $settings = [PSCustomObject]@{}
}

# Convert path to forward slashes for bash compatibility
$bashPath = $dstScript.Replace('\', '/')
$statusLineConfig = [PSCustomObject]@{
    command = "bash $bashPath"
    type    = "command"
}
if ($settings.PSObject.Properties['statusLine']) {
    $settings.statusLine = $statusLineConfig
} else {
    $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $statusLineConfig -Force
}
$settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8
Write-OK "Claude Code settings updated"

# ───────────────────────────────────────────────────────
# Done
# ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "  +====================================================+" -ForegroundColor Green
Write-Host "  |   [OK] All done! Next steps:                        |" -ForegroundColor Green
Write-Host "  |                                                      |" -ForegroundColor Green
Write-Host "  |   1. Open Windows Terminal                           |" -ForegroundColor Green
Write-Host "  |   2. Settings > Font > CaskaydiaCove Nerd Font      |" -ForegroundColor Green
Write-Host "  |   3. Restart Claude Code                             |" -ForegroundColor Green
Write-Host "  +====================================================+" -ForegroundColor Green
Write-Host ""
Write-Host "  Installed:" -ForegroundColor DarkGray
Write-Host "    - Oh My Posh (tokyonight_storm theme)" -ForegroundColor DarkGray
Write-Host "    - Cascadia Code Nerd Font" -ForegroundColor DarkGray
Write-Host "    - Windows Terminal (Tokyo Night + Acrylic)" -ForegroundColor DarkGray
Write-Host "    - Claude Code Status Bar" -ForegroundColor DarkGray
Write-Host ""
