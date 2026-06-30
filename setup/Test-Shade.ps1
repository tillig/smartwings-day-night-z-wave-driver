#Requires -Version 7.0
<#
.SYNOPSIS
    Sanity-check (and optionally fix) a SmartWings day/night shade after pairing
    or a driver switch. Idempotent and safe to re-run.

.DESCRIPTION
    Given a shade's parent device, this script:

      1. Verifies the device is on the SmartWings Day/Night driver and has the
         expected components (main / scene / favorite).
      2. Removes the leftover "Z-Wave Device Multichannel" dummy child devices
         that the stock driver spawns (the metering-dimmer children, keys 01/02),
         keeping our "<name> Sheer" child.
      3. Resyncs displayed state so positions (especially the Sheer child) match
         reality. By default this is a movement-free refresh (a SWITCH_MULTILEVEL
         GET), which on these lazy motors is best-effort. With -Force it recalls
         the saved favorite -- a position command that reliably forces fresh
         reports (and barely moves the shade if it's already at the favorite).
      4. Prints a health summary.

    Nothing is deleted or commanded without being reported first.

.PARAMETER DeviceId
    The parent shade's device ID. Use this or -DeviceLabel.

.PARAMETER DeviceLabel
    The parent shade's label (e.g. 'Master Bedroom Blinds'). Resolved to an ID;
    must match exactly one device.

.PARAMETER Force
    Use the reliable position-command resync (recall favorite) instead of the
    movement-free GET refresh. May nudge the motors.

.EXAMPLE
    ./Test-Shade.ps1 -DeviceLabel 'Master Bedroom Blinds'

.EXAMPLE
    # Reliable resync (allows slight motor movement):
    ./Test-Shade.ps1 -DeviceLabel 'Family Room Shade 2' -Force

.NOTES
    Requires the authenticated SmartThings CLI (any command opens a browser to
    log in the first time).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string] $DeviceId = '',

    [Parameter()]
    [string] $DeviceLabel = '',

    [Parameter()]
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Identifiers for this project's driver and the expected shape of a shade.
$driverId = '579868c7-16a6-4b53-85c8-4f42c0c3a69e'
$expectedComponents = @('main', 'scene', 'favorite')
$problems = [System.Collections.Generic.List[string]]::new()

