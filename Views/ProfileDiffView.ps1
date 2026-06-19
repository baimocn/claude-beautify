# Module-level ref
$script:ProfileDiffViewElement = $null
$script:ProfileDiffComparison = $null
$script:ProfileDiffProfiles = @()

function Initialize-ProfileDiffView {
    param($ViewElement)

    $script:ProfileDiffViewElement = $ViewElement
    $script:ProfileDiffComparison = $null

    # Load profiles into both dropdowns
    Refresh-ProfileDiffDropdowns

    # Wire up compare button
    $ViewElement.FindName("BtnCompare").Add_Click({
        Invoke-ProfileCompare
    })

    # Wire up merge buttons
    $ViewElement.FindName("BtnMergeA").Add_Click({
        Invoke-ProfileMerge -Strategy "prefer_first"
    })

    $ViewElement.FindName("BtnMergeB").Add_Click({
        Invoke-ProfileMerge -Strategy "prefer_second"
    })
}

# ---------------------------------------------------------------------------
# Refresh both profile dropdowns
# ---------------------------------------------------------------------------

function Refresh-ProfileDiffDropdowns {
    try {
        $profiles = Get-Profiles
        $script:ProfileDiffProfiles = $profiles

        $comboA = $script:ProfileDiffViewElement.FindName("ComboProfileA")
        $comboB = $script:ProfileDiffViewElement.FindName("ComboProfileB")

        $comboA.Items.Clear()
        $comboB.Items.Clear()

        foreach ($p in $profiles) {
            $name = if ($p.name) { $p.name } else { "Unnamed" }
            [void]$comboA.Items.Add($name)
            [void]$comboB.Items.Add($name)
        }

        # Select first two by default
        if ($profiles.Count -ge 1) {
            $comboA.SelectedIndex = 0
        }
        if ($profiles.Count -ge 2) {
            $comboB.SelectedIndex = 1
        }
        elseif ($profiles.Count -ge 1) {
            $comboB.SelectedIndex = 0
        }
    }
    catch {
        Write-AppLog "Refresh-ProfileDiffDropdowns failed: $_" -Level Error
    }
}

# ---------------------------------------------------------------------------
# Run profile comparison
# ---------------------------------------------------------------------------

function Invoke-ProfileCompare {
    try {
        $comboA = $script:ProfileDiffViewElement.FindName("ComboProfileA")
        $comboB = $script:ProfileDiffViewElement.FindName("ComboProfileB")

        $nameA = $comboA.SelectedItem
        $nameB = $comboB.SelectedItem

        if (-not $nameA -or -not $nameB) {
            [System.Windows.MessageBox]::Show("请选择两个方案进行对比", "提示", "OK", "Information")
            return
        }

        if ($nameA -eq $nameB) {
            [System.Windows.MessageBox]::Show("请选择两个不同的方案", "提示", "OK", "Information")
            return
        }

        $btn = $script:ProfileDiffViewElement.FindName("BtnCompare")
        $btn.Content = "对比中..."
        $btn.IsEnabled = $false

        # Run in background
        $scriptRoot = $script:ScriptRoot

        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        $ps.AddScript({
            param($scriptRoot, $nameA, $nameB)
            $ErrorActionPreference = "Stop"
            Import-Module (Join-Path $scriptRoot "Modules\Utils.psm1") -Force -DisableNameChecking
            Import-Module (Join-Path $scriptRoot "Modules\State.psm1") -Force -DisableNameChecking
            Import-Module (Join-Path $scriptRoot "Modules\Constants.psm1") -Force -DisableNameChecking
            Import-Module (Join-Path $scriptRoot "Modules\Profiles.psm1") -Force -DisableNameChecking
            Compare-Profiles -Name1 $nameA -Name2 $nameB
        }).AddArgument($scriptRoot).AddArgument($nameA).AddArgument($nameB)

        $job = $ps.BeginInvoke()

        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $timer.Tag = @{ Job=$job; PS=$ps; RS=$rs; Btn=$btn; NameA=$nameA; NameB=$nameB }
        $timer.Add_Tick({
            param($tSender, $tArgs)
            $t = $tSender
            $info = $t.Tag
            if ($info.Job.IsCompleted) {
                $t.Stop()
                try {
                    $result = $info.PS.EndInvoke($info.Job)
                    Update-ProfileDiffView -Comparison $result -NameA $info.NameA -NameB $info.NameB
                }
                catch {
                    [System.Windows.MessageBox]::Show("对比失败: $($_.Exception.Message)", "错误", "OK", "Error")
                }
                finally {
                    $info.PS.Dispose()
                    $info.RS.Close()
                    $info.RS.Dispose()
                    $info.Btn.Content = "对比"
                    $info.Btn.IsEnabled = $true
                }
            }
        })
        $timer.Start()
    }
    catch {
        [System.Windows.MessageBox]::Show("对比启动失败: $($_.Exception.Message)", "错误", "OK", "Error")
    }
}

