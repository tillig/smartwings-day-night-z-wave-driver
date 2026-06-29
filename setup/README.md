# Setup Scripts

PowerShell automation for installing and updating the SmartWings Day/Night
Z-Wave driver. These scripts replace the manual SmartThings CLI steps.

- [Prerequisites](#prerequisites)
- [First-Time Setup](#first-time-setup)
- [Deploying Updates](#deploying-updates)
- [Scripts](#scripts)
- [Namespace Warning](#namespace-warning)

## Prerequisites

Install the SmartThings CLI and log in once (interactive browser; the token is
cached and auto-refreshed afterward), then find your hub ID:

```powershell
npm install -g @smartthings/cli
smartthings login
smartthings edge:hubs   # note your hub ID
```

## First-Time Setup

From the repo root, one command creates the custom capabilities, creates an Edge
channel, and packages + installs the driver on your hub:

```powershell
./setup/Initialize-Driver.ps1 -HubId '<your-hub-id>'
```

Then, in the SmartThings app, assign the driver to your shade (Device → **⋮** →
**Driver** → **SmartWings Day/Night Z-Wave**) and delete the two leftover junk
child devices from the stock driver.

## Deploying Updates

After a code change, push a new build with `Update-Driver.ps1`. It remembers your
channel after the first run, so routine upgrades take no arguments:

```powershell
# First time — name your channel (it gets cached):
./setup/Update-Driver.ps1 -ChannelName '<your-channel-name>'

# Every time after that:
./setup/Update-Driver.ps1
```

## Scripts

| Script | What It Does |
| --- | --- |
| `Initialize-Driver.ps1` | First-time orchestrator: runs `New-Capabilities.ps1` then `Install-Driver.ps1`. |
| `New-Capabilities.ps1` | Creates (or verifies) the three custom capabilities and presentations. Warns if your account namespace differs from the one hardcoded in the driver. |
| `Install-Driver.ps1` | Creates-or-uses a channel, then packages and assigns the driver (and installs on a hub when `-HubId` is given). |
| `Update-Driver.ps1` | Everyday deploy: resolves the channel (cached, by `-ChannelName`, or `-CreateChannel`), then packages and assigns the latest build. |

All scripts accept `-Verbose`. Run `Get-Help ./setup/<script>.ps1 -Detailed` for
full parameter documentation.

## Namespace Warning

SmartThings assigns a per-account namespace to custom capabilities (e.g.
`happyvessel61954`), and the driver source hardcodes that prefix in
`driver/profiles/smartwings-daynight.yml` and `driver/src/init.lua`. If your
account receives a different namespace, `New-Capabilities.ps1` prints a warning
listing every line to update. Update those files before packaging the driver.