function Get-Prop {
    # Null-safe property read (Set-StrictMode throws on a missing property).
    param($Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Get-StJson {
    param([Parameter(Mandatory)] [string[]] $CliArgs)
    # Run the CLI and parse the leading JSON value, ignoring any trailing
    # plain-text status lines the CLI sometimes appends.
    $raw = (& smartthings @CliArgs 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "smartthings $($CliArgs -join ' ') failed:`n$raw"
    }
    $start = $raw.IndexOf('[')
    $braceStart = $raw.IndexOf('{')
    if ($start -lt 0 -or ($braceStart -ge 0 -and $braceStart -lt $start)) { $start = $braceStart }
    $end = [Math]::Max($raw.LastIndexOf(']'), $raw.LastIndexOf('}'))
    if ($start -lt 0 -or $end -lt $start) { throw "No JSON in output of: smartthings $($CliArgs -join ' ')" }
    return $raw.Substring($start, $end - $start + 1) | ConvertFrom-Json
}

Write-Host '=== SmartWings Day/Night: Shade Sanity Check ===' -ForegroundColor Cyan

# --- Prerequisites ----------------------------------------------------------
if (-not (Get-Command 'smartthings' -ErrorAction SilentlyContinue)) {
    Write-Error 'SmartThings CLI not found. Install: npm install -g @smartthings/cli'
    exit 1
}
if (-not $DeviceId -and -not $DeviceLabel) {
    Write-Error 'Provide -DeviceId or -DeviceLabel.'
    exit 1
}

# --- Resolve the device -----------------------------------------------------
$allDevices = Get-StJson -CliArgs @('devices', '--json')

if (-not $DeviceId) {
    $found = @($allDevices | Where-Object { $_.label -eq $DeviceLabel })
    if ($found.Count -eq 0) { Write-Error "No device labeled '$DeviceLabel'."; exit 1 }
    if ($found.Count -gt 1) { Write-Error "Multiple devices labeled '$DeviceLabel'; use -DeviceId."; exit 1 }
    $DeviceId = $found[0].deviceId
}

$device = $allDevices | Where-Object { $_.deviceId -eq $DeviceId } | Select-Object -First 1
if (-not $device) { Write-Error "Device $DeviceId not found."; exit 1 }
Write-Host "Device: $($device.label)  [$DeviceId]" -ForegroundColor Green

# --- 1. Verify driver + components ------------------------------------------
Write-Host "`n--- Driver and profile ---" -ForegroundColor Cyan
$zwave = Get-Prop $device 'zwave'
$deviceDriverId = Get-Prop $zwave 'driverId'
$onOurDriver = ($deviceDriverId -eq $driverId)
if ($onOurDriver) {
    Write-Host '  Driver: SmartWings Day/Night Z-Wave (correct)' -ForegroundColor Green
}
else {
    $problems.Add('Device is NOT on the SmartWings Day/Night driver. Assign it in the app (Device -> driver).')
    Write-Host "  Driver: $deviceDriverId (NOT ours)" -ForegroundColor Yellow
}

$componentIds = @($device.components | ForEach-Object { $_.id })
foreach ($c in $expectedComponents) {
    if ($componentIds -notcontains $c) {
        $problems.Add("Missing expected component '$c' (driver may need a re-select in the app to apply the profile).")
    }
}
Write-Host "  Components: $($componentIds -join ', ')"

# --- 2. Remove stock dummy children -----------------------------------------
Write-Host "`n--- Child devices ---" -ForegroundColor Cyan
$children = @($allDevices | Where-Object { (Get-Prop $_ 'parentDeviceId') -eq $DeviceId })
foreach ($child in $children) {
    $key = Get-Prop (Get-Prop $child 'edgeChild') 'parentAssignedChildKey'
    $caps = @($child.components | ForEach-Object { $_.capabilities } | ForEach-Object { $_.id })
    $isDummy = ($key -eq '01' -or $key -eq '02') -and ($caps -contains 'powerMeter') -and ($caps -contains 'switchLevel')
    if ($isDummy) {
        Write-Host "  Dummy child: $($child.label) [$($child.deviceId)]" -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($child.label, 'Delete stock dummy child device')) {
            & smartthings devices:delete $child.deviceId *> $null
            if ($LASTEXITCODE -eq 0) { Write-Host '    deleted.' -ForegroundColor Green }
            else { $problems.Add("Failed to delete dummy child $($child.deviceId).") }
        }
    }
    else {
        Write-Host "  Keep: $($child.label) (key '$key')" -ForegroundColor Green
    }
}
if (-not ($children | Where-Object { (Get-Prop (Get-Prop $_ 'edgeChild') 'parentAssignedChildKey') -eq 'sheer' })) {
    $problems.Add("No 'Sheer' child device found. It is created on driver init; try a refresh or re-select the driver.")
}

# --- 3. Resync state --------------------------------------------------------
Write-Host "`n--- Resync state ---" -ForegroundColor Cyan
if ($onOurDriver) {
    if ($Force) {
        Write-Host '  Recalling favorite to force fresh reports (-Force)...'
        if ($PSCmdlet.ShouldProcess($device.label, 'Recall favorite (position command)')) {
            & smartthings devices:commands $DeviceId 'favorite:happyvessel61954.settings:recall' *> $null
        }
    }
    else {
        Write-Host '  Refreshing (movement-free; best-effort on lazy motors)...'
        & smartthings devices:commands $DeviceId 'main:refresh:refresh' *> $null
        Write-Host '  (If positions still look wrong, re-run with -Force, or tap a scene/favorite button.)' -ForegroundColor DarkYellow
    }
    Start-Sleep -Seconds 6
}
else {
    Write-Host '  Skipped (device not on our driver).' -ForegroundColor DarkYellow
}

# --- 4. Health summary ------------------------------------------------------
Write-Host "`n--- Health summary ---" -ForegroundColor Cyan
$status = Get-StJson -CliArgs @('devices:status', $DeviceId, '--json')
$main = Get-Prop (Get-Prop $status 'components') 'main'
$mainLevel = Get-Prop (Get-Prop $main 'windowShadeLevel') 'shadeLevel'
if ($mainLevel) { Write-Host "  Shade (bottom rail): $($mainLevel.value)%" }
$mainBatt = Get-Prop (Get-Prop $main 'battery') 'battery'
if ($mainBatt) { Write-Host "  Battery: $($mainBatt.value)%" }
$fav = Get-Prop (Get-Prop $status 'components') 'favorite'
$preset = Get-Prop (Get-Prop $fav 'happyvessel61954.presetPosition') 'position'
if ($preset) { Write-Host "  Saved favorite: $($preset.value)" }
$sheerChild = $children | Where-Object { (Get-Prop (Get-Prop $_ 'edgeChild') 'parentAssignedChildKey') -eq 'sheer' } | Select-Object -First 1
if ($sheerChild) {
    $cs = Get-StJson -CliArgs @('devices:status', $sheerChild.deviceId, '--json')
    $csLevel = Get-Prop (Get-Prop (Get-Prop (Get-Prop $cs 'components') 'main') 'windowShadeLevel') 'shadeLevel'
    if ($csLevel) { Write-Host "  Sheer: $($csLevel.value)%" }
}

Write-Host ''
if ($problems.Count -eq 0) {
    Write-Host 'OK: shade looks healthy.' -ForegroundColor Green
}
else {
    Write-Host "Found $($problems.Count) issue(s):" -ForegroundColor Yellow
    foreach ($p in $problems) { Write-Host "  - $p" -ForegroundColor Yellow }
}
