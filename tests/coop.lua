-- Run with: lua tests/coop.lua
local now = 1000
local time = 9000 / 24000
local logs, objects, nodes, thrown = {}, {}, {}, {}
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	direction = function(a, b) return {x = b.x - a.x, y = b.y - a.y, z = b.z - a.z} end,
	round = function(a) return {x = math.floor(a.x + 0.5), y = math.floor(a.y + 0.5), z = math.floor(a.z + 0.5)} end,
}

-- A flat stone floor at y = 0, air above.
for x = -12, 12 do for z = -12, 12 do nodes[key({x = x, y = 0, z = z})] = "mcl_core:stone" end end

local function entity_at(name, pos, fields)
	local mob = {name = name, health = 4}
	for k, v in pairs(fields or {}) do mob[k] = v end
	local object = {pos = vector.new(pos)}
	function object:get_pos() return self.pos end
	function object:set_pos(p) self.pos = vector.new(p) end
	function object:get_luaentity() return mob end
	function object:is_player() return false end
	function object:remove() objects[self] = nil mob.removed = true end
	mob.object = object
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
	registered_nodes = {["mcl_core:stone"] = {walkable = true}, air = {walkable = false}},
	get_node_or_nil = function(p) return {name = nodes[key(p)] or "air"} end,
	get_objects_inside_radius = function(center, radius)
		local list = {}
		for object in pairs(objects) do
			if vector.distance(object:get_pos(), center) <= radius then list[#list + 1] = object end
		end
		return list
	end,
	pos_to_string = function(p) return "(" .. p.x .. "," .. p.y .. "," .. p.z .. ")" end,
}
mcl_mobs = {spawn_child = function(pos, name) return entity_at(name, pos, {child = true}).object end}
mcl_throwing = {throw = function(item, pos, dir, velocity, thrower) thrown[#thrown + 1] = {item = item, pos = pos} end}

local coop = dofile("coop.lua")
local possessions = dofile("possessions.lua")
local ledger = dofile("ledger.lua")
local jobsite = {x = 0, y = 1, z = 0}
local function logged(text)
	for _, line in ipairs(logs) do if line:find(text, 1, true) then return true end end
	return false
end
local function tick(v)
	now = now + 11
	coop.step(v, now)
end

local butcher = {_id = "butcher1", _profession = "butcher", _jobsite = jobsite, _villages_food = 12,
	object = {get_pos = function() return {x = 1, y = 1, z = 1} end}}

-- It is never given chickens: no flock, nothing near, nothing made.
tick(butcher)
assert(#coop.scan(butcher, jobsite) == 0 and possessions.count(butcher, coop.FEATHER) == 0, "no chickens of its own")

-- It wants wheat seeds to breed them; the keeper does not.
assert(possessions.assess(butcher).needs[coop.SEEDS] == coop.COOP_SEEDS)
assert(not possessions.assess({_id = "k", _profession = "butcher", _villages_keeper = true, _jobsite = jobsite,
	_villages_food = 12}).needs[coop.SEEDS])

-- Eggs it holds: thrown near the jobsite while its flock is under MIN_FLOCK, one a THROW_SECONDS.
possessions.add(butcher, coop.EGG, 3)
tick(butcher)
assert(#thrown == 1 and thrown[1].item == coop.EGG and possessions.count(butcher, coop.EGG) == 2, "one egg thrown")
tick(butcher)
assert(#thrown == 1, "not again so soon")
now = now + coop.THROW_SECONDS
tick(butcher)
assert(#thrown == 2)

-- A chick that hatched near, and a chicken lured near, join it; a third does not (MIN_FLOCK),
-- nor one far off.
local chick = entity_at(coop.CHICKEN, {x = 2, y = 1, z = 2}, {child = true})
local hen = entity_at(coop.CHICKEN, {x = -2, y = 1, z = 2})
local far = entity_at(coop.CHICKEN, {x = 40, y = 1, z = 0})
tick(butcher)
local third = entity_at(coop.CHICKEN, {x = -3, y = 1, z = -2})
tick(butcher)
assert(chick._villages_coop == "butcher1" and hen._villages_coop == "butcher1", "the first two stay")
assert(not third._villages_coop and not far._villages_coop, "no more past MIN_FLOCK")
assert(logged("coop: butcher butche took on a chick"))
-- With a flock of two it throws no more eggs.
local before = #thrown
now = now + coop.THROW_SECONDS
tick(butcher)
assert(#thrown == before, "a flock: no more eggs thrown")

-- It picks up the eggs its hens lay near, up to EGG_KEEP.
local egg = entity_at("__builtin:item", {x = 3, y = 1, z = 0}, {itemstring = coop.EGG})
tick(butcher)
assert(egg.removed and possessions.count(butcher, coop.EGG) == 2, "picked up")
assert(logged("picked up 1 egg(s)"))

-- A hen that strays past the leash with no player near is set back.
hen.object:set_pos({x = 0, y = 1, z = 30})
tick(butcher)
assert(vector.distance(hen.object:get_pos(), jobsite) <= 10, "set back by the job block")

-- Tending: a feather a grown hen, and with two adults and seeds a chick is bred.
chick.child = nil
possessions.add(butcher, coop.SEEDS, 4)
now = now + coop.TEND_SECONDS
tick(butcher)
assert(possessions.count(butcher, coop.FEATHER) == 2, "a feather a hen")
assert(possessions.count(butcher, coop.SEEDS) == 2 and logged("bred a chick on 2 wheat seeds"))
assert(#coop.scan(butcher, jobsite) == 3)

-- Past COOP_SIZE adults it slaughters one: a raw chicken and some feathers.
for i = 1, 3 do entity_at(coop.CHICKEN, {x = i, y = 1, z = -3}, {_villages_coop = "butcher1"}) end
local feathers = possessions.count(butcher, coop.FEATHER)
now = now + coop.TEND_SECONDS
tick(butcher)
assert(logged("slaughtered a chicken for 1 chicken"))
assert(possessions.count(butcher, coop.RAW_CHICKEN) == 1 and possessions.count(butcher, coop.FEATHER) >= feathers + 5)

-- Not outside the work stage.
time = 0.9
local eggs = possessions.count(butcher, coop.EGG)
entity_at("__builtin:item", {x = 3, y = 1, z = 1}, {itemstring = coop.EGG})
tick(butcher)
assert(possessions.count(butcher, coop.EGG) == eggs, "asleep, no eggs picked up")

-- Feathers in its stash count toward FEATHER_KEEP (ticket 32): leaving feathers there made
-- room for more, and a butcher piled up 339.
do
	local stash = {x = 5, y = 1, z = 5}
	nodes[key(stash)] = "mcl_chests:chest"
	local stack = {is_empty = function() return false end, get_name = function() return coop.FEATHER end,
		get_count = function() return coop.FEATHER_KEEP end}
	minetest.get_meta = function()
		return {get_string = function() return butcher._id end,
			get_inventory = function() return {get_list = function() return {stack} end} end}
	end
	butcher._villages_stash = stash
	logs = {}
	coop.tend(butcher, jobsite, coop.scan(butcher, jobsite))
	assert(not logged("collected"), "a full stash: no feathers collected")
	butcher._villages_stash = nil
end

-- Feathers and chicken are its own make: it sells them, never buys them.
assert(ledger.outputs("butcher")[coop.FEATHER] and ledger.outputs("butcher")[coop.RAW_CHICKEN])
assert(not coop.keeps({_id = "k", _profession = "butcher", _villages_keeper = true, _jobsite = jobsite}))

print("coop.lua: ok")
