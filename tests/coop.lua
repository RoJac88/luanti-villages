-- Run with: lua tests/coop.lua
local now = 1000
local time = 0.5
local logs, objects = {}, {}

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	round = function(a) return {x = math.floor(a.x + 0.5), y = math.floor(a.y + 0.5), z = math.floor(a.z + 0.5)} end,
}

local function mob_at(name, pos, fields)
	local mob = {name = name}
	for k, v in pairs(fields or {}) do mob[k] = v end
	local object = {pos = vector.new(pos)}
	function object:get_pos() return self.pos end
	function object:get_luaentity() return mob end
	objects[object] = true
	return mob
end

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	get_timeofday = function() return time end,
	settings = {get = function() return nil end, get_bool = function(_, _, default) return default end},
	log = function(_, message) logs[#logs + 1] = message end,
	registered_items = {},
	registered_nodes = {},
	get_objects_inside_radius = function(center, radius)
		local list = {}
		for object in pairs(objects) do
			if vector.distance(object:get_pos(), center) <= radius then list[#list + 1] = object end
		end
		return list
	end,
}

local coop = dofile("coop.lua")
local possessions = dofile("possessions.lua")
local ledger = dofile("ledger.lua")
local FEATHER = coop.FEATHER
local jobsite = {x = 0, y = 1, z = 0}

-- Three chickens by the smoker, a chick, one far off and a cow: three count.
for i = 1, 3 do mob_at(coop.CHICKEN, {x = i, y = 1, z = 2}) end
mob_at(coop.CHICKEN, {x = 0, y = 1, z = 3}, {child = true})
mob_at(coop.CHICKEN, {x = 40, y = 1, z = 0})
mob_at("mobs_mc:cow", {x = 1, y = 1, z = 1})
assert(coop.count(jobsite) == 3)

-- In its work stage, a feather a chicken, once every COLLECT_SECONDS.
local butcher = {_id = "butcher1", _profession = "butcher", _jobsite = jobsite, _villages_food = 12}
time = 9000 / 24000
coop.step(butcher, now)
assert(possessions.count(butcher, FEATHER) == 3, possessions.count(butcher, FEATHER))
assert(logs[#logs]:find("coop: butcher butche collected 3 feather%(s%) from 3 chicken%(s%)"), logs[#logs])
coop.step(butcher, now + 20)
assert(possessions.count(butcher, FEATHER) == 3, "not again so soon")
coop.step(butcher, now + coop.COLLECT_SECONDS + 1)
assert(possessions.count(butcher, FEATHER) == 6)

-- Never past KEEP.
possessions.add(butcher, FEATHER, coop.KEEP - 7)
now = now + 10 * coop.COLLECT_SECONDS
coop.step(butcher, now)
assert(possessions.count(butcher, FEATHER) == coop.KEEP)

-- Not outside the work stage, not the keeper, not a child, not without a jobsite.
local function none(fields)
	local v = {_id = "x" .. tostring(math.random(1e6)), _profession = "butcher", _jobsite = jobsite, _villages_food = 12}
	for k, value in pairs(fields) do v[k] = value end
	coop.step(v, now)
	return possessions.count(v, FEATHER) == 0
end
assert(none({_villages_keeper = true}) and none({child = true}) and none({_jobsite = false}))
time = 0.9
assert(none({}), "asleep, no feathers")

-- Feathers are its own make: it sells them, never buys them.
assert(ledger.outputs("butcher")[FEATHER])

print("coop.lua: ok")
