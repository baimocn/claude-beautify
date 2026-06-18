function Initialize-ThemeSwitcherView {
    param($ViewElement)

    try {
    $themesPath = $env:POSH_THEMES_PATH
    if (-not $themesPath -or -not (Test-Path $themesPath)) {
        $themesPath = "C:\Program Files (x86)\oh-my-posh\themes"
    }

    $config = Get-AppConfig
    $script:ThemeViewElement = $ViewElement

    # Populate theme list
    $listBox = $ViewElement.FindName("ThemeList")
    $allThemes = @()
    if (Test-Path $themesPath) {
        $allThemes = Get-ChildItem -Path $themesPath -Filter "*.omp.json" | ForEach-Object {
            $_.BaseName -replace "\.omp$", ""
        } | Sort-Object
    }
    foreach ($t in $allThemes) {
        $listBox.Items.Add($t) | Out-Null
    }

    # Select current theme
    if ($listBox.Items.Contains($config.OMPTheme)) {
        $listBox.SelectedItem = $config.OMPTheme
    }

    # Search filter
    $ViewElement.FindName("SearchTheme").Add_TextChanged({
        $filter = $script:ThemeViewElement.FindName("SearchTheme").Text.ToLower()
        $lb = $script:ThemeViewElement.FindName("ThemeList")
        $lb.Items.Clear()
        foreach ($t in $allThemes) {
            if ($t.ToLower().Contains($filter)) {
                $lb.Items.Add($t) | Out-Null
            }
        }
    })

    # Theme selection -> preview
    $listBox.Add_SelectionChanged({
        $lb = $script:ThemeViewElement.FindName("ThemeList")
        $selected = $lb.SelectedItem
        if (-not $selected) { return }
        $script:ThemeViewElement.FindName("ThemeName").Text = $selected
        Update-Preview -Canvas $script:ThemeViewElement.FindName("ThemePreviewCanvas")
    })

    # Apply button
    $ViewElement.FindName("BtnApplyTheme").Add_Click({
        $selected = $script:ThemeViewElement.FindName("ThemeList").SelectedItem
        if (-not $selected) { return }
        Set-AppData -Path "Config.OMPTheme" -Value $selected
        $r = Apply-PSProfile
        if ($r.Success) {
            [System.Windows.MessageBox]::Show("主题已切换为: $selected", "提示", "OK", "Information")
        } else {
            [System.Windows.MessageBox]::Show("切换失败: $($r.Message)", "错误", "OK", "Error")
        }
    })

    # Revert button
    $ViewElement.FindName("BtnRevertTheme").Add_Click({
        Set-AppData -Path "Config.OMPTheme" -Value "tokyonight_storm"
        $script:ThemeViewElement.FindName("ThemeList").SelectedItem = "tokyonight_storm"
        Update-Preview -Canvas $script:ThemeViewElement.FindName("ThemePreviewCanvas")
    })

    # Initial preview
    $canvas = $ViewElement.FindName("ThemePreviewCanvas")
    if ($canvas) { Update-Preview -Canvas $canvas }

    } catch {
        [System.Windows.MessageBox]::Show("主题页面加载失败: $($_.Exception.Message)", "错误", "OK", "Error")
    }
}
