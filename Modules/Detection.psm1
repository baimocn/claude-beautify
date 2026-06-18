# Detection.psm1 -- Component installation detection and state synchronization
# NOTE: Utils.psm1 and State.psm1 are imported by the entry point (ClaudeBeautify.ps1)
# Do NOT re-import them here with -Force as it resets their exported functions.

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function Detect-OhMyPosh {
    [CmdletBinding()]
    param()

    try {
        $cmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
        $version = ""
        if ($null -ne $cmd) {
            $raw = & oh-my-posh version 2>&1
            $version = ($raw | Out-String).Trim()
        }
        Set-AppData "Components.OhMyPosh.Installed" ($null -ne $cmd)
        Set-AppData "Components.OhMyPosh.Version"   $version
        Write-AppLog "Oh-My-Posh: Installed=$($null -ne $cmd), Version=$version"
    }
    catch {
        Write-AppLog "Detect-OhMyPosh failed: $_" -Level Error
        Set-AppData "Components.OhMyPosh.Installed" $false
        Set-AppData "Components.OhMyPosh.Version"   ""
    }
}

function Detect-NerdFont {
    [CmdletBinding()]
    param()

    try {
        $fontFiles = Get-ChildItem "C:\Windows\Fonts" -Filter "*Caskaydia*" -ErrorAction SilentlyContinue
        $found = ($null -ne $fontFiles) -and ($fontFiles.Count -gt 0)
        Set-AppData "Components.NerdFont.Installed" $found
        Set-AppData "Components.NerdFont.Version"   $(if ($found) { "installed" } else { "" })
        Write-AppLog "Nerd Font (Caskaydia): Installed=$found"
    }
    catch {
        Write-AppLog "Detect-NerdFont failed: $_" -Level Error
        Set-AppData "Components.NerdFont.Installed" $false
        Set-AppData "Components.NerdFont.Version"   ""
    }
}

function Detect-WindowsTerminal {
    [CmdletBinding()]
    param()

    try {
        $cmd = Get-Command wt -ErrorAction SilentlyContinue
        $wtInstalled = $null -ne $cmd
        $wtVersion   = ""

        if ($wtInstalled) {
            $wtVersion = "detected"
            $settingsPath = Get-WTSettingsPath
            $settings = Read-JsonFile $settingsPath

            if ($null -ne $settings) {
                $defaults = $null
                if ($settings.profiles -and $settings.profiles.defaults) {
                    $defaults = $settings.profiles.defaults
                }

                $fontFace = ""
                if ($defaults -and $defaults.font -and $defaults.font.face) {
                    $fontFace = $defaults.font.face
                }

                if ($fontFace -match "Nerd|Caskaydia|NF") {
                    $wtVersion = "nerd font configured"
                }
                else {
                    $wtVersion = "no nerd font"
                }
            }
        }

        Set-AppData "Components.WinTerminal.Installed" $wtInstalled
        Set-AppData "Components.WinTerminal.Version"   $wtVersion
        Write-AppLog "Windows Terminal: Installed=$wtInstalled, Version=$wtVersion"
    }
    catch {
        Write-AppLog "Detect-WindowsTerminal failed: $_" -Level Error
        Set-AppData "Components.WinTerminal.Installed" $false
        Set-AppData "Components.WinTerminal.Version"   ""
    }
}

