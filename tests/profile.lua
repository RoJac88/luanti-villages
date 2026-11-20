-- Run with: lua tests/profile.lua
local now = 0
local commands, globalsteps, logs = {}, {}, {}
minetest = {
	get_modpath = function() return "." end,
	get_us_time = function() return now end,
	settings = {
		get_bool = function(_, name, default)
			if name == "living_villages_profile" then return true end
			return default
		end,
		get = function(_, name)
			if name == "living_villages_profile_log_seconds" then return "10" end
		end,
	},
	register_chatcommand = function(name, def) commands[name] = def end,
	register_globalstep = function(fn) globalsteps[#globalsteps + 1] = fn end,
	log = function(_, text) logs[#logs + 1] = text end,
}
local profile = dofile("profile.lua")
assert(profile.enabled())
assert(#globalsteps == 1, "the log timer is the only globalstep, and is not timed")

-- A chain like init.lua's: vanilla inside, each module wrapping the last.
local def = {
	do_custom = function() now = now + 100 return "vanilla" end,
	on_step = function(self, dtime) now = now + 40 local r = self.def.do_custom(self, dtime) now = now + 10 return r end,
}
profile.mark(def, "vanilla")
local inner = def.do_custom
def.do_custom = function(self, dtime)
	now = now + 20
	local r = inner(self, dtime)
	now = now + 5
	return r
end
profile.mark(def, "farmer")
profile.mark(def, "unchanged")

local self = {def = def}
for _ = 1, 4 do assert(def.on_step(self, 0.1) == "vanilla", "return values pass through") end

local snap = profile.snapshot()
local by = {}
for _, e in ipairs(snap.entries) do by[e.name] = e end
assert(by["do_custom:vanilla"].time == 400 and by["do_custom:vanilla"].calls == 4)
assert(by["do_custom:farmer"].time == 100, "farmer's own time, without vanilla's")
assert(by["on_step:vanilla"].time == 200, "mcl_mobs's step without the do_custom chain")
assert(not by["do_custom:unchanged"], "an install that changed nothing gets no timer")
assert(snap.total == 700 and snap.entries[1].name == "do_custom:vanilla")

-- get_staticdata: timed, with the size of what it saves.
def.get_staticdata = function() now = now + 7 return string.rep("x", 30) end
profile.wrap_staticdata(def)
def.get_staticdata({})
def.get_staticdata({})
snap = profile.snapshot()
assert(snap.staticdata.calls == 2 and snap.staticdata.bytes == 60 and snap.staticdata.max == 30)

-- The chat command reports, and resets.
local ok, text = commands.living_villages_profile.func("admin", "")
assert(ok and text:find("do_custom:farmer", 1, true) and text:find("staticdata: 2 saves", 1, true))
commands.living_villages_profile.func("admin", "reset")
assert(#profile.snapshot().entries == 0)

-- The log line comes every 10 s and starts the window over.
def.on_step(self, 0.1)
globalsteps[1](6)
local before = #logs
globalsteps[1](5)
assert(#logs == before + 1 and logs[#logs]:find("do_custom:vanilla=", 1, true), logs[#logs])
assert(#profile.snapshot().entries == 0)

print("profile tests passed")
