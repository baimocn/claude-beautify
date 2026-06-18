function Initialize-DashboardView {
    param($ViewElement)

    # Run detection (modules already imported by entry point)
    Update-ComponentStatus

    $data = Get-AppData
    $components = $data.Components

    # Update summary
    $installed = ($components.Values | Where-Object { $_.Installed }).Count
    $total = $components.Count
    $ViewElement.FindName("SummarySubtitle").Text = "已安装 $installed / $total 个组件"

    # Card mapping: component key -> UI element names
    $cardMap = @{
        "OhMyPosh"    = @{ Card="CardOhMyPosh";    Badge="StatusBadgeOhMyPosh";    Version="VersionOhMyPosh";    Btn="BtnOhMyPosh" }
        "NerdFont"    = @{ Card="CardNerdFont";    Badge="StatusBadgeNerdFont";    Version="VersionNerdFont";    Btn="BtnNerdFont" }
        "WinTerminal" = @{ Card="CardWinTerminal";  Badge="StatusBadgeWinTerminal"; Version="VersionWinTerminal"; Btn="BtnWinTerminal" }
        "WTConfig"    = @{ Card="CardWTConfig";     Badge="StatusBadgeWTConfig";    Version="VersionWTConfig";    Btn="BtnWTConfig" }
        "PSProfile"   = @{ Card="CardPSProfile";    Badge="StatusBadgePSProfile";   Version="VersionPSProfile";   Btn="BtnPSProfile" }
        "StatusLine"  = @{ Card="CardStatusLine";   Badge="StatusBadgeStatusLine";  Version="VersionStatusLine";  Btn="BtnStatusLine" }
    }

    foreach ($entry in $cardMap.GetEnumerator()) {
        $comp = $components[$entry.Key]
        $names = $entry.Value

        $badge = $ViewElement.FindName($names.Badge)
        $ver = $ViewElement.FindName($names.Version)
        $btn = $ViewElement.FindName($names.Btn)

        if ($comp.Installed) {
            # Update badge to green "Installed"
            $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E8F5E9")
            $badge.Child.Text = "已安装"
            $badge.Child.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5A8F5A")
            # Update button
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
    }
}
