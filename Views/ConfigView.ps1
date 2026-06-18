# Module-level ref for event handlers (PowerShell closure scope fix)
$script:ConfigViewElement = $null

function Initialize-ConfigView {
    param($ViewElement)

    try {

    # Store at script scope so event handlers can access it
    $script:ConfigViewElement = $ViewElement
    $config = Get-AppConfig

    # Populate combo boxes
    # Font combo: add common fonts + installed nerd fonts
    $fontCombo = $script:ConfigViewElement.FindName("ComboFont")
    @("CaskaydiaCove Nerd Font", "Consolas", "Cascadia Code", "Fira Code", "JetBrains Mono") | ForEach-Object {
        $fontCombo.Items.Add($_) | Out-Null
    }
    $fontCombo.SelectedItem = $config.FontFace

    # Color scheme combo
    $schemeCombo = $script:ConfigViewElement.FindName("ComboScheme")
    $schemes = Get-WTColorSchemes
    foreach ($s in $schemes) {
        $schemeCombo.Items.Add($s.name) | Out-Null
    }
    if ($schemeCombo.Items.Contains($config.ColorScheme)) {
        $schemeCombo.SelectedItem = $config.ColorScheme
    } else {
        $schemeCombo.SelectedIndex = 0
    }

    # Cursor shape combo
    $cursorCombo = $script:ConfigViewElement.FindName("ComboCursor")
    @("filledBox", "bar", "underscore", "emptyBox", "vintage") | ForEach-Object {
        $cursorCombo.Items.Add($_) | Out-Null
    }
    $cursorCombo.SelectedItem = $config.CursorShape

    # OMP theme combo
    $themeCombo = $script:ConfigViewElement.FindName("ComboTheme")
    $themesPath = $env:POSH_THEMES_PATH
    if (-not $themesPath -or -not (Test-Path $themesPath)) {
        $themesPath = "C:\Program Files (x86)\oh-my-posh\themes"
    }
    if (Test-Path $themesPath) {
        Get-ChildItem -Path $themesPath -Filter "*.omp.json" | ForEach-Object {
            $name = $_.BaseName -replace "\.omp$", ""
            $themeCombo.Items.Add($name) | Out-Null
        }
    }
    if ($themeCombo.Items.Contains($config.OMPTheme)) {
        $themeCombo.SelectedItem = $config.OMPTheme
    }

    # Set slider values
    $script:ConfigViewElement.FindName("SliderOpacity").Value = $config.Opacity
    $script:ConfigViewElement.FindName("TextOpacity").Text = [string]$config.Opacity
    $script:ConfigViewElement.FindName("SliderFontSize").Value = $config.FontSize
    $script:ConfigViewElement.FindName("TextFontSize").Text = [string]$config.FontSize
    $script:ConfigViewElement.FindName("SliderCursorHeight").Value = $config.CursorHeight
    $script:ConfigViewElement.FindName("TextCursorHeight").Text = [string]$config.CursorHeight
    $script:ConfigViewElement.FindName("ChkAcrylic").IsChecked = $config.UseAcrylic

    # Debounce timer for preview updates
    $script:PreviewTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:PreviewTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:PreviewTimer.Add_Tick({
        $script:PreviewTimer.Stop()
        try {
            $cv = $script:ConfigViewElement.FindName("PreviewCanvas")
            if ($cv) {
                $op = [int]$script:ConfigViewElement.FindName("SliderOpacity").Value
                $fs = [int]$script:ConfigViewElement.FindName("SliderFontSize").Value
                $ff = $script:ConfigViewElement.FindName("ComboFont").SelectedItem
                $cs = $script:ConfigViewElement.FindName("ComboScheme").SelectedItem
                $cr = $script:ConfigViewElement.FindName("ComboCursor").SelectedItem
                $th = $script:ConfigViewElement.FindName("ComboTheme").SelectedItem
                Update-Preview -Canvas $cv -OverrideOpacity $op -OverrideFontSize $fs -OverrideFontFace $ff -OverrideColorScheme $cs -OverrideCursorShape $cr -OverrideTheme $th
            }
        } catch {}
    })

    # Helper: schedule preview update (debounced)
    $schedulePreview = {
        if ($script:PreviewTimer) { $script:PreviewTimer.Stop(); $script:PreviewTimer.Start() }
    }

    # Wire slider value changes
    $script:ConfigViewElement.FindName("SliderOpacity").Add_ValueChanged({
        try {
            $slider = $script:ConfigViewElement.FindName("SliderOpacity")
            $textbox = $script:ConfigViewElement.FindName("TextOpacity")
            if ($slider -and $textbox) {
                $textbox.Text = [string][int]$slider.Value
            }
            if ($script:PreviewTimer) { $script:PreviewTimer.Stop(); $script:PreviewTimer.Start() }
        } catch {}
    })
    $script:ConfigViewElement.FindName("SliderFontSize").Add_ValueChanged({
        try {
            $val = [int]$script:ConfigViewElement.FindName("SliderFontSize").Value
            $script:ConfigViewElement.FindName("TextFontSize").Text = [string]$val
            if ($script:PreviewTimer) { $script:PreviewTimer.Stop(); $script:PreviewTimer.Start() }
        } catch {}
    })
    $script:ConfigViewElement.FindName("SliderCursorHeight").Add_ValueChanged({
        try {
            $tb = $script:ConfigViewElement.FindName("TextCursorHeight")
            if ($tb) { $tb.Text = [string][int]$script:ConfigViewElement.FindName("SliderCursorHeight").Value }
            if ($script:PreviewTimer) { $script:PreviewTimer.Stop(); $script:PreviewTimer.Start() }
        } catch {}
    })

    # Wire combo changes
    foreach ($comboName in @("ComboFont", "ComboScheme", "ComboCursor", "ComboTheme")) {
        $script:ConfigViewElement.FindName($comboName).Add_SelectionChanged({
            try { if ($script:PreviewTimer) { $script:PreviewTimer.Stop(); $script:PreviewTimer.Start() } } catch {}
        })
    }

    # Wire acrylic checkbox
    $script:ConfigViewElement.FindName("ChkAcrylic").Add_Checked({
        try { if ($script:PreviewTimer) { $script:PreviewTimer.Stop(); $script:PreviewTimer.Start() } } catch {}
    })
    $script:ConfigViewElement.FindName("ChkAcrylic").Add_Unchecked({
        try { if ($script:PreviewTimer) { $script:PreviewTimer.Stop(); $script:PreviewTimer.Start() } } catch {}
    })

    # Initial preview
    Update-Preview -Canvas $script:ConfigViewElement.FindName("PreviewCanvas")

    # Apply button
    $script:ConfigViewElement.FindName("BtnApply").Add_Click({
        # Read all current control values into config
        Set-AppData -Path "Config.Opacity" -Value ([int]$script:ConfigViewElement.FindName("SliderOpacity").Value)
        Set-AppData -Path "Config.FontSize" -Value ([int]$script:ConfigViewElement.FindName("SliderFontSize").Value)
        Set-AppData -Path "Config.FontFace" -Value $script:ConfigViewElement.FindName("ComboFont").SelectedItem
        Set-AppData -Path "Config.ColorScheme" -Value $script:ConfigViewElement.FindName("ComboScheme").SelectedItem
        Set-AppData -Path "Config.UseAcrylic" -Value $script:ConfigViewElement.FindName("ChkAcrylic").IsChecked
        Set-AppData -Path "Config.CursorShape" -Value $script:ConfigViewElement.FindName("ComboCursor").SelectedItem
        Set-AppData -Path "Config.CursorHeight" -Value ([int]$script:ConfigViewElement.FindName("SliderCursorHeight").Value)
        Set-AppData -Path "Config.OMPTheme" -Value $script:ConfigViewElement.FindName("ComboTheme").SelectedItem

        # Apply to Windows Terminal and PS Profile
        $r1 = Apply-WTSettings
        $r2 = Apply-PSProfile -ThemeName $script:ConfigViewElement.FindName("ComboTheme").SelectedItem

        if ($r1.Success -and $r2.Success) {
            [System.Windows.MessageBox]::Show("配置已应用！", "提示", "OK", "Information")
        } else {
            $errMsg = @()
            if (-not $r1.Success) { $errMsg += "终端配置: $($r1.Message)" }
            if (-not $r2.Success) { $errMsg += "PowerShell配置: $($r2.Message)" }
            [System.Windows.MessageBox]::Show("部分配置应用失败:`n$($errMsg -join "`n")", "警告", "OK", "Warning")
        }
    })

    # Reset button
    $script:ConfigViewElement.FindName("BtnReset").Add_Click({
        Reset-AppData
        $config = Get-AppConfig
        $script:ConfigViewElement.FindName("SliderOpacity").Value = $config.Opacity
        $script:ConfigViewElement.FindName("SliderFontSize").Value = $config.FontSize
        $script:ConfigViewElement.FindName("SliderCursorHeight").Value = $config.CursorHeight
        $script:ConfigViewElement.FindName("ChkAcrylic").IsChecked = $config.UseAcrylic
        if ($script:ConfigViewElement.FindName("ComboFont").Items.Contains($config.FontFace)) {
            $script:ConfigViewElement.FindName("ComboFont").SelectedItem = $config.FontFace
        }
        if ($script:ConfigViewElement.FindName("ComboScheme").Items.Contains($config.ColorScheme)) {
            $script:ConfigViewElement.FindName("ComboScheme").SelectedItem = $config.ColorScheme
        }
        if ($script:ConfigViewElement.FindName("ComboCursor").Items.Contains($config.CursorShape)) {
            $script:ConfigViewElement.FindName("ComboCursor").SelectedItem = $config.CursorShape
        }
        if ($script:ConfigViewElement.FindName("ComboTheme").Items.Contains($config.OMPTheme)) {
            $script:ConfigViewElement.FindName("ComboTheme").SelectedItem = $config.OMPTheme
        }
        Update-Preview -Canvas $script:ConfigViewElement.FindName("PreviewCanvas")
        [System.Windows.MessageBox]::Show("已恢复默认配置", "提示", "OK", "Information")
    })

    } catch {
        [System.Windows.MessageBox]::Show("设置页面加载失败: $($_.Exception.Message)", "错误", "OK", "Error")
    }
}
