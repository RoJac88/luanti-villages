-- Run with: lua tests/labour.lua
local now, day, time = 1000, 5, 9000 / 24000
local settings = {}
local nodes, objects, logs = {}, {}, {}
local player_leaves = {}
local metas = {}
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
local function parse(k)
	local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
	return {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
end

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	round = function(a) return {x = math.floor(a.x + 0.5), y = math.floor(a.y + 0.5), z = math.floor(a.z + 0.5)} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	equals = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end,
}

local GROUPS = {
	["mcl_core:dirt_with_grass"] = {soil_sapling = 2},
	["mcl_core:grass_path"] = {path = 1},
	["mcl_flowers:tallgrass"] = {plant = 1},
	["mcl_core:sapling"] = {plant = 1},
	["mcl_core:acaciasapling"] = {plant = 1},
	["mcl_core:lava_flowing"] = {lava = 3},
	["mcl_core:lava_source"] = {lava = 3},
	["mcl_core:water_source"] = {water = 3},
	["mcl_core:water_flowing"] = {water = 3},
	["mcl_core:tree"] = {tree = 1},
}

-- "name count wear"; a stack whose text is in `named` has that metadata.
local named = {}
ItemStack = function(text)
	local name, count, wear = text:match("^(%S+)%s*(%d*)%s*(%d*)")
	return {get_name = function() return name end, get_count = function() return tonumber(count) or 1 end,
		get_wear = function() return tonumber(wear) or 0 end,
		get_meta = function() return {to_table = function() return {fields = named[text] or {}} end} end}
end

local function name_at(pos) return nodes[key(pos)] or "air" end
local function matches(name, wanted)
	for _, want in ipairs(wanted) do
		local group = want:match("^group:(.*)")
		if want == name or (group and GROUPS[name] and GROUPS[name][group]) then return true end
	end
	return false
