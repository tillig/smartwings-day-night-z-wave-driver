-- SmartWings Day/Night Z-Wave driver
-- Licensed under the MIT License (see repository LICENSE).
--
-- A SmartWings day/night cellular shade is a single Z-Wave node with two
-- multichannel SWITCH_MULTILEVEL endpoints, one per motor:
--   * endpoint 1 = BOTTOM rail  (component "main")
--   * endpoint 2 = MIDDLE rail  (component "sheer")
--
-- Coordinate model (confirmed empirically): value = rail HEIGHT on a single
-- vertical scale, 0 = window bottom, 100 = window top. Higher = more open.
-- The window is split top->bottom into three bands:
--   [top .. middle]    = SHEER fabric        (sheer% = 100 - middle)
--   [middle .. bottom] = OPAQUE fabric
--   [bottom .. floor]  = OPEN / see-through  (= bottom)
-- Hard physical rule: middle >= bottom. The firmware enforces this by validating
-- a move against the OTHER rail's *target* (not its current physical position),
-- so to raise the bottom past the middle we command the middle first, then the
-- bottom; both motors then run simultaneously.
--
-- UX (parent device components):
--   * "main"  presents the BOTTOM rail as an ordinary window shade so that
--     Google Home / voice "open|close|set NN%" behave like a normal blind.
--   * "scene" offers one-tap day/night scenes as three push-buttons (each fires
--     immediately): Blackout / Sheer / Open.
--   * "favorite" saves/recalls a full both-rail position (gear + button).
-- The MIDDLE rail (sheer) has NO parent component; it is exposed only through a
-- CHILD device ("<label> Sheer") -- an ordinary window shade so Google Home can
-- voice-control the sheer (open = full sheer) -- so the sheer appears just once.
--
-- CUSTOM CAPABILITIES: this driver references several custom capabilities whose
-- IDs embed a per-SmartThings-account namespace prefix (here "happyvessel61954."):
--   happyvessel61954.dayNightBlackout / dayNightSheer / dayNightOpen (scene buttons)
--   happyvessel61954.dayNightFavorite (save + recall a both-rail favorite)
-- Their source definitions live in driver/capabilities/*.json. A DIFFERENT account
-- gets a DIFFERENT namespace, so a fork must recreate them and find/replace the
-- prefix here and in profiles/*.yml. See CONTRIBUTING.md.

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local log = require "log"

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BOTTOM_COMPONENT = "main"   -- bottom rail, Z-Wave endpoint 1 (a real UI component)
-- "sheer" is a Z-Wave ROUTING KEY for the middle rail (endpoint 2), used with
-- send_to_component / the endpoint map. It is NOT a UI component on this device:
-- the middle rail is surfaced only through the child "Sheer" device, so the sheer
-- never appears twice. Do not emit display events to this key on the parent.
local SHEER_COMPONENT = "sheer"
local BOTTOM_EP = 1
local MIDDLE_EP = 2

-- Custom "day/night scene" buttons: one stateless push-button capability per
-- scene (Blackout / Sheer / Open), each firing its `push` command immediately.
-- (A custom capability can't render a row of always-fire buttons any other way --
-- `list` is a dropdown -- so we use a separate pushButton capability per scene.)
-- Capability IDs: happyvessel61954.dayNight{Blackout,Sheer,Open}; handlers are
-- registered explicitly in the driver template below.
-- Custom "day/night favorite" capability: save (gear) + recall (button) of a
-- full both-rail position, with a string readout of the saved value. Modeled on
-- the stock windowShadePreset, but it stores BOTH rails (stock holds only one).
local FAVORITE_CAP = "happyvessel61954.dayNightFavorite"

-- Persisted favorite position {middle, bottom}. Defaults match the user's typical
-- favorite until they save their own.
local FIELD_FAV_MIDDLE = "fav_middle"
local FIELD_FAV_BOTTOM = "fav_bottom"
local DEFAULT_FAV_MIDDLE = 76 -- sheer ~24%
local DEFAULT_FAV_BOTTOM = 0

-- Child "Sheer" device: presents the middle rail as its own ordinary window
-- shade so Google Home exposes it as a second, voice-controllable blind.
-- On the child, shadeLevel == sheer% (open = full sheer, close = no sheer).
local SHEER_CHILD_KEY = "sheer"
local SHEER_CHILD_PROFILE = "smartwings-sheer"

-- Device fields holding each rail's last-known true physical height (0-100).
-- These are the single source of truth for the coupling math; we never read it
-- back through the (inverted) sheer display value.
local FIELD_MIDDLE = "middle_height"
local FIELD_BOTTOM = "bottom_height"

-- Seconds to wait between the two ordered rail SETs so the firmware registers
-- the first rail's new target before validating the second.
local RAIL_STAGGER = 2.5

-- Day/night scene presets, expressed as physical rail heights {middle, bottom}.
local MODE_BLACKOUT = "Blackout"
local MODE_SHEER = "Sheer"
local MODE_OPEN = "Open"

-- The motor treats 99 as "100%". Map between the SmartThings 0-100 scale and
-- the Z-Wave 0-99 wire scale.
local function to_wire(level)
  if level >= 100 then return 99 end
  if level <= 0 then return 0 end
  return level
end

local function from_wire(value)
  if type(value) == "string" then return 0 end -- e.g. "OFF_DISABLE"
  if value == nil then return 0 end
  if value >= 99 then return 100 end
  if value <= 0 then return 0 end
  return value
end

--------------------------------------------------------------------------------
-- Component <-> endpoint mapping
--------------------------------------------------------------------------------

local function component_to_endpoint(device, component_id)
  if component_id == SHEER_COMPONENT then
    return { MIDDLE_EP }
  else
    return { BOTTOM_EP }
  end
end

local function endpoint_to_component(device, endpoint)
  if endpoint == MIDDLE_EP then
    return SHEER_COMPONENT
  else
    return BOTTOM_COMPONENT
  end
end

--------------------------------------------------------------------------------
-- State (true physical rail heights, kept in device fields)
--------------------------------------------------------------------------------

local function get_middle(device)
  local v = device:get_field(FIELD_MIDDLE)
  if v == nil then return 100 end
  return v
end

local function get_bottom(device)
  local v = device:get_field(FIELD_BOTTOM)
  if v == nil then return 0 end
  return v
end

-- Emit the bottom rail's display state to the "main" window-shade component.
-- (The middle rail has no parent UI component; it is shown via the child device.)
local function emit_bottom(device, height)
  local comp = device.profile.components[BOTTOM_COMPONENT]
  local attr = capabilities.windowShade.windowShade
  local state = attr.partially_open()
  if height >= 100 then
    state = attr.open()
  elseif height <= 0 then
    state = attr.closed()
  end
  device:emit_component_event(comp, state)
  device:emit_component_event(comp, capabilities.windowShadeLevel.shadeLevel(height))
end

--------------------------------------------------------------------------------
-- Child "Sheer" device
--------------------------------------------------------------------------------

local function get_sheer_child(device)
  return device:get_child_by_parent_assigned_key(SHEER_CHILD_KEY)
end

-- Create the child "Sheer" device once, if it doesn't already exist.
local function ensure_sheer_child(driver, device)
  if device.network_type == "DEVICE_EDGE_CHILD" then return end
  if get_sheer_child(device) ~= nil then return end
  driver:try_create_device({
    type = "EDGE_CHILD",
    label = (device.label or "Shade") .. " Sheer",
    profile = SHEER_CHILD_PROFILE,
    parent_device_id = device.id,
    parent_assigned_child_key = SHEER_CHILD_KEY,
  })
end

-- Push the current sheer% (= 100 - middle height) to the child device's
-- windowShade + windowShadeLevel so it stays in sync with the parent. open = full
-- sheer (level 100), close = no sheer (level 0).
local function sync_sheer_child(device, middle_height)
  local child = get_sheer_child(device)
  if child == nil then return end
  local sheer = 100 - middle_height
  local attr = capabilities.windowShade.windowShade
  local state = attr.partially_open()
  if sheer >= 100 then
    state = attr.open()
  elseif sheer <= 0 then
    state = attr.closed()
  end
  child:emit_event(state)
  child:emit_event(capabilities.windowShadeLevel.shadeLevel(sheer))
end

--------------------------------------------------------------------------------
-- Motor moves
--------------------------------------------------------------------------------

-- Send an absolute-position SET to one rail's endpoint, optimistically record the
-- new height, and update that component's display. A delayed GET re-reads the
-- firmware's (possibly clamped) true position to self-correct.
local function set_rail(device, component, height)
  height = math.max(0, math.min(100, height))
  device:send_to_component(SwitchMultilevel:Set({
    value = to_wire(height),
    duration = constants.DEFAULT_DIMMING_DURATION,
  }), component)
  -- Record the intended height for the coupling math, but DON'T emit display
  -- state optimistically -- the delayed GET's REPORT is the single source of
  -- truth for what the UI shows, which keeps hub and cloud state in lockstep.
  if component == SHEER_COMPONENT then
    device:set_field(FIELD_MIDDLE, height, { persist = true })
  else
    device:set_field(FIELD_BOTTOM, height, { persist = true })
  end
  device.thread:call_with_delay(8, function()
    device:send_to_component(SwitchMultilevel:Get({}), component)
  end)
end

-- Move both rails to physical heights {middle, bottom}, enforcing middle >= bottom
-- and ordering the two SETs so neither is rejected for crossing the other's target:
--   * raising the bottom toward/above the middle  -> set MIDDLE first, then bottom
--   * lowering the middle toward/below the bottom  -> set BOTTOM first, then middle
-- A short stagger lets the firmware register the first target; the motors then run
-- simultaneously.
local function move_to(device, middle, bottom)
  middle = math.max(0, math.min(100, middle))
  bottom = math.max(0, math.min(100, bottom))
  if middle < bottom then middle = bottom end -- enforce invariant

  local first, second
  if bottom > get_bottom(device) then
    -- bottom is rising: clear the middle out of the way first
    first = function() set_rail(device, SHEER_COMPONENT, middle) end
    second = function() set_rail(device, BOTTOM_COMPONENT, bottom) end
  else
    -- bottom is steady/falling: move it first so the middle has room to drop
    first = function() set_rail(device, BOTTOM_COMPONENT, bottom) end
    second = function() set_rail(device, SHEER_COMPONENT, middle) end
  end
  first()
  device.thread:call_with_delay(RAIL_STAGGER, second)
end

--------------------------------------------------------------------------------
-- Capability command handlers
--------------------------------------------------------------------------------

-- main: bottom rail as an ordinary window shade
local function bottom_set_level(driver, device, command)
  local target = command.args.shadeLevel or command.args.level or 0
  -- opening the bottom past the middle lifts the middle with it
  move_to(device, math.max(get_middle(device), target), target)
end

local function bottom_open(driver, device, command)
  move_to(device, 100, 100)
end

local function bottom_close(driver, device, command)
  -- Close = lower the bottom rail only; leave the sheer/middle rail as-is.
  move_to(device, get_middle(device), 0)
end

-- Set the sheer amount (0-100) on a given PARENT device: middle = 100 - sheer,
-- clamped so the middle rail never drops below the bottom rail. Driven by the
-- child "Sheer" device's commands.
local function set_sheer(parent, sheer)
  sheer = math.max(0, math.min(100, sheer))
  move_to(parent, 100 - sheer, get_bottom(parent))
end

local function pause(driver, device, command)
  device:send_to_component(SwitchMultilevel:StopLevelChange({}), command.component)
end

--------------------------------------------------------------------------------
-- Child "Sheer" device command handlers (route to the parent's middle rail).
-- On the child, shadeLevel == sheer%, open = full sheer, close = no sheer.
--------------------------------------------------------------------------------

local function child_sheer_set_level(driver, child, command)
  local parent = child:get_parent_device()
  if parent then set_sheer(parent, command.args.shadeLevel or command.args.level or 0) end
end

local function child_sheer_open(driver, child, command)
  local parent = child:get_parent_device()
  if parent then set_sheer(parent, 100) end -- full sheer
end

local function child_sheer_close(driver, child, command)
  local parent = child:get_parent_device()
  if parent then set_sheer(parent, 0) end -- no sheer
end

local function child_sheer_pause(driver, child, command)
  local parent = child:get_parent_device()
  if parent then parent:send_to_component(SwitchMultilevel:StopLevelChange({}), SHEER_COMPONENT) end
end

-- Favorite position: a saved {middle, bottom} pair, recalled with one tap. Modeled
-- on windowShadePreset (gear = save, button = recall) but stores BOTH rails.
local function get_favorite(device)
  return device:get_field(FIELD_FAV_MIDDLE) or DEFAULT_FAV_MIDDLE,
         device:get_field(FIELD_FAV_BOTTOM) or DEFAULT_FAV_BOTTOM
end

-- Emit the readout shown under the Favorite control, e.g. "sheer 24% / open 0%".
local function emit_favorite(device)
  local middle, bottom = get_favorite(device)
  local text = string.format('sheer %d%% / open %d%%', 100 - middle, bottom)
  device:emit_component_event(device.profile.components['favorite'],
    capabilities[FAVORITE_CAP].favorite(text))
end

-- gear: capture the current both-rail position as the favorite.
local function save_favorite(driver, device, command)
  local middle, bottom = get_middle(device), get_bottom(device)
  device:set_field(FIELD_FAV_MIDDLE, middle, { persist = true })
  device:set_field(FIELD_FAV_BOTTOM, bottom, { persist = true })
  log.info(string.format('save_favorite: middle=%d bottom=%d', middle, bottom))
  emit_favorite(device)
end

-- button: drive both rails back to the saved favorite.
local function recall_favorite(driver, device, command)
  local middle, bottom = get_favorite(device)
  move_to(device, middle, bottom)
end

-- Drive the rails to a named scene.
local function apply_scene(device, scene)
  if scene == MODE_BLACKOUT then
    move_to(device, 100, 0)
  elseif scene == MODE_SHEER then
    move_to(device, 0, 0)
  elseif scene == MODE_OPEN then
    move_to(device, 100, 100)
  else
    log.warn("apply_scene: unknown scene " .. tostring(scene))
  end
end

-- Each scene push-button's `push` command maps to a fixed scene.
local function make_scene_button(scene)
  return function(driver, device, command)
    apply_scene(device, scene)
  end
end


--------------------------------------------------------------------------------
-- Z-Wave report handler (single path; updates field + display per endpoint)
--------------------------------------------------------------------------------

local function switch_multilevel_report(driver, device, cmd)
  local raw = cmd.args.target_value
  if raw == nil or raw == "OFF_DISABLE" then raw = cmd.args.value end
  local height = from_wire(raw)
  local endpoint = cmd.src_channel or 0

  if endpoint == MIDDLE_EP then
    device:set_field(FIELD_MIDDLE, height, { persist = true })
    sync_sheer_child(device, height) -- the middle rail is shown only on the child "Sheer" device
  else
    device:set_field(FIELD_BOTTOM, height, { persist = true })
    emit_bottom(device, height)
  end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function refresh_positions(device)
  device:send_to_component(SwitchMultilevel:Get({}), BOTTOM_COMPONENT)
  device:send_to_component(SwitchMultilevel:Get({}), SHEER_COMPONENT)
  device:send(Battery:Get({}))
end

local function device_init(self, device)
  if device.network_type == "DEVICE_EDGE_CHILD" then return end
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  emit_favorite(device)
  ensure_sheer_child(self, device)
  -- Re-query both rails so displayed state (incl. the child "Sheer" device) is
  -- corrected after a driver reload, when the in-memory height fields are stale.
  refresh_positions(device)
end

local function device_added(self, device)
  if device.network_type == "DEVICE_EDGE_CHILD" then
    -- Child "Sheer" device: seed its display from the parent's current middle rail.
    device:emit_event(capabilities.windowShade.supportedWindowShadeCommands(
      { "open", "close", "pause" }, { visibility = { displayed = false } }))
    local parent = device:get_parent_device()
    if parent then sync_sheer_child(parent, get_middle(parent)) end
    return
  end
  device:emit_component_event(device.profile.components[BOTTOM_COMPONENT],
    capabilities.windowShade.supportedWindowShadeCommands(
      { "open", "close", "pause" }, { visibility = { displayed = false } }))
  emit_favorite(device)
  ensure_sheer_child(self, device)
  refresh_positions(device)
end

local function do_refresh(driver, device, command)
  if device.network_type == "DEVICE_EDGE_CHILD" then
    local parent = device:get_parent_device()
    if parent then refresh_positions(parent) end
    return
  end
  refresh_positions(device)
end

--------------------------------------------------------------------------------
-- Driver definition
--------------------------------------------------------------------------------

local driver_template = {
  supported_capabilities = {
    capabilities.battery,
  },
  zwave_handlers = {
    [cc.SWITCH_MULTILEVEL] = {
      [SwitchMultilevel.REPORT] = switch_multilevel_report,
    },
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    ["happyvessel61954.dayNightBlackout"] = { ["push"] = make_scene_button(MODE_BLACKOUT) },
    ["happyvessel61954.dayNightSheer"] = { ["push"] = make_scene_button(MODE_SHEER) },
    ["happyvessel61954.dayNightOpen"] = { ["push"] = make_scene_button(MODE_OPEN) },
    [FAVORITE_CAP] = {
      ["save"] = save_favorite,
      ["recall"] = recall_favorite,
    },
    -- windowShade/windowShadeLevel arrive from EITHER the parent's "main" (bottom
    -- rail) OR the child "Sheer" device. Dispatch by device type.
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = function(driver, device, command)
        if device.network_type == "DEVICE_EDGE_CHILD" then return child_sheer_open(driver, device, command) end
        return bottom_open(driver, device, command)
      end,
      [capabilities.windowShade.commands.close.NAME] = function(driver, device, command)
        if device.network_type == "DEVICE_EDGE_CHILD" then return child_sheer_close(driver, device, command) end
        return bottom_close(driver, device, command)
      end,
      [capabilities.windowShade.commands.pause.NAME] = function(driver, device, command)
        if device.network_type == "DEVICE_EDGE_CHILD" then return child_sheer_pause(driver, device, command) end
        return pause(driver, device, command)
      end,
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = function(driver, device, command)
        if device.network_type == "DEVICE_EDGE_CHILD" then return child_sheer_set_level(driver, device, command) end
        return bottom_set_level(driver, device, command)
      end,
    },
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
}

-- Register defaults only for battery; all shade reports/commands are handled
-- explicitly above so there is exactly ONE report path (no stock handler writing
-- conflicting values to the inverted sheer component).
defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)

--- @type st.zwave.Driver
local smartwings_daynight = ZwaveDriver("smartwings-daynight-zwave", driver_template)
smartwings_daynight:run()
