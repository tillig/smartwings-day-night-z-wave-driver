# Contributing

- [Repo Layout](#repo-layout)
- [Coordinate Model](#coordinate-model)
- [Custom Capabilities](#custom-capabilities)
- [Development Workflow](#development-workflow)
- [How Distribution Works](#how-distribution-works)
- [Scenes and State](#scenes-and-state)
- [Child "Sheer" Device](#child-sheer-device)
- [Why the Shade and Sheer Controls Look Different](#why-the-shade-and-sheer-controls-look-different)
- [Z-Wave Details](#z-wave-details)

## Repo Layout

- **`driver/`** — the Edge driver package uploaded to SmartThings.
  - `config.yml` — driver metadata. The only supported keys are `name`, `packageKey`, `permissions`, `description`, and `vendorSupportInformation`.
  - `fingerprints.yml` — claims Z-Wave `manufacturerId 0x045A` / `productType 0x0004` / `productId 0x0509` and maps it to the `smartwings-daynight` profile.
  - `profiles/` — device profiles. `smartwings-daynight` is the real device; `smartwings-sheer` is the child "Sheer" device; `smartwings-daynight-diagnostic` is unused but kept for hardware debugging (two raw motor sliders).
  - `src/init.lua` — all driver logic: component↔endpoint mapping, coordinate math, scene handling, child-device management, Z-Wave report handling, and capability command handlers.
  - `capabilities/` — source JSON for the custom capabilities (a `.capability.json` and `.presentation.json` per capability).
- **`setup/`** — PowerShell automation for installing and updating the driver.
- **`assets/`** — the SmartWings Z-Wave programming guide PDF.
- **`.github/`** — CI workflow.

## Coordinate Model

The firmware uses a single vertical scale: **value = rail HEIGHT**, 0 = window bottom, 100 = window top. Higher = more open.

- **Bottom rail** = Z-Wave endpoint 1, component `main`
- **Middle rail** = Z-Wave endpoint 2, component `sheer`
- **Sheer%** displayed = `100 - middle_height`
- **Hard rule:** `middle >= bottom` (firmware-enforced; the driver orders the two motor commands and staggers them by ~2.5 s so both motors run simultaneously without the firmware rejecting a cross)

The `FIELD_MIDDLE` / `FIELD_BOTTOM` device fields are the single source of truth for coupling math — the driver never reads back through the inverted sheer display value.

## Custom Capabilities

The driver uses three custom capabilities, which live in the SmartThings account (not in the driver package):

| Capability | ID | Purpose |
| --- | --- | --- |
| Sheer Level | `<namespace>.sheerLevel` | 0–100% slider for the middle rail |
| Activate Scene | `<namespace>.activateScene` | Stateless "Apply selected mode" push button |
| Save Favorite | `<namespace>.saveFavorite` | Stateless "Save current as Favorite" push button |

Create them with the CLI (or `setup/New-Capabilities.ps1`, which does all three):

```powershell
smartthings capabilities:create -i driver/capabilities/<name>.capability.json
smartthings capabilities:presentation:create <capabilityId> -i driver/capabilities/<name>.presentation.json
```

The resulting ID takes the form `<accountNamespace>.<name>` (e.g. `happyvessel61954.sheerLevel`). The namespace is assigned per SmartThings account, and `driver/profiles/smartwings-daynight.yml` and `driver/src/init.lua` hardcode the prefix `happyvessel61954.`. **To run this on a different account**, find your namespace (`smartthings capabilities:namespaces`), then find-and-replace `happyvessel61954.` with it in those two files before packaging.

## Development Workflow

Prerequisites: the [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli) (`npm install -g @smartthings/cli`), and Lua + [luacheck](https://github.com/lunarmodules/luacheck) for linting.

Lint and validate (the same checks CI runs):

```powershell
# Lint + syntax check (Lua, JSON, YAML, Markdown) via the pre-commit hooks
pre-commit run --all-files

# Validate the driver packages cleanly — no upload, no auth
smartthings edge:drivers:package driver --build-only out.zip
```

Deploy a new build. Releases are a **local** step — there is no CI upload, because SmartThings has no long-lived API token (PATs expire after 24 hours). The simplest path is `setup/Deploy-Driver.ps1`, which resolves your channel (cached after the first run) and packages + assigns the driver:

```powershell
# First time — point it at your channel by name (then it's cached):
./setup/Deploy-Driver.ps1 -ChannelName '<your channel name>'

# Every time after that — no arguments needed:
./setup/Deploy-Driver.ps1
```

After deploying, **Lua-only changes** hot-reload on the hub automatically, but **profile changes** (adding/removing components or capabilities) require re-selecting the driver in the SmartThings app (Device → **⋮** → **Driver** → re-select **SmartWings Day/Night Z-Wave**) before the new layout appears.

To watch hub logs while testing: `smartthings edge:drivers:logcat <driverId> --hub-address <hub-ip>`. The connection is flaky and typically drops after 1–2 minutes, so use short bursts.

> **luacheck needs Lua 5.4, not 5.5.** The current luacheck release (1.2.0) cannot run under Lua 5.5 — an upstream gap that will resolve when luacheck adds 5.5 support. If your default `lua` is 5.5, install Lua 5.4 (`brew install lua@5.4`), install luacheck against it (`luarocks install luacheck`), and put `~/.luarocks/bin` ahead on your `PATH`. CI is unaffected — it pins its own Lua version.

## How Distribution Works

Edge drivers are distributed through **channels**: an author packages a driver and uploads it to a channel, and any hub **subscribed** to that channel pulls the driver down and **auto-updates** whenever a new version is uploaded (hubs poll roughly every 12 hours). Installing a community driver by clicking a shared "channel invitation" link is just subscribing your hub to someone else's channel — that is why such drivers seem to "just work" and update themselves: the author keeps uploading new versions to the channel you're subscribed to.

This project uses the same model, except you are on **both** sides of it: you own the channel *and* you build and upload to it. That is the extra step versus subscribing to someone else's channel — your local code changes don't reach the channel until you run a deploy. Once deployed, the hub auto-pulls it like any other channel update. `Deploy-Driver.ps1` automates the author's side (package, assign to your channel), and the first install also enrolls your hub.

## Scenes and State

Scenes are stored as rail heights `{middle, bottom}`:

| Scene | Middle Height | Bottom Height |
| --- | --- | --- |
| Blackout | 100 | 0 |
| Sheer | 0 | 0 |
| Open | 100 | 100 |
| Favorite | persisted per device | persisted per device |

The Favorite defaults to `{middle: 76, bottom: 0}` (sheer ~24%) until the user saves their own with "Save current as Favorite". The Scene component uses the standard `mode` capability for the dropdown; because the true state is two rail heights (not an enum), the displayed mode reflects the named preset the rails currently sit on, or the last-invoked scene otherwise.

## Child "Sheer" Device

On first init the driver creates a child device named `<shade name> Sheer` using the `smartwings-sheer` profile. This exposes the middle rail as an ordinary `windowShade` so Google Home picks it up as a second blind with full voice control ("open the sheer", "set the sheer to 50%"). It stays in sync via `sync_sheer_child()` whenever the parent receives a Z-Wave report for the middle rail.

## Why the Shade and Sheer Controls Look Different

The **Shade** (bottom rail) uses the stock `windowShade` capability — the combined tile with Open/Close/Pause buttons and a draggable percentage bar. The **Sheer** (middle rail) uses the custom `sheerLevel` slider. This asymmetry is deliberate, for two reasons:

1. **Voice control.** `windowShade` is a standard capability that Google Home / Alexa map to their blind/openable traits, enabling "open/close/set to N%" by voice. Custom capabilities like `sheerLevel` are not exposed to voice assistants — which is why the sheer rail also gets its own child `windowShade` device for voice.
2. **Inverted semantics.** The sheer value is inverted relative to rail height (`sheer% = 100 − middle`). Driving that through the stock `windowShade` / `windowShadeLevel` pair fought the platform's built-in shade-vs-level linkage and left the displayed value wedged. A custom slider avoids that.

So: stock `windowShade` where voice and standard behavior matter (the opaque shade), custom slider where clean inverted control matters (the in-app sheer). Unifying the look would break one or both.

## Z-Wave Details

- **ManufacturerId:** `0x045A` (1114)
- **ProductType:** `0x0004` (4)
- **ProductId:** `0x0509` (1289)
- **Command class:** `SWITCH_MULTILEVEL` v4, one SET/GET/REPORT per endpoint
- **Wire scale:** 0–99 (99 = 100%); `to_wire()` / `from_wire()` convert to and from the 0–100 SmartThings scale
