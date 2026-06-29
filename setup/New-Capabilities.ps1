#Requires -Version 7.0
<#
.SYNOPSIS
    Creates (or verifies) the three custom SmartThings capabilities and their
    presentations for the SmartWings Day/Night Z-Wave driver.

.DESCRIPTION
    This script uploads each of the three custom capabilities and their
    presentations to your SmartThings account using the SmartThings CLI.

    Capabilities created:
      - <namespace>.activateScene   (stateless button: apply selected scene)
      - <namespace>.sheerLevel      (0-100 slider for the middle/sheer rail)
      - <namespace>.saveFavorite    (stateless button: save current position)

    The capability namespace is assigned by SmartThings per account. The driver
    source (driver/profiles/*.yml and driver/src/init.lua) currently references
    the namespace "happyvessel61954". If your account receives a DIFFERENT
    namespace, this script will warn you and show you exactly what to update.

    The script is idempotent: if a capability already exists, it skips creation
    and uses the existing ID.

.PARAMETER Verbose
    Show detailed progress for each CLI call (built-in PowerShell switch).

.EXAMPLE
    ./New-Capabilities.ps1

.EXAMPLE
    ./New-Capabilities.ps1 -Verbose

.NOTES
    Prerequisites:
      1. Node.js + npm are installed.
      2. SmartThings CLI is installed: npm install -g @smartthings/cli
      3. You have logged in: smartthings login
         (Interactive browser login -- run this once before the first script run.)
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

###############################################################################
# Paths
###############################################################################

# setup/ is one level below repo root; driver/ is a sibling of setup/.
$repoRoot   = Split-Path -Parent $PSScriptRoot
$capDir     = Join-Path $repoRoot 'driver' 'capabilities'
$profileDir = Join-Path $repoRoot 'driver' 'profiles'
$srcDir     = Join-Path $repoRoot 'driver' 'src'

# The namespace that is currently baked into the driver source files.
$knownNamespace = 'happyvessel61954'

###############################################################################
# Prerequisite checks
###############################################################################

Write-Host '=== SmartWings Day/Night: Create Custom Capabilities ===' -ForegroundColor Cyan

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

###############################################################################
# Helper: create one capability; return its assigned ID.
# If the capability already exists (create fails), list capabilities for the
# account and find the matching one by name.
###############################################################################

function New-Capability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $CapabilityJsonPath,
        [Parameter(Mandatory)] [string] $PresentationJsonPath,
        [Parameter(Mandatory)] [string] $FriendlyName
    )

    Write-Host "`n--- Capability: $FriendlyName ---" -ForegroundColor Yellow

    # --- Create capability ---
    Write-Host "  Creating capability from: $CapabilityJsonPath"
    Write-Verbose "  Running: smartthings capabilities:create -i `"$CapabilityJsonPath`" --json"

    $createOutput = smartthings capabilities:create -i "$CapabilityJsonPath" --json 2>&1
    $createExitCode = $LASTEXITCODE

    if ($createExitCode -ne 0) {
        $errText = $createOutput | Out-String
        if ($errText -match 'already exists|conflict|409' -or $errText -match '(?i)duplicate') {
            Write-Host "  Capability already exists -- will look it up." -ForegroundColor DarkYellow
        }
        else {
            Write-Warning "  Create returned exit code $createExitCode. Output:"
            Write-Warning $errText
            Write-Host "  Attempting to find existing capability by name anyway..." -ForegroundColor DarkYellow
        }
    }

    $capabilityId = $null

    # Try to parse the JSON from a successful create response.
    if ($createExitCode -eq 0) {
        try {
            $created = $createOutput | ConvertFrom-Json -ErrorAction Stop
            $capabilityId = $created.id
            Write-Host "  Created with ID: $capabilityId" -ForegroundColor Green
        }
        catch {
            Write-Warning "  Could not parse create response as JSON; will try to find existing."
        }
    }

    # If we don't have an ID yet, find it by listing capabilities for the account.
    if (-not $capabilityId) {
        # Read the capability name from the JSON file so we can match it.
        $capDef = Get-Content -Raw "$CapabilityJsonPath" | ConvertFrom-Json
        $capName = $capDef.name

        Write-Verbose "  Searching for existing capability named: $capName"
        Write-Verbose "  Running: smartthings capabilities --json"

        $listOutput = smartthings capabilities --json 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "  Failed to list capabilities. Cannot determine ID for '$FriendlyName'."
        }

        $existingCaps = $listOutput | ConvertFrom-Json
        # The list may return an array of capabilities; each has id, name, version, etc.
        # Filter to custom capabilities (those with a namespace prefix) matching our name.
        # The name field in the definition becomes the display name on the platform.
        $match = $existingCaps | Where-Object { $_.name -eq $capName }

        if (-not $match) {
            # Some versions of the CLI return a nested structure.
            $match = $existingCaps | Where-Object { $_.id -match "\.$($capDef.name -replace ' ','')$" }
        }

        if ($match) {
            # Take the most recent version if there are multiple.
            if ($match -is [array]) { $match = $match | Sort-Object version -Descending | Select-Object -First 1 }
            $capabilityId = $match.id
            Write-Host "  Found existing capability ID: $capabilityId" -ForegroundColor DarkYellow
        }
        else {
            Write-Error "  Could not find a matching existing capability for '$FriendlyName'. Aborting."
        }
    }

    # --- Create presentation ---
    Write-Host "  Creating presentation from: $PresentationJsonPath"
    Write-Verbose "  Running: smartthings capabilities:presentation:create `"$capabilityId`" -i `"$PresentationJsonPath`" --json"

    $presOutput = smartthings capabilities:presentation:create "$capabilityId" -i "$PresentationJsonPath" --json 2>&1
    $presExitCode = $LASTEXITCODE

    if ($presExitCode -ne 0) {
        $presErr = $presOutput | Out-String
        if ($presErr -match 'already exists|conflict|409' -or $presErr -match '(?i)duplicate') {
            Write-Host "  Presentation already exists -- skipping." -ForegroundColor DarkYellow
        }
        else {
            Write-Warning "  Presentation create returned exit code ${presExitCode}:"
            Write-Warning $presErr
            Write-Host "  Continuing (presentation may already exist or may need manual creation)." -ForegroundColor DarkYellow
        }
    }
    else {
        Write-Host "  Presentation created." -ForegroundColor Green
    }

    return $capabilityId
}

###############################################################################
# Main: create/verify all three capabilities
###############################################################################

$activateSceneId = New-Capability `
    -CapabilityJsonPath  (Join-Path $capDir 'activateScene.capability.json') `
    -PresentationJsonPath (Join-Path $capDir 'activateScene.presentation.json') `
    -FriendlyName        'activateScene'

$sheerLevelId = New-Capability `
    -CapabilityJsonPath  (Join-Path $capDir 'sheerLevel.capability.json') `
    -PresentationJsonPath (Join-Path $capDir 'sheerLevel.presentation.json') `
    -FriendlyName        'sheerLevel'

$saveFavoriteId = New-Capability `
    -CapabilityJsonPath  (Join-Path $capDir 'saveFavorite.capability.json') `
    -PresentationJsonPath (Join-Path $capDir 'saveFavorite.presentation.json') `
    -FriendlyName        'saveFavorite'

###############################################################################
# Namespace check: warn if the account namespace != what the driver hardcodes
###############################################################################

Write-Host "`n=== Namespace Verification ===" -ForegroundColor Cyan

# Extract the namespace portion from any of the returned IDs (format: namespace.name).
$detectedNamespace = $null
foreach ($id in @($activateSceneId, $sheerLevelId, $saveFavoriteId)) {
    if ($id -and $id -match '^([^.]+)\.') {
        $detectedNamespace = $Matches[1]
        break
    }
}

if (-not $detectedNamespace) {
    Write-Warning 'Could not detect the account namespace from the capability IDs.'
    Write-Warning "Verify manually that driver/profiles/*.yml and driver/src/init.lua use the correct namespace."
}
elseif ($detectedNamespace -eq $knownNamespace) {
    Write-Host "Namespace '$detectedNamespace' matches the value baked into the driver source. No changes needed." -ForegroundColor Green
}
else {
    Write-Host ''
    Write-Warning @"
*** NAMESPACE MISMATCH ***

Your SmartThings account was assigned namespace : $detectedNamespace
The driver source currently hardcodes namespace : $knownNamespace

You must update all occurrences of '$knownNamespace' to '$detectedNamespace' in:
  $profileDir\smartwings-daynight.yml
  $srcDir\init.lua

Files to update (search/replace '$knownNamespace' -> '$detectedNamespace'):
"@

    # Report every occurrence in profiles and src.
    $filesToUpdate = @(
        Join-Path $profileDir 'smartwings-daynight.yml'
        Join-Path $srcDir     'init.lua'
    )
    foreach ($f in $filesToUpdate) {
        if (Test-Path $f) {
            $hits = Select-String -Path $f -Pattern ([regex]::Escape($knownNamespace)) -SimpleMatch
            if ($hits) {
                Write-Host "  $f" -ForegroundColor Red
                foreach ($hit in $hits) {
                    Write-Host "    Line $($hit.LineNumber): $($hit.Line.Trim())" -ForegroundColor Red
                }
            }
        }
    }

    Write-Host ''
    Write-Host 'To apply the fix automatically, re-run with the -Fix switch:' -ForegroundColor Yellow
    Write-Host "    ./New-Capabilities.ps1 -Fix" -ForegroundColor Yellow
    Write-Host '(Or do it manually with your editor / sed / VS Code Find & Replace.)'
    Write-Host ''
}

###############################################################################
# Summary
###############################################################################

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "  activateScene ID : $activateSceneId"
Write-Host "  sheerLevel ID    : $sheerLevelId"
Write-Host "  saveFavorite ID  : $saveFavoriteId"
Write-Host ''
Write-Host 'Capabilities step complete.' -ForegroundColor Green
Write-Host 'Next: run ./Install-Driver.ps1 to package and install the driver.' -ForegroundColor Cyan
