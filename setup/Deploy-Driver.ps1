#Requires -Version 7.0
<#
.SYNOPSIS
    Package the driver and deploy it to your SmartThings channel — for both the
    first install and every later upgrade.

.DESCRIPTION
    One script for all deploys. It:

      1. Resolves your channel, in order: explicit -ChannelId, then a locally
         cached channel ID (setup/.local/channel-id), then a channel matching
         -ChannelName, then (with -CreateChannel) a newly created channel. The
         resolved ID is cached so later runs need no arguments.
      2. Packages the driver and assigns it to that channel. If -HubId is given,
         the driver is also installed directly on that hub.

    Every hub already enrolled in the channel picks up the new version
    automatically (within ~12 hours, or immediately if you re-select the driver
    on the device in the SmartThings app). No secrets required.

    First-time install: pass -ChannelName (with -CreateChannel if the channel
    does not exist yet) and -HubId to enroll your hub. After that, a bare
    ./Deploy-Driver.ps1 upgrades using the cached channel.

.PARAMETER ChannelId
    (Optional) Explicit channel ID. Overrides the cache and -ChannelName, and is
    written to the cache for next time.

.PARAMETER ChannelName
    (Optional) Channel name to search for when there is no cached ID. Your
    personal channel name (e.g. the one you created at install time).

.PARAMETER CreateChannel
    (Optional switch) If the channel can't be found by ID or name, create a new
    one named -ChannelName instead of failing.

.PARAMETER HubId
    (Optional) If supplied, the driver is also installed directly on this hub.
    Needed for a first-time install on a hub not yet enrolled in the channel;
    not needed for routine upgrades.

.EXAMPLE
    # Everyday upgrade (uses the cached channel):
    ./Deploy-Driver.ps1

.EXAMPLE
    # First-time install: create the channel and enroll your hub:
    ./Deploy-Driver.ps1 -ChannelName 'My Drivers' -CreateChannel -HubId '<hub-id>'

.EXAMPLE
    # Point at an existing channel by name (then it's cached):
    ./Deploy-Driver.ps1 -ChannelName 'Tillig Personal Drivers'

.NOTES
    Prerequisites:
      1. SmartThings CLI installed: npm install -g @smartthings/cli
      2. Logged in once: smartthings login
      3. Custom capabilities created: ./New-Capabilities.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string] $ChannelId = '',

    [Parameter()]
    [string] $ChannelName = '',

    [Parameter()]
    [switch] $CreateChannel,

    [Parameter()]
    [string] $HubId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$driverDir = Join-Path $repoRoot 'driver'
$cacheDir = Join-Path $PSScriptRoot '.local'
$cacheFile = Join-Path $cacheDir 'channel-id'

Write-Host '=== SmartWings Day/Night: Update / Deploy ===' -ForegroundColor Cyan

# --- Prerequisite checks ----------------------------------------------------
if (-not (Get-Command 'smartthings' -ErrorAction SilentlyContinue)) {
    Write-Error @'
The SmartThings CLI was not found on PATH.

Install it with:   npm install -g @smartthings/cli
Then log in once:  smartthings login
'@
    exit 1
}

Write-Verbose 'Probing authentication (smartthings edge:channels --json)...'
$channelsJson = smartthings edge:channels --json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error @"
The SmartThings CLI is not authenticated (or returned an error).

Log in (interactive browser) with:   smartthings login
Then re-run this script.

CLI output:
$($channelsJson | Out-String)
"@
    exit 1
}

if (-not (Test-Path (Join-Path $driverDir 'config.yml'))) {
    Write-Error "Driver directory does not contain config.yml. Expected: $driverDir"
    exit 1
}

# --- Step 1: resolve the channel (cache -> ChannelId -> name -> create) ------
Write-Host "`n=== Step 1: Channel ===" -ForegroundColor Cyan

$channels = $channelsJson | ConvertFrom-Json
$channelId = ''

function Resolve-ChannelId([object]$channels, [string]$id) {
    # Confirm the given ID is actually one we own; return it if so.
    foreach ($c in $channels) {
        $cid = if ($c.channelId) { $c.channelId } else { $c.id }
        if ($cid -eq $id) { return $cid }
    }
    return ''
}

