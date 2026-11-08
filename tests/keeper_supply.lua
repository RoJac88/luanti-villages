-- Run with: lua tests/keeper_supply.lua
local time = 10000 / 24000
local now, day = 1000, 3
local nodes, metas, inventories, logs = {}, {}, {}, {}
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
local function parse(k)
	local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
	return {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
end

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	equals = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	add = function(a, n) return {x = a.x + n, y = a.y + n, z = a.z + n} end,
	subtract = function(a, n) return {x = a.x - n, y = a.y - n, z = a.z - n} end,
}

local function split(item)
	local name, count = item:match("^(%S+)%s*(%d*)")
	return name, tonumber(count) or 1
end

local function inventory(list)
	return {
		get_size = function() return list and 27 or 0 end,
		get_list = function()
			local out = {}
			for name, count in pairs(list or {}) do
				out[#out + 1] = {get_name = function() return name end, get_count = function() return count end}
			end
			return out
		end,
		remove_item = function(_, _, item)
			local name, count = split(item)
			local moved = math.min(list[name] or 0, count)
			list[name] = (list[name] or 0) - moved
			if list[name] == 0 then list[name] = nil end
			return {get_count = function() return moved end}
		end,
		room_for_item = function() return true end,
		add_item = function(_, _, item)
			local name, count = split(item)
			list[name] = (list[name] or 0) + count
			return {get_count = function() return 0 end}
		end,
	}
end

minetest = {
	get_modpath = function() return "." end,
	get_timeofday = function() return time end,
	get_gametime = function() return now end,
	get_day_count = function() return day end,
	get_item_group = function() return 0 end,
	registered_nodes = {["mcl_jukebox:jukebox"] = {}},
	get_translator = function() return function(message) return message end end,
	get_color_escape_sequence = function() return "" end,
	formspec_escape = function(text) return text end,
	serialize = function(value) return value end,
	settings = {get = function() return nil end, get_bool = function(_, _, default) return default end},
	log = function(_, message) table.insert(logs, message) end,
	is_protected = function() return false end,
	pos_to_string = function(p) return key(p) end,
	get_node_or_nil = function(pos) return {name = nodes[key(pos)] or "air"} end,
	get_meta = function(pos)
		local k = key(pos)
		metas[k] = metas[k] or {}
		return {
			get_string = function(_, field) return metas[k][field] or "" end,
			set_string = function(_, field, value) metas[k][field] = value end,
			get_inventory = function() return inventory(inventories[k]) end,
		}
	end,
	find_nodes_in_area = function(minp, maxp, names)
		local wanted = {}
		for _, name in ipairs(names) do wanted[name] = true end
		local found = {}
		for k, name in pairs(nodes) do
			local p = parse(k)
			if wanted[name] and p.x >= minp.x and p.x <= maxp.x and p.y >= minp.y and p.y <= maxp.y
				and p.z >= minp.z and p.z <= maxp.z then
				table.insert(found, p)
			end
		end
		table.sort(found, function(a, b) return key(a) < key(b) end)
		return found
	end,
}

local supply = dofile("keeper_supply.lua")
local pantry = dofile("tavern_pantry.lua")

-- A tavern with its pantry chest behind the bar, and a farm 20 away with a full chest.
local jukebox, pantry_chest = {x = 0, y = 0, z = 0}, {x = 3, y = 0, z = 0}
local composter, farm_chest = {x = 20, y = 0, z = 0}, {x = 21, y = 0, z = 0}
nodes[key(jukebox)] = "mcl_jukebox:jukebox"
nodes[key(pantry_chest)] = "mcl_chests:chest_small"
nodes[key(composter)] = "mcl_composters:composter_3"
nodes[key(farm_chest)] = "mcl_chests:chest_small"
inventories[key(pantry_chest)] = {["mcl_core:emerald"] = 1}
inventories[key(farm_chest)] = {["mcl_farming:bread"] = 4, ["mcl_farming:wheat_item"] = 30, ["mcl_farming:potato_item"] = 10}
metas[key(jukebox)] = {villager = "kate"}
metas[key(composter)] = {villager = "fred"}

local pos = {x = 0, y = 0, z = 1}
local trip
local kate = {
	_id = "kate", _villages_keeper = true, _jobsite = jukebox, _profession = "butcher", state = "stand",
	object = {get_pos = function() return pos end},
	gopath = function(_, target, arrived)
		trip = {target = target, arrived = arrived}
		return true
	end,
}
local function arrive_at(target)
	pos = {x = target.x, y = target.y, z = target.z + 1}
	local callback = trip.arrived
	trip = nil
	callback(kate)
end

-- Free hours, the pantry empty: off to the farm's chest.
local chests = pantry.chests(jukebox)
assert(chests and #chests == 1 and supply.meals(chests) == 0)
supply.step(kate, now)
assert(trip and vector.equals(trip.target, farm_chest), "walks to the farmer's chest")
assert(kate._villages_farm_pouch["mcl_core:emerald"] == 1 and not inventories[key(pantry_chest)]["mcl_core:emerald"],
	"takes the pantry's emeralds to pay with")
assert(kate._villages_supply_target, "an errand for far_trips.lua")
-- Takes up to 24, bread first, then potatoes, then wheat.
arrive_at(farm_chest)
assert(kate._villages_farm_pouch["mcl_farming:bread"] == 4)
assert(kate._villages_farm_pouch["mcl_farming:potato_item"] == 10)
assert(kate._villages_farm_pouch["mcl_farming:wheat_item"] == 10)
assert(inventories[key(farm_chest)]["mcl_farming:wheat_item"] == 20 and not kate._villages_supply_target)
-- It owes more than the one emerald it has: it pays that, and takes the food anyway.
-- A dinner's price per meal the food makes: a loaf or a potato is one, wheat a third.
local owed = supply.worth({["mcl_farming:bread"] = 4, ["mcl_farming:potato_item"] = 10, ["mcl_farming:wheat_item"] = 10})
assert(math.abs(owed - (4 + 10 + 10 / 3)) < 1e-9, "worth " .. owed)
assert(inventories[key(farm_chest)]["mcl_core:emerald"] == 1 and not kate._villages_farm_pouch["mcl_core:emerald"])
-- The rest it owes in the chest, up to the cap; past that it is forgiven.
assert(supply.tab(farm_chest) == supply.TAB_CAP, "owes " .. supply.tab(farm_chest))
inventories[key(farm_chest)]["mcl_core:emerald"] = nil
-- With a full purse it pays what it owes first, and carries a fraction over.
do
	local chest = {x = 30, y = 0, z = 0}
	inventories[key(chest)] = {}
	nodes[key(chest)] = nodes[key(farm_chest)]
	local buyer = {_id = "kim", _villages_farm_pouch = {["mcl_core:emerald"] = 8}}
	local paid, left = supply.pay(buyer, chest, {["mcl_farming:wheat_item"] = 4})
	assert(paid == 1 and math.abs(left - 1 / 3) < 1e-3 and math.abs(supply.tab(chest) - 1 / 3) < 1e-3, paid .. " " .. left)
	paid, left = supply.pay(buyer, chest, {["mcl_farming:wheat_item"] = 2})
	assert(paid == 1 and left < 1e-3 and supply.tab(chest) == 0, "two thirds and the third owed make one")
	assert(inventories[key(chest)]["mcl_core:emerald"] == 2 and buyer._villages_farm_pouch["mcl_core:emerald"] == 6)
end

-- At the next check it carries the food back to the pantry.
supply.step(kate, now + 1)
assert(not trip, "waits for the next check")
now = now + supply.CHECK_SECONDS
supply.step(kate, now)
assert(trip and vector.equals(trip.target, pantry_chest), "carries it to the pantry")
arrive_at(pantry_chest)
assert(inventories[key(pantry_chest)]["mcl_farming:bread"] == 4)
assert(inventories[key(pantry_chest)]["mcl_farming:wheat_item"] == 10)
assert(next(kate._villages_farm_pouch) == nil, "pouch emptied")
-- What it did not spend goes back.
kate._villages_farm_pouch = {["mcl_core:emerald"] = 2, ["mcl_farming:bread"] = 1}
supply.step(kate, now + supply.CHECK_SECONDS)
arrive_at(pantry_chest)
assert(inventories[key(pantry_chest)]["mcl_core:emerald"] == 2 and inventories[key(pantry_chest)]["mcl_farming:bread"] == 5)
inventories[key(pantry_chest)]["mcl_core:emerald"], inventories[key(pantry_chest)]["mcl_farming:bread"] = nil, 4
kate._villages_supply_next = nil
-- 4 loaves, 10 potatoes and three loaves' worth of wheat: enough, so no trip.
assert(supply.meals(chests) == 17)
now = now + supply.CHECK_SECONDS
supply.step(kate, now)
assert(not trip, "pantry stocked: stays")

-- A walk that ends without arriving: tried again later, not at once.
inventories[key(pantry_chest)] = {}
now = now + supply.CHECK_SECONDS
supply.step(kate, now)
assert(trip)
trip = nil
supply.step(kate, now + 1)
assert(not trip and not kate._villages_supply_target, "gave the trip up")
supply.step(kate, now + supply.CHECK_SECONDS + 1)
assert(not trip, "waits RETRY_SECONDS")
now = now + supply.RETRY_SECONDS + 1
supply.step(kate, now)
assert(trip, "tries again")
trip, kate._villages_supply_target = nil, nil

-- Busy walking or planning: nothing.
kate._villages_supply_next = nil
kate.state = "gowp"
supply.step(kate, now)
assert(not trip)
kate.state = "stand"
kate._villages_goto_route = {status = "planning"}
supply.step(kate, now)
assert(not trip)
kate._villages_goto_route = nil

-- An unclaimed composter's chest, or a chest that is a pantry, is no source.
metas[key(composter)] = {}
assert(supply.source(jukebox, chests) == nil)
metas[key(composter)] = {villager = "fred"}
local near_composter = {x = 2, y = 0, z = 0}
nodes[key(near_composter)] = "mcl_composters:composter"
metas[key(near_composter)] = {villager = "gus"}
assert(vector.equals(supply.source(jukebox, chests), farm_chest), "skips the pantry nearest gus's composter")
nodes[key(near_composter)] = nil

-- A fisherman's claimed barrel with cod is a source too, nearer than the farm.
local barrel = {x = 10, y = 0, z = 0}
nodes[key(barrel)] = "mcl_barrels:barrel_closed"
inventories[key(barrel)] = {["mcl_fishing:fish_raw"] = 5}
assert(vector.equals(supply.source(jukebox, chests), farm_chest), "an unclaimed barrel is no source")
metas[key(barrel)] = {villager = "finn"}
assert(vector.equals(supply.source(jukebox, chests), barrel))
inventories[key(barrel)] = {["mcl_fishing:salmon_raw"] = 5}
assert(vector.equals(supply.source(jukebox, chests), farm_chest), "no cod, no trip there")
nodes[key(barrel)] = nil

-- A farm with nothing to fetch: no trip, and it checks again later.
inventories[key(farm_chest)] = {["mcl_farming:carrot_item"] = 40}
kate._villages_supply_next = nil
supply.step(kate, now)
assert(not trip and kate._villages_supply_next == now + supply.RETRY_SECONDS)

-- Its shift: one dish every COOK_SECONDS at the jukebox, three wheat to the loaf first.
inventories[key(pantry_chest)] = {["mcl_farming:wheat_item"] = 4, ["mcl_farming:potato_item"] = 1}
time = 15000 / 24000
kate.order = "work"
supply.step(kate, now)
assert(inventories[key(pantry_chest)]["mcl_farming:bread"] == 1)
assert(inventories[key(pantry_chest)]["mcl_farming:wheat_item"] == 1)
supply.step(kate, now + 1)
assert(inventories[key(pantry_chest)]["mcl_farming:potato_item"] == 1, "one dish per COOK_SECONDS")
now = now + supply.COOK_SECONDS
supply.step(kate, now)
assert(inventories[key(pantry_chest)]["mcl_farming:potato_item_baked"] == 1)
now = now + supply.COOK_SECONDS
supply.step(kate, now)
assert(inventories[key(pantry_chest)]["mcl_farming:wheat_item"] == 1, "one wheat makes nothing")
-- Not cooking until it is at the jukebox working.
inventories[key(pantry_chest)]["mcl_farming:wheat_item"] = 3
kate.order = nil
now = now + supply.COOK_SECONDS
supply.step(kate, now)
assert(inventories[key(pantry_chest)]["mcl_farming:wheat_item"] == 3)
assert(not trip, "no fetching on shift")

-- Another stage: no errand left behind.
time = 20000 / 24000
kate._villages_supply_target = {x = 1, y = 1, z = 1}
supply.step(kate, now)
assert(kate._villages_supply_target == nil)

-- A chest the village generator fills by a jukebox gets the starting stock; others not.
local new_pantry, house_chest = {x = 0, y = 0, z = 4}, {x = 40, y = 0, z = 40}
inventories[key(new_pantry)], inventories[key(house_chest)] = {}, {}
assert(supply.stock_new_pantry(new_pantry))
for _, entry in ipairs(supply.STARTING_STOCK) do
	assert(inventories[key(new_pantry)][entry[1]] == entry[2], entry[1])
end
assert(not supply.stock_new_pantry(house_chest) and next(inventories[key(house_chest)]) == nil)

-- install wraps settlements.fill_chest so new taverns get it.
local filled = {}
settlements = {fill_chest = function(p) filled[#filled + 1] = p end}
local def = {do_custom = function() return true end}
supply.install(def)
local another = {x = 0, y = 0, z = -4}
inventories[key(another)] = {}
settlements.fill_chest(another)
assert(#filled == 1 and inventories[key(another)]["mcl_farming:bread"] == 6)

print("keeper_supply.lua: ok")
