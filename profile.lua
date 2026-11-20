-- A profiler for the villager's callbacks, off unless living_villages_profile is set.
--
-- About forty modules each wrap the villager's do_custom (init.lua installs them one
-- inside the next), so every loaded villager runs the whole chain every server step.
-- init.lua calls M.mark(def, name) after each install: if do_custom or on_step changed,
-- the new outermost function is wrapped in a timer named after the module. A timer
-- counts only its own time: what the timers nested inside it took is taken off, so
-- "do_custom:farmer" is farmer.lua's wrapper alone, not everything it calls through.
-- "on_step:vanilla" is mcl_mobs's own step (physics, animation, its AI) less the
-- do_custom chain it calls.
--
-- The mod's globalsteps, ABMs, LBMs and core.after callbacks are timed too, named by
-- the file that registered them, and so is the villager's get_staticdata with the size
-- of what it saves. Two clock reads per timer add a little to every figure.
--
-- Read it with /living_villages_profile (or `reset`), or in the log every
-- living_villages_profile_log_seconds.
local core = minetest

local M = {}

local function setting_bool(name)
	return core.settings and core.settings:get_bool(name, false) or false
end

local enabled = setting_bool("living_villages_profile")

function M.enabled() return enabled end

-- Microseconds; os.clock stands in where the engine is not there (tests).
local clock = core.get_us_time or function() return os.clock() * 1e6 end

local entries, order = {}, {}
local nested = 0
local window_start = clock()
local staticdata = {calls = 0, bytes = 0, max = 0}

