# Setup Scripts

PowerShell automation for setting up the SmartWings Day/Night Z-Wave driver on
a SmartThings account. These scripts replace the manual CLI steps.

## Prerequisites

1. **Node.js + npm** are installed.
2. **SmartThings CLI** is installed:
   ```
   npm install -g @smartthings/cli
   ```
3. **Log in once** (interactive browser; token is cached afterward):
   ```
   smartthings login
   ```
4. **Your hub ID.** Find it with:
   ```
   smartthings edge:hubs
   ```

## Quick Start (fresh account / first-time setup)

```powershell
cd setup
./Setup.ps1 -HubId '<your-hub-id>'
```

That single command:
1. Creates the three custom SmartThings capabilities and their presentations.
2. Creates a new Edge channel (type `DRIVER`).
3. Packages the driver, assigns it to the channel, and installs it on the hub.

## Re-installing After a Code Change

If you already have a channel and just want to push an updated driver build:

```powershell
./Install-Driver.ps1 `
    -HubId     '<your-hub-id>' `
    -ChannelId '<your-channel-id>'
```

## Scripts

| Script | What it does |
|---|---|
| `Setup.ps1` | Orchestrator: runs `New-Capabilities.ps1` then `Install-Driver.ps1`. Use for first-time setup. |
| `New-Capabilities.ps1` | Creates (or verifies) the 3 custom capabilities + presentations. Warns if the account namespace differs from what the driver source hardcodes. |
| `Install-Driver.ps1` | Creates-or-uses an Edge channel, packages the driver, assigns it to the channel, and installs it on the hub. |

All scripts accept `-Verbose` for detailed output and `-WhatIf` / `-Confirm` is
not needed (no destructive operations).

## Parameters

### `Setup.ps1` / `Install-Driver.ps1`

| Parameter | Required | Description |
|---|---|---|
| `-HubId` | Yes | SmartThings hub ID. Find with `smartthings edge:hubs`. |
| `-ChannelId` | No | Existing Edge channel ID. If omitted, a new channel is created. |
| `-ChannelName` | No | Name for a new channel. Default: `SmartWings Day/Night Z-Wave`. |
| `-ChannelDescription` | No | Description for a new channel. Has a sensible default. |

### `New-Capabilities.ps1`

No parameters beyond the built-in `-Verbose`.

## Namespace Warning

SmartThings assigns a per-account namespace to custom capabilities
(e.g. `happyvessel61954`). The driver source hardcodes `happyvessel61954` in:

- `driver/profiles/smartwings-daynight.yml`
- `driver/src/init.lua`

If your account receives a different namespace, `New-Capabilities.ps1` will
print a warning that lists every line that needs updating. Update those files
before packaging the driver (before running `Install-Driver.ps1`).

## Example Session

```text
$ smartthings edge:hubs
# -> note your hub ID

$ cd setup
$ ./Setup.ps1 -HubId '00000000-0000-0000-0000-00000000HUB0'

########################################################
#   SmartWings Day/Night Z-Wave -- Full Setup           #
########################################################

>>> Step 1/2: Creating custom capabilities...
=== SmartWings Day/Night: Create Custom Capabilities ===
Checking SmartThings authentication...

--- Capability: activateScene ---
  Creating capability from: .../driver/capabilities/activateScene.capability.json
  Created with ID: mynamespace12345.activateScene
  Creating presentation from: .../driver/capabilities/activateScene.presentation.json
  Presentation created.

... (sheerLevel and saveFavorite follow) ...

=== Namespace Verification ===
*** NAMESPACE MISMATCH ***
Your SmartThings account was assigned namespace : mynamespace12345
The driver source currently hardcodes namespace : happyvessel61954
...

# -> Update driver/profiles/smartwings-daynight.yml and driver/src/init.lua,
#    then re-run or continue:

>>> Step 2/2: Packaging and installing driver...
...
Installation complete.
```
