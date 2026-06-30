# Setup Scripts

PowerShell automation for installing and updating the SmartWings Day/Night
Z-Wave driver. These scripts replace the manual SmartThings CLI steps.

- [Prerequisites](#prerequisites)
- [First-Time Setup](#first-time-setup)
- [Deploying Updates](#deploying-updates)
- [Scripts](#scripts)
- [Namespace Warning](#namespace-warning)

## Prerequisites

Install the SmartThings CLI, then list your hubs. The first command that needs
authentication opens a browser to log in; the token is cached and auto-refreshed
afterward. Note your hub ID from the output:

```powershell
npm install -g @smartthings/cli
smartthings devices --type HUB   # first run opens a browser to log in; note the hub ID
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

After a code change, push a new build with `Deploy-Driver.ps1`. It packages the
driver, assigns it to your channel, and forces your hub to install it. It
remembers your channel and hub after the first run, so routine upgrades take no
arguments:

```powershell
# First time — name your channel and hub (both get cached):
./setup/Deploy-Driver.ps1 -ChannelName '<your-channel-name>' -HubId '<your-hub-id>'

# Every time after that:
./setup/Deploy-Driver.ps1
```

## Scripts

| Script | What It Does |
| --- | --- |
| `Initialize-Driver.ps1` | First-time orchestrator: runs `New-Capabilities.ps1` then `Deploy-Driver.ps1`. |
| `New-Capabilities.ps1` | Creates (or verifies) the custom capabilities and presentations. Warns if your account namespace differs from the one hardcoded in the driver. |
| `Deploy-Driver.ps1` | Packages and assigns the driver for both first install and upgrades, then forces the hub to install the new version. Resolves the channel (explicit `-ChannelId`, cached, by `-ChannelName`, or `-CreateChannel`) and the hub (`-HubId` or cached); both are cached for argument-free re-runs. |
| `Test-Shade.ps1` | Sanity-checks a shade (`-DeviceLabel` or `-DeviceId`): verifies it's on this driver with the right components, deletes the stock dummy child devices, resyncs displayed state (movement-free by default; `-Force` recalls the favorite for a reliable resync), and prints a health summary. Idempotent. Run it after pairing a new shade or switching its driver. |

All scripts accept `-Verbose`. Run `Get-Help ./setup/<script>.ps1 -Detailed` for
full parameter documentation.

## Namespace Warning

SmartThings assigns a per-account namespace to custom capabilities (e.g.
`happyvessel61954`), and the driver source hardcodes that prefix in
`driver/profiles/smartwings-daynight.yml` and `driver/src/init.lua`. If your
account receives a different namespace, `New-Capabilities.ps1` prints a warning
listing every line to update. Update those files before packaging the driver.
