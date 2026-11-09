-- Run with: lua tests/labour.lua
local now, day, time = 1000, 5, 9000 / 24000
local settings = {}
local nodes, objects, logs = {}, {}, {}
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
}

ItemStack = function(text)
	local name, count = text:match("^(%S+)%s*(%d*)")
	return {get_name = function() return name end, get_count = function() return tonumber(count) or 1 end}
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
	v.object = {get_pos = function() return pos end}
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
assert(not nodes[key({x = spot.x, y = spot.y + 2, z = spot.z})], "trunk gone")
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
	quinn.arrive()
	assert(count(quinn, "mcl_core:cobble") == 1 and nodes[key(at(6, 1, 0))] == nil, "mined, the lava will flow back")
	assert(quinn._villages_tally.made["mcl_core:cobble"] == 1)
	-- Full, it stops.
	possessions.add(quinn, "mcl_core:cobble", labour.QUARRY_KEEP)
	nodes[key(at(6, 1, 0))] = "mcl_core:cobble"
	assert(#labour.quarry_targets(quinn) == 0)
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
	local pam = villager({_id = "pam", _villages_labour = {day = day, activity = "porter"}})
	labour.step(pam, now + 5000)
	assert(#pam.walks == 0, "it walks only on a trip")
	assert(labour.status(pam) == "porter, waiting for hire")
end

print("labour.lua: ok")
