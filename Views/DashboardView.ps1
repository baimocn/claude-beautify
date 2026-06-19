# Module-level ref for event handlers
$script:DashboardViewElement = $null

function Initialize-DashboardView {
    param($ViewElement)

    $script:DashboardViewElement = $ViewElement

    # Run detection
    Update-ComponentStatus

    $data = Get-AppData
    $components = $data.Components

    # Update summary
    $installed = ($components.Values | Where-Object { $_.Installed }).Count
    $total = $components.Count
    $ViewElement.FindName("SummarySubtitle").Text = "已安装 $installed / $total 个组件"

    # Card mapping
    $cardMap = @{
        "OhMyPosh"    = @{ Badge="StatusBadgeOhMyPosh";    Version="VersionOhMyPosh";    Btn="BtnOhMyPosh" }
        "NerdFont"    = @{ Badge="StatusBadgeNerdFont";    Version="VersionNerdFont";    Btn="BtnNerdFont" }
        "WinTerminal" = @{ Badge="StatusBadgeWinTerminal"; Version="VersionWinTerminal"; Btn="BtnWinTerminal" }
        "WTConfig"    = @{ Badge="StatusBadgeWTConfig";    Version="VersionWTConfig";    Btn="BtnWTConfig" }
        "PSProfile"   = @{ Badge="StatusBadgePSProfile";   Version="VersionPSProfile";   Btn="BtnPSProfile" }
        "StatusLine"  = @{ Badge="StatusBadgeStatusLine";  Version="VersionStatusLine";  Btn="BtnStatusLine" }
    }

    foreach ($entry in $cardMap.GetEnumerator()) {
        $compKey = $entry.Key
        $comp = $components[$compKey]
        $names = $entry.Value

        $badge = $ViewElement.FindName($names.Badge)
        $ver = $ViewElement.FindName($names.Version)
        $btn = $ViewElement.FindName($names.Btn)

        if ($comp.Installed) {
            $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E8F5E9")
            $badge.Child.Text = "已安装"
            $badge.Child.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5A8F5A")
            $btn.Content = "卸载"
            $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#C45454")
        } else {
            $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F5F5F5")
            $badge.Child.Text = "未安装"
            $badge.Child.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7A7067")
            $btn.Content = "安装"
            $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5A8F5A")
        }
        $btn.Foreground = [System.Windows.Media.Brushes]::White
        $btn.BorderThickness = [System.Windows.Thickness]::new(0)
        $btn.Padding = [System.Windows.Thickness]::new(12,4,12,4)
        $btn.FontSize = 11

        if ($comp.Version) {
            $ver.Text = "v$($comp.Version)"
        }

        # Wire click handler - async with runspace
        $key = $compKey
        $isInstalled = $comp.Installed
        $scriptRoot = $script:ScriptRoot
        $btn.Add_Click({
            param($sender, $e)
            try {
                $b = $sender
                if ($isInstalled) { $fn = "Uninstall-$key" } else { $fn = "Install-$key" }

                if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
                    [System.Windows.MessageBox]::Show("功能暂未实现: $fn", "提示", "OK", "Information")
                    return
                }

                $actionLabel = if ($isInstalled) { "卸载" } else { "安装" }
                $confirm = [System.Windows.MessageBox]::Show("确定要${actionLabel} $($key) 吗？", "确认操作", "YesNo", "Question")
                if ($confirm -ne "Yes") { return }

                # Disable button and show loading
                $origContent = $b.Content
                $origBg = $b.Background
                $b.Content = "请稍候..."
                $b.IsEnabled = $false
                $b.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#999999")

                # Create background runspace
                $rs = [runspacefactory]::CreateRunspace()
                $rs.Open()
                $ps = [powershell]::Create()
                $ps.Runspace = $rs
                $ps.AddScript({
                    param($scriptRoot, $fnName)
                    $ErrorActionPreference = "Stop"
                    Import-Module (Join-Path $scriptRoot "Modules\Utils.psm1") -Force -DisableNameChecking
                    Import-Module (Join-Path $scriptRoot "Modules\State.psm1") -Force -DisableNameChecking
                    Import-Module (Join-Path $scriptRoot "Modules\Detection.psm1") -Force -DisableNameChecking
                    Import-Module (Join-Path $scriptRoot "Modules\Actions.psm1") -Force -DisableNameChecking
                    Import-Module (Join-Path $scriptRoot "Modules\Preview.psm1") -Force -DisableNameChecking
                    Import-Module (Join-Path $scriptRoot "Modules\Profiles.psm1") -Force -DisableNameChecking
                    & $fnName
                }).AddArgument($scriptRoot).AddArgument($fn)

                $job = $ps.BeginInvoke()

                # Poll with DispatcherTimer
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromMilliseconds(500)
                $timer.Tag = @{ Job=$job; PS=$ps; RS=$rs; Btn=$b; OrigContent=$origContent; OrigBg=$origBg }
                $timer.Add_Tick({
                    param($tSender, $tArgs)
                    $t = $tSender
                    $info = $t.Tag
                    if ($info.Job.IsCompleted) {
                        $t.Stop()
                        try {
                            $r = $info.PS.EndInvoke($info.Job)
                            if ($r -and $r.Success) {
                                [System.Windows.MessageBox]::Show($r.Message, "完成", "OK", "Information")
                            } elseif ($r) {
                                [System.Windows.MessageBox]::Show($r.Message, "失败", "OK", "Warning")
                            } else {
                                [System.Windows.MessageBox]::Show("操作已完成（无返回结果）", "完成", "OK", "Information")
                            }
                        } catch {
                            [System.Windows.MessageBox]::Show("操作失败: $($_.Exception.Message)", "错误", "OK", "Error")
                        } finally {
                            $info.PS.Dispose()
                            $info.RS.Close()
                            $info.RS.Dispose()
                            # Re-enable button
                            $info.Btn.Content = $info.OrigContent
                            $info.Btn.Background = $info.OrigBg
                            $info.Btn.IsEnabled = $true
                            # Refresh dashboard
                            Initialize-DashboardView -ViewElement $script:DashboardViewElement
                        }
                    }
                })
                $timer.Start()
            } catch {
                $btn.Content = $origContent
                $btn.IsEnabled = $true
                $btn.Background = $origBg
                [System.Windows.MessageBox]::Show("操作失败: $($_.Exception.Message)", "错误", "OK", "Error")
            }
        })
    }

    # Refresh button
    $ViewElement.FindName("BtnRefresh").Add_Click({
        Initialize-DashboardView -ViewElement $script:DashboardViewElement
    })

    # Health check button
    $ViewElement.FindName("BtnHealthCheck").Add_Click({
        try {
            $btn = $ViewElement.FindName("BtnHealthCheck")
            $btn.Content = "检查中..."
            $btn.IsEnabled = $false

            $scriptRoot = $script:ScriptRoot

            # Run health check in background runspace
            $rs = [runspacefactory]::CreateRunspace()
            $rs.Open()
            $ps = [powershell]::Create()
            $ps.Runspace = $rs
            $ps.AddScript({
                param($scriptRoot)
                $ErrorActionPreference = "Stop"
                Import-Module (Join-Path $scriptRoot "Modules\Utils.psm1") -Force -DisableNameChecking
                Import-Module (Join-Path $scriptRoot "Modules\State.psm1") -Force -DisableNameChecking
                Import-Module (Join-Path $scriptRoot "Modules\Constants.psm1") -Force -DisableNameChecking
                Import-Module (Join-Path $scriptRoot "Modules\Detection.psm1") -Force -DisableNameChecking
                Import-Module (Join-Path $scriptRoot "Modules\Actions.psm1") -Force -DisableNameChecking
                Import-Module (Join-Path $scriptRoot "Modules\HealthCheck.psm1") -Force -DisableNameChecking
                Get-SystemDiagnostics
            }).AddArgument($scriptRoot)

            $job = $ps.BeginInvoke()

            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(800)
            $timer.Tag = @{ Job=$job; PS=$ps; RS=$rs; Btn=$btn; View=$ViewElement }
            $timer.Add_Tick({
                param($tSender, $tArgs)
                $t = $tSender
                $info = $t.Tag
                if ($info.Job.IsCompleted) {
                    $t.Stop()
                    try {
                        $result = $info.PS.EndInvoke($info.Job)
                        Update-DashboardHealth -ViewElement $info.View -Diagnostics $result
                    } catch {
                        [System.Windows.MessageBox]::Show("健康检查失败: $($_.Exception.Message)", "错误", "OK", "Error")
                    } finally {
                        $info.PS.Dispose()
                        $info.RS.Close()
                        $info.RS.Dispose()
                        $info.Btn.Content = "运行健康检查"
                        $info.Btn.IsEnabled = $true
                    }
                }
            })
            $timer.Start()
        } catch {
            [System.Windows.MessageBox]::Show("健康检查启动失败: $($_.Exception.Message)", "错误", "OK", "Error")
            $ViewElement.FindName("BtnHealthCheck").Content = "运行健康检查"
            $ViewElement.FindName("BtnHealthCheck").IsEnabled = $true
        }
    })

    # Fix button
    $ViewElement.FindName("BtnFixSelected").Add_Click({
        Invoke-SelectedHealthFix -ViewElement $script:DashboardViewElement
    })
}