end

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	get_day_count = function() return day end,
	get_timeofday = function() return time end,
	get_item_group = function(name, group) return GROUPS[name] and GROUPS[name][group] or 0 end,
	registered_nodes = {},
	get_meta = function(pos)
		return {
			get_int = function(_, field)
				if field == "player_leaves" then return player_leaves[key(pos)] or 0 end
				return metas[key(pos) .. field] or 0
			end,
			set_int = function(_, field, value) metas[key(pos) .. field] = value end,
		}
	end,
	settings = {
		get = function(_, name) return settings[name] end,
		get_bool = function(_, name, default)
			if settings[name] == nil then return default end
			return settings[name]
		end,
	},
	log = function(_, message) logs[#logs + 1] = message end,
	pos_to_string = function(p) return "(" .. key(p) .. ")" end,
	get_node_or_nil = function(pos) return {name = name_at(pos)} end,
	swap_node = function(pos, node) nodes[key(pos)] = node.name end,
	set_node = function(pos, node) nodes[key(pos)] = node.name ~= "air" and node.name or nil end,
	remove_node = function(pos) nodes[key(pos)] = nil end,
	-- Every cell of the box, air included, as the engine counts it.
	find_nodes_in_area = function(minp, maxp, names)
		local found = {}
		for x = minp.x, maxp.x do
			for y = minp.y, maxp.y do
				for z = minp.z, maxp.z do
					local p = {x = x, y = y, z = z}
					if matches(name_at(p), names) then found[#found + 1] = p end
				end
			end
		end
		return found
	end,
	find_nodes_in_area_under_air = function(minp, maxp, names)
		local found = {}
		for k, name in pairs(nodes) do
			local p = parse(k)
			if matches(name, names) and p.x >= minp.x and p.x <= maxp.x and p.y >= minp.y and p.y <= maxp.y
				and p.z >= minp.z and p.z <= maxp.z and name_at({x = p.x, y = p.y + 1, z = p.z}) == "air" then
				found[#found + 1] = p
			end
		end
		table.sort(found, function(a, b) return key(a) < key(b) end)
		return found
	end,
	get_objects_inside_radius = function(pos, radius)
		local found = {}
		for _, object in ipairs(objects) do
			if not object.removed and vector.distance(object:get_pos(), pos) <= radius then found[#found + 1] = object end
		end
		return found
	end,
}

local labour = dofile("labour.lua")
local possessions = dofile("possessions.lua")

local function count(v, item) return possessions.count(v, item) end
local function villager(fields)
	local pos = {x = 0, y = 1, z = 0}
	local v = {_id = "nina", _profession = "nitwit", _bed = {x = 0, y = 1, z = 0}, state = "stand", walks = {}}
	for k, value in pairs(fields or {}) do v[k] = value end
	v.object = {get_pos = function() return pos end, set_velocity = function() end,
		set_pos = function(_, p) pos = {x = p.x, y = p.y, z = p.z} end}
	v.move_to = function(p) pos = {x = p.x, y = p.y, z = p.z} end
	v.gopath = function(self, target, arrived)
		self.walks[#self.walks + 1] = target
		self.arrive = function()
			pos = {x = target.x, y = target.y, z = target.z + 1}
			arrived(self)
		end
		return true
	end
	return v
end

-- Who works: nitwits, and the unemployed with no jobsite; no child, no one with a job.
assert(labour.eligible(villager()))
assert(labour.eligible(villager({_profession = "unemployed"})))
assert(not labour.eligible(villager({_profession = "unemployed", _jobsite = {x = 1, y = 1, z = 1}})))
assert(not labour.eligible(villager({child = true})))
assert(not labour.eligible(villager({_profession = "farmer"})))
-- A crafter with nothing to make labours for the day, and is not called back to its
-- jobsite (ticket 19b); one with something to make, or on another day, works its trade.
do
	local jobsite = {x = 3, y = 1, z = 0}
	local smithy = villager({_id = "tilly", _profession = "tool_smith", _jobsite = jobsite})
	assert(labour.eligible(smithy) and smithy._villages_idle.idle == true)
	assert(labour.activity_override(smithy, "work") == "putter")
	assert(labour.activity_override(smithy, "home") == nil)
	day = day + 1
	assert(labour.activity_override(smithy, "work") == nil, "only the day it was idle")
	possessions.add(smithy, "mcl_core:cobble", 3)
	possessions.add(smithy, "mcl_core:stick", 2)
	assert(not labour.eligible(smithy), "with goods to craft it works its trade")
	day = day - 1
	assert(labour.activity_override(villager({_jobsite = jobsite}), "work") == nil)
end

-- The choice: the best heard income, yesterday's counted a little over; at random
-- with no prices heard; never an activity with no site.
local both = {forager = true, woodcutter = true}
local function asks(item, price) return {item = item, kind = "needs", price = price, who = "x", heard = now, hops = 1} end
assert(labour.choose({asks("mcl_core:tree", 0.5)}, both, nil, 0) == "woodcutter")
assert(labour.choose({asks("mcl_farming:sweet_berry", 0.5)}, both, nil, 0) == "forager")
assert(labour.choose({asks("mcl_core:tree", 0.5)}, {forager = true}, nil, 0) == "forager", "no grove, no wood")
assert(labour.choose({}, both, nil, 0) == "forager" and labour.choose({}, both, nil, 0.99) == "woodcutter")
assert(labour.choose({}, {}, nil, 0) == nil)
-- An offer ("has") is no asking price.
assert(labour.choose({{item = "mcl_core:tree", kind = "has", price = 0.5, who = "x", heard = now, hops = 1}}, both, nil, 0) == "forager")
-- Close incomes: yesterday's holds; a clear gap moves it.
local close = {asks("mcl_core:tree", 0.11), asks("mcl_farming:sweet_berry", 0.2)}
assert(labour.choose(close, both, "woodcutter", 0) == "woodcutter" and labour.choose(close, both, nil, 0) == "forager")

-- The share choosing wood falls after wood's price does.
local function wood_share(log_price)
	local wood = 0
	for i = 1, 20 do
		local heard = {asks("mcl_core:tree", log_price * (0.8 + i / 50)), asks("mcl_farming:sweet_berry", 0.2)}
		if labour.choose(heard, both, i % 2 == 0 and "woodcutter" or "forager", (i - 1) / 20) == "woodcutter" then
			wood = wood + 1
		end
	end
	return wood
end
local before, after = wood_share(0.5), wood_share(0.05)
assert(before == 20 and after == 0, before .. " then " .. after)

-- Cane is worth the paper it makes: a need for paper alone sends it foraging, and
-- above a little wood (ColonyFood, day 108: two wanted paper, no one asked for cane).
assert(labour.prices({asks("mcl_core:paper", 40)})["mcl_core:reeds"] == 40, "three cane, three paper")
assert(labour.prices({asks("mcl_core:paper", 40), asks("mcl_core:reeds", 55)})["mcl_core:reeds"] == 55,
	"its own price when higher")
assert(labour.choose({asks("mcl_core:paper", 40), asks("mcl_core:acaciatree", 2)}, both, "woodcutter", 0)
	== "forager")
-- A pile it has not sold is worth less, and nothing at KEEP_GATHERED: seventy logs no one
-- bought turn it to other work.
local pile = {["mcl_core:acaciatree"] = 70}
assert(labour.unsold_share(0, 32) == 1 and labour.unsold_share(16, 32) == 0.5 and labour.unsold_share(70, 32) == 0)
assert(labour.incomes({asks("mcl_core:acaciatree", 2)}, 0, nil, nil, pile).woodcutter == 0)
assert(labour.choose({asks("mcl_core:acaciatree", 2)}, both, "woodcutter", 0) == "woodcutter")
assert(labour.choose({asks("mcl_core:acaciatree", 2), asks("mcl_farming:sweet_berry", 0.01)}, both, "woodcutter", 0,
	0, nil, nil, pile) == "forager")

-- Foraging: ripe berries, leaving the bush to grow back; cane above its bottom block;
-- apples on the ground.
local nina = villager()
nodes[key({x = 3, y = 1, z = 0})] = "mcl_farming:sweet_berry_bush_3"
nodes[key({x = 4, y = 1, z = 0})] = "mcl_farming:sweet_berry_bush_1"
for y = 1, 3 do nodes[key({x = 6, y = y, z = 0})] = "mcl_core:reeds" end
nodes[key({x = 7, y = 1, z = 0})] = "mcl_core:reeds"
local apple = {removed = false, get_pos = function() return {x = 9, y = 1, z = 0} end,
	get_luaentity = function() return {name = "__builtin:item", itemstring = "mcl_core:apple 2"} end}
apple.remove = function(self) self.removed = true end
objects[#objects + 1] = apple
local targets = labour.forage_targets(nina)
assert(#targets == 3, "the ripe bush, the cane top and the apple; not the picked bush or a lone cane")
for _, target in ipairs(targets) do labour.forage(nina, target) end
assert(nodes[key({x = 3, y = 1, z = 0})] == "mcl_farming:sweet_berry_bush_1")
local berries = count(nina, "mcl_farming:sweet_berry")
assert(berries >= 2 and berries <= 3)
assert(count(nina, "mcl_core:reeds") == 2 and nodes[key({x = 6, y = 1, z = 0})] == "mcl_core:reeds"
	and not nodes[key({x = 6, y = 2, z = 0})], "the bottom block stays")
assert(count(nina, "mcl_core:apple") == 2 and apple.removed)
-- A crafter idle for the day forages nearer its bed than a nitwit or the unemployed
-- (ColonyFood, 2026-11-16: a weapon smith went out of the loaded area for flowers).
do
	assert(labour.EMPLOYED_FORAGE_RADIUS < labour.FORAGE_RADIUS)
	local far = {x = labour.EMPLOYED_FORAGE_RADIUS + 8, y = 1, z = 0}
	nodes[key(far)] = "mcl_farming:sweet_berry_bush_3"
	local function sees_far(v)
		for _, target in ipairs(labour.forage_targets(v)) do
			if target.pos.x == far.x and target.pos.z == far.z then return true end
		end
		return false
	end
	assert(labour.forage_radius(villager()) == labour.FORAGE_RADIUS)
	assert(sees_far(villager()), "a nitwit roams")
	assert(sees_far(villager({_profession = "unemployed"})), "so does one with no job block")
	local smith = villager({_profession = "weapon_smith", _jobsite = {x = 2, y = 1, z = 2}})
	assert(labour.forage_radius(smith) == labour.EMPLOYED_FORAGE_RADIUS)
	assert(not sees_far(smith), "an idle crafter stays near home")
	nodes[key(far)] = nil
end
-- Dropped goods: anything priced, plain, picked up first, since it would despawn; dirt,
-- a worn tool and a named item are left.
do
	local function drop(x, text)
		local object = {removed = false, get_pos = function() return {x = x, y = 1, z = 5} end,
			get_luaentity = function() return {name = "__builtin:item", itemstring = text} end}
		object.remove = function(self) self.removed = true end
		objects[#objects + 1] = object
		return object
	end
	named["mcl_core:emerald 2"] = {description = "Lucky"}
	local flesh = drop(20, "mcl_mobitems:rotten_flesh 3")
	-- A skeleton's bone is priced, so picked up too (19h: it sells as bone meal or dye).
	assert(labour.worth_picking(ItemStack("mcl_mobitems:bone 2")), "a bone")
	local dirt = drop(21, "mcl_core:dirt 5")
	local worn = drop(22, "mcl_tools:pick_stone 1 300")
	local lucky = drop(23, "mcl_core:emerald 2")
	local finds = labour.forage_targets(villager({_id = "pip"}))
	local pickups = {}
	for _, target in ipairs(finds) do
		if target.kind == "pickup" then pickups[#pickups + 1] = target end
	end
	assert(#pickups == 1 and pickups[1].object == flesh, "only the rotten flesh")
	-- It goes to the drop first, past the nearer berries.
	nodes[key({x = 1, y = 1, z = 0})] = "mcl_farming:sweet_berry_bush_3"
	local pip = villager({_id = "pip"})
	pip._villages_labour = {day = day, activity = "forager"}
	labour.step(pip, now + 5000)
	assert(#pip.walks == 1 and pip.walks[1].x == 20, "to the drop")
	pip.arrive()
	assert(count(pip, "mcl_mobitems:rotten_flesh") == 3 and flesh.removed)
	assert(not pip._villages_gather_record or not pip._villages_gather_record.forager
		or pip._villages_gather_record.forager.made == 0, "no gathering")
	assert(not dirt.removed and not worn.removed and not lucky.removed)
	nodes[key({x = 1, y = 1, z = 0})] = nil
	for _, object in ipairs({dirt, worn, lucky}) do object.removed = true end
	named["mcl_core:emerald 2"] = nil
end
-- A cane top stands in the air: it is reached from the ground beside the column's foot
-- (ColonyFood, 2026-11-13: a forager walked to the top itself and found no way).
do
	minetest.registered_nodes.air = {walkable = false}
	minetest.registered_nodes["mcl_core:water_source"] = {walkable = false}
	for y = 1, 3 do nodes[key({x = 300, y = y, z = 0})] = "mcl_core:reeds" end
	nodes[key({x = 300, y = 0, z = 0})] = "mcl_core:dirt_with_grass"
	nodes[key({x = 301, y = 0, z = 0})] = "mcl_core:water_source"
	nodes[key({x = 299, y = 0, z = 0})] = "mcl_core:dirt_with_grass"
	local spot = labour.beside_cane({x = 300, y = 3, z = 0})
	assert(spot and spot.x == 299 and spot.y == 1 and spot.z == 0, "on the ground beside its foot, not over the water")
	-- Another column beside it is no place to stand.
	minetest.registered_nodes["mcl_core:reeds"] = {walkable = false}
	for y = 1, 2 do nodes[key({x = 299, y = y, z = 0})] = "mcl_core:reeds" end
	nodes[key({x = 300, y = 0, z = 1})] = "mcl_core:dirt_with_grass"
	spot = labour.beside_cane({x = 300, y = 3, z = 0})
	assert(spot and spot.x == 300 and spot.z == 1, "past the next column")
	for y = 1, 2 do nodes[key({x = 299, y = y, z = 0})] = nil end
	nodes[key({x = 300, y = 0, z = 1})] = nil
	minetest.registered_nodes["mcl_core:reeds"] = nil
	-- Ground only a step up: beside the block above the foot.
	nodes[key({x = 299, y = 0, z = 0})] = nil
	nodes[key({x = 299, y = 1, z = 0})] = "mcl_core:dirt_with_grass"
	spot = labour.beside_cane({x = 300, y = 3, z = 0})
	assert(spot and spot.x == 299 and spot.y == 2, "a step up")
	for y = 0, 3 do nodes[key({x = 300, y = y, z = 0})] = nil end
	nodes[key({x = 301, y = 0, z = 0})], nodes[key({x = 299, y = 1, z = 0})] = nil, nil
	minetest.registered_nodes.air, minetest.registered_nodes["mcl_core:water_source"] = nil, nil
end
-- Enough of a good: it leaves the rest.
nodes[key({x = 3, y = 1, z = 0})] = "mcl_farming:sweet_berry_bush_2"
nina._villages_belongings["mcl_farming:sweet_berry"] = labour.KEEP_GATHERED
assert(#labour.forage_targets(nina) == 0)

-- The day: chosen once, by what it has a site for, and worked by walking there.
local fen = villager({_id = "fen"})
nodes[key({x = 3, y = 1, z = 0})] = "mcl_farming:sweet_berry_bush_3"
assert(labour.today(fen) == "forager" and fen._villages_labour.day == day and logs[#logs]:find("works as a forager"))
labour.step(fen, now)
assert(#fen.walks == 1 and fen._villages_labour_target, "walks to the bush")
fen.arrive()
assert(count(fen, "mcl_farming:sweet_berry") >= 2 and not fen._villages_labour_target)
assert(logs[#logs]:find("gathered"))
assert(fen._villages_tally.made["mcl_farming:sweet_berry"] == count(fen, "mcl_farming:sweet_berry"), "in its tally")
-- In reach it picks at once.
nodes[key({x = 3, y = 1, z = 0})] = "mcl_farming:sweet_berry_bush_3"
fen.move_to({x = 3, y = 1, z = 1})
local had = count(fen, "mcl_farming:sweet_berry")
labour.step(fen, now + 10)
assert(count(fen, "mcl_farming:sweet_berry") > had and #fen.walks == 1)
-- A walk that ended short is tried again later.
fen._villages_labour_target = {x = 1, y = 1, z = 1}
labour.step(fen, now + 20)
assert(not fen._villages_labour_target and fen._villages_labour_next == now + 20 + 60)

-- Woodcutting. Open grass all round the bed.
nodes = {}
objects = {}
for x = -24, 32 do for z = -24, 24 do nodes[key({x = x, y = 0, z = z})] = "mcl_core:dirt_with_grass" end end
local wade = villager({_id = "wade"})
-- No sapling and no grove: one from under a wild oak, once a day.
nodes[key({x = 30, y = 1, z = 0})] = "mcl_core:tree"
nodes[key({x = 30, y = 2, z = 0})] = "mcl_core:tree"
nodes[key({x = 30, y = 4, z = 1})] = "mcl_core:leaves"
local job = labour.wood_target(wade)
assert(job and job.kind == "sapling" and job.pos.x == 30)
labour.cut(wade, job)
assert(count(wade, "mcl_core:sapling") == 1 and nodes[key({x = 30, y = 1, z = 0})] == "mcl_core:tree", "the wild tree stands")
-- With a sapling: a grove spot on open grass, GROVE_MIN or more from its bed.
job = labour.wood_target(wade)
assert(job and job.kind == "plant" and vector.distance(job.pos, wade._bed) >= 8)
labour.cut(wade, job)
local spot = wade._villages_grove[1]
assert(spot and nodes[key(spot)] == "mcl_core:sapling" and count(wade, "mcl_core:sapling") == 0)
-- Not beside a path, nor in a cramped spot.
local roadside = {x = 12, y = 1, z = 12}
nodes[key({x = 13, y = 0, z = 12})] = "mcl_core:grass_path"
assert(not labour.grove_spot_ok(wade, roadside))
local cramped = {x = -12, y = 1, z = -12}
nodes[key({x = -11, y = 3, z = -12})] = "mcl_core:stone"
assert(not labour.grove_spot_ok(wade, cramped))
assert(not labour.grove_spot_ok(wade, {x = spot.x + 1, y = spot.y, z = spot.z}), "too near its other tree")
-- The sapling grows: felled, its logs taken, and a sapling planted in its place.
for y = 0, 4 do nodes[key({x = spot.x, y = spot.y + y, z = spot.z})] = "mcl_core:tree" end
nodes[key({x = spot.x + 1, y = spot.y + 3, z = spot.z})] = "mcl_core:tree"
job = labour.wood_target(wade)
assert(job and job.kind == "fell")
labour.cut(wade, job)
assert(count(wade, "mcl_core:tree") == 6 and nodes[key(spot)] == "mcl_core:sapling" and #wade._villages_grove == 1)
-- A grove short of trees gets a spare sapling from the felling, to plant a new spot.
assert(count(wade, "mcl_core:sapling") == 1, "the spare sapling")
assert(not nodes[key({x = spot.x, y = spot.y + 2, z = spot.z})], "trunk gone")
-- A felled tree's own leaves decay, though its grove neighbour stands 5 away; leaves
-- nearer the neighbour, and leaves a player placed, stay.
do
	minetest.registered_nodes["mcl_core:leaves_orphan"] = {}
	local a, b = {x = 200, y = 1, z = 200}, {x = 205, y = 1, z = 200}
	for y = 0, 4 do
		nodes[key({x = a.x, y = a.y + y, z = a.z})] = "mcl_core:tree"
		nodes[key({x = b.x, y = b.y + y, z = b.z})] = "mcl_core:tree"
	end
	local own, shared, near_b, placed = {x = 198, y = 5, z = 200}, {x = 202, y = 5, z = 201}, {x = 203, y = 5, z = 200}, {x = 199, y = 5, z = 201}
	for _, leaf in ipairs({own, shared, near_b, placed}) do nodes[key(leaf)] = "mcl_core:leaves" end
	player_leaves[key(placed)] = 1
	local log, felled = labour.fell(a)
	assert(log == "mcl_core:tree" and felled == 5)
	assert(nodes[key(own)] == "mcl_core:leaves_orphan", "its own leaf decays")
	assert(nodes[key(shared)] == "mcl_core:leaves_orphan", "nearer the felled trunk than the standing one")
	assert(nodes[key(near_b)] == "mcl_core:leaves", "the standing tree keeps its own")
	assert(nodes[key(placed)] == "mcl_core:leaves", "a player's leaves stay")
	assert(nodes[key(b)] == "mcl_core:tree")
	for y = 0, 4 do nodes[key({x = b.x, y = b.y + y, z = b.z})] = nil end
	for _, leaf in ipairs({own, shared, near_b, placed}) do nodes[key(leaf)] = nil end
	minetest.registered_nodes["mcl_core:leaves_orphan"] = nil
end
-- A sapling someone broke: replanted if it has one, else the spot is given up.
nodes[key(spot)] = nil
wade._villages_belongings["mcl_core:sapling"] = nil
job = labour.wood_target(wade)
assert(job and job.kind == "replant")
labour.cut(wade, job)
assert(#wade._villages_grove == 0)

-- A savanna village: acacia, its own sapling back, and the house logs left alone.
nodes = {}
for x = -24, 32 do for z = -24, 24 do nodes[key({x = x, y = 0, z = z})] = "mcl_core:dirt_with_grass" end end
local sal = villager({_id = "sal"})
nodes[key({x = 2, y = 1, z = 2})] = "mcl_core:tree"
assert(labour.wood_target(sal) == nil, "a log in a wall, with no leaves, is no tree")
nodes[key({x = 28, y = 1, z = 0})] = "mcl_core:acaciatree"
nodes[key({x = 29, y = 6, z = 0})] = "mcl_core:acacialeaves"
job = labour.wood_target(sal)
assert(job and job.kind == "sapling" and job.sapling == "mcl_core:acaciasapling")
labour.cut(sal, job)
job = labour.wood_target(sal)
labour.cut(sal, job)
local acacia = sal._villages_grove[1]
assert(nodes[key(acacia)] == "mcl_core:acaciasapling")
for y = 0, 3 do nodes[key({x = acacia.x, y = acacia.y + y, z = acacia.z})] = "mcl_core:acaciatree" end
nodes[key({x = acacia.x + 2, y = acacia.y + 4, z = acacia.z})] = "mcl_core:acaciatree"
labour.cut(sal, labour.wood_target(sal))
assert(count(sal, "mcl_core:acaciatree") == 5 and nodes[key(acacia)] == "mcl_core:acaciasapling")
-- A trip to a tree ends beside its trunk; a tree it cannot reach is passed over.
local tess = villager({_id = "tess"})
nodes[key({x = 20, y = 1, z = -20})] = "mcl_core:acaciatree"
nodes[key({x = 20, y = 6, z = -20})] = "mcl_core:acacialeaves"
labour.today(tess)
tess._villages_labour.activity = "woodcutter"
local first = labour.wood_target(tess).pos
labour.step(tess, now + 100)
local goal = tess.walks[1]
assert(goal and not (goal.x == first.x and goal.z == first.z) and vector.distance(goal, first) == 1, "beside the trunk")
tess._villages_labour_next = nil
labour.step(tess, now + 101)
assert(logs[#logs]:find("did not reach"))
local second = labour.wood_target(tess)
assert(second and not (second.pos.x == first.x and second.pos.z == first.z), "the other tree next")

-- A sapling is planted from beside its spot: a tree grown around a villager standing
-- on it would suffocate it.
do
	local pia = villager({_id = "pia"})
	possessions.add(pia, "mcl_core:sapling", 1)
	labour.today(pia)
	pia._villages_labour.activity = "woodcutter"
	pia._villages_grove = {}
	local plant = labour.wood_target(pia)
	if plant.kind == "plant" then
		labour.step(pia, now + 200)
		local at = pia.walks[#pia.walks]
		assert(at and vector.distance(at, plant.pos) == 1, "beside the spot")
		pia.arrive()
		assert(nodes[key(plant.pos)] == "mcl_core:sapling", "planted from beside")
	else
		error("expected a plant job, got " .. tostring(plant.kind))
	end
end

-- Prices it has heard for acacia count for woodcutting.
assert(labour.choose({asks("mcl_core:acaciatree", 0.5)}, both, nil, 0) == "woodcutter")

-- Charcoal: logs past 16 burn 8 to 7, the commonest log first, up to 32 charcoal.
local colin = villager({_id = "colin"})
possessions.add(colin, "mcl_core:tree", 20)
possessions.add(colin, "mcl_core:acaciatree", 13)
assert(labour.burn_charcoal(colin) == 14, "two burns")
assert(count(colin, "mcl_core:tree") == 12 and count(colin, "mcl_core:acaciatree") == 5, "the commonest each time")
assert(count(colin, "mcl_core:charcoal_lump") == 14 and logs[#logs]:find("burned 14 charcoal"))
assert(colin._villages_tally.made["mcl_core:charcoal_lump"] == 14 and colin._villages_tally.used["mcl_core:tree"] == 8)
assert(labour.burn_charcoal(colin) == 0, "17 logs left: one burn would leave fewer than 16")
possessions.add(colin, "mcl_core:charcoal_lump", 20)
possessions.add(colin, "mcl_core:tree", 40)
assert(labour.burn_charcoal(colin) == 0, "34 charcoal: enough")

-- The inspector line, and nothing with the economy off.
assert(labour.status(villager({_profession = "farmer"})) == "not looking for work")
settings.living_villages_economy = false
assert(not labour.eligible(villager()))
local def = {do_custom = function() end}
local before_custom = def.do_custom
labour.install(def)
assert(def.do_custom == before_custom)

-- Quarrier: only a generator's cobble, lava and water both beside or above it.
do
	settings.living_villages_economy = nil
	local function at(x, y, z) return {x = x, y = y, z = z} end
	local defs = minetest.registered_nodes
	defs.air = {walkable = false}
	defs["mcl_core:stone"], defs["mcl_core:cobble"] = {walkable = true}, {walkable = true}
	defs["mcl_core:lava_source"] = {walkable = false, liquidtype = "source", damage_per_second = 4}
	defs["mcl_core:lava_flowing"] = {walkable = false, liquidtype = "flowing", damage_per_second = 4}
	defs["mcl_core:water_source"] = {walkable = false, liquidtype = "source"}
	defs["mcl_core:water_flowing"] = {walkable = false, liquidtype = "flowing"}
	local saved = {}
	for k, v in pairs(nodes) do saved[k] = v end
	for k in pairs(nodes) do nodes[k] = nil end
	-- A generator 6 east of the bed: lava, the cobble, water; a floor to stand on in front.
	nodes[key(at(5, 1, 0))] = "mcl_core:lava_source"
	nodes[key(at(6, 1, 0))] = "mcl_core:cobble"
	nodes[key(at(7, 1, 0))] = "mcl_core:water_flowing"
	nodes[key(at(6, 0, 1))] = "mcl_core:stone"
	-- Terrain cobble, and cobble by lava alone: not mined.
	nodes[key(at(-6, 1, 0))] = "mcl_core:cobble"
	nodes[key(at(-6, 1, 3))] = "mcl_core:cobble"
	nodes[key(at(-5, 1, 3))] = "mcl_core:lava_flowing"
	assert(labour.is_generated(at(6, 1, 0)))
	assert(not labour.is_generated(at(-6, 1, 0)) and not labour.is_generated(at(-6, 1, 3)))
	-- Water below does not count: lava cools only from the side or above.
	nodes[key(at(7, 1, 0))] = nil
	nodes[key(at(6, 0, 0))] = "mcl_core:water_source"
	assert(not labour.is_generated(at(6, 1, 0)))
	nodes[key(at(6, 0, 0))] = nil
	nodes[key(at(7, 1, 0))] = "mcl_core:water_flowing"

	local quinn = villager({_id = "quinn"})
	local targets = labour.quarry_targets(quinn)
	assert(#targets == 1 and targets[1].kind == "cobble" and targets[1].pos.x == 6)
	-- Chosen by the price of cobble heard; with none heard, among what it has sites for.
	assert(labour.choose({asks("mcl_core:cobble", 0.05)}, {forager = true, quarrier = true}, nil, 0) == "quarrier")
	quinn._villages_labour = {day = day, activity = "quarrier"}
	labour.step(quinn, now + 1000)
	assert(#quinn.walks == 1 and quinn.walks[1].x == 6 and quinn.walks[1].z == 1, "stands in front of it")
	assert(not labour.waiting(quinn), "setting off is no wait (ticket 23a)")
	quinn.arrive()
	assert(count(quinn, "mcl_core:cobble") == 1 and nodes[key(at(6, 1, 0))] == nil, "mined, the lava will flow back")
	assert(quinn._villages_tally.made["mcl_core:cobble"] == 1)
	-- By hand a block takes MINE_SECONDS (a pickaxe divides it, wants.lua).
	assert(quinn._villages_labour_next == now + labour.MINE_SECONDS)
	-- Empty, the cell is still its generator: it waits beside it rather than going off.
	targets = labour.quarry_targets(quinn)
	assert(#targets == 1 and targets[1].ready == false and targets[1].mine == true)
	labour.step(quinn, now + 1100)
	assert(#quinn.walks == 1 and quinn._villages_labour_next == now + 1101, "waits a second at it")
	assert(labour.waiting(quinn), "between blocks it waits, and crafts (ticket 23a)")
	labour.step(quinn, now + 1100.5)
	assert(labour.waiting(quinn), "between ticks as it was")
	-- Another quarrier leaves the cell it works alone.
	local rhea = villager({_id = "rhea"})
	assert(#labour.quarry_targets(rhea) == 0)
	-- The lava flows back and cools: it mines again where it stands.
	nodes[key(at(6, 1, 0))] = "mcl_core:lava_flowing"
	assert(#labour.quarry_targets(quinn) == 1, "a flowing liquid in it, still the generator")
	nodes[key(at(6, 1, 0))] = "mcl_core:cobble"
	labour.step(quinn, now + 1200)
	assert(count(quinn, "mcl_core:cobble") == 2 and nodes[key(at(6, 1, 0))] == nil)
	-- With the water gone it is no generator; empty, it is forgotten.
	nodes[key(at(7, 1, 0))] = nil
	assert(#labour.quarry_targets(quinn) == 0)
	nodes[key(at(7, 1, 0))] = "mcl_core:water_flowing"
	-- A stone generator: lava over the cell and water beside it; stone drops cobble.
	nodes[key(at(6, 1, 0))] = nil
	nodes[key(at(0, 1, -6))] = "mcl_core:stone"
	nodes[key(at(0, 2, -6))] = "mcl_core:lava_source"
	nodes[key(at(1, 1, -6))] = "mcl_core:water_flowing"
	nodes[key(at(-1, 0, -6))] = "mcl_core:stone"
	local sid = villager({_id = "sid"})
	targets = labour.quarry_targets(sid)
	assert(#targets == 1 and targets[1].pos.z == -6 and targets[1].ready)
	sid._villages_labour = {day = day, activity = "quarrier"}
	labour.step(sid, now + 2000)
	assert(sid.walks[1].x == -1 and sid.walks[1].z == -6, "stands where there is floor")
	sid.arrive()
	assert(count(sid, "mcl_core:cobble") == 1 and nodes[key(at(0, 1, -6))] == nil)
	-- Nowhere dry to stand: not walked to.
	nodes[key(at(-1, 0, -6))] = nil
	nodes[key(at(0, 1, -6))] = "mcl_core:stone"
	assert(labour.stand_by(at(0, 1, -6)) == nil)
	-- Full, it stops.
	possessions.add(quinn, "mcl_core:cobble", labour.QUARRY_KEEP)
	nodes[key(at(6, 1, 0))] = "mcl_core:cobble"
	assert(#labour.quarry_targets(quinn) == 0)
	-- An alchemist quarries for itself only with no stone or cobble at all, then up to a
	-- day's stone; it takes no other labour (lv_pair e12d).
	possessions.take(quinn, "mcl_core:cobble", count(quinn, "mcl_core:cobble"))
	quinn._profession, quinn._villages_alchemist, quinn._jobsite = "cleric", true, at(0, 1, 3)
	quinn._villages_labour, quinn._villages_quarries = nil, nil
	possessions.add(quinn, "mcl_core:stone", 1)
	assert(not labour.self_quarry(quinn) and not labour.eligible(quinn), "it holds a stone")
	possessions.take(quinn, "mcl_core:stone", 1)
	assert(labour.self_quarry(quinn) and labour.eligible(quinn), "none left")
	assert(labour.today(quinn) == "quarrier")
	assert(labour.activity_override(quinn, "work") == "putter", "not called back to its stand")
	possessions.add(quinn, "mcl_core:cobble", labour.alchemist_stone() - 1)
	quinn._villages_quarry_hold = {cell = at(6, 1, 0), stand = at(5, 1, 0)}
	assert(labour.eligible(quinn), "quarrying, short of a day's stone")
	possessions.add(quinn, "mcl_core:cobble", 1)
	assert(not labour.eligible(quinn), "a day's stone: back to its stand")
	-- Back at its stand, a stone short, it does not walk to the generator for one more.
	quinn._villages_quarry_hold = nil
	possessions.take(quinn, "mcl_core:cobble", 1)
	assert(not labour.eligible(quinn), "not for one stone")
	possessions.take(quinn, "mcl_core:cobble", labour.alchemist_stone() - 1)
	-- With no generator in reach it does not labour.
	nodes[key(at(7, 1, 0))] = nil
	assert(not labour.eligible(quinn), "no generator")
	nodes[key(at(7, 1, 0))] = "mcl_core:water_flowing"
	-- A mason with nothing to make today quarries, over any other labour; a busy one does not.
	quinn._villages_alchemist, quinn._profession, quinn._villages_labour, quinn._villages_quarries = nil, "mason", nil, nil
	quinn._villages_idle = {day = day, idle = true, at = now}
	assert(labour.self_quarry(quinn) and labour.eligible(quinn))
	assert(labour.today(quinn) == "quarrier")
	quinn._villages_idle, quinn._villages_labour = {day = day, idle = false, at = now}, nil
	assert(not labour.self_quarry(quinn) and not labour.eligible(quinn))
	-- A Builder (a mason to vanilla) never.
	quinn._villages_builder, quinn._villages_idle = true, {day = day, idle = true, at = now}
	assert(not labour.self_quarry(quinn))
	for _, name in ipairs({"air", "mcl_core:stone", "mcl_core:cobble", "mcl_core:lava_source", "mcl_core:lava_flowing",
		"mcl_core:water_source", "mcl_core:water_flowing"}) do
		defs[name] = nil
	end
	for k in pairs(nodes) do nodes[k] = nil end
	for k, v in pairs(saved) do nodes[k] = v end
end

-- ColonyFood's first generator (2026-11-14): water, cell, lava in a row, walled, reached
-- down a one-wide corridor that ends at the cell, which has a floor. A quarrier stepped
-- into the mined cell and burned; now it is held where it stands, facing the cell.
do
	settings.living_villages_economy = nil
	local function at(x, y, z) return {x = x, y = y, z = z} end
	local defs = minetest.registered_nodes
	defs.air = {walkable = false}
	defs["mcl_core:stone"], defs["mcl_core:cobble"] = {walkable = true}, {walkable = true}
	defs["mcl_core:lava_source"] = {walkable = false, liquidtype = "source", damage_per_second = 4}
	defs["mcl_core:lava_flowing"] = {walkable = false, liquidtype = "flowing", damage_per_second = 4}
	defs["mcl_core:water_source"] = {walkable = false, liquidtype = "source"}
	local saved = {}
	for k, v in pairs(nodes) do saved[k] = v end
	for k in pairs(nodes) do nodes[k] = nil end
	for x = -2, 2 do for z = -3, 1 do nodes[key(at(x, 0, z))] = "mcl_core:stone" end end
	nodes[key(at(-1, 1, 0))] = "mcl_core:water_source"
	nodes[key(at(0, 1, 0))] = "mcl_core:cobble"
	nodes[key(at(1, 1, 0))] = "mcl_core:lava_source"
	for _, x in ipairs({-2, -1, 1, 2}) do nodes[key(at(x, 1, -1))] = "mcl_core:stone" end
	for x = -2, 2 do nodes[key(at(x, 1, 1))] = "mcl_core:stone" end
	-- The corridor is (0, 1, -1) and (0, 1, -2); its end, the cell, is (0, 1, 0).
	local cole = villager({_id = "cole", _bed = at(0, 1, -10)})
	cole._villages_labour = {day = day, activity = "quarrier"}
	cole.order = "work"
	cole.move_to(at(0, 1, -1))
	labour.step(cole, now + 3000)
	assert(cole._villages_quarry_hold and vector.equals(cole._villages_quarry_hold.stand, at(0, 1, -1)))
	assert(cole.order == "stand" and cole.state == "stand")
	assert(count(cole, "mcl_core:cobble") == 1 and nodes[key(at(0, 1, 0))] == nil)
	-- Pushed into the open cell, it is put back.
	cole.move_to(at(0, 0.5, 0))
	labour.hold(cole)
	local pos = cole.object:get_pos()
	assert(pos.x == 0 and pos.z == -1, "back on its cell")
	-- Drifted 0.25 toward the lava diagonal to it, still in its cell: its 0.6 box then
	-- reaches into the next cells, which vanilla counts as touching the lava, so it is put
	-- back in the middle (ColonyFood, 2026-11-19: the cartographer burned at 0.2 off).
	cole.move_to(at(0.25, 0.5, -0.8))
	labour.hold(cole)
	pos = cole.object:get_pos()
	assert(pos.x == 0 and pos.z == -1, "back in the middle of its cell")
	cole.move_to(at(0.1, 0.5, -1))
	labour.hold(cole)
	assert(cole.object:get_pos().x == 0.1, "a little off, it is left be")
	-- The refill: cobble where the lava is beside the cell, never on someone in it.
	cole.move_to(at(0, 0.5, 0))
	objects[#objects + 1] = cole.object
	assert(labour.refill(at(0, 1, 0)) == nil and nodes[key(at(0, 1, 0))] == nil, "not on a villager")
	table.remove(objects)
	assert(labour.refill(at(0, 1, 0)) == "mcl_core:cobble" and nodes[key(at(0, 1, 0))] == "mcl_core:cobble")
	assert(labour.refill(at(0, 1, 0)) == nil, "already full")
	-- Stone under lava: lava above the cell, water beside it.
	nodes[key(at(0, 1, 0))] = nil
	nodes[key(at(1, 1, 0))] = "mcl_core:stone"
	nodes[key(at(0, 2, 0))] = "mcl_core:lava_source"
	assert(labour.refill(at(0, 1, 0)) == "mcl_core:stone")
	-- A better pick refills the generator faster too (ticket 29): REGEN_SECONDS over its
	-- rate, stone's 3, gold's or diamond's 5.
	local delays = {}
	local saved_after = minetest.after
	minetest.after = function(delay, fn, ...) delays[#delays + 1] = delay end
	for _, case in ipairs({{"mcl_tools:pick_stone", 3}, {"mcl_tools:pick_iron", 4}, {"mcl_tools:pick_gold", 5}}) do
		cole._villages_wants = {pickaxe = {item = case[1], left = 10}}
		nodes[key(at(0, 1, 0))] = "mcl_core:stone"
		assert(labour.quarry(cole, {pos = at(0, 1, 0)}), case[1])
		assert(math.abs(delays[#delays] - labour.REGEN_SECONDS / case[2]) < 1e-9, case[1] .. " " .. delays[#delays])
	end
	minetest.after = saved_after
	cole._villages_wants = nil
	-- Off work, its cell full, it is let go with its order back.
	nodes[key(at(0, 1, 0))] = "mcl_core:cobble"
	labour.release(cole)
	assert(cole._villages_quarry_hold == nil and cole.order == "work")
	-- Let go with the cell it mined still open, it stays held until the cell fills: five
	-- alchemists walked into the open cell as they set off home and burned (ColonyFood,
	-- 2026-11-25).
	cole.move_to(at(0, 1, -1))
	nodes[key(at(0, 1, 0))] = "mcl_core:cobble"
	labour.step(cole, now + 6000)
	assert(cole._villages_quarry_hold and nodes[key(at(0, 1, 0))] == nil, "mined")
	assert(labour.release(cole) == false and cole._villages_quarry_hold, "held while open")
	cole.move_to(at(0, 0.5, 0))
	labour.hold(cole)
	assert(cole._villages_quarry_hold and cole.object:get_pos().z == -1, "kept off the open cell")
	nodes[key(at(0, 1, 0))] = "mcl_core:cobble"
	labour.hold(cole)
	assert(cole._villages_quarry_hold == nil and cole.order == "work", "free once it fills")
	-- Never filling, it is let go after LEAVE_SECONDS.
	labour.step(cole, now + 9000)
	assert(cole._villages_quarry_hold and nodes[key(at(0, 1, 0))] == nil)
	assert(labour.release(cole) == false)
	now = now + labour.LEAVE_SECONDS
	labour.hold(cole)
	assert(cole._villages_quarry_hold == nil, "let go at the end")
	now = now - labour.LEAVE_SECONDS
	-- Put straight onto another stand, it is let go at once.
	nodes[key(at(0, 1, 0))] = "mcl_core:cobble"
	labour.step(cole, now + 12000)
	assert(labour.release(cole, true) and cole._villages_quarry_hold == nil)
	for k in pairs(nodes) do nodes[k] = nil end
	for k, v in pairs(saved) do nodes[k] = v end
	for _, name in ipairs({"air", "mcl_core:stone", "mcl_core:cobble", "mcl_core:lava_source", "mcl_core:lava_flowing",
		"mcl_core:water_source"}) do
		defs[name] = nil
	end
end

-- Flowers (ticket 19c): a forager picks a poppy's or dandelion's bloom and leaves the
-- plant, which blooms again some days later.
do
	settings.living_villages_economy = nil
	local saved = {}
	for k, v in pairs(nodes) do saved[k] = v end
	for k in pairs(nodes) do nodes[k] = nil end
	local poppy = {x = 4, y = 1, z = 4}
	nodes[key(poppy)] = "mcl_flowers:poppy"
	nodes[key({x = -4, y = 1, z = 4})] = "mcl_flowers:tulip_red"
	local flo = villager({_id = "flo"})
	local targets = labour.forage_targets(flo)
	assert(#targets == 1 and targets[1].kind == "flower" and targets[1].pos.x == 4, "poppies and dandelions only")
	assert(labour.forage(flo, targets[1]) == "mcl_flowers:poppy" and count(flo, "mcl_flowers:poppy") == 1)
	assert(nodes[key(poppy)] == "mcl_flowers:poppy", "the plant stays")
	assert(#labour.forage_targets(flo) == 0 and labour.forage(flo, targets[1]) == nil, "picked today")
	day = day + 3
	assert(#labour.forage_targets(flo) == 1, "in bloom again")
	possessions.add(flo, "mcl_flowers:poppy", 7)
	assert(#labour.forage_targets(flo) == 0, "it keeps eight")
	day = day - 3
	-- A lily of the valley too (19h), for the shepherd's white dye; it keeps eight of them.
	for k in pairs(nodes) do nodes[k] = nil end
	local lily = {x = 2, y = 1, z = -4}
	nodes[key(lily)] = "mcl_flowers:lily_of_the_valley"
	local lil = villager({_id = "lil"})
	local found = labour.forage_targets(lil)
	assert(#found == 1 and found[1].kind == "flower", "the lily is a target")
	assert(labour.forage(lil, found[1]) == "mcl_flowers:lily_of_the_valley" and nodes[key(lily)] ~= nil)
	day = day + 3
	possessions.add(lil, "mcl_flowers:lily_of_the_valley", 7)
	assert(#labour.forage_targets(lil) == 0, "eight lilies kept")
	day = day - 3
	for k in pairs(nodes) do nodes[k] = nil end
	for k, v in pairs(saved) do nodes[k] = v end
end

-- Porter: open when it has heard of a trade waiting, one villager needing what another
-- has; its income is a fee or two; its day is left to trade_trips.lua.
do
	settings.living_villages_economy = nil
	local wants = {item = "mcl_core:coal_lump", kind = "needs", price = 0.2, who = "smith", heard = now, hops = 1}
	local offers = {item = "mcl_core:coal_lump", kind = "has", price = 0.05, who = "cole", heard = now, hops = 1}
	assert(labour.trade_waiting({wants, offers}))
	assert(not labour.trade_waiting({wants}) and not labour.trade_waiting({offers}))
	assert(not labour.trade_waiting({wants, {item = "mcl_core:coal_lump", kind = "has", who = "smith", heard = now, hops = 0}}),
		"a villager does not trade with itself")
	assert(labour.incomes({wants, offers}).porter > 0 and labour.incomes({}).porter == 0)
	assert(labour.choose({wants, offers}, {porter = true, forager = true}, nil, 0) == "porter")
	-- What portering pays is learnt: a fee per hire per porter day, from one in two.
	assert(labour.porter_income(nil) == 32 and labour.porter_income({days = 6, hires = 0}) == 8)
	assert(labour.porter_income({days = 2, hires = 3}) == 64)
	-- A small peddling deal beats portering nobody hires.
	local offers2 = {item = "mcl_core:coal_lump", kind = "has", price = 6, count = 4, who = "cole", heard = now, hops = 1}
	local wants2 = {item = "mcl_core:coal_lump", kind = "needs", price = 14, count = 4, who = "smith", heard = now, hops = 1}
	local open2 = {porter = true, peddler = true}
	assert(labour.choose({offers2, wants2}, open2, nil, 0, 1000) == "porter", "a new porter's hopes")
	assert(labour.choose({offers2, wants2}, open2, nil, 0, 1000, {days = 4, hires = 0}) == "peddler", "after days unhired")
	local pam = villager({_id = "pam", _villages_labour = {day = day, activity = "porter"}})
	labour.step(pam, now + 5000)
	assert(#pam.walks == 0, "it walks only on a trip")
	assert(labour.status(pam) == "porter, waiting for hire")
	-- A need for a labour good is work for a porter on commission, with no seller (ticket
	-- 26b); a need for sticks is not: a crafter makes its own.
	local lantern = {item = "mcl_lanterns:lantern_floor", kind = "needs", price = 900, who = "farm", heard = now, hops = 1}
	local sticks = {item = "mcl_core:stick", kind = "needs", price = 1, who = "farm", heard = now, hops = 1}
	assert(labour.craft_waiting({lantern}) and not labour.craft_waiting({sticks}))
	assert(labour.incomes({lantern}).porter > 0)
	-- One with a commission under way goes portering every day until it delivers.
	local cam = villager({_id = "cam", _villages_commission = {index = 10, item = "mcl_lanterns:lantern_floor",
		count = 1, client = "farm", deliver = {x = 0, y = 1, z = 9}, price = 100, day = day}})
	assert(labour.today(cam) == "porter", "a commission keeps it portering")
end

-- No bed: it works from the nearest bell near it, or where it stands; a bed takes over.
do
	local bea = villager({_id = "bea", _bed = false})
	bea.move_to({x = 200, y = 1, z = 200})
	nodes[key({x = 205, y = 4, z = 200})] = "mcl_bells:bell"
	nodes[key({x = 210, y = 1, z = 200})] = "mcl_farming:sweet_berry_bush_3"
	local from = labour.choose_home(bea)
	assert(from.x == 205 and from.y == 4 and bea._villages_labour_home and labour.home(bea) == bea._villages_labour_home)
	local found = false
	for _, target in ipairs(labour.forage_targets(bea)) do
		if target.pos.x == 210 and target.pos.z == 200 then found = true end
	end
	assert(found, "it forages about the bell")
	nodes[key({x = 205, y = 4, z = 200})] = nil
	from = labour.choose_home(bea)
	assert(from.x == 200 and from.z == 200, "no bell: where it stands")
	bea._bed = {x = 1, y = 1, z = 1}
	assert(labour.choose_home(bea) == bea._bed and bea._villages_labour_home == nil, "a bed takes over")
	nodes[key({x = 210, y = 1, z = 200})] = nil
end

-- Peddler: a deal is an item heard spare at one price and needed at PEDDLE_MARGIN times
-- that elsewhere; it buys at its bid, then sells, and the peddle ends sold out.
do
	local COAL = "mcl_core:coal_lump"
	-- Prices at ledger.SCALE, as heard.
	local S = 64
	local offers = {item = COAL, kind = "has", price = 4 * S, count = 10, who = "cole", heard = now, hops = 1}
	local wants = {item = COAL, kind = "needs", price = 10 * S, count = 6, who = "smith", heard = now, hops = 1}
	local deal = labour.deal({offers, wants}, 100000)
	assert(deal and deal.item == COAL and deal.count == 6 and deal.bid == 4 * S + 6 * S * labour.BID_SHARE and deal.sell_at == 10 * S)
	assert(math.abs(deal.income - 6 * (10 * S - deal.bid)) < 1e-9)
	assert(labour.deal({offers, wants}, 12 * S).count == 2, "as many as its emeralds buy")
	assert(labour.deal({offers, wants}, S) == nil, "none at all")
	assert(labour.deal({offers, {item = COAL, kind = "needs", price = 5 * S, count = 6, who = "smith", heard = now, hops = 1}}, 100000) == nil,
		"too thin a margin")
	assert(labour.deal({offers, {item = COAL, kind = "needs", price = 10 * S, count = 6, who = "cole", heard = now, hops = 1}}, 100000) == nil,
		"not from and to the same villager")
	assert(labour.incomes({offers, wants}, 100000).peddler > 0 and labour.incomes({offers, wants}, 0).peddler == 0)

	-- Gathering is reckoned at what it has yielded (ticket 12b): a woodcutter that felled
	-- 4 logs in 10 days peddles instead, where its full rate would have kept it cutting.
	local logs = {item = "mcl_core:tree", kind = "needs", price = 48, count = 4, who = "lib", heard = now, hops = 1}
	local open3 = {woodcutter = true, peddler = true}
	assert(labour.yield_share("woodcutter", nil) == 1 and labour.yield_share("porter", {}) == 1)
	assert(labour.yield_share("woodcutter", {woodcutter = {days = 10, made = 4}}) == 14 / 110)
	assert(labour.yield_share("woodcutter", {woodcutter = {days = 2, made = 40}}) == 1, "never above the full rate")
	local WOOL = "mcl_wool:white"
	local wool = {{item = WOOL, kind = "has", price = 14, count = 16, who = "shep", heard = now, hops = 1},
		{item = WOOL, kind = "needs", price = 28, count = 10, who = "carto", heard = now, hops = 1}, logs}
	assert(labour.choose(wool, open3, "woodcutter", 0, 100000) == "woodcutter")
	assert(labour.choose(wool, open3, "woodcutter", 0, 100000, nil,
		{woodcutter = {days = 10, made = 4}}) == "peddler")

	local pedro = villager({_id = "pedro", _villages_belongings = {["mcl_core:emerald"] = 100000},
		_villages_market_news = {offers, wants}})
	day = day + 1
	-- With no site for anything else, it peddles.
	assert(labour.today(pedro) == "peddler")
	local peddle = pedro._villages_peddle
	assert(peddle and peddle.buying and peddle.item == COAL and peddle.count == 6 and peddle.day == day)
	assert(labour.status(pedro):find("buying 6", 1, true))
	-- Holding the lot, it sells.
	possessions.add(pedro, COAL, 6)
	labour.peddle_tick(pedro, day)
	assert(not peddle.buying and labour.status(pedro):find("selling 6", 1, true))
	-- A peddle under way is today's work whatever it hears.
	pedro._villages_market_news = nil
	day = day + 1
	assert(labour.today(pedro) == "peddler")
	-- Sold out, it ends.
	possessions.take(pedro, COAL, 6)
	labour.peddle_tick(pedro, day)
	assert(pedro._villages_peddle == nil)
	-- Buying gives way to selling after its buying days, and a peddle with nothing bought ends.
	pedro._villages_peddle = {item = COAL, count = 6, bid = 6 * S, sell_at = 10 * S, day = day, buying = true}
	possessions.add(pedro, COAL, 2)
	labour.peddle_tick(pedro, day + labour.PEDDLE_BUY_DAYS)
	assert(pedro._villages_peddle and not pedro._villages_peddle.buying)
	labour.peddle_tick(pedro, day + labour.PEDDLE_DAYS)
	assert(pedro._villages_peddle == nil, "its days are over")
end

-- A woodcutter by trade (woodcutter.lua, ticket 16): woodcutting every day, its grove
-- around its chopping block rather than its bed, up to twelve trees.
do
	nodes = {}
	for x = -24, 72 do for z = -24, 24 do nodes[key({x = x, y = 0, z = z})] = "mcl_core:dirt_with_grass" end end
	local block = {x = 40, y = 1, z = 0}
	local woody = villager({_id = "woody", _villages_woodcutter = true, _jobsite = block})
	assert(labour.eligible(woody))
	assert(labour.today(woody) == "woodcutter" and woody._villages_labour.activity == "woodcutter")
	assert(labour.home(woody) == block)
	possessions.add(woody, "mcl_core:sapling", 1)
	local plant_job = labour.wood_target(woody)
	assert(plant_job and plant_job.kind == "plant" and vector.distance(plant_job.pos, block) <= 20, "by the block")
	-- Twelve trees, not eight: with eleven planted it still plants.
	woody._villages_grove = {}
	for i = 1, 11 do woody._villages_grove[i] = {x = 100 + i * 10, y = 1, z = 100} end
	for i = 1, 11 do nodes[key(woody._villages_grove[i])] = "mcl_core:sapling" end
	local more = labour.wood_target(woody)
	assert(more and more.kind == "plant")
	assert(labour.status(woody):find("woodcutter by trade"))
end


-- Ticket 39e: every good a labourer gathers counts as one the village supplies (ledger.lua
-- keeps its own list, since it cannot read labour.lua).
do
	local ledger = dofile("ledger.lua")
	for name, activity in pairs(labour.ACTIVITIES) do
		for item in pairs(activity.goods) do
			assert(ledger.supplied(item), name .. " gathers " .. item .. ", which ledger.supplied misses")
		end
	end
end

print("labour.lua: ok")
