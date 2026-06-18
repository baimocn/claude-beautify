# Preview.psm1 -- Live terminal preview renderer on a WPF Canvas
# Depends on State.psm1 (imported by the entry point; do NOT re-import here)

# ============================================================
#  Get-WTColorSchemes
# ============================================================
function Get-WTColorSchemes {
    [CmdletBinding()]
    param()

    $defaultScheme = Get-TokyoNightScheme

    try {
        $settingsPath = Get-WTSettingsPath

        if (-not (Test-Path $settingsPath)) {
            Write-Verbose "Windows Terminal settings not found; using default Tokyo Night scheme."
            return @($defaultScheme)
        }

        $json = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($json.schemes -and $json.schemes.Count -gt 0) {
            return $json.schemes
        }

        return @($defaultScheme)
    }
    catch {
        Write-Verbose "Error reading WT schemes: $_"
        return @($defaultScheme)
    }
}

# ============================================================
#  Get-ThemeColors
# ============================================================
function Get-ThemeColors {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$ThemeName = "tokyonight_storm"
    )

    $defaults = @{
        PromptBg   = "#1A1B26"
        PromptFg   = "#C0CAF5"
        PathColor  = "#7AA2F7"
        GitColor   = "#9ECE6A"
        AccentColor = "#F7768E"
    }

    try {
        $themesPath = if ($env:POSH_THEMES_PATH) {
            $env:POSH_THEMES_PATH
        } else {
            "C:\Program Files (x86)\oh-my-posh\themes"
        }

        $themeFile = Join-Path $themesPath "${ThemeName}.omp.json"

        if (-not (Test-Path $themeFile)) {
            Write-Verbose "OMP theme file not found: $themeFile; using defaults."
            return $defaults
        }

        $json = Get-Content $themeFile -Raw -Encoding UTF8 | ConvertFrom-Json

        # --- helper: detect whether a hex colour is "dark" -----------------
        $isDark = {
            param([string]$hex)
            if (-not $hex -or $hex.Length -lt 7) { return $true }
            $hex = $hex.TrimStart('#')
            try {
                $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
                $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
                $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
                $luminance = (0.299 * $r + 0.587 * $g + 0.114 * $b) / 255
                return ($luminance -lt 0.5)
            } catch { return $true }
        }

        # --- helper: detect blue-ish colour --------------------------------
        $isBlue = {
            param([string]$hex)
            if (-not $hex -or $hex.Length -lt 7) { return $false }
            $hex = $hex.TrimStart('#')
            try {
                $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
                $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
                $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
                return ($b -gt $r -and $b -gt $g)
            } catch { return $false }
        }

        # --- helper: detect green-ish colour -------------------------------
        $isGreen = {
            param([string]$hex)
            if (-not $hex -or $hex.Length -lt 7) { return $false }
            $hex = $hex.TrimStart('#')
            try {
                $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
                $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
                $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
                return ($g -gt $r -and $g -gt $b)
            } catch { return $false }
        }

        # --- helper: detect orange/pink accent colour ----------------------
        $isOrangePink = {
            param([string]$hex)
            if (-not $hex -or $hex.Length -lt 7) { return $false }
            $hex = $hex.TrimStart('#')
            try {
                $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
                $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
                $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
                return ($r -gt $g -and $r -gt $b)
            } catch { return $false }
        }

        if ($json.palette) {
            $palette = $json.palette

            # Collect all colour values from the palette
            $colors = @()
            foreach ($prop in $palette.PSObject.Properties) {
                if ($prop.Value -match '^#[0-9A-Fa-f]{6}') {
                    $colors += $prop.Value
                }
            }

            if ($colors.Count -gt 0) {
                # PromptBg: first dark colour or fallback
                $promptBg = $colors | Where-Object { & $isDark $_ } | Select-Object -First 1
                if (-not $promptBg) { $promptBg = $defaults.PromptBg }

                # PromptFg: first light colour or fallback
                $promptFg = $colors | Where-Object { -not (& $isDark $_) } | Select-Object -First 1
                if (-not $promptFg) { $promptFg = $defaults.PromptFg }

                # PathColor: first blue-ish colour
                $pathColor = $colors | Where-Object { & $isBlue $_ } | Select-Object -First 1
                if (-not $pathColor) { $pathColor = $defaults.PathColor }

                # GitColor: first green-ish colour
                $gitColor = $colors | Where-Object { & $isGreen $_ } | Select-Object -First 1
                if (-not $gitColor) { $gitColor = $defaults.GitColor }

                # AccentColor: first orange/pink colour
                $accentColor = $colors | Where-Object { & $isOrangePink $_ } | Select-Object -First 1
                if (-not $accentColor) { $accentColor = $defaults.AccentColor }

                return @{
                    PromptBg    = $promptBg
                    PromptFg    = $promptFg
                    PathColor   = $pathColor
                    GitColor    = $gitColor
                    AccentColor = $accentColor
                }
            }
        }

        return $defaults
    }
    catch {
        Write-Verbose "Error reading OMP theme: $_"
        return $defaults
    }
}