local function entry(name)
	local found = entries[name]
	if not found then
		found = {name = name, time = 0, calls = 0, max = 0}
		entries[name] = found
		order[#order + 1] = name
	end
	return found
end

local function finish(e, started, saved, ...)
	local elapsed = clock() - started
	local own = elapsed - nested
	e.time = e.time + own
	e.calls = e.calls + 1
	if own > e.max then e.max = own end
	nested = saved + elapsed
	return ...
end

-- fn, timed under name.
function M.timed(name, fn)
	local e = entry(name)
	return function(...)
		local saved = nested
		nested = 0
		local started = clock()
		return finish(e, started, saved, fn(...))
	end
end

local marked = setmetatable({}, {__mode = "k"})

-- Wraps do_custom and on_step if they changed since the last mark.
function M.mark(def, name)
	if not enabled then return end
	local last = marked[def]
	if not last then
		last = {}
		marked[def] = last
	end
	for _, field in ipairs({"do_custom", "on_step"}) do
		local fn = def[field]
		if type(fn) == "function" and fn ~= last[field] then
			def[field] = M.timed(field .. ":" .. name, fn)
			last[field] = def[field]
		end
	end
end

-- Times get_staticdata and counts what it saves.
function M.wrap_staticdata(def)
	if not enabled or type(def.get_staticdata) ~= "function" then return end
	local timed = M.timed("get_staticdata", def.get_staticdata)
	def.get_staticdata = function(self)
		local data = timed(self)
		if type(data) == "string" then
			staticdata.calls = staticdata.calls + 1
			staticdata.bytes = staticdata.bytes + #data
			if #data > staticdata.max then staticdata.max = #data end
		end
		return data
	end
end

function M.reset()
	for _, e in pairs(entries) do e.time, e.calls, e.max = 0, 0, 0 end
	staticdata.calls, staticdata.bytes, staticdata.max = 0, 0, 0
	window_start = clock()
end

-- The window so far: entries with calls, most time first.
function M.snapshot()
	local list = {}
	for _, name in ipairs(order) do
		local e = entries[name]
		if e.calls > 0 then list[#list + 1] = {name = e.name, time = e.time, calls = e.calls, max = e.max} end
	end
	table.sort(list, function(a, b)
		if a.time ~= b.time then return a.time > b.time end
		return a.name < b.name
	end)
	local total = 0
	for _, e in ipairs(list) do total = total + e.time end
	return {seconds = (clock() - window_start) / 1e6, total = total, entries = list,
		staticdata = {calls = staticdata.calls, bytes = staticdata.bytes, max = staticdata.max}}
end

local function villager_steps(snap)
	for _, e in ipairs(snap.entries) do
		if e.name == "on_step:vanilla" then return e.calls end
	end
	return 0
end

-- One line per entry, for the chat command; limit caps the entries.
function M.report(limit)
	local snap = M.snapshot()
	local seconds = math.max(snap.seconds, 1e-6)
	local lines = {string.format(
		"living_villages profile: %.1f s, %.1f ms of Lua a second (%.2f%% of one core), %d villager steps a second",
		snap.seconds, snap.total / 1000 / seconds, snap.total / 1e4 / seconds, villager_steps(snap) / seconds)}
	for i, e in ipairs(snap.entries) do
		if limit and i > limit then break end
		lines[#lines + 1] = string.format("%5.1f%%  %8.2f ms/s  %7.1f us/call  max %7.0f us  %8d calls  %s",
			snap.total > 0 and 100 * e.time / snap.total or 0, e.time / 1000 / seconds, e.time / e.calls,
			e.max, e.calls, e.name)
	end
	local sd = snap.staticdata
	if sd.calls > 0 then
		lines[#lines + 1] = string.format("staticdata: %d saves, %.0f bytes average, %d max", sd.calls,
			sd.bytes / sd.calls, sd.max)
	end
	return table.concat(lines, "\n")
end

-- One line for the log: the totals and every entry (or the top limit) as name=ms/s.
function M.log_line(limit)
	local snap = M.snapshot()
	local seconds = math.max(snap.seconds, 1e-6)
	local parts = {}
	for i, e in ipairs(snap.entries) do
		if limit and i > limit then break end
		parts[#parts + 1] = string.format("%s=%.2f", e.name, e.time / 1000 / seconds)
	end
	local sd = snap.staticdata
	return string.format("[living_villages] profile: %.0f s, lua %.2f ms/s, villager steps %.1f/s, "
		.. "staticdata %d saves avg %.0f max %d B; ms/s: %s",
		snap.seconds, snap.total / 1000 / seconds, villager_steps(snap) / seconds, sd.calls,
		sd.calls > 0 and sd.bytes / sd.calls or 0, sd.max, table.concat(parts, " "))
end

-- The file a registration came from, if it is one of this mod's, or nil. level counts
-- from the caller: 2 is whoever called the function that calls this.
local modpath = core.get_modpath and core.get_modpath("living_villages")
local function own_source(level)
	if not modpath or not debug or not debug.getinfo then return nil end
	local info = debug.getinfo(level + 1, "S")
	local source = info and info.source
	if type(source) ~= "string" then return nil end
	source = source:gsub("^@", ""):gsub("\\", "/")
	local base = modpath:gsub("\\", "/")
	if source:sub(1, #base) ~= base then return nil end
	return source:sub(#base + 2):gsub("%.lua$", "")
end

-- Times this mod's globalsteps, ABMs, LBMs and core.after callbacks; others pass through.
local function capture_registrations()
	if core.register_globalstep then
		local original = core.register_globalstep
		core.register_globalstep = function(fn, ...)
			local source = own_source(2)
			if source then fn = M.timed("globalstep:" .. source, fn) end
			return original(fn, ...)
		end
	end
	for _, kind in ipairs({"abm", "lbm"}) do
		local key = "register_" .. kind
		local original = core[key]
		if original then
			core[key] = function(spec, ...)
				local source = own_source(2)
				if source and type(spec) == "table" and type(spec.action) == "function" then
					spec.action = M.timed(kind .. ":" .. (spec.label or source), spec.action)
				end
				return original(spec, ...)
			end
		end
	end
	if core.after then
		local original = core.after
		core.after = function(delay, fn, ...)
			local source = own_source(2)
			if source and type(fn) == "function" then fn = M.timed("after:" .. source, fn) end
			return original(delay, fn, ...)
		end
	end
end

local function start()
	if core.register_chatcommand then
		core.register_chatcommand("living_villages_profile", {
			params = "[reset]",
			description = "Show where the villagers' Lua time goes since the last reset",
			privs = {server = true},
			func = function(_, param)
				if param == "reset" then
					M.reset()
					return true, "profile reset"
				end
				return true, M.report()
			end,
		})
	end
	local every = tonumber(core.settings and core.settings:get("living_villages_profile_log_seconds")) or 60
	if every > 0 and core.register_globalstep then
		local elapsed = 0
		-- Registered before the capture below: not one of the timed globalsteps.
		core.register_globalstep(function(dtime)
			elapsed = elapsed + dtime
			if elapsed < every then return end
			elapsed = 0
			core.log("action", M.log_line())
			M.reset()
		end)
	end
	capture_registrations()
	core.log("action", "[living_villages] profiler on")
end

if enabled then start() end

return M
