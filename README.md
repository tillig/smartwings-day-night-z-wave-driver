# SmartWings Day/Night Z-Wave Driver

A SmartThings Edge driver (Lua, runs on the hub) for [SmartWings day/night cellular shades](https://www.smartwingshome.com/collections/day-night-shades) with the Z-Wave motor. These shades have two motors on one Z-Wave node — a bottom rail (opaque) and a middle rail (sheer) — and the stock SmartThings "Z-Wave Window Treatment" driver mishandles them. This driver fixes that.

**Not published to any SmartThings channel marketplace. Personal-use, MIT-licensed.**

- [How It Works](#how-it-works)
- [What You See in the App](#what-you-see-in-the-app)
  - [Scene Modes](#scene-modes)
  - [Why the Shade and Sheer Controls Look Different](#why-the-shade-and-sheer-controls-look-different)
- [Voice Control (Google Home)](#voice-control-google-home)
- [Install](#install)
  - [Prerequisites](#prerequisites)
  - [Option A — Setup Scripts (Recommended)](#option-a--setup-scripts-recommended)
  - [Option B — Manual Install](#option-b--manual-install)
  - [Custom Capabilities Caveat](#custom-capabilities-caveat)
- [FAQ](#faq)
- [History](#history)
- [Reference](#reference)

## How It Works

The shade splits the window into three bands:

```text
┌──────────────────────────┐  ← window top
│  sheer fabric            │
│    (middle rail)         │
├──────────────────────────┤  ← middle rail
│  opaque fabric           │
│    (bottom rail)         │
├──────────────────────────┤  ← bottom rail
│  open / see-through      │
└──────────────────────────┘  ← floor
```

The two motors share one Z-Wave node (two multichannel endpoints). The stock driver ignores the second motor and spawns two useless "metering-dimmer" child devices. This driver handles both rails correctly.

**Hardware rule:** the middle rail can never be below the bottom rail. Opening the bottom past the middle automatically lifts the middle with it.

## What You See in the App

The device detail screen has four sections, in order:

| Section     | What it is                                  | What it controls                                                        |
| ----------- | ------------------------------------------- | ----------------------------------------------------------------------- |
| **Sheer**   | Slider (0–100%)                             | Middle rail. 0% = no sheer (middle up), 100% = full sheer (middle down) |
| **Shade**   | Window shade tile with Open/Close/Pause + % | Bottom rail. 0% = closed/covered, 100% = open/see-through               |
| **Scene**   | Mode dropdown + buttons                     | Preset positions for both rails at once                                 |
| **Battery** | Battery level                               | —                                                                       |

### Scene Modes

| Mode         | Position                                    |
| ------------ | ------------------------------------------- |
| **Blackout** | Middle up, bottom down — maximum privacy    |
| **Sheer**    | Both rails down — full sheer fabric visible |
| **Open**     | Both rails up — fully open, see-through     |
| **Favorite** | Your saved position                         |

**Apply selected mode** re-fires the currently selected mode. This matters because the dropdown is stateful — re-selecting an already-selected mode won't re-trigger it; the button always fires.

**Save current as Favorite** captures wherever both rails are right now.

### Why the Shade and Sheer Controls Look Different

You'll notice the **Shade** control (with Open/Close buttons and a percentage bar) looks different from the clean **Sheer** slider. That's on purpose: the Shade control is built the specific way that lets Google Home and Alexa recognize it as a real blind, so voice commands like "open the blinds" or "set the blinds to 50%" work. Making the two look identical would break that. It's a small cosmetic quirk in exchange for working voice control. (For the technical details, see [CONTRIBUTING.md](./CONTRIBUTING.md).)

## Voice Control (Google Home)

The driver creates two devices in Google Home:

| Google Home device        | Voice examples                                                 | Controls                   |
| ------------------------- | -------------------------------------------------------------- | -------------------------- |
| `<your shade name>`       | "open the blinds", "close the blinds", "set the blinds to 50%" | Bottom rail (opaque shade) |
| `<your shade name> Sheer` | "open the sheer", "set the sheer to 50%"                       | Middle rail (sheer fabric) |

For scenes/Favorite: create SmartThings Scenes (Google Home exposes those as voice commands).

## Install

### Prerequisites

- A SmartThings hub with Z-Wave
- The shade already paired to SmartThings (it pairs as a standard Z-Wave device)
- [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli) installed and logged in:

  ```powershell
  npm install -g @smartthings/cli
  smartthings login
  ```

### Option A — Setup Scripts (Recommended)

The `setup/` directory contains PowerShell scripts that automate everything (creating custom capabilities, creating a channel, and installing the driver):

1. Run `setup/New-Capabilities.ps1` to create the custom capabilities in your SmartThings account.
2. Run `setup/Install-Driver.ps1 -HubId <your-hub-id>` to package, upload, and install the driver. (`smartthings edge:hubs` lists your hub IDs.)
3. In the SmartThings app, go to the device → **⋮** → **Driver** → select **SmartWings Day/Night Z-Wave**.
4. Delete the two old junk child devices left behind by the stock driver (they will show up as unrecognized devices).

**Later, to deploy an updated version of the driver**, just run:

```powershell
./setup/Update.ps1
```

It remembers your channel after the first run, so upgrades are a single command with no arguments.

### Option B — Manual Install

1. Create the three custom capabilities from `driver/capabilities/`:

   ```powershell
   smartthings capabilities:create -i driver/capabilities/activateScene.capability.json
   smartthings capabilities:presentation:create <id> -i driver/capabilities/activateScene.presentation.json

   smartthings capabilities:create -i driver/capabilities/sheerLevel.capability.json
   smartthings capabilities:presentation:create <id> -i driver/capabilities/sheerLevel.presentation.json

   smartthings capabilities:create -i driver/capabilities/saveFavorite.capability.json
   smartthings capabilities:presentation:create <id> -i driver/capabilities/saveFavorite.presentation.json
   ```

2. Note the assigned capability IDs (they'll have your account namespace prefix, e.g. `yournamespace.activateScene`). Update the namespace prefix in `driver/profiles/*.yml` and `driver/src/init.lua` if it differs from `happyvessel61954.` — see [CONTRIBUTING.md](./CONTRIBUTING.md) for details.
3. Create a channel in the [SmartThings Developer Console](https://developer.smartthings.com/console/integrations).
4. Package and upload the driver:

   ```powershell
   smartthings edge:drivers:package driver --channel <channelId> --hub <hubId>
   ```

5. Enroll your hub in the channel.
6. In the SmartThings app, go to the device → **⋮** → **Driver** → select **SmartWings Day/Night Z-Wave**.
7. Delete the two old junk child devices left behind by the stock driver.

### Custom Capabilities Caveat

SmartThings custom capability IDs embed a per-account namespace prefix (e.g. `happyvessel61954.`). If you're installing on a different SmartThings account, the profiles and driver source will reference the wrong prefix. See [CONTRIBUTING.md](./CONTRIBUTING.md) for the find-and-replace steps.

## FAQ

**The app shows a GUID as the driver developer name.**
That is a SmartThings platform limitation — it shows the account GUID, not a human name. There is no way to change it from within the driver package.

**The two Shade/Sheer controls look different from each other.**
This is intentional. See [Why the Shade and Sheer Controls Look Different](#why-the-shade-and-sheer-controls-look-different).

## History

I bought three sets of the day/night shades with the Z-Wave motor. When I added them to SmartThings, each shade showed up as two devices: one that controlled the blinds incorrectly (treated as single-motor, no in-between positions), and one unrecognized "dummy" device that did nothing. SmartWings briefly had a custom driver on their site — listed as "under development" and "being tested" — but it disappeared. The shades were falling back to the default Z-Wave window treatments driver, which doesn't understand dual-motor shades. This driver is the fix.

## Reference

- [SmartWings Z-Wave Programming Guide](./assets/smartwings-z-wave-programming-guide.pdf): Retrieved [from their site](https://cdn.shopify.com/s/files/1/0573/0215/5461/files/SmartWings_Z-wave_Motor_Programming_Guide_cb52ae04-036e-446c-bff2-6e944bedbb5f.pdf?v=1754441184) for local reference/indexing.
- [SmartThings Developer Center](https://developer.smartthings.com/) - Information on creating [device integrations](https://developer.smartthings.com/docs/devices/device-basics) for interacting with Z-Wave and other device types.
- [SmartThings Edge driver for Z-Wave window treatments](https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/tree/main/drivers/SmartThings/zwave-window-treatment) - This is what drives the blinds by default.
- [SmartThings Advanced Dashboard](https://my.smartthings.com/advanced/devices) - Advanced view of the devices available on your Home Hub, which allows better control of drivers, etc.
- [SmartThings Developer Console](https://developer.smartthings.com/console/integrations) - Testing and development for new device integrations.
