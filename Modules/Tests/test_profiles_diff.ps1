# test_profiles_diff.ps1
# Tests for Compare-Profiles, Merge-Profiles, and Apply-ProfilePartial
#
# Run on Windows: powershell -ExecutionPolicy Bypass -File test_profiles_diff.ps1
#
# These tests work by temporarily creating test profile files in a test directory,
# exercising the profile functions, and cleaning up afterward.

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Setup: determine paths and import modules
# ---------------------------------------------------------------------------

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulesDir = Split-Path -Parent $ScriptDir
$ProjectRoot = Split-Path -Parent $ModulesDir

# Import dependencies
Import-Module (Join-Path $ModulesDir "Utils.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $ModulesDir "State.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $ModulesDir "Constants.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $ModulesDir "Detection.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $ModulesDir "Actions.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $ModulesDir "Profiles.psm1") -Force -DisableNameChecking

# Override ProfilesDir to use a temp test directory
$TestProfilesDir = Join-Path $env:TEMP "claude_beautify_test_profiles_$(Get-Random)"
New-Item -ItemType Directory -Path $TestProfilesDir -Force | Out-Null

# Access the module's internal variable via reflection
$profilesModule = Get-Module "Profiles"
if ($profilesModule) {
    & $profilesModule { $Script:ProfilesDir = $using:TestProfilesDir }
}

$passed = 0
$failed = 0
$failures = @()

function Assert-Equal {
    param($Expected, $Actual, $Message)
    if ($Expected -ne $Actual) {
        throw "$Message — expected '$Expected', got '$Actual'"
    }
}

function Assert-True {
    param($Condition, $Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-False {
    param($Condition, $Message)
    if ($Condition) {
        throw $Message
    }
}

function Assert-ArrayEqual {
    param($Expected, $Actual, $Message)
    if ($Expected.Count -ne $Actual.Count) {
        throw "$Message — count mismatch: expected $($Expected.Count), got $($Actual.Count)"
    }
    for ($i = 0; $i -lt $Expected.Count; $i++) {
        if ($Expected[$i] -ne $Actual[$i]) {
            throw "$Message — index $i: expected '$($Expected[$i])', got '$($Actual[$i])'"
        }
    }
}

function Run-Test {
    param(
        [string]$Name,
        [scriptblock]$Block
    )
    try {
        & $Block
        $script:passed++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    }
    catch {
        $script:failed++
        $script:failures += @{ Name = $Name; Error = $_.Exception.Message }
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        Write-Host "         $($_.Exception.Message)" -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------------------
# Helper: create a test profile file with given config
# ---------------------------------------------------------------------------

function New-TestProfile {
    param(
        [string]$Name,
        [hashtable]$Config,
        [string]$Notes = ""
    )

    $profileObj = @{
        name      = $Name
        version   = 1
        createdAt = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
        config    = [PSCustomObject]$Config
        notes     = $Notes
    }

    $json = $profileObj | ConvertTo-Json -Depth 10
    $safeName = $Name -replace '[^\w\-\.]', '_'
    $filePath = Join-Path $TestProfilesDir "$safeName.json"
    [System.IO.File]::WriteAllText($filePath, $json, [System.Text.Encoding]::UTF8)
    Write-Host "    Created test profile: $filePath" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# Test suite 1: Compare-Profiles with identical profiles
# ---------------------------------------------------------------------------

Write-Host "`n=== Test Suite 1: Compare-Profiles (identical profiles) ===" -ForegroundColor Cyan

Run-Test -Name "Compare identical profiles returns 0 differences" -Block {
    New-TestProfile -Name "IdenticalA" -Config @{
        Opacity   = 85
        FontSize  = 12
        FontFace  = "CaskaydiaCove Nerd Font"
        UseAcrylic = $true
        OMPTheme  = "tokyonight_storm"
    }

    New-TestProfile -Name "IdenticalB" -Config @{
        Opacity   = 85
        FontSize  = 12
        FontFace  = "CaskaydiaCove Nerd Font"
        UseAcrylic = $true
        OMPTheme  = "tokyonight_storm"
    }

    $result = Compare-Profiles -Name1 "IdenticalA" -Name2 "IdenticalB"

    Assert-True $result.Success "Compare should succeed"
    Assert-Equal 0 $result.Differences.Count "Differences count"
    Assert-Equal 5 $result.Identical.Count "Identical count"
    Assert-Equal 0 $result.OnlyIn1.Count "OnlyIn1 count"
    Assert-Equal 0 $result.OnlyIn2.Count "OnlyIn2 count"
    Assert-Equal 5 $result.TotalKeys "Total keys"
}

Run-Test -Name "Compare identical profiles marks all keys as identical" -Block {
    $result = Compare-Profiles -Name1 "IdenticalA" -Name2 "IdenticalB"

    $expectedKeys = @("Opacity", "FontSize", "FontFace", "UseAcrylic", "OMPTheme")
    $sortedIdentical = $result.Identical | Sort-Object
    $sortedExpected = $expectedKeys | Sort-Object

    Assert-ArrayEqual $sortedExpected $sortedIdentical "Identical keys list"
}

# ---------------------------------------------------------------------------
# Test suite 2: Compare-Profiles with different profiles
# ---------------------------------------------------------------------------

Write-Host "`n=== Test Suite 2: Compare-Profiles (different profiles) ===" -ForegroundColor Cyan

Run-Test -Name "Compare different profiles correctly identifies all differences" -Block {
    New-TestProfile -Name "DarkTheme" -Config @{
        Opacity      = 90
        FontSize     = 14
        FontFace     = "CaskaydiaCove Nerd Font"
        UseAcrylic   = $true
        CursorShape  = "filledBox"
        CursorHeight = 25
        ColorScheme  = "Tokyo Night"
        OMPTheme     = "tokyonight_storm"
        Padding      = "8, 8, 8, 8"
    } -Notes "Dark theme + big font"

    New-TestProfile -Name "LightTheme" -Config @{
        Opacity      = 80
        FontSize     = 10
        FontFace     = "Consolas"
        UseAcrylic   = $false
        CursorShape  = "bar"
        CursorHeight = 100
        ColorScheme  = "Light Theme"
        OMPTheme     = "light-plus"
        Padding      = "8, 8, 8, 8"
    } -Notes "Light theme + small font"

    $result = Compare-Profiles -Name1 "DarkTheme" -Name2 "LightTheme"

    Assert-True $result.Success "Compare should succeed"

    # Padding is the same, everything else differs
    Assert-Equal 8 $result.Differences.Count "Differences count"
    Assert-Equal 1 $result.Identical.Count "Identical count (Padding)"
    Assert-Equal "Padding" $result.Identical[0] "Identical key should be Padding"
    Assert-Equal 0 $result.OnlyIn1.Count "OnlyIn1 count"
    Assert-Equal 0 $result.OnlyIn2.Count "OnlyIn2 count"
    Assert-Equal 9 $result.TotalKeys "Total keys"

    # Verify specific diff values
    $opacityDiff = $result.Differences | Where-Object { $_.Key -eq "Opacity" }
    Assert-True ($null -ne $opacityDiff) "Opacity diff should exist"
    Assert-Equal "90" ($opacityDiff.Profile1Value.ToString()) "Profile1 Opacity"
    Assert-Equal "80" ($opacityDiff.Profile2Value.ToString()) "Profile2 Opacity"

    $fontDiff = $result.Differences | Where-Object { $_.Key -eq "FontFace" }
    Assert-Equal "CaskaydiaCove Nerd Font" ($fontDiff.Profile1Value.ToString()) "Profile1 FontFace"
    Assert-Equal "Consolas" ($fontDiff.Profile2Value.ToString()) "Profile2 FontFace"
}

Run-Test -Name "Compare with keys only in one profile" -Block {
    New-TestProfile -Name "ProfileA" -Config @{
        Opacity  = 85
        FontSize = 12
        FontFace = "CaskaydiaCove Nerd Font"
        OMPTheme = "tokyonight_storm"
        ExtraA   = "only-in-a"
    }

    New-TestProfile -Name "ProfileB" -Config @{
        Opacity  = 85
        FontSize = 12
        FontFace = "CaskaydiaCove Nerd Font"
        OMPTheme = "tokyonight_storm"
        ExtraB   = "only-in-b"
    }

    $result = Compare-Profiles -Name1 "ProfileA" -Name2 "ProfileB"

    Assert-Equal 1 $result.OnlyIn1.Count "OnlyIn1 should have 1 key"
    Assert-Equal "ExtraA" $result.OnlyIn1[0] "OnlyIn1 key"
    Assert-Equal 1 $result.OnlyIn2.Count "OnlyIn2 should have 1 key"
    Assert-Equal "ExtraB" $result.OnlyIn2[0] "OnlyIn2 key"
    Assert-Equal 4 $result.Identical.Count "Identical count"
}

Run-Test -Name "Compare with non-existent profile returns error" -Block {
    $result = Compare-Profiles -Name1 "NoExistA" -Name2 "DarkTheme"
    Assert-False $result.Success "Should fail for missing profile A"
    Assert-True ($result.Message -like "*NoExistA*") "Error message mentions missing profile"

    $result2 = Compare-Profiles -Name1 "DarkTheme" -Name2 "NoExistB"
    Assert-False $result2.Success "Should fail for missing profile B"
    Assert-True ($result2.Message -like "*NoExistB*") "Error message mentions missing profile"
}

# ---------------------------------------------------------------------------
# Test suite 3: Merge-Profiles — three strategies
# ---------------------------------------------------------------------------

Write-Host "`n=== Test Suite 3: Merge-Profiles (strategies) ===" -ForegroundColor Cyan

Run-Test -Name "Merge with prefer_first takes conflicting values from profile A" -Block {
    $result = Merge-Profiles -Name1 "DarkTheme" -Name2 "LightTheme" -NewName "MergedPreferA" -Strategy "prefer_first"

    Assert-True $result.Success "Merge should succeed"
    Assert-Equal "MergedPreferA" $result.NewName "New name"
    Assert-Equal "prefer_first" $result.Strategy "Strategy"

    # Load the merged profile and verify
    $merged = Get-ProfileDetail -Name "MergedPreferA"
    Assert-True ($null -ne $merged) "Merged profile should exist"

    # Conflicting keys should have profile A values
    Assert-Equal "90" ($merged.config.Opacity.ToString()) "Opacity should be from profile A (90)"
    Assert-Equal "14" ($merged.config.FontSize.ToString()) "FontSize should be from profile A (14)"
    Assert-Equal "Tokyo Night" ($merged.config.ColorScheme.ToString()) "ColorScheme should be from profile A"
    Assert-Equal "tokyonight_storm" ($merged.config.OMPTheme.ToString()) "OMPTheme should be from profile A"

    # Non-conflicting (same) keys should be preserved
    Assert-Equal "8, 8, 8, 8" ($merged.config.Padding.ToString()) "Padding should be same"
}

Run-Test -Name "Merge with prefer_second takes conflicting values from profile B" -Block {
    $result = Merge-Profiles -Name1 "DarkTheme" -Name2 "LightTheme" -NewName "MergedPreferB" -Strategy "prefer_second"

    Assert-True $result.Success "Merge should succeed"
    Assert-Equal "prefer_second" $result.Strategy "Strategy"

    $merged = Get-ProfileDetail -Name "MergedPreferB"
    Assert-True ($null -ne $merged) "Merged profile should exist"

    # Conflicting keys should have profile B values
    Assert-Equal "80" ($merged.config.Opacity.ToString()) "Opacity should be from profile B (80)"
    Assert-Equal "10" ($merged.config.FontSize.ToString()) "FontSize should be from profile B (10)"
    Assert-Equal "Light Theme" ($merged.config.ColorScheme.ToString()) "ColorScheme should be from profile B"
    Assert-Equal "light-plus" ($merged.config.OMPTheme.ToString()) "OMPTheme should be from profile B"
}

Run-Test -Name "Merge with manual strategy returns comparison only, no save" -Block {
    $result = Merge-Profiles -Name1 "DarkTheme" -Name2 "LightTheme" -NewName "ManualMerge" -Strategy "manual"

    Assert-True $result.Success "Merge (manual) should succeed"
    Assert-True $result.Manual "Manual flag should be true"
    Assert-True ($null -ne $result.Comparison) "Should return comparison"
    Assert-True ($result.Comparison.Differences.Count -gt 0) "Comparison should have differences"

    # Manual mode should NOT save a new profile
    $manualProfile = Get-ProfileDetail -Name "ManualMerge"
    Assert-True ($null -eq $manualProfile) "Manual mode should not create a profile file"
}

Run-Test -Name "Merge preserves keys unique to each profile" -Block {
    $result = Merge-Profiles -Name1 "ProfileA" -Name2 "ProfileB" -NewName "MergedUnique" -Strategy "prefer_first"

    Assert-True $result.Success "Merge should succeed"

    $merged = Get-ProfileDetail -Name "MergedUnique"
    Assert-True ($null -ne $merged) "Merged profile should exist"

    # Both unique keys should be present
    Assert-True ($null -ne $merged.config.PSObject.Properties['ExtraA']) "ExtraA should exist"
    Assert-True ($null -ne $merged.config.PSObject.Properties['ExtraB']) "ExtraB should exist"
    Assert-Equal "only-in-a" ($merged.config.ExtraA.ToString()) "ExtraA value"
    Assert-Equal "only-in-b" ($merged.config.ExtraB.ToString()) "ExtraB value"
}

Run-Test -Name "Merge with non-existent source returns error" -Block {
    $result = Merge-Profiles -Name1 "NoSuch" -Name2 "DarkTheme" -NewName "FailMerge" -Strategy "prefer_first"
    Assert-False $result.Success "Should fail with missing first profile"
    Assert-True ($result.Message -like "*NoSuch*") "Error mentions missing profile"

    $result2 = Merge-Profiles -Name1 "DarkTheme" -Name2 "NoSuchEither" -NewName "FailMerge2" -Strategy "prefer_first"
    Assert-False $result2.Success "Should fail with missing second profile"
}

# ---------------------------------------------------------------------------
# Test suite 4: Apply-ProfilePartial
# ---------------------------------------------------------------------------

Write-Host "`n=== Test Suite 4: Apply-ProfilePartial ===" -ForegroundColor Cyan

Run-Test -Name "Apply-ProfilePartial only modifies specified keys" -Block {
    # Save current config
    $origConfig = Get-AppConfig

    # Create a test profile with different values
    New-TestProfile -Name "PartialTest" -Config @{
        Opacity      = 99
        FontSize     = 99
        FontFace     = "TestFont"
        UseAcrylic   = $false
        CursorShape  = "vintage"
        CursorHeight = 50
        ColorScheme  = "TestScheme"
        OMPTheme     = "test_theme"
        Padding      = "1, 2, 3, 4"
    }

    # Apply only FontSize and FontFace
    $result = Apply-ProfilePartial -Name "PartialTest" -Keys @("FontSize", "FontFace")

    Assert-True $result.Success "Partial apply should succeed"
    Assert-Equal 2 $result.AppliedKeys.Count "Should apply 2 keys"
    Assert-True ($result.AppliedKeys -contains "FontSize") "FontSize applied"
    Assert-True ($result.AppliedKeys -contains "FontFace") "FontFace applied"

    # Verify only specified keys changed
    $newConfig = Get-AppConfig
    Assert-Equal "99" ($newConfig.FontSize.ToString()) "FontSize should change"
    Assert-Equal "TestFont" ($newConfig.FontFace.ToString()) "FontFace should change"

    # Other keys should remain unchanged
    Assert-Equal $origConfig.Opacity $newConfig.Opacity "Opacity should NOT change"
    Assert-Equal $origConfig.UseAcrylic $newConfig.UseAcrylic "UseAcrylic should NOT change"
    Assert-Equal $origConfig.ColorScheme $newConfig.ColorScheme "ColorScheme should NOT change"
    Assert-Equal $origConfig.OMPTheme $newConfig.OMPTheme "OMPTheme should NOT change"
    Assert-Equal $origConfig.CursorShape $newConfig.CursorShape "CursorShape should NOT change"
    Assert-Equal $origConfig.Padding $newConfig.Padding "Padding should NOT change"
}

Run-Test -Name "Apply-ProfilePartial skips non-existent keys" -Block {
    $result = Apply-ProfilePartial -Name "PartialTest" -Keys @("FontSize", "NonExistentKey", "AnotherFake")

    Assert-True $result.Success "Partial apply should succeed even with bad keys"
    Assert-Equal 1 $result.AppliedKeys.Count "Only 1 valid key applied"
    Assert-Equal 2 $result.SkippedKeys.Count "2 keys should be skipped"
    Assert-True ($result.SkippedKeys -contains "NonExistentKey") "NonExistentKey skipped"
    Assert-True ($result.SkippedKeys -contains "AnotherFake") "AnotherFake skipped"
}

Run-Test -Name "Apply-ProfilePartial with all keys applies everything" -Block {
    $result = Apply-ProfilePartial -Name "PartialTest" -Keys @("Opacity", "FontSize", "FontFace", "OMPTheme")

    Assert-True $result.Success "Should succeed"
    Assert-Equal 4 $result.AppliedKeys.Count "All 4 keys applied"

    $newConfig = Get-AppConfig
    Assert-Equal "99" ($newConfig.Opacity.ToString()) "Opacity changed"
    Assert-Equal "99" ($newConfig.FontSize.ToString()) "FontSize changed"
    Assert-Equal "TestFont" ($newConfig.FontFace.ToString()) "FontFace changed"
    Assert-Equal "test_theme" ($newConfig.OMPTheme.ToString()) "OMPTheme changed"
}

Run-Test -Name "Apply-ProfilePartial with non-existent profile returns error" -Block {
    $result = Apply-ProfilePartial -Name "NoSuchProfile" -Keys @("FontSize")
    Assert-False $result.Success "Should fail for missing profile"
    Assert-True ($result.Message -like "*NoSuchProfile*") "Error mentions missing profile"
}

Run-Test -Name "Apply-ProfilePartial with empty keys array does nothing" -Block {
    $before = Get-AppConfig

    $result = Apply-ProfilePartial -Name "PartialTest" -Keys @()

    # Empty keys might succeed but apply nothing
    Assert-Equal 0 $result.AppliedKeys.Count "Should apply 0 keys"

    $after = Get-AppConfig
    # Config should be unchanged
    foreach ($key in $before.Keys) {
        $beforeVal = if ($null -eq $before[$key]) { "" } else { $before[$key].ToString() }
        $afterVal = if ($null -eq $after[$key]) { "" } else { $after[$key].ToString() }
        Assert-Equal $beforeVal $afterVal "Key $key should be unchanged"
    }
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

Write-Host "`n=== Cleanup ===" -ForegroundColor Cyan
try {
    Remove-Item -Path $TestProfilesDir -Recurse -Force -ErrorAction Stop
    Write-Host "  Cleaned up test directory: $TestProfilesDir" -ForegroundColor Gray
}
catch {
    Write-Host "  Warning: could not clean up $TestProfilesDir : $_" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Results: $passed passed, $failed failed" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($failures.Count -gt 0) {
    Write-Host "`nFailed tests:" -ForegroundColor Red
    foreach ($f in $failures) {
        Write-Host "  - $($f.Name): $($f.Error)" -ForegroundColor Red
    }
    exit 1
}
else {
    Write-Host "`nAll tests passed!`n" -ForegroundColor Green
    exit 0
}