# ============================================================
#  Update-Preview  (main renderer)
# ============================================================
function Update-Preview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Windows.Controls.Canvas]$Canvas,
        [string]$OverrideTheme,
        [int]$OverrideOpacity = -1,
        [int]$OverrideFontSize = -1,
        [string]$OverrideFontFace,
        [string]$OverrideCursorShape,
        [string]$OverrideColorScheme
    )

    try {
        # --- guard: null or zero-size canvas --------------------------------
        if ($null -eq $Canvas) { return }
        if ($Canvas.ActualWidth -lt 1 -or $Canvas.ActualHeight -lt 1) {
            # Width/Height may not be laid out yet; try Width/Height properties
            if ($Canvas.Width -lt 1 -or $Canvas.Height -lt 1) { return }
        }

        # 1. Clear canvas
        $Canvas.Children.Clear()

        # 2. Load config with overrides
        $Config = Get-AppConfig
        if ($OverrideTheme) { $Config.OMPTheme = $OverrideTheme }
        if ($OverrideOpacity -ge 0) { $Config.Opacity = $OverrideOpacity }
        if ($OverrideFontSize -ge 0) { $Config.FontSize = $OverrideFontSize }
        if ($OverrideFontFace) { $Config.FontFace = $OverrideFontFace }
        if ($OverrideCursorShape) { $Config.CursorShape = $OverrideCursorShape }
        if ($OverrideColorScheme) { $Config.ColorScheme = $OverrideColorScheme }

        # 3. Resolve colour scheme
        $schemes    = Get-WTColorSchemes
        $schemeName = $Config.ColorScheme
        $scheme     = $schemes | Where-Object { $_.name -eq $schemeName } | Select-Object -First 1

        # Build a lookup hashtable from the matched scheme (or defaults)
        $defaultTokyo = Get-TokyoNightScheme

        $sc = @{}
        foreach ($key in $defaultTokyo.Keys) {
            if ($scheme -and $scheme.PSObject.Properties[$key]) {
                $sc[$key] = $scheme.PSObject.Properties[$key].Value
            } else {
                $sc[$key] = $defaultTokyo[$key]
            }
        }

        # 4. Resolve theme colours
        $theme = Get-ThemeColors -ThemeName $Config.OMPTheme

        # 5. Canvas dimensions
        $cWidth  = if ($Canvas.ActualWidth  -gt 0) { $Canvas.ActualWidth  } else { 560 }
        $cHeight = if ($Canvas.ActualHeight -gt 0) { $Canvas.ActualHeight } else { 300 }

        # 6. Font resolution
        $fontSize = if ($Config.FontSize) { $Config.FontSize } else { 12 }
        $fontFace = if ($Config.FontFace) { $Config.FontFace } else { "Consolas" }

        try {
            $installedFonts = [System.Drawing.Text.InstalledFontCollection]::new().Families
            $fontFound = $installedFonts | Where-Object { $_.Name -eq $fontFace }
            if (-not $fontFound) {
                $fontFace = "Consolas"
            }
        }
        catch {
            # If font detection fails, just use whatever was requested
            Write-Verbose "Font check failed, using '$fontFace' as-is."
        }

        # 7. Background rectangle
        $bgRect = New-Object System.Windows.Shapes.Rectangle
        $bgRect.Width  = $cWidth
        $bgRect.Height = $cHeight
        $bgRect.Fill   = (New-Object System.Windows.Media.SolidColorBrush(
            ([System.Windows.Media.ColorConverter]::ConvertFromString($sc.background))
        ))
        if ($Config.UseAcrylic) {
            $bgRect.Opacity = [double]$Config.Opacity / 100.0
        }
        [System.Windows.Controls.Canvas]::SetLeft($bgRect, 0)
        [System.Windows.Controls.Canvas]::SetTop($bgRect, 0)
        $Canvas.Children.Add($bgRect) | Out-Null

        # 8. Title bar
        $titleBar = New-Object System.Windows.Shapes.Rectangle
        $titleBar.Width  = $cWidth
        $titleBar.Height = 28
        $titleBar.Fill   = (New-Object System.Windows.Media.SolidColorBrush(
            ([System.Windows.Media.ColorConverter]::ConvertFromString("#2C2521"))
        ))
        [System.Windows.Controls.Canvas]::SetLeft($titleBar, 0)
        [System.Windows.Controls.Canvas]::SetTop($titleBar, 0)
        $Canvas.Children.Add($titleBar) | Out-Null

        $currentDir = (Get-Location).Path
        $titleText = New-Object System.Windows.Controls.TextBlock
        $titleText.Text        = $currentDir
        $titleText.Foreground  = (New-Object System.Windows.Media.SolidColorBrush(
            ([System.Windows.Media.ColorConverter]::ConvertFromString("#A9B1D6"))
        ))
        $titleText.FontSize    = 11
        $titleText.FontFamily  = New-Object System.Windows.Media.FontFamily($fontFace)
        $titleText.Margin      = New-Object System.Windows.Thickness(8, 4, 0, 0)
        [System.Windows.Controls.Canvas]::SetLeft($titleText, 0)
        [System.Windows.Controls.Canvas]::SetTop($titleText, 0)
        $Canvas.Children.Add($titleText) | Out-Null

        # 9. Prompt line at y = 40
        $promptPanel = New-Object System.Windows.Controls.StackPanel
        $promptPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        # "PS "
        $psLabel = New-Object System.Windows.Controls.TextBlock
        $psLabel.Text       = "PS "
        $psLabel.Foreground = (New-Object System.Windows.Media.SolidColorBrush(
            ([System.Windows.Media.ColorConverter]::ConvertFromString($theme.PathColor))
        ))
        $psLabel.FontSize   = $fontSize
        $psLabel.FontFamily = New-Object System.Windows.Media.FontFamily($fontFace)
        $promptPanel.Children.Add($psLabel) | Out-Null

        # Current path
        $userName = if ($env:USERNAME) { $env:USERNAME } else { "user" }
        $pathText = New-Object System.Windows.Controls.TextBlock
        $pathText.Text       = "C:\Users\$userName "
        $pathText.Foreground = (New-Object System.Windows.Media.SolidColorBrush(
            ([System.Windows.Media.ColorConverter]::ConvertFromString($theme.PathColor))
        ))
        $pathText.FontSize   = $fontSize
        $pathText.FontFamily = New-Object System.Windows.Media.FontFamily($fontFace)
        $promptPanel.Children.Add($pathText) | Out-Null

        # "$ "
        $dollarSign = New-Object System.Windows.Controls.TextBlock
        $dollarSign.Text       = "`$ "
        $dollarSign.Foreground = (New-Object System.Windows.Media.SolidColorBrush(
            ([System.Windows.Media.ColorConverter]::ConvertFromString($theme.AccentColor))
        ))
        $dollarSign.FontSize   = $fontSize
        $dollarSign.FontFamily = New-Object System.Windows.Media.FontFamily($fontFace)
        $promptPanel.Children.Add($dollarSign) | Out-Null

        [System.Windows.Controls.Canvas]::SetLeft($promptPanel, 0)
        [System.Windows.Controls.Canvas]::SetTop($promptPanel, 40)
        $Canvas.Children.Add($promptPanel) | Out-Null

        # 10. Sample output lines
        $outputY = 40 + $fontSize * 1.8

        $outLine1 = New-Object System.Windows.Controls.TextBlock
        $outLine1.Text       = "Hello from Claude Beautify!"
        $outLine1.Foreground = (New-Object System.Windows.Media.SolidColorBrush(
            ([System.Windows.Media.ColorConverter]::ConvertFromString($sc.foreground))
        ))
        $outLine1.FontSize   = $fontSize
        $outLine1.FontFamily = New-Object System.Windows.Media.FontFamily($fontFace)
        [System.Windows.Controls.Canvas]::SetLeft($outLine1, 0)
        [System.Windows.Controls.Canvas]::SetTop($outLine1, $outputY)
        $Canvas.Children.Add($outLine1) | Out-Null

        $line2Y = $outputY + $fontSize * 1.6

        $outLine2 = New-Object System.Windows.Controls.TextBlock
        $outLine2.Text       = "Tokyo Night theme active"
        $outLine2.Foreground = (New-Object System.Windows.Media.SolidColorBrush(
            ([System.Windows.Media.ColorConverter]::ConvertFromString($sc.green))
        ))
        $outLine2.FontSize   = $fontSize
        $outLine2.FontFamily = New-Object System.Windows.Media.FontFamily($fontFace)
        [System.Windows.Controls.Canvas]::SetLeft($outLine2, 0)
        [System.Windows.Controls.Canvas]::SetTop($outLine2, $line2Y)
        $Canvas.Children.Add($outLine2) | Out-Null

        # 11. Cursor
        $cursorY = $line2Y + $fontSize * 1.6
        $cursorX = 0

        $cursorW = $fontSize * 0.6
        $cursorH = $fontSize * 1.2

        $cursorShape = if ($Config.CursorShape) { $Config.CursorShape } else { "filledBox" }
        $cursorBrush = (New-Object System.Windows.Media.SolidColorBrush(
            ([System.Windows.Media.ColorConverter]::ConvertFromString($sc.foreground))
        ))

        $cursor = New-Object System.Windows.Shapes.Rectangle

        switch ($cursorShape) {
            "filledBox" {
                $cursor.Width  = $cursorW
                $cursor.Height = $cursorH
                $cursor.Fill   = $cursorBrush
            }
            "emptyBox" {
                $cursor.Width    = $cursorW
                $cursor.Height   = $cursorH
                $cursor.Stroke   = $cursorBrush
                $cursor.StrokeThickness = 1
            }
            "bar" {
                $cursor.Width  = 2
                $cursor.Height = $cursorH
                $cursor.Fill   = $cursorBrush
            }
            "underscore" {
                $cursor.Width  = $cursorW
                $cursor.Height = 2
                $cursor.Fill   = $cursorBrush
            }
            "vintage" {
                $cursor.Width   = 2
                $cursor.Height  = $cursorH
                $cursor.Fill    = $cursorBrush
                $cursor.Opacity = 0.5
            }
            default {
                # Fallback to filledBox
                $cursor.Width  = $cursorW
                $cursor.Height = $cursorH
                $cursor.Fill   = $cursorBrush
            }
        }

        [System.Windows.Controls.Canvas]::SetLeft($cursor, $cursorX)
        [System.Windows.Controls.Canvas]::SetTop($cursor, $cursorY)
        $Canvas.Children.Add($cursor) | Out-Null
    }
    catch {
        Write-Verbose "Preview rendering error: $_"
    }
}

# ============================================================
#  Exports
# ============================================================
Export-ModuleMember -Function Get-WTColorSchemes, Get-ThemeColors, Update-Preview
