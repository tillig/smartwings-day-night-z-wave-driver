# Contributing

- [Repo Layout](#repo-layout)
- [Coordinate Model](#coordinate-model)
- [Custom Capabilities](#custom-capabilities)
- [Development Workflow](#development-workflow)
- [How Distribution Works](#how-distribution-works)
- [Scenes and State](#scenes-and-state)
- [Child "Sheer" Device](#child-sheer-device)
- [Why the Sheer Is a Separate Device](#why-the-sheer-is-a-separate-device)
- [Z-Wave Details](#z-wave-details)

## Repo Layout

- **`driver/`** — the Edge driver package uploaded to SmartThings.
  - `config.yml` — driver metadata. The only supported keys are `name`, `packageKey`, `permissions`, `description`, and `vendorSupportInformation`.
  - `fingerprints.yml` — claims Z-Wave `manufacturerId 0x045A` / `productType 0x0004` / `productId 0x0509` and maps it to the `smartwings-daynight` profile.
  - `profiles/` — device profiles. `smartwings-daynight` is the real device; `smartwings-sheer` is the child "Sheer" device; `smartwings-daynight-diagnostic` is unused but kept for hardware debugging (two raw motor sliders).
  - `src/init.lua` — all driver logic: component↔endpoint mapping, coordinate math, scene handling, child-device management, Z-Wave report handling, and capability command handlers.
  - `capabilities/` — source JSON for the custom capabilities (a `.capability.json` and `.presentation.json` per capability).
- **`setup/`** — PowerShell automation: `New-Capabilities.ps1` (create the custom capabilities), `Deploy-Driver.ps1` (package + assign + force-install), `Initialize-Driver.ps1` (first-time orchestrator), and `Test-Shade.ps1` (per-shade sanity check / cleanup).
- **`assets/`** — the SmartWings Z-Wave programming guide PDF.
- **`.github/`** — CI workflow + the PSScriptAnalyzer hook script.

## Coordinate Model

The firmware uses a single vertical scale: **value = rail HEIGHT**, 0 = window bottom, 100 = window top. Higher = more open.

- **Bottom rail** = Z-Wave endpoint 1 (the `main` window-shade component)
- **Middle rail** = Z-Wave endpoint 2 (no parent UI component; surfaced via the child "Sheer" device). `sheer` remains the internal routing key for that endpoint.
- **Sheer%** displayed = `100 - middle_height`
- **Hard rule:** `middle >= bottom` (firmware-enforced; the driver orders the two motor commands and staggers them by ~2.5 s so both motors run simultaneously without the firmware rejecting a cross)

The `FIELD_MIDDLE` / `FIELD_BOTTOM` device fields are the single source of truth for coupling math — the driver never reads back through the inverted sheer display value. They are persisted (`{ persist = true }`) so positions survive driver reloads; `device_init` also re-queries both rails so the display (and the child Sheer device) self-correct after an update.

**Note on lazy motors:** these motors reliably answer a `SET` (position command) but often ignore a bare `GET` (refresh), even for 60+ seconds. So the dependable way to resync displayed state is a position command (e.g. recalling the favorite), which is what `Test-Shade.ps1 -Force` does.

**Deferred optimization — simultaneous motion.** A full-travel move (Open, Sheer, recall from afar) currently moves the two rails one at a time with a ~2.5 s stagger to avoid the firmware rejecting a cross. The physical remote can run both motors at once using continuous-motion commands (`SWITCH_MULTILEVEL` `StartLevelChange`/`StopLevelChange`), which skip the absolute-position validation. Switching full-travel scenes to that approach would shave a few seconds, but needs careful re-testing of the no-cross safety (continuous motion doesn't self-clamp the way absolute SETs do). Left as-is because the staggered approach is proven correct.

## Custom Capabilities

The driver uses five custom capabilities, which live in the SmartThings account (not in the driver package):

| Capability | ID | Purpose |
| --- | --- | --- |
| Scene buttons | `<namespace>.blackout`, `.sheer`, `.open` | One stateless push-button per scene; each `push` drives the rails to that scene immediately |
| Preset position | `<namespace>.presetPosition` | Read-only readout of the saved favorite position ("Sheer N% / Open N%") |
| Settings | `<namespace>.settings` | Save and Activate buttons for the both-rail favorite position |

Create them with the CLI (or `setup/New-Capabilities.ps1`, which does all of them):

```powershell
smartthings capabilities:create -i driver/capabilities/<name>.capability.json
smartthings capabilities:presentation:create <capabilityId> -i driver/capabilities/<name>.presentation.json
```

The resulting ID takes the form `<accountNamespace>.<name>` (e.g. `happyvessel61954.blackout`). The namespace is assigned per SmartThings account, and `driver/profiles/smartwings-daynight.yml` and `driver/src/init.lua` hardcode the prefix `happyvessel61954.`. **To run this on a different account**, find your namespace (`smartthings capabilities:namespaces`), then find-and-replace `happyvessel61954.` with it in those two files before packaging.

## Development Workflow

Prerequisites: the [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli) (`npm install -g @smartthings/cli`), and Lua + [luacheck](https://github.com/lunarmodules/luacheck) for linting.

Lint and validate (the same checks CI runs):

```powershell
# Lint + syntax check (Lua, JSON, YAML, Markdown) via the pre-commit hooks
pre-commit run --all-files

# Validate the driver packages cleanly — no upload, no auth
smartthings edge:drivers:package driver --build-only out.zip
```

Deploy a new build. Releases are a **local** step — there is no CI upload, because SmartThings has no long-lived API token (PATs expire after 24 hours). The simplest path is `setup/Deploy-Driver.ps1`, which resolves your channel and hub (both cached after the first run), packages and assigns the driver, then **forces the hub to install the new version**:

```powershell
# First time — name your channel and hub (both get cached):
./setup/Deploy-Driver.ps1 -ChannelName '<your channel name>' -HubId '<your hub id>'

# Every time after that — no arguments needed:
./setup/Deploy-Driver.ps1
```

The force-install matters: assigning to the channel alone does **not** update an enrolled hub right away — the hub only auto-pulls on its periodic (~12 h) poll, so without forcing an install a driver re-select in the app would just re-apply the stale version still on the hub. After deploying, **Lua-only changes** hot-reload on the hub automatically, but **profile changes** (adding/removing components or capabilities) still require re-selecting the driver in the SmartThings app (Device → **⋮** → **Driver** → re-select **SmartWings Day/Night Z-Wave**) before the new layout appears.

To watch hub logs while testing: `smartthings edge:drivers:logcat <driverId> --hub-address <hub-ip>`. The connection is flaky and typically drops after 1–2 minutes, so use short bursts.

> **luacheck needs Lua 5.4, not 5.5.** The current luacheck release (1.2.0) cannot run under Lua 5.5 — an upstream gap that will resolve when luacheck adds 5.5 support. If your default `lua` is 5.5, install Lua 5.4 (`brew install lua@5.4`), install luacheck against it (`luarocks install luacheck`), and put `~/.luarocks/bin` ahead on your `PATH`. CI is unaffected — it pins its own Lua version.

## How Distribution Works

Edge drivers are distributed through **channels**: an author packages a driver and uploads it to a channel, and any hub **subscribed** to that channel pulls the driver down and **auto-updates** whenever a new version is uploaded (hubs poll roughly every 12 hours). Installing a community driver by clicking a shared "channel invitation" link is just subscribing your hub to someone else's channel — that is why such drivers seem to "just work" and update themselves: the author keeps uploading new versions to the channel you're subscribed to.

This project uses the same model, except you are on **both** sides of it: you own the channel *and* you build and upload to it. That is the extra step versus subscribing to someone else's channel — your local code changes don't reach the channel until you run a deploy, and the hub won't pick up a channel update until its slow periodic poll. `Deploy-Driver.ps1` handles the author's side end to end: it packages, assigns to your channel, and then forces your hub to install the new version immediately rather than waiting for the poll.

## Scenes and State

Scenes are stored as rail heights `{middle, bottom}`:

| Scene | Middle Height | Bottom Height |
| --- | --- | --- |
| Blackout | 100 | 0 |
| Sheer | 0 | 0 |
| Open | 100 | 100 |

The Scene component uses three stateless push-button capabilities (`blackout`, `sheer`, `open`) — one button each, and each `push` drives both rails to that scene immediately. (A custom capability can't render a single control as a row of always-fire buttons: `displayType: list` is a dropdown, and only the built-in `windowShade` gets the platform's special button treatment. One `pushButton` capability per scene is how you get genuine immediate-fire buttons.)

Separately, the `favorite` component holds the favorite controls: the `presetPosition` capability shows the saved position as a read-only readout, and the `settings` capability provides the Save and Activate buttons. The favorite stores a full `{middle, bottom}` position and defaults to `{middle: 76, bottom: 0}` (sheer ~24%) until the user saves their own.

## Child "Sheer" Device

On first init the driver creates a child device named `<shade name> Sheer` using the `smartwings-sheer` profile. This exposes the middle rail as an ordinary `windowShade` so Google Home picks it up as a second blind with full voice control ("open the sheer", "set the sheer to 50%"). It stays in sync via `sync_sheer_child()` whenever the parent receives a Z-Wave report for the middle rail.

## Why the Sheer Is a Separate Device

The opaque/bottom rail lives on the main device as a stock `windowShade`. The sheer/middle rail is **not** a control on the main device — it is exposed only through the child `<shade> Sheer` device (also a stock `windowShade`). Two reasons drove this:

1. **Voice control.** `windowShade` is a standard capability that Google Home / Alexa map to their blind/openable traits, so both the main shade and the child Sheer device are voice-controllable ("open the blinds", "open the sheer"). Custom capabilities are not exposed to voice assistants, so a custom in-app sheer slider could not be voiced.
2. **One place, no inversion fight.** An earlier design put a custom `sheerLevel` slider on the main device too, which showed the sheer twice and fought the platform's `windowShade`/`windowShadeLevel` linkage (the displayed value wedged). Putting the sheer solely on its own `windowShade` device removed the duplication and the linkage problem.

The child device's `windowShade` is mapped so **open = full sheer** (middle rail down) and **close = no sheer** (middle rail up); `sync_sheer_child()` keeps it in step with the middle rail.

## Z-Wave Details

- **ManufacturerId:** `0x045A` (1114)
- **ProductType:** `0x0004` (4)
- **ProductId:** `0x0509` (1289)
- **Command class:** `SWITCH_MULTILEVEL` v4, one SET/GET/REPORT per endpoint
- **Wire scale:** 0–99 (99 = 100%); `to_wire()` / `from_wire()` convert to and from the 0–100 SmartThings scale
