# ═══════════════════════════════════════════════════
#  PowerShell Profile - Oh My Posh + PSReadLine
# ═══════════════════════════════════════════════════

# Oh My Posh - Tokyo Night Storm Theme
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\tokyonight_storm.omp.json" | Invoke-Expression

# PSReadLine - Better command line experience
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -PredictiveViewSource History
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}
