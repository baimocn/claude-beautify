# ═══════════════════════════════════════════════════════
#  Claude Code Terminal Beautify - Uninstaller
# ═══════════════════════════════════════════════════════

$ErrorActionPreference = "Stop"

function Write-OK   { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  Claude Code Terminal Beautify - Uninstaller" -ForegroundColor Cyan
Write-Host ""

# 1. Remove status bar script
$claudeDir = Join-Path $env:USERPROFILE ".claude"
$dstScript = Join-Path $claudeDir "statusline-command.sh"
if (Test-Path $dstScript) {
    Remove-Item $dstScript -Force
    Write-OK "Deleted: $dstScript"
}

# 2. Clean settings.json statusLine
$settingsPath = Join-Path $claudeDir "settings.json"
if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    if ($settings.PSObject.Properties['statusLine']) {
        $settings.PSObject.Properties.Remove('statusLine')
        $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8
        Write-OK "Removed statusLine from settings.json"
    }
}

# 3. Remove PowerShell profiles (Oh My Posh lines)
foreach ($profilePath in @(
    (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
    (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
)) {
    if (Test-Path $profilePath) {
        Remove-Item $profilePath -Force
        Write-OK "Deleted profile: $profilePath"
    }
}

# 4. Uninstall Oh My Posh
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    Write-OK "Oh My Posh still installed (uninstall manually with: choco uninstall oh-my-posh)"
} else {
    Write-OK "Oh My Posh not found"
}

# 5. Uninstall font
Write-OK "Nerd Font remains installed (safe to keep for other apps)"

Write-Host ""
Write-Host "  [OK] Uninstalled. Restart terminal." -ForegroundColor Green
Write-Host "  Note: Oh My Posh, font, and Windows Terminal are kept." -ForegroundColor DarkGray
Write-Host "  Remove them manually if needed: choco uninstall oh-my-posh cascadia-code-nerd-font" -ForegroundColor DarkGray
Write-Host ""
