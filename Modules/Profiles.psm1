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
                # Ensure each profile has the expected fields
                $entry = @{
                    name      = if ($data.PSObject.Properties['name'])      { $data.name }      else { $file.BaseName }
                    createdAt = if ($data.PSObject.Properties['createdAt']) { $data.createdAt } else { "" }
                    notes     = if ($data.PSObject.Properties['notes'])     { $data.notes }     else { "" }
                    version   = if ($data.PSObject.Properties['version'])   { $data.version }   else { 1 }
                }
                $profiles += $entry
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
# 4. Get-ProfileDetail
# ---------------------------------------------------------------------------

function Get-ProfileDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )

    try {
        $safeName = Get-SafeFileName $Name
        $filePath = Join-Path $Script:ProfilesDir "$safeName.json"

        if (-not (Test-Path $filePath)) {
            Write-AppLog "Get-ProfileDetail: profile not found: $filePath" -Level Warn
            return $null
        }

        $profile = Read-JsonFile $filePath
        if ($null -eq $profile) {
            Write-AppLog "Get-ProfileDetail: failed to read profile: $filePath" -Level Error
            return $null
        }

        Write-AppLog "Get-ProfileDetail: loaded '$Name'."
        return $profile
    }
    catch {
        Write-AppLog "Get-ProfileDetail failed: $_" -Level Error
        return $null
    }
}

# ---------------------------------------------------------------------------
# 5. Remove-Profile
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
# 6. Export-Profile
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
# 7. Import-Profile
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
# 9. Compare-Profiles
# ---------------------------------------------------------------------------

function Compare-Profiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name1,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Name2
    )

    try {
        Write-AppLog "Compare-Profiles: comparing '$Name1' vs '$Name2'"

        $p1 = Get-ProfileDetail -Name $Name1
        $p2 = Get-ProfileDetail -Name $Name2

        if ($null -eq $p1) {
            return @{ Success = $false; Message = "方案不存在: $Name1"; Differences = @(); Identical = @(); OnlyIn1 = @(); OnlyIn2 = @() }
        }
        if ($null -eq $p2) {
            return @{ Success = $false; Message = "方案不存在: $Name2"; Differences = @(); Identical = @(); OnlyIn1 = @(); OnlyIn2 = @() }
        }

        $config1 = $p1.config
        $config2 = $p2.config

        $differences = @()
        $identical = @()
        $onlyIn1 = @()
        $onlyIn2 = @()

        # Collect all keys from both configs
        $allKeys = @()
        if ($null -ne $config1) {
            foreach ($prop in $config1.PSObject.Properties) {
                $allKeys += $prop.Name
            }
        }
        if ($null -ne $config2) {
            foreach ($prop in $config2.PSObject.Properties) {
                if ($allKeys -notcontains $prop.Name) {
                    $allKeys += $prop.Name
                }
            }
        }

        # Compare each key
        foreach ($key in $allKeys) {
            $val1 = $null
            $val2 = $null
            $has1 = $false
            $has2 = $false

            if ($null -ne $config1 -and $null -ne $config1.PSObject.Properties[$key]) {
                $val1 = $config1.$key
                $has1 = $true
            }
            if ($null -ne $config2 -and $null -ne $config2.PSObject.Properties[$key]) {
                $val2 = $config2.$key
                $has2 = $true
            }

            if ($has1 -and $has2) {
                # Both have the key — compare values
                $v1Str = if ($null -eq $val1) { "" } else { $val1.ToString() }
                $v2Str = if ($null -eq $val2) { "" } else { $val2.ToString() }

                if ($v1Str -eq $v2Str) {
                    $identical += $key
                }
                else {
                    $differences += @{
                        Key           = $key
                        Profile1Value = $val1
                        Profile2Value = $val2
                    }
                }
            }
            elseif ($has1) {
                $onlyIn1 += $key
            }
            elseif ($has2) {
                $onlyIn2 += $key
            }
        }

        Write-AppLog "Compare-Profiles: $($differences.Count) differences, $($identical.Count) identical, $($onlyIn1.Count) only in '$Name1', $($onlyIn2.Count) only in '$Name2'"

        return @{
            Success     = $true
            Profile1    = $Name1
            Profile2    = $Name2
            Differences = $differences
            Identical   = $identical
            OnlyIn1     = $onlyIn1
            OnlyIn2     = $onlyIn2
            TotalKeys   = $allKeys.Count
        }
    }
    catch {
        Write-AppLog "Compare-Profiles failed: $_" -Level Error
        return @{ Success = $false; Message = "对比失败: $_"; Differences = @(); Identical = @(); OnlyIn1 = @(); OnlyIn2 = @() }
    }
}

