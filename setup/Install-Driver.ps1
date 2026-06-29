#Requires -Version 7.0
<#
.SYNOPSIS
    Packages, assigns to a channel, and installs the SmartWings Day/Night
    Z-Wave driver onto a SmartThings hub.

.DESCRIPTION
    This script does the following in order:

      1. Resolves (or creates) a SmartThings Edge channel.
      2. Packages the driver (driver/ directory), assigns it to the channel,
         and installs it on the target hub -- all with one CLI call:
             smartthings edge:drivers:package driver --channel <id> --hub <id>

    The hub is automatically enrolled in the channel by that command.

.PARAMETER HubId
    The SmartThings hub ID to install the driver on.
    Run `smartthings edge:hubs` to find yours.
    Example: 00000000-0000-0000-0000-00000000HUB0

.PARAMETER ChannelId
    (Optional) An existing Edge channel ID to use.
    If not supplied, a new channel is created and its ID is printed so you can
    record it for future runs.
    Example: 00000000-0000-0000-0000-0000000CHAN0

.PARAMETER ChannelName
    (Optional) Name for the new channel if -ChannelId is not provided.
    Defaults to "SmartWings Day/Night Z-Wave".

.PARAMETER ChannelDescription
    (Optional) Description for the new channel if one is being created.
    Defaults to a short driver description.

.EXAMPLE
    # Create a new channel automatically, then install on hub:
    ./Install-Driver.ps1 -HubId '00000000-0000-0000-0000-00000000HUB0'

.EXAMPLE
    # Use an existing channel:
    ./Install-Driver.ps1 `
        -HubId       '00000000-0000-0000-0000-00000000HUB0' `
        -ChannelId   '00000000-0000-0000-0000-0000000CHAN0'

.EXAMPLE
    ./Install-Driver.ps1 -HubId '00000000-0000-0000-0000-00000000HUB0' -Verbose

.NOTES
    Prerequisites:
      1. Node.js + npm are installed.
      2. SmartThings CLI is installed: npm install -g @smartthings/cli
      3. You have logged in: smartthings login
         (Interactive browser login -- run this once before the first script run.)
      4. Custom capabilities have already been created.
         Run ./New-Capabilities.ps1 first if you have not done so.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $HubId,

    [Parameter()]
    [string] $ChannelId = '',

    [Parameter()]
    [string] $ChannelName = 'SmartWings Day/Night Z-Wave',

    [Parameter()]
    [string] $ChannelDescription = 'Edge channel for the SmartWings dual-motor day/night cellular shade Z-Wave driver.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

###############################################################################
# Paths
###############################################################################

$repoRoot  = Split-Path -Parent $PSScriptRoot
$driverDir = Join-Path $repoRoot 'driver'

###############################################################################
# Prerequisite checks
###############################################################################

Write-Host '=== SmartWings Day/Night: Install Driver ===' -ForegroundColor Cyan

Write-Verbose 'Checking for smartthings CLI on PATH...'
if (-not (Get-Command 'smartthings' -ErrorAction SilentlyContinue)) {
    Write-Error @'
The SmartThings CLI was not found on PATH.

Install it with:
    npm install -g @smartthings/cli

Then log in once with:
    smartthings login
'@
    exit 1
}
Write-Verbose "smartthings CLI found at: $((Get-Command 'smartthings').Source)"

Write-Host 'Checking SmartThings authentication...' -ForegroundColor Cyan
Write-Verbose 'Running: smartthings devices --json (used as auth probe)'
$authTest = smartthings devices --json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error @'
The SmartThings CLI does not appear to be authenticated (or returned an error).

Run the following to log in (interactive browser):
    smartthings login

Then re-run this script.
'@
    exit 1
}
Write-Verbose 'Authentication probe succeeded.'

# Verify the driver directory exists and looks like a driver package.
if (-not (Test-Path (Join-Path $driverDir 'config.yml'))) {
    Write-Error "Driver directory does not contain config.yml. Expected: $driverDir"
    exit 1
}

###############################################################################
# Step 1: Resolve or create the channel
###############################################################################

Write-Host "`n=== Step 1: Channel ===" -ForegroundColor Cyan

