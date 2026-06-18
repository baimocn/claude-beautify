function Initialize-ProfilesView {
    param($ViewElement)

    try {
    $script:ProfilesViewElement = $ViewElement

    # Refresh profile list
    $refreshList = {
        $panel = $script:ProfilesViewElement.FindName("ProfileList")
        $panel.Children.Clear()

        $profiles = Get-Profiles

        if ($profiles.Count -eq 0) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = "暂无保存的配置方案。点击上方按钮保存当前配置。"
            $tb.FontSize = 13
            $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7A7067")
            $tb.Margin = [System.Windows.Thickness]::new(0,16,0,0)
            $panel.Children.Add($tb) | Out-Null
            return
        }

        foreach ($p in $profiles) {
            $card = New-Object System.Windows.Controls.Border
            $card.Background = [System.Windows.Media.Brushes]::White
            $card.CornerRadius = [System.Windows.CornerRadius]::new(8)
            $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E0D8CC")
            $card.BorderThickness = [System.Windows.Thickness]::new(1)
            $card.Padding = [System.Windows.Thickness]::new(16)
            $card.Margin = [System.Windows.Thickness]::new(0,0,0,8)

            $grid = New-Object System.Windows.Controls.Grid
            $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
            $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))

            # Row 0: name + date
            $header = New-Object System.Windows.Controls.Grid
            $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
            $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition @{ Width=[System.Windows.GridLength]::Auto }))

            $nameTb = New-Object System.Windows.Controls.TextBlock
            $nameTb.Text = $p.name
            $nameTb.FontSize = 14
            $nameTb.FontWeight = [System.Windows.FontWeights]::SemiBold
            [System.Windows.Controls.Grid]::SetColumn($nameTb, 0)
            $header.Children.Add($nameTb) | Out-Null

            $dateTb = New-Object System.Windows.Controls.TextBlock
            $dateTb.Text = $p.createdAt
            $dateTb.FontSize = 11
            $dateTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7A7067")
            [System.Windows.Controls.Grid]::SetColumn($dateTb, 1)
            $header.Children.Add($dateTb) | Out-Null

            [System.Windows.Controls.Grid]::SetRow($header, 0)
            $grid.Children.Add($header) | Out-Null

            # Row 1: summary + buttons
            $footer = New-Object System.Windows.Controls.Grid
            $footer.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
            $footer.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition @{ Width=[System.Windows.GridLength]::Auto }))

            $summary = New-Object System.Windows.Controls.TextBlock
            $cfg = $p.config
            $summary.Text = "$($cfg.ColorScheme) | 字号 $($cfg.FontSize) | 不透明度 $($cfg.Opacity)%"
            $summary.FontSize = 12
            $summary.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7A7067")
            [System.Windows.Controls.Grid]::SetColumn($summary, 0)
            $footer.Children.Add($summary) | Out-Null

            $btnPanel = New-Object System.Windows.Controls.StackPanel
            $btnPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal

            $loadBtn = New-Object System.Windows.Controls.Button
            $loadBtn.Content = "加载"
            $loadBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#5A8F5A")
            $loadBtn.Foreground = [System.Windows.Media.Brushes]::White
            $loadBtn.Padding = [System.Windows.Thickness]::new(12,4,12,4)
            $loadBtn.BorderThickness = [System.Windows.Thickness]::new(0)
            $loadBtn.FontSize = 11
            $profileName = $p.name
            $loadBtn.Add_Click({ Load-Profile -Name $profileName; & $refreshList })
            $btnPanel.Children.Add($loadBtn) | Out-Null

            $delBtn = New-Object System.Windows.Controls.Button
            $delBtn.Content = "删除"
            $delBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#C45454")
            $delBtn.Foreground = [System.Windows.Media.Brushes]::White
            $delBtn.Padding = [System.Windows.Thickness]::new(12,4,12,4)
            $delBtn.BorderThickness = [System.Windows.Thickness]::new(0)
            $delBtn.FontSize = 11
            $delBtn.Margin = [System.Windows.Thickness]::new(8,0,0,0)
            $dn = $p.name
            $delBtn.Add_Click({
                $confirm = [System.Windows.MessageBox]::Show("确定要删除配置方案 ""$dn"" 吗？", "确认删除", "YesNo", "Question")
                if ($confirm -eq "Yes") { Remove-Profile -Name $dn }
                & $refreshList
            })
            $btnPanel.Children.Add($delBtn) | Out-Null

            $expBtn = New-Object System.Windows.Controls.Button
            $expBtn.Content = "导出"
            $expBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E0D8CC")
            $expBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2C2521")
            $expBtn.Padding = [System.Windows.Thickness]::new(12,4,12,4)
            $expBtn.BorderThickness = [System.Windows.Thickness]::new(0)
            $expBtn.FontSize = 11
            $expBtn.Margin = [System.Windows.Thickness]::new(8,0,0,0)
            $en = $p.name
            $expBtn.Add_Click({
                $dlg = New-Object Microsoft.Win32.SaveFileDialog
                $dlg.Filter = "JSON|*.json"
                $dlg.FileName = "$en.json"
                if ($dlg.ShowDialog()) { Export-Profile -Name $en -Destination $dlg.FileName }
            })
            $btnPanel.Children.Add($expBtn) | Out-Null

            [System.Windows.Controls.Grid]::SetColumn($btnPanel, 1)
            $footer.Children.Add($btnPanel) | Out-Null

            [System.Windows.Controls.Grid]::SetRow($footer, 1)
            $grid.Children.Add($footer) | Out-Null

            $card.Child = $grid
            $panel.Children.Add($card) | Out-Null
        }
    }

    & $refreshList

    # Save button
    $ViewElement.FindName("BtnSaveProfile").Add_Click({
        $name = [Microsoft.VisualBasic.Interaction]::InputBox("请输入配置方案名称:", "保存配置", "我的方案")
        if ($name) {
            Save-Profile -Name $name
            & $refreshList
            [System.Windows.MessageBox]::Show("配置已保存: $name", "提示", "OK", "Information")
        }
    })

    # Import button
    $ViewElement.FindName("BtnImportProfile").Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = "JSON|*.json"
        if ($dlg.ShowDialog()) {
            $r = Import-Profile -Source $dlg.FileName
            if ($r.Success) {
                & $refreshList
                [System.Windows.MessageBox]::Show("导入成功: $($r.Name)", "提示", "OK", "Information")
            } else {
                [System.Windows.MessageBox]::Show("导入失败: $($r.Message)", "错误", "OK", "Error")
            }
        }
    })

    } catch {
        [System.Windows.MessageBox]::Show("配置方案页面加载失败: $($_.Exception.Message)", "错误", "OK", "Error")
    }
}
