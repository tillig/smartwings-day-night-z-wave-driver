#Requires -Version 7.0
<#
.SYNOPSIS
    Full end-to-end setup: creates the 3 custom capabilities and then packages
    and installs the SmartWings Day/Night Z-Wave driver on your SmartThings hub.

.DESCRIPTION
    This is the "run this one script" entry point. It calls New-Capabilities.ps1
    and then Deploy-Driver.ps1 in sequence.

    For finer-grained control (e.g. re-deploying without re-creating
    capabilities) call the individual scripts directly. Later upgrades are just
    ./Deploy-Driver.ps1.

.PARAMETER HubId
    The SmartThings hub ID to install the driver on.
    Run `smartthings devices --type HUB` to find yours.
    Example: 00000000-0000-0000-0000-00000000HUB0

.PARAMETER ChannelId
    (Optional) An existing Edge channel ID to use.
    If not supplied, a new channel is created automatically.
    Example: 00000000-0000-0000-0000-0000000CHAN0

.PARAMETER ChannelName
    (Optional) Name for the channel. If -ChannelId is not provided, a channel
    with this name is found or created. Defaults to "SmartWings Day/Night Z-Wave".

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
      3. Authenticated (any command opens a browser to log in the first time)
         (Interactive browser login -- run once, then the token is cached.)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $HubId,

    [Parameter()]
    [string] $ChannelId = '',

    [Parameter()]
    [string] $ChannelName = 'SmartWings Day/Night Z-Wave'
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

$deployScript = Join-Path $scriptDir 'Deploy-Driver.ps1'

# First-time setup: install on the hub and create the channel if it's not found.
$deployArgs = @{
    HubId         = $HubId
    ChannelName   = $ChannelName
    CreateChannel = $true
}
if ($ChannelId) {
    $deployArgs['ChannelId'] = $ChannelId
}

& $deployScript @deployArgs @verboseArg
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Write-Error "Deploy-Driver.ps1 exited with code $LASTEXITCODE. Aborting."
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
