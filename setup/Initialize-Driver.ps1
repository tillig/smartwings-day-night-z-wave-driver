#Requires -Version 7.0
<#
.SYNOPSIS
    Full end-to-end setup: creates the 3 custom capabilities and then packages
    and installs the SmartWings Day/Night Z-Wave driver on your SmartThings hub.

.DESCRIPTION
    This is the "run this one script" entry point. It calls New-Capabilities.ps1
    and then Install-Driver.ps1 in sequence.

    For finer-grained control (e.g. re-running just the install step) call the
    individual scripts directly.

.PARAMETER HubId
    The SmartThings hub ID to install the driver on.
    Run `smartthings edge:hubs` to find yours.
    Example: 00000000-0000-0000-0000-00000000HUB0

.PARAMETER ChannelId
    (Optional) An existing Edge channel ID to use.
    If not supplied, a new channel is created automatically.
    Example: 00000000-0000-0000-0000-0000000CHAN0

.PARAMETER ChannelName
    (Optional) Name for the new channel if -ChannelId is not provided.
    Defaults to "SmartWings Day/Night Z-Wave".

.PARAMETER ChannelDescription
    (Optional) Description for the new channel if one is being created.

.EXAMPLE
    # First time on a fresh account -- create everything:
    ./Initialize-Driver.ps1 -HubId '00000000-0000-0000-0000-00000000HUB0'

.EXAMPLE
    # Re-install with an existing channel:
    ./Initialize-Driver.ps1 `
        -HubId     '00000000-0000-0000-0000-00000000HUB0' `
        -ChannelId '00000000-0000-0000-0000-0000000CHAN0'

.EXAMPLE
    ./Initialize-Driver.ps1 -HubId '00000000-0000-0000-0000-00000000HUB0' -Verbose

.NOTES
    Prerequisites:
      1. Node.js + npm are installed.
      2. SmartThings CLI is installed: npm install -g @smartthings/cli
      3. You have logged in: smartthings login
         (Interactive browser login -- run once, then the token is cached.)
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

$scriptDir = $PSScriptRoot

Write-Host '########################################################' -ForegroundColor Cyan
Write-Host '#   SmartWings Day/Night Z-Wave -- Full Setup           #' -ForegroundColor Cyan
Write-Host '########################################################' -ForegroundColor Cyan
Write-Host ''

###############################################################################
# Step 1: Custom Capabilities
###############################################################################

Write-Host '>>> Step 1/2: Creating custom capabilities...' -ForegroundColor Cyan
Write-Host ''

$capScript = Join-Path $scriptDir 'New-Capabilities.ps1'

# Forward -Verbose if the caller requested it.
$verboseArg = @{}
if ($VerbosePreference -eq 'Continue') {
    $verboseArg = @{ Verbose = $true }
}

& $capScript @verboseArg
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Write-Error "New-Capabilities.ps1 exited with code $LASTEXITCODE. Aborting."
}

Write-Host ''
Write-Host '>>> Step 1/2 complete.' -ForegroundColor Green
Write-Host ''

###############################################################################
# Step 2: Install Driver
###############################################################################

Write-Host '>>> Step 2/2: Packaging and installing driver...' -ForegroundColor Cyan
Write-Host ''

$installScript = Join-Path $scriptDir 'Install-Driver.ps1'

$installArgs = @{
    HubId              = $HubId
    ChannelName        = $ChannelName
    ChannelDescription = $ChannelDescription
}
if ($ChannelId) {
    $installArgs['ChannelId'] = $ChannelId
}

& $installScript @installArgs @verboseArg
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Write-Error "Install-Driver.ps1 exited with code $LASTEXITCODE. Aborting."
}

Write-Host ''
Write-Host '>>> Step 2/2 complete.' -ForegroundColor Green
Write-Host ''

###############################################################################
# Done
###############################################################################

Write-Host '########################################################' -ForegroundColor Green
Write-Host '#   Setup finished successfully!                        #' -ForegroundColor Green
Write-Host '########################################################' -ForegroundColor Green
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host '  1. If the namespace printed above differs from "happyvessel61954",' -ForegroundColor Cyan
Write-Host '     update driver/profiles/smartwings-daynight.yml and' -ForegroundColor Cyan
Write-Host '     driver/src/init.lua (New-Capabilities.ps1 already flagged this).' -ForegroundColor Cyan
Write-Host '  2. Pair your SmartWings shade to your hub (Z-Wave inclusion).' -ForegroundColor Cyan
Write-Host '  3. The driver should claim it automatically via the fingerprint.' -ForegroundColor Cyan
