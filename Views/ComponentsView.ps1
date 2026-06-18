function Initialize-ComponentsView {
    param($ViewElement)

    # Run detection
    Update-ComponentStatus
    $components = Get-Components

    # Mapping: component key -> UI element names
    $map = @{
        "OhMyPosh"    = @{ Chk="ChkOhMyPosh";    Badge="BadgeOhMyPosh";    BadgeText="BadgeTextOhMyPosh" }
        "NerdFont"    = @{ Chk="ChkNerdFont";    Badge="BadgeNerdFont";    BadgeText="BadgeTextNerdFont" }
        "WinTerminal" = @{ Chk="ChkWinTerminal";  Badge="BadgeWinTerminal"; BadgeText="BadgeTextWinTerminal" }
        "WTConfig"    = @{ Chk="ChkWTConfig";     Badge="BadgeWTConfig";    BadgeText="BadgeTextWTConfig" }
        "PSProfile"   = @{ Chk="ChkPSProfile";    Badge="BadgePSProfile";   BadgeText="BadgeTextPSProfile" }
        "StatusLine"  = @{ Chk="ChkStatusLine";   Badge="BadgeStatusLine";  BadgeText="BadgeTextStatusLine" }
    }

    # Set initial checkbox and badge states
    foreach ($entry in $map.GetEnumerator()) {
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

    # Update selection summary
    $updateSummary = {
        $count = 0
        foreach ($entry in $map.GetEnumerator()) {
            $chk = $ViewElement.FindName($entry.Value.Chk)
            if ($chk.IsChecked) { $count++ }
        }
        $ViewElement.FindName("SelectionSummary").Text = "已选择 $count 项"
    }

    # Wire checkbox change events
    foreach ($entry in $map.GetEnumerator()) {
        $chk = $ViewElement.FindName($entry.Value.Chk)
        $chk.Add_Checked($updateSummary)
        $chk.Add_Unchecked($updateSummary)
    }

    # Select All button
    $ViewElement.FindName("BtnSelectAll").Add_Click({
        foreach ($entry in $map.GetEnumerator()) {
            $ViewElement.FindName($entry.Value.Chk).IsChecked = $true
        }
    })

    # Apply button
    $ViewElement.FindName("BtnApply").Add_Click({
        $results = @()
        foreach ($entry in $map.GetEnumerator()) {
            $comp = $components[$entry.Key]
            $chk = $ViewElement.FindName($entry.Value.Chk)
            $wantInstalled = $chk.IsChecked
            $isInstalled = $comp.Installed

            if ($wantInstalled -and -not $isInstalled) {
                # Need to install
                $fn = "Install-$($entry.Key)"
                if (Get-Command $fn -ErrorAction SilentlyContinue) {
                    $r = & $fn
                    $results += $r
                }
            } elseif (-not $wantInstalled -and $isInstalled) {
                # Need to uninstall
                $fn = "Uninstall-$($entry.Key)"
                if (Get-Command $fn -ErrorAction SilentlyContinue) {
                    $r = & $fn
                    $results += $r
                }
            }
        }

        # Refresh the view
        Update-ComponentStatus

        $successCount = ($results | Where-Object { $_.Success }).Count
        $failCount = ($results | Where-Object { -not $_.Success }).Count
        $msg = "操作完成: $successCount 成功"
        if ($failCount -gt 0) { $msg += ", $failCount 失败" }
        [System.Windows.MessageBox]::Show($msg, "提示", "OK", "Information")

        # Re-initialize view to refresh badges
        Initialize-ComponentsView -ViewElement $ViewElement
    })

    # Call initial summary update
    & $updateSummary
}