# ---------------------------------------------------------------------------
# Update UI with comparison results
# ---------------------------------------------------------------------------

function Update-ProfileDiffView {
    param($Comparison, $NameA, $NameB)

    $view = $script:ProfileDiffViewElement

    if (-not $Comparison -or -not $Comparison.Success) {
        $msg = if ($Comparison.Message) { $Comparison.Message } else { "对比失败" }
        [System.Windows.MessageBox]::Show($msg, "错误", "OK", "Error")
        return
    }

    $script:ProfileDiffComparison = $Comparison

    # Update headers
    $view.FindName("HeaderA").Text = $NameA
    $view.FindName("HeaderB").Text = $NameB

    # Update summary
    $summaryBar = $view.FindName("DiffSummaryBar")
    $summaryBar.Visibility = [System.Windows.Visibility]::Visible

    $diffCount = if ($Comparison.Differences) { $Comparison.Differences.Count } else { 0 }
    $sameCount = if ($Comparison.Identical) { $Comparison.Identical.Count } else { 0 }
    $onlyCount = if ($Comparison.OnlyIn1) { $Comparison.OnlyIn1.Count } else { 0 } +
                 if ($Comparison.OnlyIn2) { $Comparison.OnlyIn2.Count } else { 0 }

    $view.FindName("DiffSummaryText").Text = "共 $($Comparison.TotalKeys) 个配置项"
    $view.FindName("DiffCountDifferent").Text = "$diffCount 项不同"
    $view.FindName("DiffCountSame").Text = "$sameCount 项相同"
    $view.FindName("DiffCountOnly").Text = "$onlyCount 项独有"

    # Hide empty state, show action bar
    $view.FindName("DiffEmptyState").Visibility = [System.Windows.Visibility]::Collapsed
    $view.FindName("DiffActionBar").Visibility = [System.Windows.Visibility]::Visible

    # Build diff rows
    $rowsPanel = $view.FindName("DiffRowsPanel")
    $rowsPanel.Children.Clear()

    $brushConverter = New-Object System.Windows.Media.BrushConverter

    # 1. Differences (highlighted)
    if ($diffCount -gt 0) {
        foreach ($diff in $Comparison.Differences) {
            $row = New-Object System.Windows.Controls.Grid
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.Background = $brushConverter.ConvertFromString("#FFEBEE")

            # Key label
            $keyBorder = New-Object System.Windows.Controls.Border
            $keyBorder.Padding = New-Object System.Windows.Thickness(12, 8)
            $keyBorder.BorderBrush = $brushConverter.ConvertFromString("#E0D8CC")
            $keyBorder.BorderThickness = New-Object System.Windows.Thickness(0, 0, 1, 1)
            $keyText = New-Object System.Windows.Controls.TextBlock
            $keyText.Text = $diff.Key
            $keyText.FontSize = 12
            $keyText.Foreground = $brushConverter.ConvertFromString("#C45454")
            $keyText.FontWeight = "SemiBold"
            $keyBorder.Child = $keyText
            [System.Windows.Controls.Grid]::SetColumn($keyBorder, 0)
            $row.Children.Add($keyBorder)

            # Value A
            $valABorder = New-Object System.Windows.Controls.Border
            $valABorder.Padding = New-Object System.Windows.Thickness(12, 8)
            $valABorder.BorderBrush = $brushConverter.ConvertFromString("#E0D8CC")
            $valABorder.BorderThickness = New-Object System.Windows.Thickness(0, 0, 1, 1)
            $valAText = New-Object System.Windows.Controls.TextBlock
            $valAText.Text = if ($null -ne $diff.Profile1Value) { $diff.Profile1Value.ToString() } else { "(空)" }
            $valAText.FontSize = 12
            $valAText.Foreground = $brushConverter.ConvertFromString("#2C2521")
            $valAText.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $valABorder.Child = $valAText
            [System.Windows.Controls.Grid]::SetColumn($valABorder, 1)
            $row.Children.Add($valABorder)

            # Value B
            $valBBorder = New-Object System.Windows.Controls.Border
            $valBBorder.Padding = New-Object System.Windows.Thickness(12, 8)
            $valBBorder.BorderBrush = $brushConverter.ConvertFromString("#E0D8CC")
            $valBBorder.BorderThickness = New-Object System.Windows.Thickness(0, 0, 0, 1)
            $valBText = New-Object System.Windows.Controls.TextBlock
            $valBText.Text = if ($null -ne $diff.Profile2Value) { $diff.Profile2Value.ToString() } else { "(空)" }
            $valBText.FontSize = 12
            $valBText.Foreground = $brushConverter.ConvertFromString("#2C2521")
            $valBText.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $valBBorder.Child = $valBText
            [System.Windows.Controls.Grid]::SetColumn($valBBorder, 2)
            $row.Children.Add($valBBorder)

            $rowsPanel.Children.Add($row)
        }
    }

    # 2. Identical items
    if ($sameCount -gt 0) {
        # Section header
        $headerRow = New-Object System.Windows.Controls.Border
        $headerRow.Background = $brushConverter.ConvertFromString("#F5F0E8")
        $headerRow.Padding = New-Object System.Windows.Thickness(12, 8)
        $headerRow.BorderBrush = $brushConverter.ConvertFromString("#E0D8CC")
        $headerRow.BorderThickness = New-Object System.Windows.Thickness(0, 0, 0, 1)
        $headerText = New-Object System.Windows.Controls.TextBlock
        $headerText.Text = "相同项 ($sameCount)"
        $headerText.FontSize = 11
        $headerText.Foreground = $brushConverter.ConvertFromString("#7A7067")
        $headerText.FontWeight = "SemiBold"
        $headerRow.Child = $headerText
        $rowsPanel.Children.Add($headerRow)

        foreach ($key in $Comparison.Identical) {
            $row = New-Object System.Windows.Controls.Grid
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.Background = [System.Windows.Brushes]::White

            $keyBorder = New-Object System.Windows.Controls.Border
            $keyBorder.Padding = New-Object System.Windows.Thickness(12, 8)
            $keyBorder.BorderBrush = $brushConverter.ConvertFromString("#EFE9DF")
            $keyBorder.BorderThickness = New-Object System.Windows.Thickness(0, 0, 1, 1)
            $keyText = New-Object System.Windows.Controls.TextBlock
            $keyText.Text = $key
            $keyText.FontSize = 12
            $keyText.Foreground = $brushConverter.ConvertFromString("#5A5047")
            $keyBorder.Child = $keyText
            [System.Windows.Controls.Grid]::SetColumn($keyBorder, 0)
            $row.Children.Add($keyBorder)

            # Value (same in both, show once spanning 2 cols)
            $valBorder = New-Object System.Windows.Controls.Border
            $valBorder.Padding = New-Object System.Windows.Thickness(12, 8)
            $valBorder.BorderBrush = $brushConverter.ConvertFromString("#EFE9DF")
            $valBorder.BorderThickness = New-Object System.Windows.Thickness(0, 0, 0, 1)
            $valText = New-Object System.Windows.Controls.TextBlock
            $valText.Text = "(值相同)"
            $valText.FontSize = 12
            $valText.Foreground = $brushConverter.ConvertFromString("#9E9589")
            $valText.FontStyle = "Italic"
            $valBorder.Child = $valText
            [System.Windows.Controls.Grid]::SetColumn($valBorder, 1)
            [System.Windows.Controls.Grid]::SetColumnSpan($valBorder, 2)
            $row.Children.Add($valBorder)

            $rowsPanel.Children.Add($row)
        }
    }

    # 3. Only in A
    if ($Comparison.OnlyIn1 -and $Comparison.OnlyIn1.Count -gt 0) {
        foreach ($key in $Comparison.OnlyIn1) {
            $row = New-Object System.Windows.Controls.Grid
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.Background = $brushConverter.ConvertFromString("#E3F2FD")

            $keyBorder = New-Object System.Windows.Controls.Border
            $keyBorder.Padding = New-Object System.Windows.Thickness(12, 8)
            $keyBorder.BorderBrush = $brushConverter.ConvertFromString("#E0D8CC")
            $keyBorder.BorderThickness = New-Object System.Windows.Thickness(0, 0, 1, 1)
            $keyText = New-Object System.Windows.Controls.TextBlock
            $keyText.Text = $key + " (仅方案A)"
            $keyText.FontSize = 12
            $keyText.Foreground = $brushConverter.ConvertFromString("#1565C0")
            $keyBorder.Child = $keyText
            [System.Windows.Controls.Grid]::SetColumn($keyBorder, 0)
            $row.Children.Add($keyBorder)

            $valABorder = New-Object System.Windows.Controls.Border
            $valABorder.Padding = New-Object System.Windows.Thickness(12, 8)
            $valABorder.BorderBrush = $brushConverter.ConvertFromString("#E0D8CC")
            $valABorder.BorderThickness = New-Object System.Windows.Thickness(0, 0, 1, 1)
            $valAText = New-Object System.Windows.Controls.TextBlock
            $valAText.Text = "存在"
            $valAText.FontSize = 12
            $valAText.Foreground = $brushConverter.ConvertFromString("#2C2521")
            $valABorder.Child = $valAText
            [System.Windows.Controls.Grid]::SetColumn($valABorder, 1)
            $row.Children.Add($valABorder)

            $valBBorder = New-Object System.Windows.Controls.Border
            $valBBorder.Padding = New-Object System.Windows.Thickness(12, 8)
            $valBBorder.BorderBrush = $brushConverter.ConvertFromString("#E0D8CC")
            $valBBorder.BorderThickness = New-Object System.Windows.Thickness(0, 0, 0, 1)
            $valBText = New-Object System.Windows.Controls.TextBlock
            $valBText.Text = "-"
            $valBText.FontSize = 12
            $valBText.Foreground = $brushConverter.ConvertFromString("#C0B8AE")
            $valBBorder.Child = $valBText
            [System.Windows.Controls.Grid]::SetColumn($valBBorder, 2)
            $row.Children.Add($valBBorder)

            $rowsPanel.Children.Add($row)
        }
    }

    # 4. Only in B
    if ($Comparison.OnlyIn2 -and $Comparison.OnlyIn2.Count -gt 0) {
        foreach ($key in $Comparison.OnlyIn2) {
            $row = New-Object System.Windows.Controls.Grid
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
            $row.Background = $brushConverter.ConvertFromString("#FFF3E0")

            $keyBorder = New-Object System.Windows.Controls.Border
            $keyBorder.Padding = New-Object System.Windows.Thickness(12, 8)
            $keyBorder.BorderBrush = $brushConverter.ConvertFromString("#E0D8CC")
            $keyBorder.BorderThickness = New-Object System.Windows.Thickness(0, 0, 1, 1)
            $keyText = New-Object System.Windows.Controls.TextBlock
            $keyText.Text = $key + " (仅方案B)"
            $keyText.FontSize = 12
            $keyText.Foreground = $brushConverter.ConvertFromString("#E65100")
            $keyBorder.Child = $keyText
            [System.Windows.Controls.Grid]::SetColumn($keyBorder, 0)
            $row.Children.Add($keyBorder)

            $valABorder = New-Object System.Windows.Controls.Border
            $valABorder.Padding = New-Object System.Windows.Thickness(12, 8)
            $valABorder.BorderBrush = $brushConverter.ConvertFromString("#E0D8CC")
            $valABorder.BorderThickness = New-Object System.Windows.Thickness(0, 0, 1, 1)
            $valAText = New-Object System.Windows.Controls.TextBlock
            $valAText.Text = "-"
            $valAText.FontSize = 12
            $valAText.Foreground = $brushConverter.ConvertFromString("#C0B8AE")
            $valABorder.Child = $valAText
            [System.Windows.Controls.Grid]::SetColumn($valABorder, 1)
            $row.Children.Add($valABorder)

            $valBBorder = New-Object System.Windows.Controls.Border
            $valBBorder.Padding = New-Object System.Windows.Thickness(12, 8)
            $valBBorder.BorderBrush = $brushConverter.ConvertFromString("#E0D8CC")
            $valBBorder.BorderThickness = New-Object System.Windows.Thickness(0, 0, 0, 1)
            $valBText = New-Object System.Windows.Controls.TextBlock
            $valBText.Text = "存在"
            $valBText.FontSize = 12
            $valBText.Foreground = $brushConverter.ConvertFromString("#2C2521")
            $valBBorder.Child = $valBText
            [System.Windows.Controls.Grid]::SetColumn($valBBorder, 2)
            $row.Children.Add($valBBorder)

            $rowsPanel.Children.Add($row)
        }
    }
}

