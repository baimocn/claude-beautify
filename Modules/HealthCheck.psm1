# HealthCheck.psm1 -- Component health diagnosis and auto-repair
#
# Provides deep health checks beyond simple "installed/not installed" detection,
# plus automatic repair for common issues.
#
# NOTE: Utils.psm1, State.psm1, Constants.psm1, Detection.psm1, and Actions.psm1
# are imported by the entry point. Do NOT re-import them here with -Force.

# ---------------------------------------------------------------------------
# Helper: New a single check result
# ---------------------------------------------------------------------------

function New-HealthCheckResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComponentName,

        [bool]$Healthy = $true,
        [array]$Checks = @(),
        [array]$Warnings = @(),
        [array]$Fixes = @()
    )

    return @{
        ComponentName = $ComponentName
        Healthy       = $Healthy
        Checks        = $Checks
        Warnings      = $Warnings
        Fixes         = $Fixes
        Timestamp     = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }
}

function New-CheckEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Pass", "Warn", "Fail", "Info")]
        [string]$Status,

        [string]$Detail = "",
        [string]$FixId = ""
    )

    return @{
        Id      = $Id
        Name    = $Name
        Status  = $Status
        Detail  = $Detail
        FixId   = $FixId
    }
}

# ---------------------------------------------------------------------------
# 1. Oh My Posh health checks
# ---------------------------------------------------------------------------

