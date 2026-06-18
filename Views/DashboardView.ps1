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
}
