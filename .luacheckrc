-- luacheck configuration for SmartThings Edge driver
--
-- The driver runs in a sandboxed Lua 5.3 environment provided by SmartThings.
-- Runtime-injected modules (st.*, log, etc.) are accessed via require() and
-- bound to local variables, so they do not appear as globals at lint time.
-- This config targets catching real bugs (undefined globals, unused locals,
-- shadowed variables) without generating noise from handler-signature args
-- that are legitimately unused.

std = "lua53"

-- Do not enforce a max line length. The project already tolerates long lines
-- (markdownlint MD013 is disabled).
max_line_length = false

-- Handler functions throughout the driver follow the SmartThings callback
-- signature (driver, device, command) even when some args are not used in
-- that particular handler. Suppressing unused-argument warnings keeps the
-- output focused on genuine issues.
unused_args = false

-- Allow self-assignment patterns (e.g. "local x = x") which are idiomatic
-- in Lua for upvalue capture.
allow_defined_top = true

-- Files / patterns to check.
files = {
  ["driver/src/**/*.lua"] = {},
}

-- Globals that are either built into the Lua 5.3 std or injected by the
-- SmartThings Edge sandbox at runtime. The st.* modules are required() into
-- locals, so they do not need to be listed here.  The only true implicit
-- globals are the ones below.
globals = {
  -- None needed: all ST modules are accessed through require() into locals.
}

-- Read-only globals (standard Lua 5.3 built-ins are handled by std="lua53").
read_globals = {
  -- SmartThings sandbox additionally exposes these at the module level:
  -- (none beyond what lua53 std already provides)
}
