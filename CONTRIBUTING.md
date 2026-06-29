# Contributing

## Repo layout

```
smartwings-day-night-z-wave-driver/
├── driver/
│   ├── config.yml                  # Driver metadata (name, packageKey, permissions)
│   ├── fingerprints.yml            # Z-Wave device matching rules
│   ├── profiles/
│   │   ├── smartwings-daynight.yml         # Main profile (the real device)
│   │   ├── smartwings-sheer.yml            # Child "Sheer" device profile
│   │   └── smartwings-daynight-diagnostic.yml  # UNUSED — kept for troubleshooting
│   ├── src/
│   │   └── init.lua                # All driver logic (~530 lines)
│   └── capabilities/
│       ├── activateScene.capability.json   # "Apply selected mode" button
│       ├── activateScene.presentation.json
│       ├── sheerLevel.capability.json      # 0–100% sheer slider
│       ├── sheerLevel.presentation.json
│       ├── saveFavorite.capability.json    # "Save current as Favorite" button
│       └── saveFavorite.presentation.json
├── assets/
│   └── smartwings-z-wave-programming-guide.pdf
├── setup/                          # PowerShell install automation
└── .github/                        # CI/CD
```

### Key files

**`driver/config.yml`** — Driver name, `packageKey`, Z-Wave permission, and support URL. The supported top-level keys are `name`, `packageKey`, `permissions`, `description`, and `vendorSupportInformation`.

**`driver/fingerprints.yml`** — Claims Z-Wave `manufacturerId 0x045A` / `productType 0x0004` / `productId 0x0509` → profile `smartwings-daynight`.

**`driver/profiles/smartwings-daynight-diagnostic.yml`** — An old diagnostic profile with two raw motor sliders (Motor A / Motor B). Not used in normal operation; keep it around for hardware debugging.

**`driver/src/init.lua`** — Contains all logic: component↔endpoint mapping, coordinate math, scene handling, child device management, Z-Wave report handling, and all capability command handlers.

---

## Coordinate model

The firmware uses a single vertical scale: **value = rail HEIGHT**, 0 = window bottom, 100 = window top. Higher = more open.

- **Bottom rail** = Z-Wave endpoint 1, component `main`
- **Middle rail** = Z-Wave endpoint 2, component `sheer`
- **Sheer%** displayed = `100 - middle_height`
- **Hard rule:** `middle >= bottom` (firmware-enforced; the driver orders the two motor commands and staggers them by ~2.5 s so both motors run simultaneously without the firmware rejecting a cross)

The two `FIELD_MIDDLE` / `FIELD_BOTTOM` device fields are the single source of truth for coupling math — the driver never reads back through the inverted sheer display value.

---

## Custom capabilities

The driver uses three custom capabilities:

| Capability | ID | Purpose |
|------------|----|---------|
| Sheer Level | `<namespace>.sheerLevel` | 0–100% slider for the middle rail |
| Activate Scene | `<namespace>.activateScene` | Stateless "Apply selected mode" push button |
| Save Favorite | `<namespace>.saveFavorite` | Stateless "Save current as Favorite" push button |

Custom capabilities live in the SmartThings account, not in the driver package. They are created with the CLI:

```sh
smartthings capabilities:create -i driver/capabilities/<name>.capability.json
smartthings capabilities:presentation:create <capabilityId> \
  -i driver/capabilities/<name>.presentation.json
```

The resulting ID takes the form `<accountNamespace>.<name>` (e.g. `happyvessel61954.sheerLevel`).

### Namespace prefix: the main fork gotcha

The profiles (`driver/profiles/smartwings-daynight.yml`) and `driver/src/init.lua` hardcode the namespace prefix `happyvessel61954.`. On a different SmartThings account the namespace will be different. To use this driver on another account:

1. Find your namespace: `smartthings capabilities:namespaces` (or `smartthings capabilities` to list capabilities and read the prefix off any of them).
2. Find and replace `happyvessel61954.` with your namespace in:
   - `driver/profiles/smartwings-daynight.yml`
   - `driver/src/init.lua`
3. Re-create the capabilities under your account (steps above), then re-deploy the driver.

---

## Development workflow

### Prerequisites