function Detect-WTConfig {
    [CmdletBinding()]
    param()

    try {
        $settingsPath = Get-WTSettingsPath
        $settings = Read-JsonFile $settingsPath

        if ($null -eq $settings) {
            Set-AppData "Components.WTConfig.Installed" $false
            Set-AppData "Components.WTConfig.Theme"     ""
            Write-AppLog "WTConfig: settings.json not found or unreadable"
            return
        }

        # Locate profiles.defaults
        $defaults = $null
        if ($settings.profiles -and $settings.profiles.defaults) {
            $defaults = $settings.profiles.defaults
        }

        # Read color scheme
        $colorScheme = ""
        if ($settings.profiles -and $settings.profiles.defaults -and $settings.profiles.defaults.colorScheme) {
            $colorScheme = $settings.profiles.defaults.colorScheme
        }
        elseif ($settings.profiles -and $settings.profiles.defaults -and $null -ne $settings.profiles.defaults.PSObject.Properties['colorScheme']) {
            $colorScheme = $settings.profiles.defaults.colorScheme
        }

        $configured = -not [string]::IsNullOrWhiteSpace($colorScheme)

        # Sync actual WT config values back into State.Config
        if ($null -ne $defaults) {
            # Opacity
            if ($null -ne $defaults.PSObject.Properties['opacity']) {
                Set-AppData "Config.Opacity" ([int]$defaults.opacity)
            }

            # useAcrylic
            if ($null -ne $defaults.PSObject.Properties['useAcrylic']) {
                Set-AppData "Config.UseAcrylic" ([bool]$defaults.useAcrylic)
            }

            # cursorShape
            if ($null -ne $defaults.PSObject.Properties['cursorShape']) {
                Set-AppData "Config.CursorShape" $defaults.cursorShape
            }

            # font.face
            if ($null -ne $defaults.font -and $null -ne $defaults.font.PSObject.Properties['face']) {
                Set-AppData "Config.FontFace" $defaults.font.face
            }

            # font.size
            if ($null -ne $defaults.font -and $null -ne $defaults.font.PSObject.Properties['size']) {
                Set-AppData "Config.FontSize" ([int]$defaults.font.size)
            }

            # padding
            if ($null -ne $defaults.PSObject.Properties['padding']) {
                Set-AppData "Config.Padding" $defaults.padding
            }
        }

        # Sync colorScheme to Config
        if ($configured) {
            Set-AppData "Config.ColorScheme" $colorScheme
        }

        Set-AppData "Components.WTConfig.Installed" $configured
        Set-AppData "Components.WTConfig.Theme"     $colorScheme
        Write-AppLog "WTConfig: Installed=$configured, ColorScheme=$colorScheme"
    }
    catch {
        Write-AppLog "Detect-WTConfig failed: $_" -Level Error
        Set-AppData "Components.WTConfig.Installed" $false
        Set-AppData "Components.WTConfig.Theme"     ""
    }
}