if ($ChannelId) {
    Write-Host "Using supplied channel ID: $ChannelId" -ForegroundColor Green
}
else {
    Write-Host "No -ChannelId provided. Creating a new channel named: $ChannelName"

    # Build the JSON payload. The `type` field is REQUIRED (omitting it causes a
    # 400 "Channel type must be provided" error from the API).
    $channelPayload = [pscustomobject]@{
        name        = $ChannelName
        description = $ChannelDescription
        type        = 'DRIVER'
        termsOfServiceUrl = ''
    } | ConvertTo-Json -Compress

    # Write to a temp file so we don't have to worry about shell quoting JSON on
    # every platform.
    $tmpPayload = Join-Path ([System.IO.Path]::GetTempPath()) "st-channel-$([System.IO.Path]::GetRandomFileName()).json"
    try {
        Set-Content -Path $tmpPayload -Value $channelPayload -Encoding utf8

        Write-Verbose "Channel payload: $channelPayload"
        Write-Verbose "Running: smartthings edge:channels:create --input `"$tmpPayload`" --json"

        $createOutput = smartthings edge:channels:create --input "$tmpPayload" --json 2>&1
        $createExit   = $LASTEXITCODE

        if ($createExit -ne 0) {
            Write-Error "Failed to create channel (exit $createExit):`n$($createOutput | Out-String)"
        }

        $channel   = $createOutput | ConvertFrom-Json
        $ChannelId = $channel.channelId
        if (-not $ChannelId) {
            # Some CLI versions return 'id' instead of 'channelId'.
            $ChannelId = $channel.id
        }
        if (-not $ChannelId) {
            Write-Error "Channel created but could not extract ID from response:`n$($createOutput | Out-String)"
        }

        Write-Host "Channel created. ID: $ChannelId" -ForegroundColor Green
        Write-Host "(Record this ID; pass it as -ChannelId on future installs to skip re-creation.)" -ForegroundColor DarkYellow
    }
    finally {
        if (Test-Path $tmpPayload) { Remove-Item $tmpPayload -Force }
    }
}

###############################################################################
# Step 2: Package, assign to channel, and install on hub
###############################################################################

Write-Host "`n=== Step 2: Package + Assign + Install ===" -ForegroundColor Cyan
Write-Host "  Driver directory : $driverDir"
Write-Host "  Channel ID       : $ChannelId"
Write-Host "  Hub ID           : $HubId"
Write-Host ''

Write-Verbose "Running: smartthings edge:drivers:package `"$driverDir`" --channel `"$ChannelId`" --hub `"$HubId`" --json"

$pkgOutput = smartthings edge:drivers:package "$driverDir" --channel "$ChannelId" --hub "$HubId" --json 2>&1
$pkgExit   = $LASTEXITCODE

if ($pkgExit -ne 0) {
    Write-Error "Driver package/assign/install failed (exit $pkgExit):`n$($pkgOutput | Out-String)"
}

# Parse the result to display the driver ID.
$driverResult = $null
try {
    $driverResult = $pkgOutput | ConvertFrom-Json
}
catch {
    Write-Verbose 'Response was not parseable JSON; showing raw output.'
}

if ($driverResult) {
    $driverId = $driverResult.driverId
    if (-not $driverId) { $driverId = $driverResult.id }
    Write-Host "Driver packaged and installed successfully." -ForegroundColor Green
    if ($driverId) {
        Write-Host "  Driver ID: $driverId" -ForegroundColor Green
    }
}
else {
    Write-Host 'Driver packaged and installed (raw output below).' -ForegroundColor Green
    Write-Host ($pkgOutput | Out-String)
}

###############################################################################
# Summary
###############################################################################

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "  Channel ID : $ChannelId"
Write-Host "  Hub ID     : $HubId"
if ($driverResult) {
    $driverId = $driverResult.driverId
    if (-not $driverId) { $driverId = $driverResult.id }
    if ($driverId) { Write-Host "  Driver ID  : $driverId" }
}
Write-Host ''
Write-Host 'Installation complete.' -ForegroundColor Green
Write-Host 'The hub has been enrolled in the channel and the driver is installed.' -ForegroundColor Cyan
Write-Host 'Pair your SmartWings shade to the hub to start using it.' -ForegroundColor Cyan