- [`lua`/`luac`](https://www.lua.org/) for syntax checking: `brew install lua`
- [`luacheck`](https://github.com/lunarmodules/luacheck) for linting (see note below): `luarocks install luacheck`
- [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli): `npm install -g @smartthings/cli`

### Syntax check

```sh
luac -p driver/src/init.lua
```

No output = clean. This catches Lua syntax errors before deploying to the hub. `luac -p` works under any Lua version.

### Lint

```sh
luacheck driver/src/init.lua    # uses .luacheckrc
```

This is also run in CI and via the `luacheck` pre-commit hook.

> **luacheck needs Lua 5.4 — not 5.5.** The current luacheck release (1.2.0) cannot run under Lua 5.5 (its own code fails to load). This is an upstream gap, not a project issue, and will resolve when luacheck adds 5.5 support. If your default `lua` is 5.5, install Lua 5.4 (`brew install lua@5.4`) and install luacheck against it (`luarocks install luacheck`); the resulting wrapper at `~/.luarocks/bin/luacheck` is bound to 5.4. Put `~/.luarocks/bin` ahead on your `PATH` so `luacheck` resolves to it:
>
> ```sh
> export PATH="$HOME/.luarocks/bin:$PATH"
> ```
>
> CI is unaffected — it pins its own Lua version.

### Build / validate (dry run)

```sh
smartthings edge:drivers:package driver --build-only out.zip
```

Packages the driver and validates the YAML/JSON **without uploading and without
any authentication**. This is exactly what CI runs on every push/PR.

### Deploy / release

Releases are a **local** step — there is no CI upload. SmartThings has no
long-lived API token (personal access tokens expire after 24 hours), so
automating channel uploads in CI is impractical. Use the local CLI login
(`smartthings login`, which auto-refreshes) and the setup script:

```powershell
# Release to the channel (enrolled hubs auto-update):
./setup/Install-Driver.ps1 -ChannelId <channelId>

# Or release AND install directly on a specific hub:
./setup/Install-Driver.ps1 -ChannelId <channelId> -HubId <hubId>
```

Or invoke the CLI directly:

```sh
smartthings edge:drivers:package driver --channel <channelId> [--hub <hubId>]
```

Re-running re-uploads the driver. Notes:

- **Lua-only changes** hot-reload on the hub without requiring any action in the app.
- **Profile changes** (adding/removing components or capabilities) may require re-selecting the driver in the SmartThings app (Device → **⋮** → **Driver** → re-select **SmartWings Day/Night Z-Wave**) before the new layout appears.

### Watch logs

```sh
smartthings edge:drivers:logcat <driverId> --hub-address <hub-ip>
```

The `logcat` connection is flaky and typically drops after 1–2 minutes. Use short observation bursts rather than leaving it running.

### Re-selecting the driver after a profile change

1. Open the SmartThings app.
2. Go to the shade device → **⋮** (three dots) → **Driver**.
3. Select **SmartWings Day/Night Z-Wave**.

---

## Scenes and state

Scenes are stored as rail heights `{middle, bottom}`:

| Scene | Middle height | Bottom height |
|-------|--------------|---------------|
| Blackout | 100 | 0 |
| Sheer | 0 | 0 |
| Open | 100 | 100 |
| Favorite | persisted per device | persisted per device |

The Favorite defaults to `{middle: 76, bottom: 0}` (sheer ~24%) until the user saves their own with "Save current as Favorite".

The Scene component uses the standard `mode` capability to display the dropdown. Because the true state is two rail heights (not an enum), the displayed mode reflects the named preset the rails currently sit on — or the last-invoked scene otherwise.

---

## Child "Sheer" device

On first init, the driver automatically creates a child device named `<shade name> Sheer` using the `smartwings-sheer` profile. This exposes the middle rail as an ordinary `windowShade` so Google Home picks it up as a second blind with full voice control ("open the sheer", "set the sheer to 50%").

The child device is kept in sync by `sync_sheer_child()` every time the parent receives a Z-Wave report for the middle rail.

---

## Z-Wave details

- **ManufacturerId:** `0x045A` (1114)
- **ProductType:** `0x0004` (4)
- **ProductId:** `0x0509` (1289)
- **Command class:** `SWITCH_MULTILEVEL` v4, one SET/GET/REPORT per endpoint
- **Wire scale:** 0–99 (99 = 100%); `to_wire()` / `from_wire()` convert to/from the 0–100 SmartThings scale