function Detect-PSProfile {
    [CmdletBinding()]
    param()

    try {
        $profilePaths = @(
            (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
            (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
        )

        $found     = $false
        $themeName = ""

        foreach ($pp in $profilePaths) {
            if (Test-Path $pp) {
                $content = Get-Content -Path $pp -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($content -and $content -match "oh-my-posh init") {
                    $found = $true

                    # Try to extract theme reference
                    if ($content -match '--config\s+"?([^"\s;]+)"?') {
                        $themeName = $Matches[1]
                    }
                    elseif ($content -match '--config\s+(\S+)') {
                        $themeName = $Matches[1]
                    }
                    else {
                        $themeName = "default"
                    }
                    break
                }
            }
        }

        Set-AppData "Components.PSProfile.Installed" $found
        Set-AppData "Components.PSProfile.Theme"     $themeName
        Write-AppLog "PS Profile: Installed=$found, Theme=$themeName"
    }
    catch {
        Write-AppLog "Detect-PSProfile failed: $_" -Level Error
        Set-AppData "Components.PSProfile.Installed" $false
        Set-AppData "Components.PSProfile.Theme"     ""
    }
}

function Detect-StatusLine {
    [CmdletBinding()]
    param()

    try {
        $scriptExists = Test-Path (Join-Path $env:USERPROFILE ".claude\statusline-command.sh")
        $settingsJson = Read-JsonFile (Join-Path $env:USERPROFILE ".claude\settings.json")
        $keyExists    = $false

        if ($null -ne $settingsJson) {
            $keyExists = ($null -ne $settingsJson.PSObject.Properties['statusLine']) -or
                         ($null -ne $settingsJson.statusLine)
        }

        $installed = $scriptExists -or $keyExists

        Set-AppData "Components.StatusLine.Installed" $installed
        Write-AppLog "StatusLine: Installed=$installed (script=$scriptExists, key=$keyExists)"
    }
    catch {
        Write-AppLog "Detect-StatusLine failed: $_" -Level Error
        Set-AppData "Components.StatusLine.Installed" $false
    }
}

# ---------------------------------------------------------------------------
# Primary exported function
# ---------------------------------------------------------------------------

function Update-ComponentStatus {
    [CmdletBinding()]
    param()

    Write-AppLog "Starting component status scan..."

    Detect-OhMyPosh
    Detect-NerdFont
    Detect-WindowsTerminal
    Detect-WTConfig
    Detect-PSProfile
    Detect-StatusLine

    Set-AppData "LastScan" (Get-Date)
    Write-AppLog "Component status scan complete."
}

# ---------------------------------------------------------------------------
# Dashboard summary
# ---------------------------------------------------------------------------

function Get-ComponentSummary {
    [CmdletBinding()]
    param()

    $data = Get-AppData

    $summary = @(
        @{
            Name        = "Oh-My-Posh"
            Key         = "OhMyPosh"
            Installed   = $data.Components.OhMyPosh.Installed
            Status      = if ($data.Components.OhMyPosh.Installed) { "v$($data.Components.OhMyPosh.Version)" } else { "Not installed" }
            Icon        = if ($data.Components.OhMyPosh.Installed) { [char]0x2705 } else { [char]0x274C }
            Description = $data.Components.OhMyPosh.Description
        },
        @{
            Name        = "Nerd Font"
            Key         = "NerdFont"
            Installed   = $data.Components.NerdFont.Installed
            Status      = if ($data.Components.NerdFont.Installed) { "Installed" } else { "Not found" }
            Icon        = if ($data.Components.NerdFont.Installed) { [char]0x2705 } else { [char]0x274C }
            Description = $data.Components.NerdFont.Description
        },
        @{
            Name        = "Windows Terminal"
            Key         = "WinTerminal"
            Installed   = $data.Components.WinTerminal.Installed
            Status      = if ($data.Components.WinTerminal.Installed) { $data.Components.WinTerminal.Version } else { "Not installed" }
            Icon        = if ($data.Components.WinTerminal.Installed) { [char]0x2705 } else { [char]0x274C }
            Description = $data.Components.WinTerminal.Description
        },
        @{
            Name        = "WT Config"
            Key         = "WTConfig"
            Installed   = $data.Components.WTConfig.Installed
            Status      = if ($data.Components.WTConfig.Installed) { $data.Components.WTConfig.Theme } else { "Not configured" }
            Icon        = if ($data.Components.WTConfig.Installed) { [char]0x2705 } else { [char]0x274C }
            Description = $data.Components.WTConfig.Description
        },
        @{
            Name        = "PS Profile"
            Key         = "PSProfile"
            Installed   = $data.Components.PSProfile.Installed
            Status      = if ($data.Components.PSProfile.Installed) { $data.Components.PSProfile.Theme } else { "Not configured" }
            Icon        = if ($data.Components.PSProfile.Installed) { [char]0x2705 } else { [char]0x274C }
            Description = $data.Components.PSProfile.Description
        },
        @{
            Name        = "Status Line"
            Key         = "StatusLine"
            Installed   = $data.Components.StatusLine.Installed
            Status      = if ($data.Components.StatusLine.Installed) { "Active" } else { "Not set up" }
            Icon        = if ($data.Components.StatusLine.Installed) { [char]0x2705 } else { [char]0x274C }
            Description = $data.Components.StatusLine.Description
        }
    )

    return $summary
}

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

# [Removed] Export-ModuleMember