# 1) explicit -ChannelId wins
if ($ChannelId) {
    $channelId = Resolve-ChannelId $channels $ChannelId
    if ($channelId) { Write-Host "Using channel ID (from -ChannelId): $channelId" -ForegroundColor Green }
    else { Write-Warning "Channel ID '$ChannelId' is not among channels you own; ignoring." }
}

# 2) cached ID from a previous run
if (-not $channelId -and (Test-Path $cacheFile)) {
    $cached = (Get-Content $cacheFile -Raw).Trim()
    $channelId = Resolve-ChannelId $channels $cached
    if ($channelId) { Write-Host "Using cached channel ID: $channelId" -ForegroundColor Green }
    else { Write-Verbose "Cached channel '$cached' no longer exists; ignoring cache." }
}

# 3) find by name
if (-not $channelId -and $ChannelName) {
    $match = $channels | Where-Object { $_.name -eq $ChannelName } | Select-Object -First 1
    if ($match) {
        $channelId = if ($match.channelId) { $match.channelId } else { $match.id }
        Write-Host "Found channel '$ChannelName'. ID: $channelId" -ForegroundColor Green
    }
}

# 4) create (only if asked)
if (-not $channelId) {
    if (-not $CreateChannel) {
        Write-Error @"
Could not resolve a channel.

- No valid cached channel (setup/.local/channel-id), and
- no -ChannelId given (or it wasn't one you own), and
$(if ($ChannelName) { "- no channel named '$ChannelName' was found." } else { '- no -ChannelName was given.' })

Options:
  * First-time install: ./Deploy-Driver.ps1 -ChannelName '<your channel>' -CreateChannel -HubId '<hub-id>'
  * Existing channel:   ./Deploy-Driver.ps1 -ChannelName '<your channel>'

Your channels:
$(($channels | ForEach-Object { "  $($_.name)  [$(if ($_.channelId) { $_.channelId } else { $_.id })]" }) -join "`n")
"@
        exit 1
    }
    $name = if ($ChannelName) { $ChannelName } else { 'SmartWings Day/Night Z-Wave' }
    Write-Host "Creating channel '$name'..."
    $payload = [pscustomobject]@{
        name              = $name
        description       = 'Edge channel for the SmartWings dual-motor day/night cellular shade Z-Wave driver.'
        type              = 'DRIVER'
        termsOfServiceUrl = ''
    } | ConvertTo-Json -Compress
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "st-channel-$([System.IO.Path]::GetRandomFileName()).json"
    try {
        Set-Content -Path $tmp -Value $payload -Encoding utf8
        $createOut = smartthings edge:channels:create --input "$tmp" --json 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create channel:`n$($createOut | Out-String)" }
        $created = $createOut | ConvertFrom-Json
        $channelId = if ($created.channelId) { $created.channelId } else { $created.id }
        Write-Host "Channel created. ID: $channelId" -ForegroundColor Green
    }
    finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
    }
}

# Cache the resolved ID for next time.
if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
Set-Content -Path $cacheFile -Value $channelId -Encoding ascii
Write-Verbose "Cached channel ID to $cacheFile"

# --- Step 2: package + assign (+ optional install) --------------------------
Write-Host "`n=== Step 2: Package + assign$(if ($HubId) { ' + install' }) ===" -ForegroundColor Cyan

$pkgArgs = @($driverDir, '--channel', $channelId)
if ($HubId) { $pkgArgs += @('--hub', $HubId) }

Write-Verbose "Running: smartthings edge:drivers:package $($pkgArgs -join ' ') --json"
$pkgOut = smartthings edge:drivers:package @pkgArgs --json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Package/assign failed:`n$($pkgOut | Out-String)"
}

$result = $null
try { $result = $pkgOut | ConvertFrom-Json } catch { Write-Verbose 'Package output was not JSON; continuing without parsed details.' }
$driverId = if ($result) { if ($result.driverId) { $result.driverId } else { $result.id } } else { $null }
$version = if ($result) { $result.version } else { $null }

Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "  Channel ID : $channelId"
if ($driverId) { Write-Host "  Driver ID  : $driverId" }
if ($version) { Write-Host "  Version    : $version" }
if ($HubId) {
    Write-Host "  Installed on hub: $HubId"
}
else {
    Write-Host 'Enrolled hubs will pick up the new version automatically' -ForegroundColor Cyan
    Write-Host '(within ~12h, or immediately if you re-select the driver in the app).' -ForegroundColor Cyan
}