function Test-OhMyPoshHealth {
    [CmdletBinding()]
    param()

    Write-AppLog "Test-OhMyPoshHealth: starting..."
    $result = New-HealthCheckResult -ComponentName "OhMyPosh"
    $checks = @()
    $fixes = @()
    $warnings = @()

    # Check 1: Command exists in PATH
    try {
        $cmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $raw = & oh-my-posh version 2>&1
            $version = ($raw | Out-String).Trim()
            $checks += New-CheckEntry -Id "command_in_path" -Name "命令在 PATH 中" -Status "Pass" -Detail "版本: $version"
        }
        else {
            $checks += New-CheckEntry -Id "command_in_path" -Name "命令在 PATH 中" -Status "Fail" -Detail "oh-my-posh 命令找不到" -FixId "refresh_path_omp"
            $fixes += @{ Id = "refresh_path_omp"; Name = "刷新 PATH 环境变量"; Description = "重新扫描 PATH 使 oh-my-posh 命令可用" }
            $result.Healthy = $false
        }
    }
    catch {
        $checks += New-CheckEntry -Id "command_in_path" -Name "命令在 PATH 中" -Status "Fail" -Detail "检查失败: $_" -FixId "refresh_path_omp"
        $fixes += @{ Id = "refresh_path_omp"; Name = "刷新 PATH 环境变量"; Description = "重新扫描 PATH 使 oh-my-posh 命令可用" }
        $result.Healthy = $false
    }

    # Check 2: Version >= 18.0
    if ($null -ne $cmd -and $version) {
        try {
            $verObj = [version]($version -replace "[^0-9.]", "")
            if ($verObj.Major -lt 18) {
                $checks += New-CheckEntry -Id "version_age" -Name "版本过旧检查" -Status "Warn" -Detail "当前版本 $version，建议升级到 v18.0+" -FixId "upgrade_omp"
                $fixes += @{ Id = "upgrade_omp"; Name = "升级 Oh My Posh"; Description = "通过 winget 升级到最新版本" }
                $warnings += "Oh My Posh 版本较旧 ($version)，建议升级以获得最新功能和主题"
            }
            else {
                $checks += New-CheckEntry -Id "version_age" -Name "版本过旧检查" -Status "Pass" -Detail "版本 $version 满足要求"
            }
        }
        catch {
            $checks += New-CheckEntry -Id "version_age" -Name "版本过旧检查" -Status "Info" -Detail "无法解析版本号: $version"
        }
    }

    # Check 3: Theme files exist
    $themesPath = $env:POSH_THEMES_PATH
    if ($themesPath -and (Test-Path $themesPath)) {
        $themeCount = (Get-ChildItem $themesPath -Filter "*.omp.json" -ErrorAction SilentlyContinue).Count
        $checks += New-CheckEntry -Id "themes_exist" -Name "主题文件存在" -Status "Pass" -Detail "找到 $themeCount 个主题文件 ($themesPath)"
    }
    else {
        $checks += New-CheckEntry -Id "themes_exist" -Name "主题文件存在" -Status "Warn" -Detail "POSH_THEMES_PATH 环境变量未设置或路径不存在" -FixId "restore_themes_path"
        $fixes += @{ Id = "restore_themes_path"; Name = "恢复主题路径环境变量"; Description = "设置 POSH_THEMES_PATH 指向 Oh My Posh 主题目录" }
        $warnings += "主题路径未配置，可能无法加载内置主题"
    }

    # Check 4: PSProfile init command is correct
    $profilePaths = @(
        (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
        (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
    )
    $ompInProfile = $false
    $initLine = ""
    foreach ($pp in $profilePaths) {
        if (Test-Path $pp) {
            $content = Get-Content -Path $pp -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($content -match "oh-my-posh init") {
                $ompInProfile = $true
                $initLine = $Matches[0]
                break
            }
        }
    }

    if ($ompInProfile) {
        $checks += New-CheckEntry -Id "init_command" -Name "init 命令正确" -Status "Pass" -Detail "Profile 中已配置 oh-my-posh init"
    }
    else {
        $checks += New-CheckEntry -Id "init_command" -Name "init 命令正确" -Status "Warn" -Detail "PowerShell Profile 中未找到 oh-my-posh init 命令" -FixId "add_omp_init"
        $fixes += @{ Id = "add_omp_init"; Name = "添加 oh-my-posh 初始化"; Description = "在 PowerShell Profile 中添加 oh-my-posh init 命令" }
        $warnings += "Oh My Posh 已安装但 Profile 中未初始化，终端启动时不会应用主题"
    }

    $result.Checks = $checks
    $result.Warnings = $warnings
    $result.Fixes = $fixes

    Write-AppLog "Test-OhMyPoshHealth: Healthy=$($result.Healthy), Checks=$($checks.Count), Fixes=$($fixes.Count)"
    return $result
}

# ---------------------------------------------------------------------------
# 2. Nerd Font health checks
# ---------------------------------------------------------------------------

function Test-NerdFontHealth {
    [CmdletBinding()]
    param()

    Write-AppLog "Test-NerdFontHealth: starting..."
    $result = New-HealthCheckResult -ComponentName "NerdFont"
    $checks = @()
    $fixes = @()
    $warnings = @()

    # Check 1: Font files exist in C:\Windows\Fonts
    $fontDir = "C:\Windows\Fonts"
    $fontFiles = Get-ChildItem $fontDir -Filter "*Caskaydia*" -ErrorAction SilentlyContinue
    $fontInstalled = ($null -ne $fontFiles) -and ($fontFiles.Count -gt 0)

    if ($fontInstalled) {
        $checks += New-CheckEntry -Id "font_installed" -Name "字体文件已安装" -Status "Pass" -Detail "找到 $($fontFiles.Count) 个 Caskaydia 字体文件"
    }
    else {
        $checks += New-CheckEntry -Id "font_installed" -Name "字体文件已安装" -Status "Fail" -Detail "C:\Windows\Fonts 中未找到 Caskaydia Nerd Font" -FixId "install_nerd_font"
        $fixes += @{ Id = "install_nerd_font"; Name = "安装 Nerd Font"; Description = "下载并安装 Cascadia Code Nerd Font" }
        $result.Healthy = $false
    }

    # Check 2: Windows Terminal configured with Nerd Font
    try {
        $wtSettingsPath = Get-WTSettingsPath
        $wtSettings = Read-JsonFile $wtSettingsPath
        if ($null -ne $wtSettings -and $wtSettings.profiles -and $wtSettings.profiles.defaults -and $wtSettings.profiles.defaults.font -and $wtSettings.profiles.defaults.font.face) {
            $fontFace = $wtSettings.profiles.defaults.font.face
            if ($fontFace -match "Nerd|Caskaydia|NF") {
                $checks += New-CheckEntry -Id "wt_font_config" -Name "Windows Terminal 字体配置" -Status "Pass" -Detail "当前字体: $fontFace"
            }
            else {
                $checks += New-CheckEntry -Id "wt_font_config" -Name "Windows Terminal 字体配置" -Status "Warn" -Detail "当前字体: $fontFace，不是 Nerd Font" -FixId "set_wt_nerd_font"
                $fixes += @{ Id = "set_wt_nerd_font"; Name = "设置 WT 使用 Nerd Font"; Description = "将 Windows Terminal 默认字体改为 CaskaydiaCove Nerd Font" }
                $warnings += "Windows Terminal 未配置 Nerd Font，图标可能无法正常显示"
            }
        }
        elseif ($null -ne $wtSettings) {
            $checks += New-CheckEntry -Id "wt_font_config" -Name "Windows Terminal 字体配置" -Status "Warn" -Detail "未设置默认字体" -FixId "set_wt_nerd_font"
            $fixes += @{ Id = "set_wt_nerd_font"; Name = "设置 WT 使用 Nerd Font"; Description = "将 Windows Terminal 默认字体改为 CaskaydiaCove Nerd Font" }
            $warnings += "Windows Terminal 未配置默认字体"
        }
        else {
            $checks += New-CheckEntry -Id "wt_font_config" -Name "Windows Terminal 字体配置" -Status "Info" -Detail "未找到 Windows Terminal 配置文件"
        }
    }
    catch {
        $checks += New-CheckEntry -Id "wt_font_config" -Name "Windows Terminal 字体配置" -Status "Info" -Detail "无法检查 WT 配置: $_"
    }

    # Check 3: VS Code configured with Nerd Font
    $vscodeSettingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
    if (Test-Path $vscodeSettingsPath) {
        try {
            $vsSettings = Read-JsonFile $vscodeSettingsPath
            $termFont = ""
            if ($vsSettings -and $vsSettings.PSObject.Properties['terminal.integrated.fontFamily']) {
                $termFont = $vsSettings.'terminal.integrated.fontFamily'
            }
            if ($termFont -match "Nerd|Caskaydia|NF") {
                $checks += New-CheckEntry -Id "vscode_font_config" -Name "VS Code 终端字体" -Status "Pass" -Detail "终端字体: $termFont"
            }
            elseif ($termFont) {
                $checks += New-CheckEntry -Id "vscode_font_config" -Name "VS Code 终端字体" -Status "Info" -Detail "终端字体: $termFont"
            }
            else {
                $checks += New-CheckEntry -Id "vscode_font_config" -Name "VS Code 终端字体" -Status "Info" -Detail "未设置终端集成字体"
            }
        }
        catch {
            $checks += New-CheckEntry -Id "vscode_font_config" -Name "VS Code 终端字体" -Status "Info" -Detail "无法读取 VS Code 设置"
        }
    }
    else {
        $checks += New-CheckEntry -Id "vscode_font_config" -Name "VS Code 终端字体" -Status "Info" -Detail "未找到 VS Code 设置文件"
    }

    $result.Checks = $checks
    $result.Warnings = $warnings
    $result.Fixes = $fixes

    Write-AppLog "Test-NerdFontHealth: Healthy=$($result.Healthy), Checks=$($checks.Count), Fixes=$($fixes.Count)"
    return $result
}

# ---------------------------------------------------------------------------
# 3. Windows Terminal health checks
# ---------------------------------------------------------------------------

function Test-WindowsTerminalHealth {
    [CmdletBinding()]
    param()

    Write-AppLog "Test-WindowsTerminalHealth: starting..."
    $result = New-HealthCheckResult -ComponentName "WindowsTerminal"
    $checks = @()
    $fixes = @()
    $warnings = @()

    # Check 1: settings.json exists and is valid JSON
    $settingsPath = Get-WTSettingsPath
    if (Test-Path $settingsPath) {
        $settings = Read-JsonFile $settingsPath
        if ($null -ne $settings) {
            $checks += New-CheckEntry -Id "settings_valid" -Name "settings.json 存在且合法" -Status "Pass" -Detail "配置文件路径: $settingsPath"
        }
        else {
            $checks += New-CheckEntry -Id "settings_valid" -Name "settings.json 存在且合法" -Status "Fail" -Detail "配置文件格式错误，无法解析" -FixId "repair_wt_settings"
            $fixes += @{ Id = "repair_wt_settings"; Name = "修复 settings.json"; Description = "重建 Windows Terminal settings.json 默认配置" }
            $result.Healthy = $false
        }
    }
    else {
        $checks += New-CheckEntry -Id "settings_valid" -Name "settings.json 存在且合法" -Status "Warn" -Detail "未找到配置文件: $settingsPath" -FixId "create_wt_settings"
        $fixes += @{ Id = "create_wt_settings"; Name = "创建 settings.json"; Description = "生成默认 Windows Terminal 配置文件" }
        $warnings += "Windows Terminal 配置文件不存在，可能尚未启动过终端"
    }

    # Check 2: Tokyo Night color scheme exists
    if ($null -ne $settings) {
        $hasTokyoNight = $false
        if ($settings.schemes -and $settings.schemes -is [System.Collections.IList]) {
            foreach ($s in $settings.schemes) {
                if ($s.name -eq "Tokyo Night") { $hasTokyoNight = $true; break }
            }
        }
        if ($hasTokyoNight) {
            $checks += New-CheckEntry -Id "tokyo_night_scheme" -Name "Tokyo Night 配色方案" -Status "Pass" -Detail "配色方案已添加到 schemes 数组"
        }
        else {
            $checks += New-CheckEntry -Id "tokyo_night_scheme" -Name "Tokyo Night 配色方案" -Status "Warn" -Detail "schemes 中未找到 Tokyo Night" -FixId "add_tokyo_night"
            $fixes += @{ Id = "add_tokyo_night"; Name = "添加 Tokyo Night 配色"; Description = "在 settings.json 中添加 Tokyo Night 配色方案" }
            $warnings += "Tokyo Night 配色方案未安装"
        }

        # Check 3: colorScheme set to Tokyo Night
        if ($settings.profiles -and $settings.profiles.defaults -and $settings.profiles.defaults.colorScheme) {
            if ($settings.profiles.defaults.colorScheme -eq "Tokyo Night") {
                $checks += New-CheckEntry -Id "colorscheme_set" -Name "配色方案已应用" -Status "Pass" -Detail "colorScheme = Tokyo Night"
            }
            else {
                $checks += New-CheckEntry -Id "colorscheme_set" -Name "配色方案已应用" -Status "Warn" -Detail "当前 colorScheme: $($settings.profiles.defaults.colorScheme)" -FixId "apply_tokyo_night"
                $fixes += @{ Id = "apply_tokyo_night"; Name = "应用 Tokyo Night 配色"; Description = "将默认 profile 的 colorScheme 设为 Tokyo Night" }
                $warnings += "当前配色不是 Tokyo Night"
            }
        }
        else {
            $checks += New-CheckEntry -Id "colorscheme_set" -Name "配色方案已应用" -Status "Warn" -Detail "未设置 colorScheme" -FixId "apply_tokyo_night"
            $fixes += @{ Id = "apply_tokyo_night"; Name = "应用 Tokyo Night 配色"; Description = "将默认 profile 的 colorScheme 设为 Tokyo Night" }
            $warnings += "未设置默认配色方案"
        }

        # Check 4: Acrylic transparency
        $defaults = if ($settings.profiles -and $settings.profiles.defaults) { $settings.profiles.defaults } else { $null }
        $useAcrylic = if ($defaults -and $null -ne $defaults.PSObject.Properties['useAcrylic']) { $defaults.useAcrylic } else { $false }
        $opacity = if ($defaults -and $null -ne $defaults.PSObject.Properties['opacity']) { $defaults.opacity } else { $null }

        if ($useAcrylic -and $null -ne $opacity) {
            $checks += New-CheckEntry -Id "acrylic_config" -Name "亚克力透明效果" -Status "Pass" -Detail "useAcrylic=$useAcrylic, opacity=$opacity"
        }
        else {
            $checks += New-CheckEntry -Id "acrylic_config" -Name "亚克力透明效果" -Status "Info" -Detail "未配置 acrylic 透明效果"
        }

        # Check 5: Font is Nerd Font
        if ($defaults -and $defaults.font -and $defaults.font.face) {
            if ($defaults.font.face -match "Nerd|Caskaydia|NF") {
                $checks += New-CheckEntry -Id "font_is_nerd" -Name "字体为 Nerd Font" -Status "Pass" -Detail "字体: $($defaults.font.face)"
            }
            else {
                $checks += New-CheckEntry -Id "font_is_nerd" -Name "字体为 Nerd Font" -Status "Warn" -Detail "字体: $($defaults.font.face)" -FixId "set_wt_nerd_font"
                if (-not ($fixes | Where-Object { $_.Id -eq "set_wt_nerd_font" })) {
                    $fixes += @{ Id = "set_wt_nerd_font"; Name = "设置 WT 使用 Nerd Font"; Description = "将 Windows Terminal 默认字体改为 CaskaydiaCove Nerd Font" }
                }
                $warnings += "Windows Terminal 字体不是 Nerd Font，图标显示异常"
            }
        }
        else {
            $checks += New-CheckEntry -Id "font_is_nerd" -Name "字体为 Nerd Font" -Status "Info" -Detail "未设置默认字体"
        }
    }

    $result.Checks = $checks
    $result.Warnings = $warnings
    $result.Fixes = $fixes

    Write-AppLog "Test-WindowsTerminalHealth: Healthy=$($result.Healthy), Checks=$($checks.Count), Fixes=$($fixes.Count)"
    return $result
}

# ---------------------------------------------------------------------------
# 4. PSProfile health checks
# ---------------------------------------------------------------------------

function Test-PSProfileHealth {
    [CmdletBinding()]
    param()

    Write-AppLog "Test-PSProfileHealth: starting..."
    $result = New-HealthCheckResult -ComponentName "PSProfile"
    $checks = @()
    $fixes = @()
    $warnings = @()

    $profilePaths = @(
        (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
        (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
    )

    # Check 1: $PROFILE file exists
    $profileExists = $false
    $activeProfile = ""
    foreach ($pp in $profilePaths) {
        if (Test-Path $pp) { $profileExists = $true; $activeProfile = $pp; break }
    }

    if ($profileExists) {
        $checks += New-CheckEntry -Id "profile_exists" -Name "Profile 文件存在" -Status "Pass" -Detail "路径: $activeProfile"
    }
    else {
        $checks += New-CheckEntry -Id "profile_exists" -Name "Profile 文件存在" -Status "Fail" -Detail "未找到 PowerShell Profile 文件" -FixId "create_psprofile"
        $fixes += @{ Id = "create_psprofile"; Name = "创建 PowerShell Profile"; Description = "生成包含 oh-my-posh 和 PSReadLine 配置的 Profile 文件" }
        $result.Healthy = $false
    }

    # Check 2: Contains oh-my-posh init
    $hasOmpInit = $false
    $initContent = ""
    if ($profileExists) {
        try {
            $content = Get-Content -Path $activeProfile -Raw -Encoding UTF8 -ErrorAction Stop
            if ($content -match "oh-my-posh init") {
                $hasOmpInit = $true
                $checks += New-CheckEntry -Id "omp_init" -Name "oh-my-posh init 配置" -Status "Pass" -Detail "Profile 包含 oh-my-posh 初始化命令"
            }
            else {
                $checks += New-CheckEntry -Id "omp_init" -Name "oh-my-posh init 配置" -Status "Fail" -Detail "Profile 中未找到 oh-my-posh init 命令" -FixId "add_omp_init_profile"
                $fixes += @{ Id = "add_omp_init_profile"; Name = "添加 oh-my-posh 初始化"; Description = "在 Profile 中添加 oh-my-posh init pwsh 命令" }
                $result.Healthy = $false
            }
        }
        catch {
            $checks += New-CheckEntry -Id "omp_init" -Name "oh-my-posh init 配置" -Status "Fail" -Detail "无法读取 Profile: $_" -FixId "repair_psprofile"
            $fixes += @{ Id = "repair_psprofile"; Name = "修复 Profile 文件"; Description = "重建 PowerShell Profile 配置" }
            $result.Healthy = $false
        }
    }

    # Check 3: PSReadLine configuration
    if ($profileExists) {
        try {
            $content = Get-Content -Path $activeProfile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            $hasPSReadLine = ($content -match "PSReadLine|Set-PSReadLineOption")

            if ($hasPSReadLine) {
                $checks += New-CheckEntry -Id "psreadline_config" -Name "PSReadLine 配置" -Status "Pass" -Detail "Profile 包含 PSReadLine 配置"
            }
            else {
                $checks += New-CheckEntry -Id "psreadline_config" -Name "PSReadLine 配置" -Status "Warn" -Detail "Profile 中未配置 PSReadLine" -FixId "add_psreadline"
                $fixes += @{ Id = "add_psreadline"; Name = "添加 PSReadLine 配置"; Description = "在 Profile 中添加 PSReadLine 预测和键绑定配置" }
                $warnings += "PSReadLine 未配置，缺少命令历史预测等增强功能"
            }
        }
        catch {
            $checks += New-CheckEntry -Id "psreadline_config" -Name "PSReadLine 配置" -Status "Info" -Detail "无法检查 PSReadLine 配置"
        }
    }

    # Check 4: Profile is not corrupted (no syntax errors)
    if ($profileExists) {
        try {
            $tokens = $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($activeProfile, [ref]$tokens, [ref]$errors)
            if ($errors.Count -eq 0) {
                $checks += New-CheckEntry -Id "profile_syntax" -Name "Profile 语法正确" -Status "Pass" -Detail "无语法错误"
            }
            else {
                $errMsgs = ($errors | ForEach-Object { $_.Message }) -join "; "
                $checks += New-CheckEntry -Id "profile_syntax" -Name "Profile 语法正确" -Status "Fail" -Detail "语法错误: $errMsgs" -FixId "repair_psprofile_syntax"
                $fixes += @{ Id = "repair_psprofile_syntax"; Name = "修复 Profile 语法错误"; Description = "备份并重建 PowerShell Profile 文件" }
                $result.Healthy = $false
            }
        }
        catch {
            $checks += New-CheckEntry -Id "profile_syntax" -Name "Profile 语法正确" -Status "Info" -Detail "无法进行语法检查"
        }
    }

    $result.Checks = $checks
    $result.Warnings = $warnings
    $result.Fixes = $fixes

    Write-AppLog "Test-PSProfileHealth: Healthy=$($result.Healthy), Checks=$($checks.Count), Fixes=$($fixes.Count)"
    return $result
}

# ---------------------------------------------------------------------------
# 5. Status Bar health checks
# ---------------------------------------------------------------------------

function Test-StatusBarHealth {
    [CmdletBinding()]
    param()

    Write-AppLog "Test-StatusBarHealth: starting..."
    $result = New-HealthCheckResult -ComponentName "StatusBar"
    $checks = @()
    $fixes = @()
    $warnings = @()

    $scriptPath = Join-Path $env:USERPROFILE ".claude\statusline-command.sh"
    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"

    # Check 1: statusline.sh exists
    if (Test-Path $scriptPath) {
        $size = (Get-Item $scriptPath).Length
        $checks += New-CheckEntry -Id "script_exists" -Name "statusline 脚本存在" -Status "Pass" -Detail "文件大小: $size 字节"
    }
    else {
        $checks += New-CheckEntry -Id "script_exists" -Name "statusline 脚本存在" -Status "Fail" -Detail "statusline-command.sh 不存在" -FixId "install_statusline_script"
        $fixes += @{ Id = "install_statusline_script"; Name = "安装 statusline 脚本"; Description = "重新复制 statusline-command.sh 到 ~/.claude/" }
        $result.Healthy = $false
    }

    # Check 2: Claude Code settings.json points to correct path
    if (Test-Path $settingsPath) {
        try {
            $settings = Read-JsonFile $settingsPath
            if ($null -ne $settings -and $settings.statusLine) {
                $sl = $settings.statusLine
                if ($sl.command -and $sl.command -match "statusline") {
                    $checks += New-CheckEntry -Id "settings_config" -Name "Claude Code 配置正确" -Status "Pass" -Detail "statusLine 已配置: $($sl.command)"
                }
                else {
                    $checks += New-CheckEntry -Id "settings_config" -Name "Claude Code 配置正确" -Status "Warn" -Detail "statusLine 配置异常" -FixId "repair_statusline_settings"
                    $fixes += @{ Id = "repair_statusline_settings"; Name = "修复 statusline 配置"; Description = "更新 settings.json 中的 statusLine 配置" }
                    $warnings += "Claude Code 的 statusLine 配置不正确"
                }
                if ($sl.type -and $sl.type -eq "command") {
                    # Good
                }
                else {
                    $warnings += "statusLine type 不是 command 类型"
                }
            }
            else {
                $checks += New-CheckEntry -Id "settings_config" -Name "Claude Code 配置正确" -Status "Fail" -Detail "settings.json 中没有 statusLine 字段" -FixId "add_statusline_settings"
                $fixes += @{ Id = "add_statusline_settings"; Name = "添加 statusline 配置"; Description = "在 settings.json 中添加 statusLine 配置" }
                $result.Healthy = $false
            }
        }
        catch {
            $checks += New-CheckEntry -Id "settings_config" -Name "Claude Code 配置正确" -Status "Fail" -Detail "读取 settings.json 失败: $_" -FixId "repair_statusline_settings"
            $fixes += @{ Id = "repair_statusline_settings"; Name = "修复 statusline 配置"; Description = "重新生成 settings.json 中的 statusLine 配置" }
            $result.Healthy = $false
        }
    }
    else {
        $checks += New-CheckEntry -Id "settings_config" -Name "Claude Code 配置正确" -Status "Warn" -Detail "settings.json 不存在" -FixId "create_statusline_settings"
        $fixes += @{ Id = "create_statusline_settings"; Name = "创建 settings.json"; Description = "创建包含 statusLine 配置的 settings.json" }
        $warnings += "Claude Code settings.json 不存在"
    }

    $result.Checks = $checks
    $result.Warnings = $warnings
    $result.Fixes = $fixes

    Write-AppLog "Test-StatusBarHealth: Healthy=$($result.Healthy), Checks=$($checks.Count), Fixes=$($fixes.Count)"
    return $result
}

# ---------------------------------------------------------------------------
# 6. Test-ComponentHealth — main dispatcher
# ---------------------------------------------------------------------------

function Test-ComponentHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet("OhMyPosh", "NerdFont", "WindowsTerminal", "PSProfile", "StatusBar", "All")]
        [string]$ComponentName
    )

    Write-AppLog "Test-ComponentHealth: checking $ComponentName"

    switch ($ComponentName) {
        "OhMyPosh"       { return Test-OhMyPoshHealth }
        "NerdFont"       { return Test-NerdFontHealth }
        "WindowsTerminal" { return Test-WindowsTerminalHealth }
        "PSProfile"      { return Test-PSProfileHealth }
        "StatusBar"      { return Test-StatusBarHealth }
        "All"            {
            $results = @{
                OhMyPosh       = Test-OhMyPoshHealth
                NerdFont       = Test-NerdFontHealth
                WindowsTerminal = Test-WindowsTerminalHealth
                PSProfile      = Test-PSProfileHealth
                StatusBar      = Test-StatusBarHealth
            }
            return $results
        }
    }
}

