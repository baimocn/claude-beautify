# Constants.psm1 — Shared constants for Claude Terminal Beautify

# Tokyo Night color scheme
$Script:TokyoNightScheme = @{
    name          = "Tokyo Night"
    background    = "#1A1B26"
    foreground    = "#C0CAF5"
    black         = "#15161E"
    red           = "#F7768E"
    green         = "#9ECE6A"
    yellow        = "#E0AF68"
    blue          = "#7AA2F7"
    purple        = "#BB9AF7"
    cyan          = "#7DCFFF"
    white         = "#A9B1D6"
    brightBlack   = "#414868"
    brightRed     = "#F7768E"
    brightGreen   = "#9ECE6A"
    brightYellow  = "#E0AF68"
    brightBlue    = "#7AA2F7"
    brightPurple  = "#BB9AF7"
    brightCyan    = "#7DCFFF"
    brightWhite   = "#C0CAF5"
}

# Default application config
$Script:DefaultConfig = @{
    Opacity      = 85
    FontSize     = 12
    FontFace     = "CaskaydiaCove Nerd Font"
    UseAcrylic   = $true
    CursorShape  = "filledBox"
    CursorHeight = 25
    ColorScheme  = "Tokyo Night"
    OMPTheme     = "tokyonight_storm"
    Padding      = "8, 8, 8, 8"
}

function Get-WTSettingsPath {
    [CmdletBinding()]
    param()

    $storePath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path $storePath) {
        return $storePath
    }

    $nonStorePath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\settings.json"
    return $nonStorePath
}

function Get-TokyoNightScheme {
    [CmdletBinding()]
    param()

    return $Script:TokyoNightScheme
}

function Get-DefaultConfig {
    [CmdletBinding()]
    param()

    return $Script:DefaultConfig.Clone()
}
