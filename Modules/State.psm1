# State.psm1 — Singleton shared application state (no UI dependency)

$Script:AppData = @{
    Components = @{
        OhMyPosh    = @{ Installed = $false; Version = ""; Description = "PowerShell prompt theme engine" }
        NerdFont    = @{ Installed = $false; Version = ""; Description = "Cascadia Code Nerd Font with icons" }
        WinTerminal = @{ Installed = $false; Version = ""; Description = "Modern Windows terminal" }
        WTConfig    = @{ Installed = $false; Theme = ""; Description = "Tokyo Night color scheme + acrylic" }
        PSProfile   = @{ Installed = $false; Theme = ""; Description = "Oh My Posh + PSReadLine config" }
        StatusLine  = @{ Installed = $false; Description = "Claude Code context and token monitor" }
    }
    Config = Get-DefaultConfig
    OMPThemes     = @()
    WTSchemes     = @()
    SavedProfiles = @()
    CurrentView   = "Dashboard"
    IsBusy        = $false
    LastScan      = $null
}

function Get-AppData {
    [CmdletBinding()]
    param()

    return $Script:AppData
}

function Set-AppData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        $Value
    )

    $keys = $Path.Split('.')
    $current = $Script:AppData

    for ($i = 0; $i -lt $keys.Count - 1; $i++) {
        $key = $keys[$i]
        if ($current -is [hashtable] -and $current.ContainsKey($key)) {
            $current = $current[$key]
        } else {
            Write-Error "Path segment '$key' not found in AppData."
            return
        }
    }

    $leaf = $keys[-1]
    if ($current -is [hashtable]) {
        $current[$leaf] = $Value
    } else {
        Write-Error "Cannot set property '$leaf' — parent is not a hashtable."
    }
}

function Get-AppConfig {
    [CmdletBinding()]
    param()

    return $Script:AppData.Config
}

function Get-Components {
    [CmdletBinding()]
    param()

    return $Script:AppData.Components
}

function Reset-AppData {
    [CmdletBinding()]
    param()

    $Script:AppData.Config = Get-DefaultConfig
}

function Initialize-AppData {
    [CmdletBinding()]
    param()

    $Script:AppData.LastScan = Get-Date
    return $Script:AppData
}

# [Removed] Export-ModuleMember