# ---------------------------------------------------------------------------
# Update dashboard health display with diagnostic results
# ---------------------------------------------------------------------------

function Update-DashboardHealth {
    param(
        $ViewElement,
        $Diagnostics
    )

    if ($null -eq $Diagnostics -or -not $Diagnostics.OverallStatus) {
        return
    }

    $badge = $ViewElement.FindName("HealthOverallBadge")
    $statusText = $ViewElement.FindName("HealthOverallText")
    $subtitle = $ViewElement.FindName("HealthSubtitle")
    $detailPanel = $ViewElement.FindName("HealthDetailPanel")

    # Set overall status badge color
    $brushConverter = New-Object System.Windows.Media.BrushConverter
    switch ($Diagnostics.OverallStatus) {
        "Healthy" {
            $badge.Background = $brushConverter.ConvertFromString("#E8F5E9")
            $statusText.Text = "健康"
            $statusText.Foreground = $brushConverter.ConvertFromString("#5A8F5A")
        }
        "Warning" {
            $badge.Background = $brushConverter.ConvertFromString("#FFF8E1")
            $statusText.Text = "有警告"
            $statusText.Foreground = $brushConverter.ConvertFromString("#D97757")
        }
        "Critical" {
            $badge.Background = $brushConverter.ConvertFromString("#FFEBEE")
            $statusText.Text = "需修复"
            $statusText.Foreground = $brushConverter.ConvertFromString("#C45454")
        }
    }

    $subtitle.Text = "共 $($Diagnostics.TotalChecks) 项检查 | 通过 $($Diagnostics.Passed) | 警告 $($Diagnostics.Warnings) | 错误 $($Diagnostics.Errors)"

    # Show detail panel
    $detailPanel.Visibility = [System.Windows.Visibility]::Visible

    # Build component chips
    $chipsPanel = $ViewElement.FindName("HealthChipsPanel")
    $chipsPanel.Children.Clear()

    $compLabels = @{
        "OhMyPosh"       = "Oh My Posh"
        "NerdFont"       = "Nerd Font"
        "WindowsTerminal" = "Windows Terminal"
        "PSProfile"      = "PowerShell Profile"
        "StatusBar"      = "状态栏"
    }

    foreach ($compKey in $Diagnostics.Components.Keys) {
        $comp = $Diagnostics.Components[$compKey]
        $label = if ($compLabels.ContainsKey($compKey)) { $compLabels[$compKey] } else { $compKey }

        $chipBorder = New-Object System.Windows.Controls.Border
        $chipBorder.CornerRadius = New-Object System.Windows.CornerRadius(10)
        $chipBorder.Padding = New-Object System.Windows.Thickness(12, 5)
        $chipBorder.Margin = New-Object System.Windows.Thickness(0, 0, 8, 4)
        $chipBorder.Cursor = [System.Windows.Input.Cursors]::Hand

        switch ($comp.Status) {
            "Healthy"  { $chipBorder.Background = $brushConverter.ConvertFromString("#E8F5E9") }
            "Warning"  { $chipBorder.Background = $brushConverter.ConvertFromString("#FFF8E1") }
            "Critical" { $chipBorder.Background = $brushConverter.ConvertFromString("#FFEBEE") }
            default    { $chipBorder.Background = $brushConverter.ConvertFromString("#F5F5F5") }
        }

        $chipText = New-Object System.Windows.Controls.TextBlock
        $chipText.Text = "$label · $($comp.Passed)/$($comp.Checks) 通过"
        $chipText.FontSize = 11

        switch ($comp.Status) {
            "Healthy"  { $chipText.Foreground = $brushConverter.ConvertFromString("#5A8F5A") }
            "Warning"  { $chipText.Foreground = $brushConverter.ConvertFromString("#D97757") }
            "Critical" { $chipText.Foreground = $brushConverter.ConvertFromString("#C45454") }
            default    { $chipText.Foreground = $brushConverter.ConvertFromString("#7A7067") }
        }

        $chipBorder.Child = $chipText

        # Click handler to show detail
        $compDetail = $comp
        $compName = $compKey
        $chipBorder.Add_MouseLeftButtonUp({
            param($s, $e)
            Show-HealthComponentDetail -ViewElement $ViewElement -ComponentKey $compName -ComponentData $compDetail
        }.GetNewClosure())

        $chipsPanel.Children.Add($chipBorder)
    }
}

