# Module-level ref for event handlers
$script:ComponentsViewElement = $null
$script:ComponentsMap = $null

function Initialize-ComponentsView {
    param($ViewElement)

    $script:ComponentsViewElement = $ViewElement

    # Run detection
    Update-ComponentStatus
    $components = Get-Components

    # Mapping
    $script:ComponentsMap = @{
        "OhMyPosh"    = @{ Chk="ChkOhMyPosh";    Badge="BadgeOhMyPosh";    BadgeText="BadgeTextOhMyPosh" }
        "NerdFont"    = @{ Chk="ChkNerdFont";    Badge="BadgeNerdFont";    BadgeText="BadgeTextNerdFont" }
        "WinTerminal" = @{ Chk="ChkWinTerminal";  Badge="BadgeWinTerminal"; BadgeText="BadgeTextWinTerminal" }
        "WTConfig"    = @{ Chk="ChkWTConfig";     Badge="BadgeWTConfig";    BadgeText="BadgeTextWTConfig" }
        "PSProfile"   = @{ Chk="ChkPSProfile";    Badge="BadgePSProfile";   BadgeText="BadgeTextPSProfile" }
        "StatusLine"  = @{ Chk="ChkStatusLine";   Badge="BadgeStatusLine";  BadgeText="BadgeTextStatusLine" }
    }

    # Set initial checkbox and badge states
    foreach ($entry in $script:ComponentsMap.GetEnumerator()) {
        $comp = $components[$entry.Key]
        $names = $entry.Value

        $chk = $ViewElement.FindName($names.Chk)
        $badge = $ViewElement.FindName($names.Badge)
        $badgeText = $ViewElement.FindName($names.BadgeText)

        if ($comp.Installed) {
            $chk.IsChecked = $true
            $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E8F5E9")
            $badgeText.Text = "已安装"
            $badgeText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5A8F5A")
        } else {
            $chk.IsChecked = $false
            $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F5F5F5")
            $badgeText.Text = "未安装"
            $badgeText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7A7067")
        }
    }

    # Update summary helper
    $updateSummary = {
        try {
            $count = 0
            foreach ($entry in $script:ComponentsMap.GetEnumerator()) {
                $chk = $script:ComponentsViewElement.FindName($entry.Value.Chk)
                if ($chk.IsChecked) { $count++ }
            }
            $script:ComponentsViewElement.FindName("SelectionSummary").Text = "已选择 $count 项"
        } catch {}
    }

    # Wire checkbox events
    foreach ($entry in $script:ComponentsMap.GetEnumerator()) {
        $script:ComponentsViewElement.FindName($entry.Value.Chk).Add_Checked($updateSummary)
        $script:ComponentsViewElement.FindName($entry.Value.Chk).Add_Unchecked($updateSummary)
    }

    # Select All button
    $ViewElement.FindName("BtnSelectAll").Add_Click({
        try {
            foreach ($entry in $script:ComponentsMap.GetEnumerator()) {
                $script:ComponentsViewElement.FindName($entry.Value.Chk).IsChecked = $true
            }
        } catch {}
    })

    # Apply button - async with runspace
    $ViewElement.FindName("BtnApply").Add_Click({
        param($sender, $e)
        try {
            $btn = $sender
            $scriptRoot = $script:ScriptRoot

            # Build the operation list first (on UI thread, fast)
            $ops = @()
            $comps = Get-Components
            foreach ($entry in $script:ComponentsMap.GetEnumerator()) {
                $comp = $comps[$entry.Key]
                $chk = $script:ComponentsViewElement.FindName($entry.Value.Chk)
                $wantInstalled = $chk.IsChecked
                $isInstalled = $comp.Installed

                if ($wantInstalled -and -not $isInstalled) {
                    $fn = "Install-$($entry.Key)"
                    if (Get-Command $fn -ErrorAction SilentlyContinue) {
                        $ops += $fn
                    }
                } elseif (-not $wantInstalled -and $isInstalled) {
                    $fn = "Uninstall-$($entry.Key)"
                    if (Get-Command $fn -ErrorAction SilentlyContinue) {
                        $ops += $fn
                    }
                }
            }

            if ($ops.Count -eq 0) {
                [System.Windows.MessageBox]::Show("没有需要操作的组件", "提示", "OK", "Information")
                return
            }

            # Disable button and show loading
            $origContent = $btn.Content
            $origBg = $btn.Background
            $btn.Content = "请稍候..."
            $btn.IsEnabled = $false
            $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#999999")

            # Create background runspace
            $rs = [runspacefactory]::CreateRunspace()
            $rs.Open()
            $ps = [powershell]::Create()
            $ps.Runspace = $rs
            $ps.AddScript({
                param($scriptRoot, $opList)
                $ErrorActionPreference = "Stop"
                Import-Module (Join-Path $scriptRoot "Modules\Utils.psm1") -Force -DisableNameChecking
                Import-Module (Join-Path $scriptRoot "Modules\State.psm1") -Force -DisableNameChecking
                Import-Module (Join-Path $scriptRoot "Modules\Detection.psm1") -Force -DisableNameChecking
                Import-Module (Join-Path $scriptRoot "Modules\Actions.psm1") -Force -DisableNameChecking
                Import-Module (Join-Path $scriptRoot "Modules\Preview.psm1") -Force -DisableNameChecking
                Import-Module (Join-Path $scriptRoot "Modules\Profiles.psm1") -Force -DisableNameChecking

                $results = @()
                foreach ($fnName in $opList) {
                    $r = & $fnName
                    $results += $r
                }
                Update-ComponentStatus
                $results
            }).AddArgument($scriptRoot).AddArgument($ops)

            $job = $ps.BeginInvoke()

            # Poll with DispatcherTimer
            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(500)
            $timer.Tag = @{ Job=$job; PS=$ps; RS=$rs; Btn=$btn; OrigContent=$origContent; OrigBg=$origBg }
            $timer.Add_Tick({
                param($tSender, $tArgs)
                $t = $tSender
                $info = $t.Tag
                if ($info.Job.IsCompleted) {
                    $t.Stop()
                    try {
                        $results = $info.PS.EndInvoke($info.Job)
                        if ($results) {
                            $successCount = ($results | Where-Object { $_.Success }).Count
                            $failCount = ($results | Where-Object { -not $_.Success }).Count
                            $msg = "操作完成: $successCount 成功"
                            if ($failCount -gt 0) { $msg += ", $failCount 失败" }
                        } else {
                            $msg = "操作已完成（无返回结果）"
                        }
                        [System.Windows.MessageBox]::Show($msg, "提示", "OK", "Information")
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
                        # Refresh view
                        Initialize-ComponentsView -ViewElement $script:ComponentsViewElement
                    }
                }
            })
            $timer.Start()
        } catch {
            [System.Windows.MessageBox]::Show("操作失败: $($_.Exception.Message)", "错误", "OK", "Error")
        }
    })

    # Initial summary
    & $updateSummary
}
