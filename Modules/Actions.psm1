# Actions.psm1 -- Install / Uninstall / Apply operations
# NOTE: Utils.psm1, State.psm1, and Detection.psm1 are imported by the entry point.
# Do NOT re-import them here with -Force as it resets their Export-ModuleMember scope.
# All functions from those modules (Write-AppLog, Read-JsonFile, Write-JsonFile,
# Get-AppData, Set-AppData, Update-ComponentStatus, etc.) are available directly.

# ---------------------------------------------------------------------------
# Backup helper
# ---------------------------------------------------------------------------

function Backup-ConfigFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path $Path) {
        $ts = Get-Date -Format "yyyyMMdd-HHmmss"
        $bakPath = "$Path.bak.$ts"
        try {
            Copy-Item -Path $Path -Destination $bakPath -Force
            Write-AppLog "Backup-ConfigFile: backed up $Path -> $bakPath"
        }
        catch {
            Write-AppLog "Backup-ConfigFile: failed to backup $Path : $_" -Level Warn
        }
    }
}

# ---------------------------------------------------------------------------
# 1. Install-OhMyPosh
# ---------------------------------------------------------------------------

function Install-OhMyPosh {
    [CmdletBinding()]
    param()

    try {
        Write-AppLog "Install-OhMyPosh: starting..."

        if (-not (Test-ChocolateyInstalled)) {
            Write-AppLog "Chocolatey is not installed." -Level Warn
            return @{ Success = $false; Message = "请先安装 Chocolatey 包管理器" }
        }

        Write-AppLog "Running: choco install oh-my-posh -y"
        $output = & cmd /c "choco install oh-my-posh -y" 2>&1
        Write-AppLog ($output | Out-String)
        if ($LASTEXITCODE -ne 0) {
            Write-AppLog "Chocolatey exited with code $LASTEXITCODE" -Level Error
            return @{ Success = $false; Message = "安装失败 (exit code: $LASTEXITCODE)" }
        }

        # Fix PATH — ensure oh-my-posh is reachable
        $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
        if ($null -eq $ompCmd) {
            Write-AppLog "Oh-My-Posh not found in PATH after install, attempting PATH refresh..."
            $chocoPath = Join-Path $env:ChocolateyInstall "bin"
            if (Test-Path $chocoPath) {
                if ($env:Path -notlike "*$chocoPath*") {
                    $env:Path = "$chocoPath;$env:Path"
                    Write-AppLog "Added $chocoPath to session PATH."
                }
            }
            # Verify again
            $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
            if ($null -eq $ompCmd) {
                Write-AppLog "Oh-My-Posh still not found after PATH fix." -Level Warn
            }
        }

        Update-ComponentStatus
        Write-AppLog "Install-OhMyPosh: complete."
        return @{ Success = $true; Message = "Oh-My-Posh 安装成功" }
    }
    catch {
        Write-AppLog "Install-OhMyPosh failed: $_" -Level Error
        return @{ Success = $false; Message = "Oh-My-Posh 安装失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 2. Uninstall-OhMyPosh
# ---------------------------------------------------------------------------

function Uninstall-OhMyPosh {
    [CmdletBinding()]
    param()

    try {
        Write-AppLog "Uninstall-OhMyPosh: starting..."

        if (-not (Test-ChocolateyInstalled)) {
            Write-AppLog "Chocolatey is not installed." -Level Warn
            return @{ Success = $false; Message = "请先安装 Chocolatey 包管理器" }
        }

        Write-AppLog "Running: choco uninstall oh-my-posh -y"
        $output = & cmd /c "choco uninstall oh-my-posh -y" 2>&1
        Write-AppLog ($output | Out-String)
        if ($LASTEXITCODE -ne 0) {
            Write-AppLog "Chocolatey exited with code $LASTEXITCODE" -Level Error
            return @{ Success = $false; Message = "卸载失败 (exit code: $LASTEXITCODE)" }
        }

        Update-ComponentStatus
        Write-AppLog "Uninstall-OhMyPosh: complete."
        return @{ Success = $true; Message = "Oh-My-Posh 已卸载" }
    }
    catch {
        Write-AppLog "Uninstall-OhMyPosh failed: $_" -Level Error
        return @{ Success = $false; Message = "Oh-My-Posh 卸载失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 3. Install-NerdFont
# ---------------------------------------------------------------------------

function Install-NerdFont {
    [CmdletBinding()]
    param()

    try {
        Write-AppLog "Install-NerdFont: starting..."

        if (-not (Test-ChocolateyInstalled)) {
            Write-AppLog "Chocolatey is not installed." -Level Warn
            return @{ Success = $false; Message = "请先安装 Chocolatey 包管理器" }
        }

        if (Test-AdminPrivilege) {
            Write-AppLog "Running elevated: choco install cascadia-code-nerd-font -y"
            $output = & cmd /c "choco install cascadia-code-nerd-font -y" 2>&1
            Write-AppLog ($output | Out-String)
            if ($LASTEXITCODE -ne 0) {
                Write-AppLog "Chocolatey exited with code $LASTEXITCODE" -Level Error
                return @{ Success = $false; Message = "安装失败 (exit code: $LASTEXITCODE)" }
            }
        }
        else {
            Write-AppLog "Not running as admin. Launching elevated process..."
            $exitCode = Invoke-Elevated "choco install cascadia-code-nerd-font -y"
            if ($exitCode -ne 0) {
                Write-AppLog "Elevated font install exited with code $exitCode" -Level Error
                return @{ Success = $false; Message = "安装失败 (exit code: $exitCode)" }
            }
        }

        Update-ComponentStatus
        Write-AppLog "Install-NerdFont: complete."
        return @{ Success = $true; Message = "Cascadia Code Nerd Font 安装成功" }
    }
    catch {
        Write-AppLog "Install-NerdFont failed: $_" -Level Error
        return @{ Success = $false; Message = "Nerd Font 安装失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 4. Install-WindowsTerminal
# ---------------------------------------------------------------------------

function Install-WindowsTerminal {
    [CmdletBinding()]
    param()

    try {
        Write-AppLog "Install-WindowsTerminal: starting..."

        if (-not (Test-ChocolateyInstalled)) {
            Write-AppLog "Chocolatey is not installed." -Level Warn
            return @{ Success = $false; Message = "请先安装 Chocolatey 包管理器" }
        }

        Write-AppLog "Running: choco install microsoft-windows-terminal -y"
        $output = & cmd /c "choco install microsoft-windows-terminal -y" 2>&1
        Write-AppLog ($output | Out-String)
        if ($LASTEXITCODE -ne 0) {
            Write-AppLog "Chocolatey exited with code $LASTEXITCODE" -Level Error
            return @{ Success = $false; Message = "安装失败 (exit code: $LASTEXITCODE)" }
        }

        Update-ComponentStatus
        Write-AppLog "Install-WindowsTerminal: complete."
        return @{ Success = $true; Message = "Windows Terminal 安装成功" }
    }
    catch {
        Write-AppLog "Install-WindowsTerminal failed: $_" -Level Error
        return @{ Success = $false; Message = "Windows Terminal 安装失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 5. Apply-WTSettings
# ---------------------------------------------------------------------------

function Apply-WTSettings {
    [CmdletBinding()]
    param()

    try {
        Write-AppLog "Apply-WTSettings: starting..."

        # Load template
        $templatePath = Join-Path (Split-Path $PSScriptRoot) "Templates\terminal-default.json"
        if (-not (Test-Path $templatePath)) {
            Write-AppLog "Template not found: $templatePath" -Level Error
            return @{ Success = $false; Message = "找不到模板文件: terminal-default.json" }
        }
        $template = Read-JsonFile $templatePath
        if ($null -eq $template) {
            return @{ Success = $false; Message = "模板文件读取失败" }
        }

        # Load current WT settings
        $wtSettingsPath = Get-WTSettingsPath
        $wtSettings = Read-JsonFile $wtSettingsPath

        # If WT settings don't exist yet, start from scratch
        if ($null -eq $wtSettings) {
            Write-AppLog "WT settings.json not found. Creating from template..."
            $wtSettings = $template
        }

        # Ensure profiles.defaults exists
        if ($null -eq $wtSettings.profiles) {
            $wtSettings | Add-Member -NotePropertyName "profiles" -NotePropertyValue ([PSCustomObject]@{ defaults = [PSCustomObject]@{}; list = @() }) -Force
        }
        if ($null -eq $wtSettings.profiles.defaults) {
            $wtSettings.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $defaults = $wtSettings.profiles.defaults

        # Get config values from State
        $config = Get-AppConfig

        # Merge font settings
        $fontObj = [PSCustomObject]@{
            face = $config.FontFace
            size = $config.FontSize
        }
        $defaults | Add-Member -NotePropertyName "font" -NotePropertyValue $fontObj -Force

        # Merge other settings
        $defaults | Add-Member -NotePropertyName "opacity"          -NotePropertyValue $config.Opacity    -Force
        $defaults | Add-Member -NotePropertyName "useAcrylic"       -NotePropertyValue $config.UseAcrylic -Force
        $defaults | Add-Member -NotePropertyName "cursorShape"      -NotePropertyValue $config.CursorShape -Force
        $defaults | Add-Member -NotePropertyName "cursorHeight"     -NotePropertyValue $config.CursorHeight -Force
        $defaults | Add-Member -NotePropertyName "colorScheme"      -NotePropertyValue $config.ColorScheme -Force
        $defaults | Add-Member -NotePropertyName "padding"          -NotePropertyValue $config.Padding    -Force

        # Ensure Tokyo Night scheme exists in schemes array
        $tokyoNightScheme = Get-TokyoNightScheme

        # Ensure schemes array exists
        if ($null -eq $wtSettings.schemes -or $wtSettings.schemes -isnot [System.Collections.IList]) {
            $wtSettings | Add-Member -NotePropertyName "schemes" -NotePropertyValue @() -Force
        }

        # Check if Tokyo Night already exists, update or add
        $existingScheme = $null
        foreach ($scheme in $wtSettings.schemes) {
            if ($scheme.name -eq "Tokyo Night") {
                $existingScheme = $scheme
                break
            }
        }

        if ($null -ne $existingScheme) {
            # Update existing scheme properties
            foreach ($key in $tokyoNightScheme.Keys) {
                $existingScheme | Add-Member -NotePropertyName $key -NotePropertyValue $tokyoNightScheme[$key] -Force
            }
        }
        else {
            $wtSettings.schemes += [PSCustomObject]$tokyoNightScheme
        }

        # Backup and write back
        Backup-ConfigFile -Path $wtSettingsPath
        Write-AppLog "Writing WT settings to $wtSettingsPath"
        $written = Write-JsonFile $wtSettingsPath $wtSettings
        if (-not $written) {
            return @{ Success = $false; Message = "写入 Windows Terminal 配置失败" }
        }

        Update-ComponentStatus
        Write-AppLog "Apply-WTSettings: complete."
        return @{ Success = $true; Message = "Windows Terminal 配置已应用 (Tokyo Night)" }
    }
    catch {
        Write-AppLog "Apply-WTSettings failed: $_" -Level Error
        return @{ Success = $false; Message = "应用 WT 配置失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 6. Apply-PSProfile
# ---------------------------------------------------------------------------

function Apply-PSProfile {
    [CmdletBinding()]
    param(
        [string]$ThemeName = "tokyonight_storm"
    )

    try {
        Write-AppLog "Apply-PSProfile: starting... (Theme=$ThemeName)"

        # Load template
        $templatePath = Join-Path (Split-Path $PSScriptRoot) "Templates\profile-default.ps1"
        if (-not (Test-Path $templatePath)) {
            Write-AppLog "Template not found: $templatePath" -Level Error
            return @{ Success = $false; Message = "找不到模板文件: profile-default.ps1" }
        }
        $profileContent = Get-Content -Path $templatePath -Raw -Encoding UTF8 -ErrorAction Stop

        # Replace the hardcoded theme name with the selected theme
        $profileContent = $profileContent -replace '(?<=oh-my-posh init pwsh --config "\$env:POSH_THEMES_PATH\\)[^"]+(?=\.omp\.json")', $ThemeName

        # Target profile paths
        $profilePaths = @(
            (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
            (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
        )

        $errors = @()
        foreach ($pp in $profilePaths) {
            try {
                $dir = Split-Path $pp -Parent
                if (-not (Test-Path $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    Write-AppLog "Created directory: $dir"
                }
                Backup-ConfigFile -Path $pp
                [IO.File]::WriteAllText($pp, $profileContent, [Text.Encoding]::UTF8)
                Write-AppLog "Wrote profile to: $pp"
            }
            catch {
                $errors += "Failed to write $pp : $_"
                Write-AppLog "Failed to write profile to ${pp}: $_" -Level Error
            }
        }

        Update-ComponentStatus

        if ($errors.Count -gt 0) {
            return @{ Success = $false; Message = "部分配置写入失败: $($errors -join '; ')" }
        }

        Write-AppLog "Apply-PSProfile: complete."
        return @{ Success = $true; Message = "PowerShell Profile 已配置 (Oh-My-Posh + PSReadLine)" }
    }
    catch {
        Write-AppLog "Apply-PSProfile failed: $_" -Level Error
        return @{ Success = $false; Message = "应用 PS Profile 失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 7. Install-StatusLine
# ---------------------------------------------------------------------------

function Install-StatusLine {
    [CmdletBinding()]
    param()

    try {
        Write-AppLog "Install-StatusLine: starting..."

        # Copy template script
        $templatePath = Join-Path (Split-Path $PSScriptRoot) "Templates\statusline-default.sh"
        if (-not (Test-Path $templatePath)) {
            Write-AppLog "Template not found: $templatePath" -Level Error
            return @{ Success = $false; Message = "找不到模板文件: statusline-default.sh" }
        }

        $targetDir = Join-Path $env:USERPROFILE ".claude"
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            Write-AppLog "Created directory: $targetDir"
        }

        $targetScript = Join-Path $targetDir "statusline-command.sh"
        Copy-Item -Path $templatePath -Destination $targetScript -Force
        Write-AppLog "Copied statusline script to $targetScript"

        # Update settings.json with statusLine key
        $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
        $settings = Read-JsonFile $settingsPath

        if ($null -eq $settings) {
            # Create minimal settings if file doesn't exist
            $settings = [PSCustomObject]@{}
            Write-AppLog "Creating new settings.json at $settingsPath"
        }

        $statusLineObj = [PSCustomObject]@{
            command = "bash ~/.claude/statusline-command.sh"
            type    = "command"
        }
        $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $statusLineObj -Force

        Backup-ConfigFile -Path $settingsPath
        $written = Write-JsonFile $settingsPath $settings
        if (-not $written) {
            return @{ Success = $false; Message = "写入 Claude 设置失败" }
        }

        Write-AppLog "Updated settings.json with statusLine key."

        Update-ComponentStatus
        Write-AppLog "Install-StatusLine: complete."
        return @{ Success = $true; Message = "Claude Code 状态栏已安装" }
    }
    catch {
        Write-AppLog "Install-StatusLine failed: $_" -Level Error
        return @{ Success = $false; Message = "安装状态栏失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 7b. Uninstall-NerdFont
# ---------------------------------------------------------------------------

function Uninstall-NerdFont {
    [CmdletBinding()]
    param()

    try {
        Write-AppLog "Uninstall-NerdFont: starting..."

        if (-not (Test-ChocolateyInstalled)) {
            return @{ Success = $false; Message = "请先安装 Chocolatey 包管理器" }
        }

        if (Test-AdminPrivilege) {
            $output = & cmd /c "choco uninstall cascadia-code-nerd-font -y" 2>&1
            Write-AppLog ($output | Out-String)
        }
        else {
            $exitCode = Invoke-Elevated "choco uninstall cascadia-code-nerd-font -y"
            if ($exitCode -ne 0) {
                Write-AppLog "Elevated font uninstall exited with code $exitCode" -Level Warn
            }
        }

        Update-ComponentStatus
        Write-AppLog "Uninstall-NerdFont: complete."
        return @{ Success = $true; Message = "Nerd Font 已卸载" }
    }
    catch {
        Write-AppLog "Uninstall-NerdFont failed: $_" -Level Error
        return @{ Success = $false; Message = "Nerd Font 卸载失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 7c. Uninstall-WindowsTerminal
# ---------------------------------------------------------------------------

function Uninstall-WindowsTerminal {
    [CmdletBinding()]
    param()

    try {
        Write-AppLog "Uninstall-WindowsTerminal: starting..."

        if (-not (Test-ChocolateyInstalled)) {
            return @{ Success = $false; Message = "请先安装 Chocolatey 包管理器" }
        }

        $output = & cmd /c "choco uninstall microsoft-windows-terminal -y" 2>&1
        Write-AppLog ($output | Out-String)

        Update-ComponentStatus
        Write-AppLog "Uninstall-WindowsTerminal: complete."
        return @{ Success = $true; Message = "Windows Terminal 已卸载" }
    }
    catch {
        Write-AppLog "Uninstall-WindowsTerminal failed: $_" -Level Error
        return @{ Success = $false; Message = "Windows Terminal 卸载失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 8. Uninstall-StatusLine
# ---------------------------------------------------------------------------

function Uninstall-StatusLine {
    [CmdletBinding()]
    param()

    try {
        Write-AppLog "Uninstall-StatusLine: starting..."

        # Delete script file
        $scriptPath = Join-Path $env:USERPROFILE ".claude\statusline-command.sh"
        if (Test-Path $scriptPath) {
            Remove-Item -Path $scriptPath -Force
            Write-AppLog "Deleted $scriptPath"
        }
        else {
            Write-AppLog "Script not found (already removed): $scriptPath"
        }

        # Clean statusLine key from settings.json
        $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
        $settings = Read-JsonFile $settingsPath

        if ($null -ne $settings) {
            $hasKey = ($null -ne $settings.PSObject.Properties['statusLine'])
            if ($hasKey) {
                $settings.PSObject.Properties.Remove('statusLine')
                Write-JsonFile $settingsPath $settings | Out-Null
                Write-AppLog "Removed statusLine key from settings.json"
            }
            else {
                Write-AppLog "statusLine key not found in settings.json (already clean)"
            }
        }
        else {
            Write-AppLog "settings.json not found, nothing to clean."
        }

        Update-ComponentStatus
        Write-AppLog "Uninstall-StatusLine: complete."
        return @{ Success = $true; Message = "Claude Code 状态栏已移除" }
    }
    catch {
        Write-AppLog "Uninstall-StatusLine failed: $_" -Level Error
        return @{ Success = $false; Message = "移除状态栏失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 9. Uninstall-PSProfile
# ---------------------------------------------------------------------------

function Uninstall-PSProfile {
    [CmdletBinding()]
    param()

    try {
        Write-AppLog "Uninstall-PSProfile: starting..."

        $profilePaths = @(
            (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
            (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
        )

        $deleted = 0
        foreach ($pp in $profilePaths) {
            if (Test-Path $pp) {
                $content = Get-Content -Path $pp -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($content -and $content -match "oh-my-posh init") {
                    Backup-ConfigFile -Path $pp
                    Remove-Item -Path $pp -Force
                    Write-AppLog "Deleted profile: $pp"
                    $deleted++
                }
                else {
                    Write-AppLog "Skipping $pp (does not contain oh-my-posh init)"
                }
            }
            else {
                Write-AppLog "Profile not found: $pp"
            }
        }

        Update-ComponentStatus
        Write-AppLog "Uninstall-PSProfile: complete. Deleted $deleted profile(s)."
        return @{ Success = $true; Message = "PowerShell Profile 已清理 ($deleted 个文件)" }
    }
    catch {
        Write-AppLog "Uninstall-PSProfile failed: $_" -Level Error
        return @{ Success = $false; Message = "清理 PS Profile 失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 10. Uninstall-WTConfig
# ---------------------------------------------------------------------------

function Uninstall-WTConfig {
    [CmdletBinding()]
    param()

    try {
        Write-AppLog "Uninstall-WTConfig: starting..."

        $wtSettingsPath = Get-WTSettingsPath
        $wtSettings = Read-JsonFile $wtSettingsPath

        if ($null -eq $wtSettings) {
            Write-AppLog "WT settings.json not found, nothing to reset." -Level Warn
            return @{ Success = $false; Message = "未找到 Windows Terminal 配置文件" }
        }

        # Reset profiles.defaults to minimal
        if ($null -eq $wtSettings.profiles) {
            $wtSettings | Add-Member -NotePropertyName "profiles" -NotePropertyValue ([PSCustomObject]@{ defaults = [PSCustomObject]@{}; list = @() }) -Force
        }
        if ($null -eq $wtSettings.profiles.defaults) {
            $wtSettings.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }

        $defaults = $wtSettings.profiles.defaults

        # Remove custom settings, leaving a minimal defaults object
        $propsToReset = @('font', 'opacity', 'useAcrylic', 'colorScheme', 'cursorShape', 'cursorHeight', 'adjustIndistinguishableColors', 'padding')
        foreach ($prop in $propsToReset) {
            if ($null -ne $defaults.PSObject.Properties[$prop]) {
                $defaults.PSObject.Properties.Remove($prop)
            }
        }

        # Remove Tokyo Night from schemes
        if ($null -ne $wtSettings.schemes -and $wtSettings.schemes -is [System.Collections.IList]) {
            $filteredSchemes = @()
            foreach ($scheme in $wtSettings.schemes) {
                if ($scheme.name -ne "Tokyo Night") {
                    $filteredSchemes += $scheme
                }
                else {
                    Write-AppLog "Removed Tokyo Night scheme from schemes array."
                }
            }
            $wtSettings.schemes = $filteredSchemes
        }

        # Backup and write back
        Backup-ConfigFile -Path $wtSettingsPath
        $written = Write-JsonFile $wtSettingsPath $wtSettings
        if (-not $written) {
            return @{ Success = $false; Message = "写入 Windows Terminal 配置失败" }
        }

        Update-ComponentStatus
        Write-AppLog "Uninstall-WTConfig: complete."
        return @{ Success = $true; Message = "Windows Terminal 配置已重置" }
    }
    catch {
        Write-AppLog "Uninstall-WTConfig failed: $_" -Level Error
        return @{ Success = $false; Message = "重置 WT 配置失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

# [Removed] Export-ModuleMember
