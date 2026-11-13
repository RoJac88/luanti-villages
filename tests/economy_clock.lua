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

-- A night skipped while active (time of day set forward, game time running on) counts:
-- the calendar ran 0.425 of a day (10200 ticks) in 10 s, so the clock adds that day's
-- share, 510 s at time_speed 72's 1200 s day. Not when it was away across it, and never
-- more than a day for one jump.
do
	local day, tod = 10, 19200 / 24000
	minetest.get_day_count = function() return day end
	minetest.get_timeofday = function() return tod end
	local n = {}
	now = 5000
	clock.advance(n, now, true)
	now, tod = now + 10, tod + 10 / 1200
	assert(math.abs(clock.advance(n, now, true) - 10) < 1e-6, "an ordinary stamp adds game time only")
	day, tod, now = 11, 5400 / 24000, now + 10
	local after = clock.advance(n, now, true)
	assert(math.abs(after - (20 + (0.425 - 10 / 1200) * 1200 - 10)) < 1e-6, after)
	-- Away across the night: nothing.
	local away = {}
	day, tod, now = 20, 19200 / 24000, now + 1000
	clock.advance(away, now, true)
	day, tod, now = 21, 5400 / 24000, now + clock.AWAY_GAP
	assert(clock.advance(away, now, true) == 0)
	-- No player near when it was skipped: nothing.
	local idle = {}
	day, tod, now = 30, 19200 / 24000, now + 1000
	clock.advance(idle, now, true)
	now = now + 10
	clock.advance(idle, now, false)
	day, tod, now = 31, 5400 / 24000, now + 10
	assert(clock.advance(idle, now, true) == 0)
	-- A jump of days (/time) counts one day at most.
	local jumped = {}
	day, tod, now = 40, 0.5, now + 1000
	clock.advance(jumped, now, true)
	day, now = 45, now + 10
	assert(math.abs(clock.advance(jumped, now, true) - (10 + 1200)) < 1e-6)
	-- Time set back counts game time only.
	day, now = 41, now + 10
	assert(math.abs(clock.advance(jumped, now, true) - (20 + 1200)) < 1e-6)
	minetest.get_day_count, minetest.get_timeofday = nil, nil
end

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