# ---------------------------------------------------------------------------
# Show detail for a specific component in the health check panel
# ---------------------------------------------------------------------------

function Show-HealthComponentDetail {
    param(
        $ViewElement,
        [string]$ComponentKey,
        $ComponentData
    )

    $detailTitle = $ViewElement.FindName("HealthDetailTitle")
    $detailContent = $ViewElement.FindName("HealthDetailContent")
    $fixPanel = $ViewElement.FindName("HealthFixPanel")

    if (-not $ComponentData -or -not $ComponentData.Detail) {
        $detailTitle.Text = $ComponentKey
        $detailContent.Text = "暂无详细数据"
        $fixPanel.Visibility = [System.Windows.Visibility]::Collapsed
        return
    }

    $detail = $ComponentData.Detail

    $statusLabel = switch ($ComponentData.Status) {
        "Healthy"  { "状态: 健康" }
        "Warning"  { "状态: 警告" }
        "Critical" { "状态: 需修复" }
        default    { "状态: 未知" }
    }

    $detailTitle.Text = "$ComponentKey — $statusLabel"

    # Build check items text
    $checkLines = @()
    foreach ($check in $detail.Checks) {
        $icon = switch ($check.Status) {
            "Pass" { "[OK]" }
            "Warn" { "[!]" }
            "Fail" { "[X]" }
            "Info" { "[i]" }
            default { "[?]" }
        }
        $line = "$icon $($check.Name): $($check.Detail)"
        $checkLines += $line
    }

    # Add warnings if any
    if ($detail.Warnings.Count -gt 0) {
        $checkLines += ""
        $checkLines += "警告:"
        foreach ($w in $detail.Warnings) {
            $checkLines += "  [!] $w"
        }
    }

    # Add available fixes
    if ($detail.Fixes.Count -gt 0) {
        $checkLines += ""
        $checkLines += "可用修复:"
        foreach ($f in $detail.Fixes) {
            $checkLines += "  [FIX] $($f.Name) — $($f.Description)"
        }
        $fixPanel.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $fixPanel.Visibility = [System.Windows.Visibility]::Collapsed
    }

    $detailContent.Text = $checkLines -join "`r`n"

    # Store selected component for fix button
    $script:SelectedHealthComponent = $ComponentKey
    $script:SelectedHealthFixes = $detail.Fixes
}

