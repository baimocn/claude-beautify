## Modules\Utils.psm1
## Shared utility functions — no UI dependency.

$Script:AppLog = @()

function Write-AppLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Position = 1)]
        [ValidateSet("Info", "Warn", "Error")]
        [string]$Level = "Info"
    )

    $entry = @{
        Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Level     = $Level
        Message   = $Message
    }
    $Script:AppLog += $entry

    $color = switch ($Level) {
        "Info"  { "Cyan" }
        "Warn"  { "Yellow" }
        "Error" { "Red" }
    }
    Write-Host "[$($entry.Timestamp)] [$Level] $Message" -ForegroundColor $color
}

function Get-AppLog {
    [CmdletBinding()]
    param()

    return $Script:AppLog
}

function Test-AdminPrivilege {
    [CmdletBinding()]
    param()

    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-ChocolateyInstalled {
    [CmdletBinding()]
    param()

    try {
        $null = Get-Command choco -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Test-NetworkAvailable {
    [CmdletBinding()]
    param()

    try {
        $result = Test-Connection -ComputerName "community.chocolatey.org" -Count 1 -Quiet -ErrorAction Stop
        return [bool]$result
    }
    catch {
        return $false
    }
}

function Get-SafeFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )

    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $safe = $Name
    foreach ($char in $invalid) {
        $safe = $safe.Replace([string]$char, "_")
    }
    return $safe
}

function Read-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            Write-AppLog "JSON file not found: $Path" -Level Warn
            return $null
        }
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        Write-AppLog "Failed to read JSON file '$Path': $_" -Level Error
        return $null
    }
}

function Write-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        $Data
    )

    try {
        $json = $Data | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText($Path, $json, [Text.Encoding]::UTF8)
        return $true
    }
    catch {
        Write-AppLog "Failed to write JSON file '$Path': $_" -Level Error
        return $false
    }
}

function Invoke-Elevated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Command
    )

    try {
        $proc = Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$Command`"" -Wait -PassThru -ErrorAction Stop
        return $proc.ExitCode
    }
    catch {
        Write-AppLog "Failed to invoke elevated command: $_" -Level Error
        return -1
    }
}

function Get-InstalledFonts {
    [CmdletBinding()]
    param()

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $fontCollection = New-Object System.Drawing.Text.InstalledFontCollection
        $families = $fontCollection.Families | ForEach-Object { $_.Name }
        return $families
    }
    catch {
        Write-AppLog "Failed to enumerate installed fonts: $_" -Level Error
        return @()
    }
}

Export-ModuleMember -Function @(
    'Write-AppLog',
    'Get-AppLog',
    'Test-AdminPrivilege',
    'Test-ChocolateyInstalled',
    'Test-NetworkAvailable',
    'Get-SafeFileName',
    'Read-JsonFile',
    'Write-JsonFile',
    'Invoke-Elevated',
    'Get-InstalledFonts'
)
