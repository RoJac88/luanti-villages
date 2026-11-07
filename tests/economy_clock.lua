-- Run with: lua tests/economy_clock.lua
local now = 1000
local settings = {}
minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	settings = {
		get_bool = function(_, name, default)
			if settings[name] == nil then return default end
			return settings[name]
		end,
	},
}
local clock = dofile("economy_clock.lua")

-- Active: the first stamp starts the clock, later ones add the time between them.
local v = {}
assert(clock.advance(v, now, true) == 0 and v._villages_econ_stamp == 1000)
now = 1005
assert(clock.advance(v, now, true) == 0, "no stamp before STAMP_SECONDS")
assert(v._villages_econ_stamp == 1000)
now = 1010
assert(clock.advance(v, now, true) == 10)
now = 1040
assert(clock.advance(v, now, true) == 40, "a late stamp adds all the time since the last")

-- Inactive (suspended, no player in range): the clock stops and the gap is not added.
now = 1050
assert(clock.advance(v, now, false) == 40 and v._villages_econ_stamp == nil)
now = 1500
assert(clock.advance(v, now, true) == 40, "starts again from now")
now = 1510
assert(clock.advance(v, now, true) == 50)

-- Unloaded: the saved stamp is far behind, so the gap is skipped.
now = 1510 + clock.AWAY_GAP
assert(clock.advance(v, now, true) == 50 and v._villages_econ_stamp == now)
now = now + 10
assert(clock.advance(v, now, true) == 60)

-- A stamp from the future (a world's time moved back) is not trusted.
v._villages_econ_stamp = now + 500
assert(clock.advance(v, now, true) == 60 and v._villages_econ_stamp == now)

-- Asking mcl_mobs when the caller does not say.
local in_range = true
local w = {player_in_active_range = function() return in_range end}
clock.advance(w, now)
now = now + 10
assert(clock.advance(w, now) == 10)
in_range = false
now = now + 10
assert(clock.advance(w, now) == 10 and w._villages_econ_stamp == nil)

-- install wraps do_custom outermost and passes its result through; off, it does nothing.
local calls = 0
local def = {do_custom = function() calls = calls + 1 return false end}
clock.install(def)
local x = {}
assert(def.do_custom(x, 0.1) == false and calls == 1 and x._villages_econ_stamp == now)
settings.living_villages_economy = false
local plain = function() end
local def2 = {do_custom = plain}
clock.install(def2)
assert(def2.do_custom == plain)

print("economy_clock.lua: ok")