# ---------------------------------------------------------------------------
# 10. Merge-Profiles
# ---------------------------------------------------------------------------

function Merge-Profiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name1,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Name2,

        [Parameter(Mandatory = $true, Position = 2)]
        [string]$NewName,

        [Parameter(Position = 3)]
        [ValidateSet("prefer_first", "prefer_second", "manual")]
        [string]$Strategy = "prefer_first"
    )

    try {
        Write-AppLog "Merge-Profiles: '$Name1' + '$Name2' -> '$NewName' (strategy: $Strategy)"

        $p1 = Get-ProfileDetail -Name $Name1
        $p2 = Get-ProfileDetail -Name $Name2

        if ($null -eq $p1) {
            return @{ Success = $false; Message = "方案不存在: $Name1" }
        }
        if ($null -eq $p2) {
            return @{ Success = $false; Message = "方案不存在: $Name2" }
        }

        $config1 = if ($p1.config) { $p1.config } else { [PSCustomObject]@{} }
        $config2 = if ($p2.config) { $p2.config } else { [PSCustomObject]@{} }

        # First compare to get differences
        $comparison = Compare-Profiles -Name1 $Name1 -Name2 $Name2

        if ($Strategy -eq "manual") {
            # Manual strategy: just return the comparison result, don't merge
            return @{
                Success  = $true
                Manual   = $true
                Comparison = $comparison
                Message  = "手动合并模式：请根据差异列表选择每项的取值"
            }
        }

        # Build merged config
        $merged = @{}
        $allKeys = @()
        foreach ($prop in $config1.PSObject.Properties) { $allKeys += $prop.Name }
        foreach ($prop in $config2.PSObject.Properties) {
            if ($allKeys -notcontains $prop.Name) { $allKeys += $prop.Name }
        }

        foreach ($key in $allKeys) {
            $val1 = $null
            $val2 = $null
            $has1 = $false
            $has2 = $false

            if ($null -ne $config1.PSObject.Properties[$key]) {
                $val1 = $config1.$key
                $has1 = $true
            }
            if ($null -ne $config2.PSObject.Properties[$key]) {
                $val2 = $config2.$key
                $has2 = $true
            }

            if ($has1 -and $has2) {
                $v1Str = if ($null -eq $val1) { "" } else { $val1.ToString() }
                $v2Str = if ($null -eq $val2) { "" } else { $val2.ToString() }

                if ($v1Str -eq $v2Str) {
                    $merged[$key] = $val1
                }
                elseif ($Strategy -eq "prefer_first") {
                    $merged[$key] = $val1
                }
                elseif ($Strategy -eq "prefer_second") {
                    $merged[$key] = $val2
                }
            }
            elseif ($has1) {
                $merged[$key] = $val1
            }
            elseif ($has2) {
                $merged[$key] = $val2
            }
        }

        # Convert merged hashtable to PSCustomObject for consistency
        $mergedConfig = [PSCustomObject]$merged

        # Build notes
        $notes = "合并自 '$Name1' + '$Name2'，策略: $Strategy"
        if ($p1.notes) { $notes += "`n[方案A备注] $($p1.notes)" }
        if ($p2.notes) { $notes += "`n[方案B备注] $($p2.notes)" }

        # Save as new profile via Save-Profile
        # Temporarily set config in state, save, then restore
        $originalConfig = Get-AppConfig

        try {
            # Set the merged config into state
            foreach ($key in $merged.Keys) {
                Set-AppData "Config.$key" $merged[$key]
            }

            $saveResult = Save-Profile -Name $NewName -Notes $notes

            if ($saveResult.Success) {
                Write-AppLog "Merge-Profiles: merged profile saved as '$NewName'"
                return @{
                    Success = $true
                    NewName = $NewName
                    Strategy = $Strategy
                    MergedKeys = $merged.Keys.Count
                    Differences = $comparison.Differences.Count
                    Message = "合并成功，新方案 '$NewName' 已保存（共 $($merged.Keys.Count) 个配置项）"
                }
            }
            else {
                return @{ Success = $false; Message = $saveResult.Message }
            }
        }
        finally {
            # Restore original config
            foreach ($key in $originalConfig.Keys) {
                Set-AppData "Config.$key" $originalConfig[$key]
            }
        }
    }
    catch {
        Write-AppLog "Merge-Profiles failed: $_" -Level Error
        return @{ Success = $false; Message = "合并失败: $_" }
    }
}

