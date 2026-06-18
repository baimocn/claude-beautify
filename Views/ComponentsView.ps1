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

    # Apply button
    $ViewElement.FindName("BtnApply").Add_Click({
        try {
            $results = @()
            $comps = Get-Components
            foreach ($entry in $script:ComponentsMap.GetEnumerator()) {
                $comp = $comps[$entry.Key]
                $chk = $script:ComponentsViewElement.FindName($entry.Value.Chk)
                $wantInstalled = $chk.IsChecked
                $isInstalled = $comp.Installed

                if ($wantInstalled -and -not $isInstalled) {
                    $fn = "Install-$($entry.Key)"
                    if (Get-Command $fn -ErrorAction SilentlyContinue) {
                        $r = & $fn
                        $results += $r
                    }
                } elseif (-not $wantInstalled -and $isInstalled) {
                    $fn = "Uninstall-$($entry.Key)"
                    if (Get-Command $fn -ErrorAction SilentlyContinue) {
                        $r = & $fn
                        $results += $r
                    }
                }
            }

            Update-ComponentStatus

            $successCount = ($results | Where-Object { $_.Success }).Count
            $failCount = ($results | Where-Object { -not $_.Success }).Count
            $msg = "操作完成: $successCount 成功"
            if ($failCount -gt 0) { $msg += ", $failCount 失败" }
            [System.Windows.MessageBox]::Show($msg, "提示", "OK", "Information")

            # Refresh view
            Initialize-ComponentsView -ViewElement $script:ComponentsViewElement
        } catch {
            [System.Windows.MessageBox]::Show("操作失败: $($_.Exception.Message)", "错误", "OK", "Error")
        }
    })

    # Initial summary
    & $updateSummary
}
