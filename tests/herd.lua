-- Run with: lua tests/herd.lua
local now = 1000
local logs, objects, nodes = {}, {}, {}
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	round = function(a) return {x = math.floor(a.x + 0.5), y = math.floor(a.y + 0.5), z = math.floor(a.z + 0.5)} end,
}

-- A flat stone floor at y = 0, air above.
for x = -10, 10 do for z = -10, 10 do nodes[key({x = x, y = 0, z = z})] = "mcl_core:stone" end end

local function cow_at(pos, fields)
	local cow = {name = "mobs_mc:cow", health = 10}
	for k, v in pairs(fields or {}) do cow[k] = v end
	local object = {pos = vector.new(pos)}
	function object:get_pos() return self.pos end
	function object:set_pos(p) self.pos = vector.new(p) end
	function object:get_luaentity() return cow end
	function object:is_player() return false end
	function object:remove() objects[self] = nil cow.removed = true end
	cow.object = object
	objects[object] = true
	return cow
end

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	get_timeofday = function() return 0.5 end,
	settings = {get = function() return nil end, get_bool = function(_, _, default) return default end},
	log = function(_, message) logs[#logs + 1] = message end,
	registered_items = {},
	registered_nodes = {["mcl_core:stone"] = {walkable = true}, air = {walkable = false}},
	get_node_or_nil = function(p) return {name = nodes[key(p)] or "air"} end,
	get_objects_inside_radius = function(center, radius)
		local list = {}
		for object in pairs(objects) do
			if vector.distance(object:get_pos(), center) <= radius then list[#list + 1] = object end
		end
		return list
	end,
	add_entity = function(pos) return cow_at(pos).object end,
	pos_to_string = function(p) return "(" .. p.x .. "," .. p.y .. "," .. p.z .. ")" end,
}
mcl_mobs = {spawn_child = function(pos) return cow_at(pos, {child = true}).object end}

local herd = dofile("herd.lua")
local possessions = dofile("possessions.lua")
local BEEF, LEATHER, WHEAT = "mcl_mobitems:beef", "mcl_mobitems:leather", "mcl_farming:wheat_item"
local jobsite = {x = 0, y = 1, z = 0}
local function logged(text)
	for _, line in ipairs(logs) do if line:find(text, 1, true) then return true end end
	return false
end

local worker = {_id = "leather1", _profession = "leatherworker", _jobsite = jobsite, _villages_food = 12,
	object = {get_pos = function() return jobsite end}}

-- A spot to set a cow on: on the floor, two air above, beside the jobsite.
local spot = herd.spot(jobsite)
assert(spot and spot.y == 1 and math.max(math.abs(spot.x), math.abs(spot.z)) == 2)

-- No cow near: the herd is seeded once.
local list, wild = herd.scan(worker, jobsite)
assert(#list == 0 and #wild == 0)
list = herd.gather(worker, jobsite, list, wild)
assert(#list == herd.SEED_COWS and list[1]._villages_herder == "leather1" and logged("started a herd of 2"))
assert(worker._villages_herd_seeded)
-- A wild cow near is taken on; one far off, or another's, is not.
local stray = cow_at({x = 5, y = 1, z = 0})
local far = cow_at({x = 30, y = 1, z = 0})
local others = cow_at({x = 3, y = 1, z = 3}, {_villages_herder = "someone"})
list, wild = herd.scan(worker, jobsite)
assert(#list == 2 and #wild == 1 and wild[1] == stray)
list = herd.gather(worker, jobsite, list, wild)
assert(#list == 3 and stray._villages_herder == "leather1" and not far._villages_herder)
assert(others._villages_herder == "someone")

-- Breeding takes two wheat and makes a calf of the herd.
assert(herd.tend(worker, jobsite, list) == nil, "no wheat, no calf")
possessions.add(worker, WHEAT, 4)
assert(herd.tend(worker, jobsite, list) == "bred" and possessions.count(worker, WHEAT) == 2)
list = herd.scan(worker, jobsite)
assert(#list == 4)
-- A calf grown: four adults, the herd's size. One more calf, then no room.
for _, cow in ipairs(list) do cow.child = nil end
assert(herd.tend(worker, jobsite, list) == "bred")
list = herd.scan(worker, jobsite)
assert(#list == 5 and herd.tend(worker, jobsite, list) == nil, "a full herd and a calf: no more")
-- Grown past the herd size: one is slaughtered for its beef and leather.
for _, cow in ipairs(list) do cow.child = nil end
assert(herd.tend(worker, jobsite, list) == "slaughtered")
assert(possessions.count(worker, BEEF) >= 1 and possessions.count(worker, LEATHER) >= 0)
assert(#herd.scan(worker, jobsite) == herd.HERD_SIZE and logged("slaughtered a cow for"))
-- The drops' ranges.
local lo = cow_at({x = 2, y = 1, z = 2}, {_villages_herder = "leather1"})
local beef, leather = herd.slaughter(worker, lo, function(a) return a end)
assert(beef == 1 and leather == 0 and lo.removed)

-- A leatherworker wants wheat for its herd.
local view = possessions.assess({_id = "leather2", _profession = "leatherworker", _villages_food = 12})
assert((view.targets[WHEAT] or 0) >= herd.HERD_WHEAT)

assert(herd.status(worker):find("cows", 1, true) and herd.status({_profession = "farmer"}) == "not a leatherworker")

print("herd.lua: ok")