# ---------------------------------------------------------------------------
# Run repair for the currently selected health component (first fix)
# ---------------------------------------------------------------------------

function Invoke-SelectedHealthFix {
    param($ViewElement)

    $compKey = $script:SelectedHealthComponent
    $fixes = $script:SelectedHealthFixes

    if (-not $compKey -or -not $fixes -or $fixes.Count -eq 0) {
        [System.Windows.MessageBox]::Show("请先选择一个有问题的组件", "提示", "OK", "Information")
        return
    }

    # Use the first available fix
    $firstFix = $fixes[0]
    $confirm = [System.Windows.MessageBox]::Show(
        "确定要执行修复 ""$($firstFix.Name)"" 吗？`n$($firstFix.Description)",
        "确认修复",
        "YesNo",
        "Question"
    )
    if ($confirm -ne "Yes") { return }

    $btn = $ViewElement.FindName("BtnFixSelected")
    $origContent = $btn.Content
    $btn.Content = "修复中..."
    $btn.IsEnabled = $false

    $scriptRoot = $script:ScriptRoot
    $fixId = $firstFix.Id

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript({
        param($scriptRoot, $compName, $fixId)
        $ErrorActionPreference = "Stop"
        Import-Module (Join-Path $scriptRoot "Modules\Utils.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $scriptRoot "Modules\State.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $scriptRoot "Modules\Constants.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $scriptRoot "Modules\Detection.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $scriptRoot "Modules\Actions.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $scriptRoot "Modules\HealthCheck.psm1") -Force -DisableNameChecking
        Repair-Component -ComponentName $compName -FixId $fixId
    }).AddArgument($scriptRoot).AddArgument($compKey).AddArgument($fixId)

    $job = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(800)
    $timer.Tag = @{ Job=$job; PS=$ps; RS=$rs; Btn=$btn; OrigContent=$origContent; View=$ViewElement; Comp=$compKey }
    $timer.Add_Tick({
        param($tSender, $tArgs)
        $t = $tSender
        $info = $t.Tag
        if ($info.Job.IsCompleted) {
            $t.Stop()
            try {
                $r = $info.PS.EndInvoke($info.Job)
                if ($r -and $r.Success) {
                    [System.Windows.MessageBox]::Show($r.Message, "修复完成", "OK", "Information")
                } elseif ($r) {
                    [System.Windows.MessageBox]::Show($r.Message, "修复失败", "OK", "Warning")
                } else {
                    [System.Windows.MessageBox]::Show("修复操作完成", "完成", "OK", "Information")
                }
                # Refresh health check
                $script:SelectedHealthComponent = $null
                $script:SelectedHealthFixes = $null
                Update-DashboardHealthRefresh -ViewElement $info.View
            } catch {
                [System.Windows.MessageBox]::Show("修复失败: $($_.Exception.Message)", "错误", "OK", "Error")
            } finally {
                $info.PS.Dispose()
                $info.RS.Close()
                $info.RS.Dispose()
                $info.Btn.Content = $info.OrigContent
                $info.Btn.IsEnabled = $true
                Initialize-DashboardView -ViewElement $script:DashboardViewElement
            }
        }
    })
    $timer.Start()
}

# Helper: re-run health check after a fix
function Update-DashboardHealthRefresh {
    param($ViewElement)

    $scriptRoot = $script:ScriptRoot
    $btn = $ViewElement.FindName("BtnHealthCheck")
    $btn.Content = "重新检查中..."
    $btn.IsEnabled = $false

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript({
        param($scriptRoot)
        $ErrorActionPreference = "Stop"
        Import-Module (Join-Path $scriptRoot "Modules\Utils.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $scriptRoot "Modules\State.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $scriptRoot "Modules\Constants.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $scriptRoot "Modules\Detection.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $scriptRoot "Modules\Actions.psm1") -Force -DisableNameChecking
        Import-Module (Join-Path $scriptRoot "Modules\HealthCheck.psm1") -Force -DisableNameChecking
        Get-SystemDiagnostics
    }).AddArgument($scriptRoot)

    $job = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(800)
    $timer.Tag = @{ Job=$job; PS=$ps; RS=$rs; Btn=$btn; View=$ViewElement }
    $timer.Add_Tick({
        param($tSender, $tArgs)
        $t = $tSender
        $info = $t.Tag
        if ($info.Job.IsCompleted) {
            $t.Stop()
            try {
                $result = $info.PS.EndInvoke($info.Job)
                Update-DashboardHealth -ViewElement $info.View -Diagnostics $result
            } catch {
                # Silent fail on refresh
            } finally {
                $info.PS.Dispose()
                $info.RS.Close()
                $info.RS.Dispose()
                $info.Btn.Content = "运行健康检查"
                $info.Btn.IsEnabled = $true
            }
        }
    })
    $timer.Start()
}
