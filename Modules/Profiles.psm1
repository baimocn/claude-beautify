# Profiles.psm1 -- Profile save / load / export / import
# NOTE: Utils.psm1, State.psm1, Detection.psm1, and Actions.psm1 are imported
# by the entry point. Do NOT re-import them here with -Force as it resets their
# Export-ModuleMember scope. All functions from those modules (Write-AppLog,
# Get-AppConfig, Set-AppData, Get-SafeFileName, Read-JsonFile, Write-JsonFile,
# Apply-WTSettings, Apply-PSProfile, etc.) are available directly.

$Script:ProfilesDir = Join-Path $env:USERPROFILE ".claude\beautify-profiles"

# ---------------------------------------------------------------------------
# Helper: ensure profiles directory exists
# ---------------------------------------------------------------------------

function Ensure-ProfilesDir {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $Script:ProfilesDir)) {
        New-Item -ItemType Directory -Path $Script:ProfilesDir -Force | Out-Null
        Write-AppLog "Created profiles directory: $($Script:ProfilesDir)"
    }
}

# ---------------------------------------------------------------------------
# 1. Get-Profiles
# ---------------------------------------------------------------------------

function Get-Profiles {
    [CmdletBinding()]
    param()

    try {
        Ensure-ProfilesDir

        $files = Get-ChildItem -Path $Script:ProfilesDir -Filter "*.json" -File -ErrorAction Stop
        $profiles = @()

        foreach ($file in $files) {
            $data = Read-JsonFile $file.FullName
            if ($null -ne $data) {
                $profiles += $data
            }
        }

        Write-AppLog "Get-Profiles: found $($profiles.Count) profile(s)."
        return $profiles
    }
    catch {
        Write-AppLog "Get-Profiles failed: $_" -Level Error
        return @()
    }
}

# ---------------------------------------------------------------------------
# 2. Save-Profile
# ---------------------------------------------------------------------------

function Save-Profile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [Parameter(Position = 1)]
        [string]$Notes = ""
    )

    try {
        Ensure-ProfilesDir

        $safeName = Get-SafeFileName $Name
        $filePath = Join-Path $Script:ProfilesDir "$safeName.json"

        $profile = @{
            name      = $Name
            version   = 1
            createdAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
            config    = Get-AppConfig
            notes     = $Notes
        }

        $json = $profile | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText($filePath, $json, (New-Object System.Text.UTF8Encoding($true)))

        Write-AppLog "Save-Profile: saved '$Name' to $filePath"
        return @{ Success = $true; Message = "saved" }
    }
    catch {
        Write-AppLog "Save-Profile failed: $_" -Level Error
        return @{ Success = $false; Message = "保存配置失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 3. Load-Profile
# ---------------------------------------------------------------------------

function Load-Profile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )

    try {
        $safeName = Get-SafeFileName $Name
        $filePath = Join-Path $Script:ProfilesDir "$safeName.json"

        if (-not (Test-Path $filePath)) {
            Write-AppLog "Load-Profile: profile not found: $filePath" -Level Warn
            return @{ Success = $false; Message = "找不到配置: $Name" }
        }

        $profile = Read-JsonFile $filePath
        if ($null -eq $profile) {
            return @{ Success = $false; Message = "读取配置文件失败: $Name" }
        }

        # Apply each config key to state
        $config = $profile.config
        if ($null -ne $config) {
            foreach ($key in $config.PSObject.Properties) {
                Set-AppData "Config.$($key.Name)" $key.Value
            }
        }

        # Apply settings to actual environment
        Apply-WTSettings | Out-Null
        Apply-PSProfile | Out-Null

        Write-AppLog "Load-Profile: loaded '$Name'."
        return @{ Success = $true; Message = "loaded" }
    }
    catch {
        Write-AppLog "Load-Profile failed: $_" -Level Error
        return @{ Success = $false; Message = "加载配置失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 4. Remove-Profile
# ---------------------------------------------------------------------------

function Remove-Profile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )

    try {
        $safeName = Get-SafeFileName $Name
        $filePath = Join-Path $Script:ProfilesDir "$safeName.json"

        if (-not (Test-Path $filePath)) {
            Write-AppLog "Remove-Profile: profile not found: $filePath" -Level Warn
            return @{ Success = $false; Message = "找不到配置: $Name" }
        }

        Remove-Item -Path $filePath -Force -ErrorAction Stop
        Write-AppLog "Remove-Profile: deleted '$Name'."
        return @{ Success = $true }
    }
    catch {
        Write-AppLog "Remove-Profile failed: $_" -Level Error
        return @{ Success = $false; Message = "删除配置失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 5. Export-Profile
# ---------------------------------------------------------------------------

function Export-Profile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Destination
    )

    try {
        $safeName = Get-SafeFileName $Name
        $filePath = Join-Path $Script:ProfilesDir "$safeName.json"

        if (-not (Test-Path $filePath)) {
            Write-AppLog "Export-Profile: profile not found: $filePath" -Level Warn
            return @{ Success = $false; Message = "找不到配置: $Name" }
        }

        # Ensure destination directory exists
        $destDir = Split-Path $Destination -Parent
        if ($destDir -and -not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        Copy-Item -Path $filePath -Destination $Destination -Force -ErrorAction Stop
        Write-AppLog "Export-Profile: exported '$Name' to $Destination"
        return @{ Success = $true }
    }
    catch {
        Write-AppLog "Export-Profile failed: $_" -Level Error
        return @{ Success = $false; Message = "导出配置失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 6. Import-Profile
# ---------------------------------------------------------------------------

function Import-Profile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Source
    )

    try {
        if (-not (Test-Path $Source)) {
            Write-AppLog "Import-Profile: source file not found: $Source" -Level Warn
            return @{ Success = $false; Message = "找不到导入文件: $Source" }
        }

        # Validate JSON structure
        $data = Read-JsonFile $Source
        if ($null -eq $data) {
            return @{ Success = $false; Message = "JSON 解析失败: $Source" }
        }

        if (-not ($data.PSObject.Properties['version'] -and $data.PSObject.Properties['config'])) {
            Write-AppLog "Import-Profile: invalid profile JSON (missing 'version' or 'config')." -Level Warn
            return @{ Success = $false; Message = "无效的配置文件: 缺少 version 或 config 字段" }
        }

        Ensure-ProfilesDir

        # Determine target filename; append timestamp on collision
        $baseName = if ($data.PSObject.Properties['name']) { Get-SafeFileName $data.name } else { "imported" }
        $targetPath = Join-Path $Script:ProfilesDir "$baseName.json"

        if (Test-Path $targetPath) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $baseName = "${baseName}_${timestamp}"
            $targetPath = Join-Path $Script:ProfilesDir "$baseName.json"
            Write-AppLog "Import-Profile: name collision, renamed to '$baseName'."
        }

        Copy-Item -Path $Source -Destination $targetPath -Force -ErrorAction Stop
        Write-AppLog "Import-Profile: imported to $targetPath"
        return @{ Success = $true; Name = $baseName }
    }
    catch {
        Write-AppLog "Import-Profile failed: $_" -Level Error
        return @{ Success = $false; Message = "导入配置失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 7. Get-DefaultProfile
# ---------------------------------------------------------------------------

function Get-DefaultProfile {
    [CmdletBinding()]
    param()

    return @{
        name      = "Default"
        version   = 1
        createdAt = "2026-01-01T00:00:00"
        config    = @{
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
        notes     = "Default profile matching install.ps1 defaults"
    }
}

# [Removed] Export-ModuleMember
