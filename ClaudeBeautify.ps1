#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Terminal Beautify - Desktop Manager
.DESCRIPTION
    One-click terminal beautification for Claude Code.
.NOTES
    Run with: powershell -ExecutionPolicy Bypass -File ClaudeBeautify.ps1
#>

param()
$ErrorActionPreference = "Stop"

# ---------- Hide console window ----------
Add-Type -Name Win -Namespace Console -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int s);'
$h = [Console.Win]::GetConsoleWindow()
if ($h -ne [IntPtr]::Zero) { [Console.Win]::ShowWindow($h, 0) }

# ---------- Load assemblies ----------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms

# ---------- Import modules ----------
$script:ScriptRoot = $PSScriptRoot
$modulePath = Join-Path $script:ScriptRoot "Modules"

Import-Module (Join-Path $modulePath "Utils.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $modulePath "State.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $modulePath "Detection.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $modulePath "Actions.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $modulePath "Preview.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $modulePath "Profiles.psm1") -Force -DisableNameChecking

# ---------- Load view companion scripts ----------
$viewsPath = Join-Path $script:ScriptRoot "Views"
$viewScripts = Get-ChildItem -Path $viewsPath -Filter "*.ps1" -ErrorAction SilentlyContinue
foreach ($vs in $viewScripts) {
    . $vs.FullName
}

# ---------- Global refs ----------
$script:MainWindow = $null

# ---------- XAML loader ----------
function Load-XamlFile {
    param([string]$Path)
    $reader = [System.Xml.XmlReader]::Create($Path)
    try {
        return [System.Windows.Markup.XamlReader]::Load($reader)
    } finally {
        $reader.Close()
    }
}

# ---------- View management ----------
function Show-View {
    param([string]$ViewName)

    $viewsPath = Join-Path $script:ScriptRoot "Views"
    $viewFile  = Join-Path $viewsPath "${ViewName}View.xaml"

    if (-not (Test-Path $viewFile)) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "View not yet implemented: $ViewName"
        $tb.FontSize = 16
        $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7A7067")
        $tb.HorizontalAlignment = "Center"
        $tb.VerticalAlignment   = "Center"
        $script:MainWindow.FindName("MainContent").Content = $tb
        return
    }

    try {
        $view = Load-XamlFile -Path $viewFile
        $script:MainWindow.FindName("MainContent").Content = $view

        $titles = @{
            "Dashboard"     = "仪表盘"
            "Components"    = "组件管理"
            "ThemeSwitcher" = "主题切换"
            "Config"        = "设置"
            "Profiles"      = "配置方案"
        }
        $title = $titles[$ViewName]
        if (-not $title) { $title = $ViewName }
        $script:MainWindow.FindName("PageTitle").Text = $title

        Update-NavButtons -ActiveView $ViewName

        $initFn = "Initialize-${ViewName}View"
        if (Get-Command $initFn -ErrorAction SilentlyContinue) {
            & $initFn -ViewElement $view
        }

        Set-AppData -Path "CurrentView" -Value $ViewName
        Write-AppLog "Switched to view: $ViewName"
    } catch {
        Write-AppLog "Failed to load view $ViewName : $_" -Level Error
    }
}

# ---------- Nav button styling ----------
function Update-NavButtons {
    param([string]$ActiveView)

    $navMap = @{
        "Dashboard"     = "NavDashboard"
        "Components"    = "NavComponents"
        "ThemeSwitcher" = "NavThemes"
        "Config"        = "NavConfig"
        "Profiles"      = "NavProfiles"
    }

    foreach ($entry in $navMap.GetEnumerator()) {
        $btn = $script:MainWindow.FindName($entry.Value)
        if ($btn) {
            $stack = $btn.Content
            if ($entry.Key -eq $ActiveView) {
                $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D97757")
                if ($stack -and $stack.Children) {
                    foreach ($child in $stack.Children) {
                        if ($child -is [System.Windows.Controls.TextBlock]) {
                            $child.Foreground = [System.Windows.Media.Brushes]::White
                        }
                    }
                }
            } else {
                $btn.Background = [System.Windows.Media.Brushes]::Transparent
                if ($stack -and $stack.Children) {
                    $i = 0
                    foreach ($child in $stack.Children) {
                        if ($child -is [System.Windows.Controls.TextBlock]) {
                            $child.Foreground = if ($i -eq 0) {
                                [System.Windows.Media.BrushConverter]::new().ConvertFromString("#9E9589")
                            } else {
                                [System.Windows.Media.BrushConverter]::new().ConvertFromString("#C0B8AE")
                            }
                            $i++
                        }
                    }
                }
            }
        }
    }
}

# ---------- Main entry ----------
try {
    Initialize-AppData | Out-Null

    $mainXaml = Join-Path $script:ScriptRoot "Views\MainWindow.xaml"
    $script:MainWindow = Load-XamlFile -Path $mainXaml

    # Load and merge resource dictionaries
    $stylesPath = Join-Path $script:ScriptRoot "Views\Resources\Styles.xaml"
    $iconsPath = Join-Path $script:ScriptRoot "Views\Resources\Icons.xaml"
    if (Test-Path $stylesPath) {
        $styles = Load-XamlFile -Path $stylesPath
        $script:MainWindow.Resources.MergedDictionaries.Add($styles)
    }
    if (Test-Path $iconsPath) {
        $icons = Load-XamlFile -Path $iconsPath
        $script:MainWindow.Resources.MergedDictionaries.Add($icons)
    }

    # Wire navigation
    $navHandlers = @{
        "NavDashboard"  = { Show-View -ViewName "Dashboard" }
        "NavComponents" = { Show-View -ViewName "Components" }
        "NavThemes"     = { Show-View -ViewName "ThemeSwitcher" }
        "NavConfig"     = { Show-View -ViewName "Config" }
        "NavProfiles"   = { Show-View -ViewName "Profiles" }
    }
    foreach ($entry in $navHandlers.GetEnumerator()) {
        $btn = $script:MainWindow.FindName($entry.Key)
        if ($btn) {
            $handler = $entry.Value
            $btn.Add_Click($handler)
        }
    }

    # Title bar drag
    $titleBar = $script:MainWindow.FindName("TitleBar")
    if ($titleBar) {
        $titleBar.Add_MouseLeftButtonDown({ $script:MainWindow.DragMove() })
    }

    # Close / Minimize
    $closeBtn = $script:MainWindow.FindName("BtnClose")
    if ($closeBtn) { $closeBtn.Add_Click({ $script:MainWindow.Close() }) }
    $minBtn = $script:MainWindow.FindName("BtnMinimize")
    if ($minBtn) { $minBtn.Add_Click({ $script:MainWindow.WindowState = "Minimized" }) }

    # Launch
    Show-View -ViewName "Dashboard"
    Write-AppLog "Claude Terminal Beautify started"
    $script:MainWindow.ShowDialog() | Out-Null

} catch {
    [System.Windows.MessageBox]::Show("Failed to start: $_", "Error", "OK", "Error")
    Write-AppLog "Fatal: $_" -Level Error
}
