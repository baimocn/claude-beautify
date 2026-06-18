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

        # Wire click handler - capture compKey in closure
        $key = $compKey
        $isInstalled = $comp.Installed
        $btn.Add_Click({
            try {
                if ($isInstalled) {
                    $fn = "Uninstall-$key"
                } else {
                    $fn = "Install-$key"
                }
                if (Get-Command $fn -ErrorAction SilentlyContinue) {
                    $r = & $fn
                    if ($r.Success) {
                        [System.Windows.MessageBox]::Show($r.Message, "完成", "OK", "Information")
                    } else {
                        [System.Windows.MessageBox]::Show($r.Message, "失败", "OK", "Warning")
                    }
                    # Refresh dashboard
                    Initialize-DashboardView -ViewElement $script:DashboardViewElement
                } else {
                    [System.Windows.MessageBox]::Show("功能暂未实现: $fn", "提示", "OK", "Information")
                }
            } catch {
                [System.Windows.MessageBox]::Show("操作失败: $($_.Exception.Message)", "错误", "OK", "Error")
            }
        })
    }

    # Refresh button
    $ViewElement.FindName("BtnRefresh").Add_Click({
        Initialize-DashboardView -ViewElement $script:DashboardViewElement
    })
}