# ---------------------------------------------------------------------------
# Merge profiles
# ---------------------------------------------------------------------------

function Invoke-ProfileMerge {
    param([string]$Strategy)

    try {
        $comparison = $script:ProfileDiffComparison
        if (-not $comparison) {
            [System.Windows.MessageBox]::Show("请先执行对比", "提示", "OK", "Information")
            return
        }

        $newName = $script:ProfileDiffViewElement.FindName("TxtNewName").Text
        if (-not $newName -or $newName.Trim().Length -eq 0) {
            [System.Windows.MessageBox]::Show("请输入新方案名称", "提示", "OK", "Information")
            return
        }

        $strategyLabel = if ($Strategy -eq "prefer_first") { "以 A 为准" } else { "以 B 为准" }
        $confirm = [System.Windows.MessageBox]::Show(
            "确定要${strategyLabel}合并为 ""$newName"" 吗？",
            "确认合并",
            "YesNo",
            "Question"
        )
        if ($confirm -ne "Yes") { return }

        $btnName = if ($Strategy -eq "prefer_first") { "BtnMergeA" } else { "BtnMergeB" }
        $btn = $script:ProfileDiffViewElement.FindName($btnName)
        $origContent = $btn.Content
        $btn.Content = "合并中..."
        $btn.IsEnabled = $false

        $scriptRoot = $script:ScriptRoot
        $nameA = $comparison.Profile1
        $nameB = $comparison.Profile2

        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        $ps.AddScript({
            param($scriptRoot, $nameA, $nameB, $newName, $strategy)
            $ErrorActionPreference = "Stop"
            Import-Module (Join-Path $scriptRoot "Modules\Utils.psm1") -Force -DisableNameChecking
            Import-Module (Join-Path $scriptRoot "Modules\State.psm1") -Force -DisableNameChecking
            Import-Module (Join-Path $scriptRoot "Modules\Constants.psm1") -Force -DisableNameChecking
            Import-Module (Join-Path $scriptRoot "Modules\Detection.psm1") -Force -DisableNameChecking
            Import-Module (Join-Path $scriptRoot "Modules\Actions.psm1") -Force -DisableNameChecking
            Import-Module (Join-Path $scriptRoot "Modules\Profiles.psm1") -Force -DisableNameChecking
            Merge-Profiles -Name1 $nameA -Name2 $nameB -NewName $newName -Strategy $strategy
        }).AddArgument($scriptRoot).AddArgument($nameA).AddArgument($nameB).AddArgument($newName).AddArgument($Strategy)

        $job = $ps.BeginInvoke()

        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $timer.Tag = @{ Job=$job; PS=$ps; RS=$rs; Btn=$btn; OrigContent=$origContent }
        $timer.Add_Tick({
            param($tSender, $tArgs)
            $t = $tSender
            $info = $t.Tag
            if ($info.Job.IsCompleted) {
                $t.Stop()
                try {
                    $result = $info.PS.EndInvoke($info.Job)
                    if ($result -and $result.Success) {
                        [System.Windows.MessageBox]::Show($result.Message, "合并成功", "OK", "Information")
                        # Refresh dropdowns
                        Refresh-ProfileDiffDropdowns
                    }
                    elseif ($result) {
                        [System.Windows.MessageBox]::Show($result.Message, "合并失败", "OK", "Warning")
                    }
                    else {
                        [System.Windows.MessageBox]::Show("合并完成", "完成", "OK", "Information")
                    }
                }
                catch {
                    [System.Windows.MessageBox]::Show("合并失败: $($_.Exception.Message)", "错误", "OK", "Error")
                }
                finally {
                    $info.PS.Dispose()
                    $info.RS.Close()
                    $info.RS.Dispose()
                    $info.Btn.Content = $info.OrigContent
                    $info.Btn.IsEnabled = $true
                }
            }
        })
        $timer.Start()
    }
    catch {
        [System.Windows.MessageBox]::Show("合并启动失败: $($_.Exception.Message)", "错误", "OK", "Error")
    }
}
