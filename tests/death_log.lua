-- death_log.lua: the context on a villager's death line.
local day = 7
minetest = {
	get_modpath = function() return "." end,
	get_day_count = function() return day end,
	get_gametime = function() return 0 end,
	get_timeofday = function() return 0.5 end,
	settings = {get = function() return nil end, get_bool = function() return nil end},
	log = function() end,
	register_on_mods_loaded = function() end,
	get_node_or_nil = function() return nil end,
}
core = minetest
vector = vector or {}
local death_log = dofile("death_log.lua")

local v = {_id = "fred", _profession = "unemployed", state = "walk",
	_villages_labour = {day = day, activity = "woodcutter"},
	_villages_labour_target = {x = -108, y = 5, z = -30},
	_villages_grove = {{x = -100, y = 5, z = -30}, {x = -108, y = 5, z = -30}},
	_villages_food = 0}
local line = death_log.context(v, {x = -107.6, y = 4.5, z = -29.9})
assert(line:find("profession unemployed", 1, true), line)
assert(line:find("labour woodcutter", 1, true), line)
assert(line:find("heading for (-108,5,-30)", 1, true), line)
assert(line:find("on its grove spot (-108,5,-30)", 1, true), line)
assert(line:find("food 0.0", 1, true), line)
assert(line:find("state walk", 1, true), line)

-- Yesterday's labour is not today's; away from its grove says nothing of one.
v._villages_labour.day = day - 1
line = death_log.context(v, {x = 0, y = 5, z = 0})
assert(not line:find("labour", 1, true) and not line:find("grove", 1, true), line)

print("death_log ok")