# ---------------------------------------------------------------------------
# 7. Repair-Component — auto-fix detected issues
# ---------------------------------------------------------------------------

function Repair-Component {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet("OhMyPosh", "NerdFont", "WindowsTerminal", "PSProfile", "StatusBar")]
        [string]$ComponentName,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$FixId
    )

    Write-AppLog "Repair-Component: $ComponentName / $FixId"

    $backupPath = ""
    $fixed = $false
    $message = ""

    try {
        switch ($ComponentName) {
            "OhMyPosh" {
                switch ($FixId) {
                    "refresh_path_omp" {
                        # Refresh PATH from registry
                        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
                        $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
                        $env:Path = "$machinePath;$userPath"

                        $cmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
                        if ($null -ne $cmd) {
                            $fixed = $true
                            $message = "PATH 已刷新，oh-my-posh 现在可用"
                        } else {
                            $message = "PATH 已刷新但仍找不到 oh-my-posh，请确认已安装"
                        }
                    }
                    "upgrade_omp" {
                        if (Test-ChocolateyInstalled) {
                            $output = & cmd /c "choco upgrade oh-my-posh -y" 2>&1
                            Write-AppLog ($output | Out-String)
                            if ($LASTEXITCODE -eq 0) {
                                $fixed = $true
                                $message = "Oh My Posh 已升级到最新版本"
                            } else {
                                $message = "升级失败 (exit code: $LASTEXITCODE)"
                            }
                        } else {
                            $message = "Chocolatey 未安装，无法自动升级"
                        }
                    }
                    "restore_themes_path" {
                        $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
                        if ($null -ne $ompCmd) {
                            $themesDir = Join-Path (Split-Path $ompCmd.Source -Parent) "themes"
                            if (Test-Path $themesDir) {
                                [Environment]::SetEnvironmentVariable("POSH_THEMES_PATH", $themesDir, "User")
                                $env:POSH_THEMES_PATH = $themesDir
                                $fixed = $true
                                $message = "POSH_THEMES_PATH 已设置为: $themesDir"
                            } else {
                                $message = "找不到主题目录: $themesDir"
                            }
                        } else {
                            $message = "oh-my-posh 命令不可用，无法确定主题路径"
                        }
                    }
                    "add_omp_init" {
                        # Delegated to Apply-PSProfile
                        $result = Apply-PSProfile
                        if ($result.Success) {
                            $fixed = $true
                            $message = "oh-my-posh init 已添加到 PowerShell Profile"
                        } else {
                            $message = $result.Message
                        }
                    }
                    default {
                        $message = "未知的修复 ID: $FixId"
                    }
                }
            }

            "NerdFont" {
                switch ($FixId) {
                    "install_nerd_font" {
                        $result = Install-NerdFont
                        if ($result.Success) {
                            $fixed = $true
                            $message = $result.Message
                        } else {
                            $message = $result.Message
                        }
                    }
                    "set_wt_nerd_font" {
                        $wtPath = Get-WTSettingsPath
                        if (Test-Path $wtPath) {
                            Backup-ConfigFile -Path $wtPath
                            $backupPath = $wtPath + ".bak.*"

                            $settings = Read-JsonFile $wtPath
                            if ($null -eq $settings.profiles) {
                                $settings | Add-Member -NotePropertyName "profiles" -NotePropertyValue ([PSCustomObject]@{ defaults = [PSCustomObject]@{}; list = @() }) -Force
                            }
                            if ($null -eq $settings.profiles.defaults) {
                                $settings.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([PSCustomObject]@{}) -Force
                            }
                            $defaults = $settings.profiles.defaults
                            if ($null -eq $defaults.PSObject.Properties['font']) {
                                $defaults | Add-Member -NotePropertyName "font" -NotePropertyValue ([PSCustomObject]@{}) -Force
                            }
                            $defaults.font | Add-Member -NotePropertyName "face" -NotePropertyValue "CaskaydiaCove Nerd Font" -Force
                            $written = Write-JsonFile $wtPath $settings
                            if ($written) {
                                $fixed = $true
                                $message = "Windows Terminal 字体已设置为 CaskaydiaCove Nerd Font"
                            } else {
                                $message = "写入 settings.json 失败"
                            }
                        } else {
                            $message = "未找到 Windows Terminal 配置文件"
                        }
                    }
                    default {
                        $message = "未知的修复 ID: $FixId"
                    }
                }
            }

            "WindowsTerminal" {
                switch ($FixId) {
                    "repair_wt_settings" {
                        $wtPath = Get-WTSettingsPath
                        if (Test-Path $wtPath) {
                            Backup-ConfigFile -Path $wtPath
                        }
                        # Re-apply WT settings
                        $result = Apply-WTSettings
                        if ($result.Success) {
                            $fixed = $true
                            $message = $result.Message
                        } else {
                            $message = $result.Message
                        }
                    }
                    "create_wt_settings" {
                        $wtPath = Get-WTSettingsPath
                        $dir = Split-Path $wtPath -Parent
                        if (-not (Test-Path $dir)) {
                            New-Item -ItemType Directory -Path $dir -Force | Out-Null
                        }
                        $result = Apply-WTSettings
                        if ($result.Success) {
                            $fixed = $true
                            $message = $result.Message
                        } else {
                            $message = $result.Message
                        }
                    }
                    "add_tokyo_night" {
                        $wtPath = Get-WTSettingsPath
                        if (Test-Path $wtPath) {
                            Backup-ConfigFile -Path $wtPath
                            $settings = Read-JsonFile $wtPath
                            if ($null -eq $settings.schemes -or $settings.schemes -isnot [System.Collections.IList]) {
                                $settings | Add-Member -NotePropertyName "schemes" -NotePropertyValue @() -Force
                            }
                            $tokyo = Get-TokyoNightScheme
                            $settings.schemes += [PSCustomObject]$tokyo
                            $written = Write-JsonFile $wtPath $settings
                            if ($written) {
                                $fixed = $true
                                $message = "Tokyo Night 配色方案已添加"
                            } else {
                                $message = "写入 settings.json 失败"
                            }
                        } else {
                            $message = "未找到 Windows Terminal 配置文件"
                        }
                    }
                    "apply_tokyo_night" {
                        $result = Apply-WTSettings
                        if ($result.Success) {
                            $fixed = $true
                            $message = $result.Message
                        } else {
                            $message = $result.Message
                        }
                    }
                    "set_wt_nerd_font" {
                        $wtPath = Get-WTSettingsPath
                        if (Test-Path $wtPath) {
                            Backup-ConfigFile -Path $wtPath
                            $settings = Read-JsonFile $wtPath
                            if ($null -eq $settings.profiles) {
                                $settings | Add-Member -NotePropertyName "profiles" -NotePropertyValue ([PSCustomObject]@{ defaults = [PSCustomObject]@{}; list = @() }) -Force
                            }
                            if ($null -eq $settings.profiles.defaults) {
                                $settings.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([PSCustomObject]@{}) -Force
                            }
                            $defaults = $settings.profiles.defaults
                            if ($null -eq $defaults.PSObject.Properties['font']) {
                                $defaults | Add-Member -NotePropertyName "font" -NotePropertyValue ([PSCustomObject]@{}) -Force
                            }
                            $defaults.font | Add-Member -NotePropertyName "face" -NotePropertyValue "CaskaydiaCove Nerd Font" -Force
                            $written = Write-JsonFile $wtPath $settings
                            if ($written) {
                                $fixed = $true
                                $message = "字体已设置为 CaskaydiaCove Nerd Font"
                            } else {
                                $message = "写入 settings.json 失败"
                            }
                        } else {
                            $message = "未找到 Windows Terminal 配置文件"
                        }
                    }
                    default {
                        $message = "未知的修复 ID: $FixId"
                    }
                }
            }

            "PSProfile" {
                switch ($FixId) {
                    "create_psprofile" {
                        $result = Apply-PSProfile
                        if ($result.Success) {
                            $fixed = $true
                            $message = $result.Message
                        } else {
                            $message = $result.Message
                        }
                    }
                    "add_omp_init_profile" {
                        $result = Apply-PSProfile
                        if ($result.Success) {
                            $fixed = $true
                            $message = $result.Message
                        } else {
                            $message = $result.Message
                        }
                    }
                    "repair_psprofile" {
                        $profilePaths = @(
                            (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
                            (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
                        )
                        foreach ($pp in $profilePaths) {
                            if (Test-Path $pp) {
                                Backup-ConfigFile -Path $pp
                            }
                        }
                        $result = Apply-PSProfile
                        if ($result.Success) {
                            $fixed = $true
                            $message = "Profile 已重建: $($result.Message)"
                        } else {
                            $message = $result.Message
                        }
                    }
                    "repair_psprofile_syntax" {
                        $profilePaths = @(
                            (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
                            (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
                        )
                        foreach ($pp in $profilePaths) {
                            if (Test-Path $pp) {
                                Backup-ConfigFile -Path $pp
                            }
                        }
                        $result = Apply-PSProfile
                        if ($result.Success) {
                            $fixed = $true
                            $message = "Profile 语法错误已修复"
                        } else {
                            $message = $result.Message
                        }
                    }
                    "add_psreadline" {
                        $profilePaths = @(
                            (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
                            (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
                        )
                        $added = $false
                        foreach ($pp in $profilePaths) {
                            if (Test-Path $pp) {
                                Backup-ConfigFile -Path $pp
                                $psreadlineBlock = @"

# PSReadLine Configuration
Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView
Set-PSReadLineKeyHandler -Chord Tab -Function MenuComplete
"@
                                Add-Content -Path $pp -Value $psreadlineBlock -Encoding UTF8
                                $added = $true
                                break
                            }
                        }
                        if ($added) {
                            $fixed = $true
                            $message = "PSReadLine 配置已添加"
                        } else {
                            $message = "未找到可修改的 Profile 文件"
                        }
                    }
                    default {
                        $message = "未知的修复 ID: $FixId"
                    }
                }
            }

            "StatusBar" {
                switch ($FixId) {
                    "install_statusline_script" {
                        $result = Install-StatusLine
                        if ($result.Success) {
                            $fixed = $true
                            $message = $result.Message
                        } else {
                            $message = $result.Message
                        }
                    }
                    "repair_statusline_settings" {
                        $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
                        if (Test-Path $settingsPath) {
                            Backup-ConfigFile -Path $settingsPath
                        }
                        $result = Install-StatusLine
                        if ($result.Success) {
                            $fixed = $true
                            $message = "statusline 配置已修复"
                        } else {
                            $message = $result.Message
                        }
                    }
                    "add_statusline_settings" {
                        $result = Install-StatusLine
                        if ($result.Success) {
                            $fixed = $true
                            $message = "statusline 配置已添加"
                        } else {
                            $message = $result.Message
                        }
                    }
                    "create_statusline_settings" {
                        $result = Install-StatusLine
                        if ($result.Success) {
                            $fixed = $true
                            $message = "settings.json 已创建并配置 statusline"
                        } else {
                            $message = $result.Message
                        }
                    }
                    default {
                        $message = "未知的修复 ID: $FixId"
                    }
                }
            }
        }

        # Refresh component status after repair
        Update-ComponentStatus

        return @{
            Success    = $fixed
            Message    = if ($message) { $message } else { "修复完成" }
            BackupPath = $backupPath
            Component  = $ComponentName
            FixId      = $FixId
        }
    }
    catch {
        Write-AppLog "Repair-Component failed: $_" -Level Error
        return @{
            Success    = $false
            Message    = "修复失败: $_"
            BackupPath = $backupPath
            Component  = $ComponentName
            FixId      = $FixId
        }
    }
}

# ---------------------------------------------------------------------------
# 8. Get-SystemDiagnostics — full system diagnostic summary
# ---------------------------------------------------------------------------

function Get-SystemDiagnostics {
    [CmdletBinding()]
    param()

    Write-AppLog "Get-SystemDiagnostics: running full system scan..."

    # First update component status
    Update-ComponentStatus

    # Run health checks on all components
    $allResults = Test-ComponentHealth -ComponentName "All"

    $totalChecks  = 0
    $passed       = 0
    $warnings     = 0
    $errors       = 0
    $fixesTotal   = 0
    $healthyCount = 0
    $unhealthyCount = 0

    $componentSummaries = @{}

    foreach ($compKey in $allResults.Keys) {
        $health = $allResults[$compKey]
        $compChecks = 0
        $compPass   = 0
        $compWarn   = 0
        $compFail   = 0

        foreach ($check in $health.Checks) {
            $compChecks++
            switch ($check.Status) {
                "Pass" { $compPass++ }
                "Warn" { $compWarn++ }
                "Fail" { $compFail++ }
            }
        }

        $totalChecks += $compChecks
        $passed      += $compPass
        $warnings    += $compWarn
        $errors      += $compFail
        $fixesTotal  += $health.Fixes.Count

        if ($health.Healthy) { $healthyCount++ } else { $unhealthyCount++ }

        # Determine overall status: Healthy / Warning / Critical
        $status = "Healthy"
        if ($compFail -gt 0) { $status = "Critical" }
        elseif ($compWarn -gt 0) { $status = "Warning" }

        $componentSummaries[$compKey] = @{
            Name       = $compKey
            Healthy    = $health.Healthy
            Status     = $status
            Checks     = $compChecks
            Passed     = $compPass
            Warnings   = $compWarn
            Failed     = $compFail
            FixCount   = $health.Fixes.Count
            Detail     = $health
        }
    }

    $overallStatus = "Healthy"
    if ($errors -gt 0) { $overallStatus = "Critical" }
    elseif ($warnings -gt 0) { $overallStatus = "Warning" }

    $report = @{
        OverallStatus   = $overallStatus
        TotalChecks     = $totalChecks
        Passed          = $passed
        Warnings        = $warnings
        Errors          = $errors
        TotalFixes      = $fixesTotal
        HealthyCount    = $healthyCount
        UnhealthyCount  = $unhealthyCount
        Components      = $componentSummaries
        Timestamp       = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    }

    Write-AppLog "Get-SystemDiagnostics: Status=$overallStatus, Checks=$totalChecks, Pass=$passed, Warn=$warnings, Err=$errors, Fixes=$fixesTotal"
    return $report
}

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

# [Removed] Export-ModuleMember
