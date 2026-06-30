# SmartWings Day/Night Z-Wave Driver

A SmartThings Edge driver (Lua, runs on the hub) for [SmartWings day/night cellular shades](https://www.smartwingshome.com/collections/day-night-shades) with the Z-Wave motor. These shades have two motors on one Z-Wave node — a bottom rail (opaque) and a middle rail (sheer) — and the stock SmartThings "Z-Wave Window Treatment" driver mishandles them. This driver fixes that.

**Not published to any SmartThings channel marketplace. Personal-use, MIT-licensed.**

- [How It Works](#how-it-works)
- [What You See in the App](#what-you-see-in-the-app)
  - [Scenes](#scenes)
  - [Why the Sheer Is a Separate Device](#why-the-sheer-is-a-separate-device)
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

Each shade shows up as **two devices**:

**The main shade** (e.g. "Family Room Shade") controls the opaque/bottom rail and the day/night scenes:

| Section | What it is | What it controls |
| ----------- | ------------------------------------------- | --------------------------------------------------------- |
| **Shade** | Window shade tile with Open/Close/Pause + % | Bottom rail. 0% = closed/covered, 100% = open/see-through |
| **Scene** | Buttons: Blackout / Sheer / Open | One tap moves both rails to that preset (see below) |
| **Favorite** | "Preset position" readout + "Settings" Save/Activate buttons | Save the current both-rail position and recall it later |
| **Battery** | Battery level | — |

**The sheer device** (e.g. "Family Room Shade Sheer") controls the sheer/middle rail as its own shade: open = full sheer, close = no sheer, or set a percentage. It lives as a separate device so it works by voice — see [Why the sheer is a separate device](#why-the-sheer-is-a-separate-device).

### Scenes

| Scene        | Position                                    |
| ------------ | ------------------------------------------- |
| **Blackout** | Middle up, bottom down — maximum privacy    |
| **Sheer**    | Both rails down — full sheer fabric visible |
| **Open**     | Both rails up — fully open, see-through     |

Each scene is a button — tap **Blackout**, **Sheer**, or **Open** and the shade moves there immediately.

**Favorite**: tap **Save favorite setting** to remember wherever both rails are right now; **Activate favorite** restores that look in one tap. The "Preset position" readout shows the saved position (e.g. "Sheer 24% / Open 0%").

### Why the Sheer Is a Separate Device

The sheer is its own device (rather than another slider on the main shade) so that voice assistants can control it — "open the sheer", "set the sheer to 50%". Google Home and Alexa only recognize standard blind controls, and giving the sheer its own standard shade device is what makes voice work. (For the technical details, see [CONTRIBUTING.md](./CONTRIBUTING.md).)

## Voice Control (Google Home)

The driver creates two devices in Google Home:

| Google Home device        | Voice examples                                                 | Controls                   |
| ------------------------- | -------------------------------------------------------------- | -------------------------- |
| `<your shade name>`       | "open the blinds", "close the blinds", "set the blinds to 50%" | Bottom rail (opaque shade) |
| `<your shade name> Sheer` | "open the sheer", "set the sheer to 50%"                       | Middle rail (sheer fabric) |

The day/night scenes and Favorite aren't directly voice-controllable (they're custom controls Google doesn't expose), but you can reach them by voice with a **SmartThings Scene**: in the app, **Routines → Scenes → Add scene**, set the main shade and the Sheer device to the positions you want (e.g. Shade 0% + Sheer 24% for your favorite), and name it something speakable. Google Home imports SmartThings Scenes automatically, so then *"Hey Google, activate &lt;scene name&gt;"* works.

## Install

### Prerequisites

- A SmartThings hub with Z-Wave
- The shade already paired to SmartThings (it pairs as a standard Z-Wave device)
- [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli) installed and logged in:

  ```powershell
  npm install -g @smartthings/cli
  smartthings devices   # first run opens a browser to log in
  ```

### Option A — Setup Scripts (Recommended)

The `setup/` directory contains PowerShell scripts that automate everything (creating custom capabilities, creating a channel, and installing the driver):

1. Run `setup/New-Capabilities.ps1` to create the custom capabilities in your SmartThings account.
2. Run `setup/Deploy-Driver.ps1 -ChannelName '<name>' -CreateChannel -HubId <your-hub-id>` to create a channel, package the driver, and install it. (`smartthings devices --type HUB` lists your hub IDs.)
3. In the SmartThings app, go to the shade → **⋮** → **Driver** → select **SmartWings Day/Night Z-Wave**.
4. Run `setup/Test-Shade.ps1 -DeviceLabel '<your shade name>'` to tidy up: it deletes the leftover junk child devices from the stock driver, confirms the shade is set up correctly, and prints a health summary.

**Later, to deploy an updated version of the driver**, just run:

```powershell
./setup/Deploy-Driver.ps1
```

It remembers your channel and hub after the first run, so upgrades are a single command with no arguments.

> **Adding another shade?** Pair it to SmartThings, switch it to this driver (step 3), then run `Test-Shade.ps1` (step 4). That's it — the driver finds both motors itself, even if the stock driver only showed one.

### Option B — Manual Install

1. Create the custom capabilities from `driver/capabilities/`:

   ```powershell
   smartthings capabilities:create -i driver/capabilities/blackout.capability.json
   smartthings capabilities:presentation:create <id> -i driver/capabilities/blackout.presentation.json

   smartthings capabilities:create -i driver/capabilities/sheer.capability.json
   smartthings capabilities:presentation:create <id> -i driver/capabilities/sheer.presentation.json

   smartthings capabilities:create -i driver/capabilities/open.capability.json
   smartthings capabilities:presentation:create <id> -i driver/capabilities/open.presentation.json

   smartthings capabilities:create -i driver/capabilities/presetPosition.capability.json
   smartthings capabilities:presentation:create <id> -i driver/capabilities/presetPosition.presentation.json

   smartthings capabilities:create -i driver/capabilities/settings.capability.json
   smartthings capabilities:presentation:create <id> -i driver/capabilities/settings.presentation.json
   ```

2. Note the assigned capability IDs (they'll have your account namespace prefix, e.g. `yournamespace.blackout`). Update the namespace prefix in `driver/profiles/*.yml` and `driver/src/init.lua` if it differs from `happyvessel61954.` — see [CONTRIBUTING.md](./CONTRIBUTING.md) for details.
3. Create a channel (the command prompts for a name and description; choose type `DRIVER`). Note the channel ID it prints:

   ```powershell
   smartthings edge:channels:create
   ```

4. Find your hub ID:

   ```powershell
   smartthings devices --type HUB
   ```

5. Package the driver, assign it to the channel, and install it on the hub — this one command does all three (and enrolls the hub in the channel automatically):

   ```powershell
   smartthings edge:drivers:package driver --channel <channelId> --hub <hubId>
   ```

6. In the SmartThings app, go to the device → **⋮** → **Driver** → select **SmartWings Day/Night Z-Wave**.
7. Run `setup/Test-Shade.ps1 -DeviceLabel '<your shade name>'` to delete the leftover junk child devices and verify setup (or delete the "Z-Wave Device Multichannel" children by hand).

### Custom Capabilities Caveat

SmartThings custom capability IDs embed a per-account namespace prefix (e.g. `happyvessel61954.`). If you're installing on a different SmartThings account, the profiles and driver source will reference the wrong prefix. See [CONTRIBUTING.md](./CONTRIBUTING.md) for the find-and-replace steps.

## FAQ

**The app shows a GUID as the driver developer name.**
That is a SmartThings platform limitation — it shows the account GUID, not a human name. There is no way to change it from within the driver package.

**Why is the sheer a separate device instead of a control on the main shade?**
So it works by voice. See [Why the Sheer Is a Separate Device](#why-the-sheer-is-a-separate-device).

## History

I bought three sets of the day/night shades with the Z-Wave motor. When I added them to SmartThings, each shade showed up as two devices: one that controlled the blinds incorrectly (treated as single-motor, no in-between positions), and one unrecognized "dummy" device that did nothing. SmartWings briefly had a custom driver on their site — listed as "under development" and "being tested" — but it disappeared. The shades were falling back to the default Z-Wave window treatments driver, which doesn't understand dual-motor shades. This driver is the fix.

## Reference

- [SmartWings Z-Wave Programming Guide](./assets/smartwings-z-wave-programming-guide.pdf): Retrieved [from their site](https://cdn.shopify.com/s/files/1/0573/0215/5461/files/SmartWings_Z-wave_Motor_Programming_Guide_cb52ae04-036e-446c-bff2-6e944bedbb5f.pdf?v=1754441184) for local reference/indexing.
- [SmartThings Developer Center](https://developer.smartthings.com/) - Information on creating [device integrations](https://developer.smartthings.com/docs/devices/device-basics) for interacting with Z-Wave and other device types.
- [SmartThings Edge driver for Z-Wave window treatments](https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/tree/main/drivers/SmartThings/zwave-window-treatment) - This is what drives the blinds by default.
- [Mariano's Edge-Drivers-Beta](https://github.com/Mariano-Github/Edge-Drivers-Beta) - Community driver collection. Its "Z-Wave Window Treatment Mc" and "Z-Wave Switch and Childs Mc" drivers were prior attempts at multichannel Z-Wave devices (the latter is where the component↔endpoint technique used here came from). The original community driver suggested for these blinds came from this collection, distributed via a shared channel.
- [SmartThings Advanced Dashboard](https://my.smartthings.com/advanced/devices) - Advanced view of the devices available on your Home Hub, which allows better control of drivers, etc.
- [SmartThings Developer Console](https://developer.smartthings.com/console/integrations) - Testing and development for new device integrations.
- [SmartThings Edge driver channels and sharing](https://developer.smartthings.com/docs/devices/hub-connected/test-and-share-drivers) - How drivers are published to channels and how hubs subscribe and auto-update.