# ---------------------------------------------------------------------------
# 11. Apply-ProfilePartial
# ---------------------------------------------------------------------------

function Apply-ProfilePartial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [string[]]$Keys
    )

    try {
        Write-AppLog "Apply-ProfilePartial: loading '$Name' with keys: $($Keys -join ', ')"

        $profile = Get-ProfileDetail -Name $Name
        if ($null -eq $profile) {
            return @{ Success = $false; Message = "方案不存在: $Name" }
        }

        if ($null -eq $profile.config) {
            return @{ Success = $false; Message = "方案中没有配置数据" }
        }

        $appliedKeys = @()
        $skippedKeys = @()

        # Apply only the specified keys
        foreach ($key in $Keys) {
            if ($null -ne $profile.config.PSObject.Properties[$key]) {
                $value = $profile.config.$key
                Set-AppData "Config.$key" $value
                $appliedKeys += $key
                Write-AppLog "Apply-ProfilePartial: set Config.$key = $value"
            }
            else {
                $skippedKeys += $key
                Write-AppLog "Apply-ProfilePartial: key '$key' not found in profile, skipped"
            }
        }

        # Determine which apply functions to call based on changed keys
        $wtRelatedKeys = @("Opacity", "FontSize", "FontFace", "UseAcrylic", "CursorShape", "CursorHeight", "ColorScheme", "Padding")
        $psRelatedKeys = @("OMPTheme")

        $needsWT = $false
        $needsPS = $false

        foreach ($key in $appliedKeys) {
            if ($wtRelatedKeys -contains $key) { $needsWT = $true }
            if ($psRelatedKeys -contains $key) { $needsPS = $true }
        }

        $applyResults = @()

        if ($needsWT) {
            Write-AppLog "Apply-ProfilePartial: applying Windows Terminal settings"
            $wtResult = Apply-WTSettings
            $applyResults += @{ Component = "WindowsTerminal"; Result = $wtResult }
        }

        if ($needsPS) {
            Write-AppLog "Apply-ProfilePartial: applying PSProfile (theme only)"
            $config = Get-AppConfig
            $themeName = if ($config.OMPTheme) { $config.OMPTheme } else { "tokyonight_storm" }
            $psResult = Apply-PSProfile -ThemeName $themeName
            $applyResults += @{ Component = "PSProfile"; Result = $psResult }
        }

        # Update component status
        Update-ComponentStatus

        Write-AppLog "Apply-ProfilePartial: applied $($appliedKeys.Count) keys, skipped $($skippedKeys.Count)"

        return @{
            Success     = $true
            AppliedKeys = $appliedKeys
            SkippedKeys = $skippedKeys
            Components  = $applyResults
            Message     = "部分加载完成：已应用 $($appliedKeys.Count) 个配置项"
        }
    }
    catch {
        Write-AppLog "Apply-ProfilePartial failed: $_" -Level Error
        return @{ Success = $false; Message = "部分加载失败: $_" }
    }
}

# [Removed] Export-ModuleMember
