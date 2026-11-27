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
-- Dinner money for the food: 4 loaves and 10 potatoes at the base price of a loaf.
local LOAF = dofile("ledger.lua").price("mcl_farming:bread")
local POT = dofile("ledger.lua").price("mcl_farming:potato_item")
local stock = dofile("farm_stock.lua")
inventories[key(pantry_chest)] = {["mcl_core:emerald"] = math.ceil(14 * LOAF)}
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
assert(kate._villages_farm_pouch["mcl_core:emerald"] == math.ceil(14 * LOAF)
	and not inventories[key(pantry_chest)]["mcl_core:emerald"], "takes the pantry's emeralds to pay with")
assert(kate._villages_supply_target, "an errand for far_trips.lua")
-- Takes up to 24, bread first, then potatoes. Wheat it leaves: only the farmer bakes.
arrive_at(farm_chest)
assert(kate._villages_farm_pouch["mcl_farming:bread"] == 4)
assert(kate._villages_farm_pouch["mcl_farming:potato_item"] == 10)
assert(not kate._villages_farm_pouch["mcl_farming:wheat_item"])
assert(inventories[key(farm_chest)]["mcl_farming:wheat_item"] == 30 and not kate._villages_supply_target)
-- With no ask posted at the chest it pays its own reference price for each food (ticket
-- 39a): a loaf's for a loaf, a potato's for a potato, not a loaf's for every meal.
local owed = supply.worth({["mcl_farming:bread"] = 4, ["mcl_farming:potato_item"] = 10}, kate, farm_chest)
assert(math.abs(owed - (LOAF * 4 + POT * 10)) < 1e-9, "worth " .. owed)
-- One that has learnt food trades at half pays half.
local frugal = {_villages_prices = {["group:food"] = 0.5}}
assert(math.abs(supply.worth({["mcl_farming:potato_item"] = 10}, frugal) - POT * 5) < 1e-9)
assert(inventories[key(farm_chest)]["mcl_core:emerald"] == math.floor(owed + 1e-3), "paid in full")
assert(supply.tab(farm_chest) < 1, "a fraction at most owed")
-- The farmer takes up what it took as sales at its next visit, and each food costs what it
-- paid (ticket 45: a potato is a raw plate's, no longer half a baked potato).
local sold, paid_for = stock.take_chest_sales(farm_chest, "mcl_farming:potato_item")
assert(sold == 10 and math.abs(paid_for - POT * 10) < 1e-3, sold .. " " .. paid_for)
assert(stock.take_chest_sales(farm_chest, "mcl_farming:potato_item") == 0, "taken up once")
assert(stock.take_chest_sales(farm_chest, "mcl_farming:bread") == 4)
assert(math.abs(kate._villages_input_cost["mcl_farming:potato_item"] - POT) < 1e-9)
assert(kate._villages_input_cost["mcl_farming:potato_item_baked"] == nil)
assert(math.abs(kate._villages_input_cost["mcl_farming:bread"] - LOAF) < 1e-9)
-- An ask the farmer posted is what it pays.
stock.post_ask(farm_chest, "mcl_farming:potato_item", 1.5)
assert(math.abs(supply.worth({["mcl_farming:potato_item"] = 10}, kate, farm_chest) - 15) < 1e-9)
assert(supply.unit(kate, farm_chest, "mcl_farming:potato_item") == 1.5)
stock.post_ask(farm_chest, "mcl_farming:potato_item", nil)
assert(not stock.chest_ask(farm_chest, "mcl_farming:potato_item"))
-- Past the cap (a fraction, ticket 27) a tab is forgiven.
supply.pay(kate, farm_chest, {["mcl_farming:bread"] = 60})
assert(supply.tab(farm_chest) == supply.TAB_CAP, "capped at " .. supply.tab(farm_chest))
assert(logs[#logs]:find("forgave"), "and the rest forgiven")
inventories[key(farm_chest)]["mcl_core:emerald"] = nil
minetest.get_meta(farm_chest):set_string(supply.TAB, "")
-- A fraction of an emerald it owes, and pays first next time.
do
	local chest = {x = 30, y = 0, z = 0}
	inventories[key(chest)] = {}
	nodes[key(chest)] = nodes[key(farm_chest)]
	-- A loaf at 16.5: it pays 16 and owes the half.
	local buyer = {_id = "kim", _villages_farm_pouch = {["mcl_core:emerald"] = 40},
		_villages_prices = {["group:food"] = 16.5 / LOAF}}
	local paid, left = supply.pay(buyer, chest, {["mcl_farming:bread"] = 1})
	assert(paid == 16 and math.abs(left - 0.5) < 1e-3 and math.abs(supply.tab(chest) - 0.5) < 1e-3, paid .. " " .. left)
	-- The half owed comes first: a loaf (16.5) and 0.5 make 17.
	paid, left = supply.pay(buyer, chest, {["mcl_farming:bread"] = 1})
	assert(paid == 17 and left < 1e-3 and supply.tab(chest) == 0, "the tab is paid first")
	assert(inventories[key(chest)]["mcl_core:emerald"] == 33 and buyer._villages_farm_pouch["mcl_core:emerald"] == 7)
	assert((buyer._villages_tally and buyer._villages_tally.money and buyer._villages_tally.money.paid or 0) == 33, "what it paid the farm chest is trade (ticket 48b)")
end

-- At the next check it carries the food back to the pantry.
supply.step(kate, now + 1)
assert(not trip, "waits for the next check")
now = now + supply.CHECK_SECONDS
supply.step(kate, now)
assert(trip and vector.equals(trip.target, jukebox), "carries it back to the jukebox, beside the pantry")
arrive_at(jukebox)
assert(inventories[key(pantry_chest)]["mcl_farming:bread"] == 4)
assert(inventories[key(pantry_chest)]["mcl_farming:potato_item"] == 10)
assert(next(kate._villages_farm_pouch) == nil, "pouch emptied")
-- What it did not spend goes back.
kate._villages_farm_pouch = {["mcl_core:emerald"] = 2, ["mcl_farming:bread"] = 1}
supply.step(kate, now + supply.CHECK_SECONDS)
arrive_at(jukebox)
assert(inventories[key(pantry_chest)]["mcl_core:emerald"] == 2 and inventories[key(pantry_chest)]["mcl_farming:bread"] == 5)
inventories[key(pantry_chest)]["mcl_core:emerald"], inventories[key(pantry_chest)]["mcl_farming:bread"] = nil, 4
kate._villages_supply_next = nil
-- Raw potatoes kept for raw plates (ticket 39h) count toward no meal: 10 potatoes alone are
-- under the reserve, and the 4 loaves are the meals.
local RESERVE = supply.RAW_RESERVE["mcl_farming:potato_item"]
assert(RESERVE == 16 and supply.meals(chests) == 4)
-- Potatoes past the reserve count for nothing either: it bakes none (ticket 45). 14 loaves:
-- enough, so no trip.
inventories[key(pantry_chest)]["mcl_farming:potato_item"] = 20 + RESERVE
assert(supply.meals(chests) == 4, "raw potatoes are no meals")
inventories[key(pantry_chest)]["mcl_farming:bread"] = 14
assert(supply.meals(chests) == 14)
now = now + supply.CHECK_SECONDS
supply.step(kate, now)
assert(not trip, "pantry stocked: stays")

-- Stocked to demand (ticket 22c; loaves: it fetches potatoes only for the raw plates, ticket 45): last evening 30 meals were wanted, so 14 is short of the 38 it stocks to (a quarter over), and
-- it carries 38. Busier still, at most CARRY_MAX a trip; the tab's cap grows with it.
do
	local dinner = dofile("dinner.lua")
	assert(supply.target(kate) == supply.TARGET_MEALS and supply.carry(kate) == supply.CARRY)
	-- A quarter over the demand (STOCK_MARGIN): 30 wanted, 38 stocked.
	kate._villages_dinner = {day = day, factor = 1, demand = 30}
	assert(supply.target(kate) == 38 and supply.carry(kate) == 38, supply.target(kate))
	assert(supply.tab_cap() == supply.TAB_CAP, "the cap stays a fraction")
	inventories[key(farm_chest)]["mcl_farming:bread"] = 50
	-- The farmer asks 2 a loaf, and there is dinner money for all 38 (76).
	stock.post_ask(farm_chest, "mcl_farming:bread", 2)
	inventories[key(pantry_chest)]["mcl_core:emerald"] = 76
	now = now + supply.CHECK_SECONDS
	supply.step(kate, now)
	assert(trip and vector.equals(trip.target, farm_chest), "14 is short of 38")
	arrive_at(farm_chest)
	assert(kate._villages_farm_pouch["mcl_farming:bread"] == 38, "carries the target")
	assert(inventories[key(farm_chest)]["mcl_farming:bread"] == 12)
	assert(inventories[key(farm_chest)]["mcl_core:emerald"] == 76)
	-- Only the food its purse pays for (ticket 27): with 40, 20 loaves of the 24 the
	-- pantry lacks. That no longer moves dinner (ticket 39b): the price covers each plate.
	kate._villages_farm_pouch = {}
	kate._villages_supply_next = nil
	inventories[key(farm_chest)] = {["mcl_farming:bread"] = 50}
	inventories[key(pantry_chest)]["mcl_core:emerald"] = 40
	now = now + supply.CHECK_SECONDS
	supply.step(kate, now)
	arrive_at(farm_chest)
	assert(kate._villages_farm_pouch["mcl_farming:bread"] == 20, "what 40 pays for")
	assert(inventories[key(farm_chest)]["mcl_core:emerald"] == 40 and supply.tab(farm_chest) == 0)
	assert(logs[#logs]:find("left 18 food its purse could not pay for"), logs[#logs])
	local factor = dinner.factor(kate)
	day = day + 1
	dinner.settle(kate, nil, day)
	assert(math.abs(dinner.factor(kate) - factor) < 1e-9, "dinner stays")
	day = day - 1
	-- With no dinner money it pays from its own float.
	kate._villages_dinner = {day = day, factor = 1, demand = 30}
	kate._villages_farm_pouch = {}
	kate._villages_supply_next = nil
	kate._villages_belongings = {["mcl_core:emerald"] = 30}
	inventories[key(farm_chest)] = {["mcl_farming:bread"] = 50}
	inventories[key(pantry_chest)]["mcl_core:emerald"] = nil
	now = now + supply.CHECK_SECONDS
	supply.step(kate, now)
	arrive_at(farm_chest)
	assert(kate._villages_farm_pouch["mcl_farming:bread"] == 15 and not kate._villages_belongings, "its 30")
	-- A tab from before (it took food it could not pay for, up to a cap that grew) is
	-- written off when it next fetches there.
	kate._villages_farm_pouch = {}
	kate._villages_supply_next = nil
	inventories[key(farm_chest)] = {["mcl_farming:bread"] = 50}
	inventories[key(pantry_chest)]["mcl_core:emerald"] = 76
	minetest.get_meta(farm_chest):set_string(supply.TAB, "987.39")
	now = now + supply.CHECK_SECONDS
	supply.step(kate, now)
	arrive_at(farm_chest)
	assert(kate._villages_farm_pouch["mcl_farming:bread"] == 38, "the old tab takes nothing from the purse")
	local found
	for _, line in ipairs(logs) do if line:find("wrote off 987.39 emerald") then found = true end end
	assert(found and supply.tab(farm_chest) < 1, "written off")
	stock.post_ask(farm_chest, "mcl_farming:bread", nil)
	kate._villages_dinner.demand = 500
	assert(supply.carry(kate) == supply.CARRY_MAX)
	assert(dinner.demand(kate) == 500)
	-- Back as it was for what follows.
	kate._villages_dinner, kate._villages_farm_pouch = nil, {}
	kate._villages_supply_next, kate._villages_supply_target, trip = nil, nil, nil
	inventories[key(farm_chest)]["mcl_farming:bread"] = nil
	inventories[key(farm_chest)]["mcl_core:emerald"] = nil
end

-- A walk that ends without arriving: tried again later, not at once. (The farm has
-- only wheat left, which it does not fetch: some bread to go for.)
inventories[key(pantry_chest)] = {}
inventories[key(farm_chest)]["mcl_farming:bread"] = 6
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
assert(not trip, "the source it gave up on is passed over for a while")
now = now + supply.SKIP_SECONDS
kate._villages_supply_next = nil
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

-- A fisherman's barrel is no source: only the butcher cooks fish (ticket 15).
local barrel = {x = 10, y = 0, z = 0}
nodes[key(barrel)] = "mcl_barrels:barrel_closed"
inventories[key(barrel)] = {["mcl_fishing:fish_raw"] = 5}
metas[key(barrel)] = {villager = "finn"}
assert(vector.equals(supply.source(jukebox, chests), farm_chest), "the farm, not the barrel")
-- One it could not reach is passed over.
assert(supply.source(jukebox, chests, function(pos) return vector.equals(pos, farm_chest) end) == nil,
	"the farm passed over: none")
nodes[key(barrel)] = nil

-- Of two farms, the chest with the most meals, though further: the nearest one had all
-- the tavern's money while the other's potatoes piled up (ColonyFood, 2026-11-14).
local far_composter, far_chest = {x = -30, y = 0, z = 0}, {x = -31, y = 0, z = 0}
nodes[key(far_composter)] = "mcl_composters:composter"
nodes[key(far_chest)] = "mcl_chests:chest_small"
metas[key(far_composter)] = {villager = "hal"}
local near_food = inventories[key(farm_chest)]
inventories[key(farm_chest)] = {["mcl_farming:bread"] = 4, ["mcl_farming:potato_item"] = 10}
inventories[key(far_chest)] = {["mcl_farming:potato_item"] = 300}
assert(vector.equals(supply.source(jukebox, chests), far_chest), "the fullest farm")
-- Carrots count a quarter of a meal each, potatoes a raw plate's share (ticket 45): 4 loaves
-- and 10 potatoes are 6.5.
inventories[key(far_chest)] = {["mcl_farming:carrot_item"] = 20}
assert(vector.equals(supply.source(jukebox, chests), farm_chest), "20 carrots are 5 meals, under 6.5")
-- Equal: the nearer.
inventories[key(far_chest)] = {["mcl_farming:bread"] = 4, ["mcl_farming:potato_item"] = 10}
assert(vector.equals(supply.source(jukebox, chests), farm_chest), "the nearer of equals")
nodes[key(far_composter)], nodes[key(far_chest)] = nil, nil
inventories[key(farm_chest)] = near_food

-- A farm with nothing to fetch: no trip, and it checks again later.
inventories[key(farm_chest)] = {["mcl_farming:wheat_item"] = 40}
kate._villages_supply_next = nil
supply.step(kate, now)
assert(not trip and kate._villages_supply_next == now + supply.RETRY_SECONDS)
-- Carrots, the tavern's last resort (meal.lua), are worth the trip, each at its own price.
inventories[key(farm_chest)] = {["mcl_farming:carrot_item"] = 40}
assert(vector.equals(supply.source(jukebox, chests), farm_chest), "carrots to fetch")
local CARROT_PRICE = dofile("ledger.lua").price("mcl_farming:carrot_item")
assert(math.abs(supply.worth({["mcl_farming:carrot_item"] = 4}) - 4 * CARROT_PRICE) < 1e-9)
inventories[key(farm_chest)] = {}

-- Its shift: it cooks nothing (ticket 45), whatever the pantry holds or lacks. Wheat, raw
-- fish and potatoes stay raw: the farmer bakes bread, the butcher cooks the rest.
assert(supply.COOK_SECONDS == 20)
inventories[key(pantry_chest)] = {["mcl_farming:wheat_item"] = 4, ["mcl_farming:potato_item"] = 40 + RESERVE,
	["mcl_fishing:fish_raw"] = 2}
time = 15000 / 24000
kate.order = "work"
kate._villages_food = 12 -- fed: the keeper's own dinner is tested below
for _ = 1, 4 do
	supply.step(kate, now)
	now = now + supply.COOK_SECONDS
end
assert(not inventories[key(pantry_chest)]["mcl_farming:potato_item_baked"], "no baking")
assert(inventories[key(pantry_chest)]["mcl_farming:potato_item"] == 40 + RESERVE)
assert(inventories[key(pantry_chest)]["mcl_farming:wheat_item"] == 4 and not inventories[key(pantry_chest)]["mcl_farming:bread"])
assert(inventories[key(pantry_chest)]["mcl_fishing:fish_raw"] == 2 and not inventories[key(pantry_chest)]["mcl_fishing:fish_cooked"])
assert(supply.cook == nil)
assert(supply.tonight(kate) == supply.TARGET_MEALS)
inventories[key(pantry_chest)]["mcl_farming:potato_item"] = 10 + RESERVE
inventories[key(pantry_chest)]["mcl_fishing:fish_cooked"] = supply.TARGET_MEALS + 1
-- What it buys (ticket 39g): a few of each dish it knows, and dishes of any kind for the
-- rest of its target.
assert(supply.dishes(chests) == supply.TARGET_MEALS + 1)
kate._villages_dinner = {day = day, factor = 1, demand = 24}
kate._villages_known_dishes = {["mcl_mobitems:cooked_beef"] = day}
supply.update_wants(kate, chests)
assert(kate._villages_dish_wants["mcl_mobitems:cooked_beef"] == dofile("keeper.lua").MIN_DISHES)
assert(kate._villages_dish_short == supply.target(kate) - (supply.TARGET_MEALS + 1) - dofile("keeper.lua").MIN_DISHES,
	tostring(kate._villages_dish_short))
local view = dofile("possessions.lua").assess(kate)
assert((view.needs["mcl_fishing:salmon_cooked"] or 0) > 0 and (view.needs["mcl_farming:potato_item_baked"] or 0) > 0, "any dish")
assert(not view.needs["mcl_farming:potato_item"], "no raw potatoes to bake")
-- E8: a dish it knows takes the shortfall too, past its few: not only the dishes nobody
-- offers.
assert((view.needs["mcl_mobitems:cooked_beef"] or 0) == dofile("keeper.lua").MIN_DISHES + kate._villages_dish_short,
	tostring(view.needs["mcl_mobitems:cooked_beef"]))
-- What it carries counts with the pantry: 5 cooked beef bought fill its few and part of
-- the shortfall.
do
	local poss = dofile("possessions.lua")
	local before = kate._villages_dish_short
	poss.add(kate, "mcl_mobitems:cooked_beef", 5)
	supply.update_wants(kate, chests)
	assert(kate._villages_dish_short == before + dofile("keeper.lua").MIN_DISHES - 5, tostring(kate._villages_dish_short))
	assert(supply.held_dishes(kate) == 5)
	poss.take_held(kate, "mcl_mobitems:cooked_beef", 5)
	supply.update_wants(kate, chests)
	assert(kate._villages_dish_short == before)
end
-- The shortfall is split among the dishes it knows, not laid whole on each: on each, a
-- shortfall of 28 read 112 bread at market (lv_pair e8).
do
	local poss = dofile("possessions.lua")
	kate._villages_known_dishes = {["mcl_mobitems:cooked_beef"] = day, ["mcl_mobitems:cooked_porkchop"] = day}
	supply.update_wants(kate, chests)
	local short, known = kate._villages_dish_short, 0
	for _ in pairs(kate._villages_dish_wants) do known = known + 1 end
	assert(known == 2 and short and short > 1, tostring(short))
	local split = poss.assess(kate)
	local share = math.ceil(short / 2)
	for _, item in ipairs({"mcl_mobitems:cooked_beef", "mcl_mobitems:cooked_porkchop"}) do
		local want = kate._villages_dish_wants[item]
		assert(split.needs[item] == want + share, item .. " " .. tostring(split.needs[item]))
	end
	kate._villages_known_dishes = {["mcl_mobitems:cooked_beef"] = day}
	supply.update_wants(kate, chests)
end
-- Its bids (ticket 46b): the cheapest ask it heard for a dish, where over its plate cap;
-- raw food, a category's news, its own and asks under the cap left out.
assert(kate._villages_dish_bids == nil, "nothing heard")
local dinner_mod = dofile("dinner.lua")
kate._villages_plate_cost = 0.5
local cap = 0.5 * dinner_mod.MARGIN_MAX
kate._villages_market_news = {
	{kind = "has", item = "mcl_mobitems:cooked_beef", who = "b1", price = 1.4, heard = 0},
	{kind = "has", item = "mcl_mobitems:cooked_beef", who = "b2", price = 1.18, heard = 0},
	{kind = "has", item = "mcl_fishing:fish_cooked", who = "b1", price = cap - 0.1, heard = 0},
	{kind = "has", item = "mcl_mobitems:beef", who = "b1", price = 3, heard = 0},
	{kind = "needs", item = "mcl_farming:bread", who = "b1", price = 3, heard = 0},
	{kind = "has", item = "mcl_farming:bread", who = kate._id, price = 3, heard = 0}}
supply.update_wants(kate, chests)
local bids = kate._villages_dish_bids
assert(bids and math.abs(bids["mcl_mobitems:cooked_beef"] - 1.18) < 1e-9, "the cheapest ask")
assert(not bids["mcl_fishing:fish_cooked"] and not bids["mcl_mobitems:beef"] and not bids["mcl_farming:bread"])
assert(math.abs(dofile("possessions.lua").assess(kate).value("mcl_mobitems:cooked_beef") - 1.18) < 1e-9)
-- Errands by taste (ticket 49): a wanted dish with a seller, that its guests are no more
-- tired of than bread, goes before a farm fetch; one they ate all week does not.
do
	local fish, bread = "mcl_fishing:fish_cooked", "mcl_farming:bread"
	kate._villages_dish_wants = {[fish] = 3}
	kate._villages_market_news = {{kind = "has", item = fish, who = "b1", price = 1, count = 4, heard = 0},
		{kind = "has", item = "mcl_mobitems:beef", who = "b1", price = 1, count = 4, heard = 0}}
	kate._villages_served_dishes = {[day] = {[bread] = 10}}
	local dish, dish_taste, bread_taste = supply.preferred_dish(kate, now)
	assert(dish == fish and dish_taste > bread_taste, tostring(dish))
	-- Its guests ate fish all week, bread hardly: the farm first.
	kate._villages_served_dishes = {[day] = {[fish] = 10, [bread] = 1}}
	assert(supply.preferred_dish(kate, now) == nil)
	-- Preferred once: not again for a while, should the trip fail.
	kate._villages_served_dishes = {[day] = {[bread] = 10}}
	kate._villages_preferred = {[fish] = now + 600}
	assert(supply.preferred_dish(kate, now) == nil)
	assert(supply.preferred_dish(kate, now + 601) == fish)
	-- None wanted, nor short: nothing.
	kate._villages_preferred, kate._villages_dish_wants = nil, {[fish] = 0}
	assert(supply.preferred_dish(kate, now) == nil)
	kate._villages_served_dishes, kate._villages_dish_wants = nil, nil
end
kate._villages_market_news, kate._villages_plate_cost, kate._villages_dish_bids = nil, nil, nil
kate._villages_dinner, kate._villages_known_dishes, kate._villages_dish_wants, kate._villages_dish_short = nil, nil, nil, nil
inventories[key(pantry_chest)]["mcl_fishing:fish_cooked"] = nil
-- Not cooking until it is at the jukebox working.
inventories[key(pantry_chest)]["mcl_farming:potato_item"] = 3
kate.order = nil
now = now + supply.COOK_SECONDS
supply.step(kate, now)
assert(inventories[key(pantry_chest)]["mcl_farming:potato_item"] == 3)
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
assert(#filled == 1 and inventories[key(another)]["mcl_farming:bread"] == 9)


-- Cooked beef and fish it bought from the butcher (ticket 11e, 15) go from its belongings
-- to the pantry.
do
	local buyer = {_id = "kate2", _villages_keeper = true,
		_villages_belongings = {["mcl_mobitems:cooked_beef"] = 2, ["mcl_fishing:fish_cooked"] = 1}}
	local before = pantry.count(chests, "mcl_mobitems:cooked_beef")
	assert(supply.shelve(buyer, chests) == 3)
	assert(pantry.count(chests, "mcl_mobitems:cooked_beef") == before + 2)
	assert(dofile("possessions.lua").count(buyer, "mcl_mobitems:cooked_beef") == 0)
	-- It pays for them from the pantry: topped up to FLOAT, no further, as far as the pantry goes.
	local possessions = dofile("possessions.lua")
	local had = pantry.count(chests, "mcl_core:emerald")
	pantry.put(chests, "mcl_core:emerald", 600)
	local purse = {_id = "kate3", _villages_keeper = true, _villages_belongings = {["mcl_core:emerald"] = 10}}
	assert(supply.float(purse, chests) == supply.FLOAT - 10 and possessions.emeralds(purse) == supply.FLOAT)
	assert(pantry.count(chests, "mcl_core:emerald") == had + 600 - (supply.FLOAT - 10))
	assert(supply.float(purse, chests) == 0, "already full")
end

-- The keeper eats from its own pantry, free, once a day when hungry (2026-11-13: it
-- never sat down to dinner and starved all run): dishes first, raw food only starving.
do
	inventories[key(pantry_chest)] = {["mcl_farming:potato_item_baked"] = 3, ["mcl_farming:carrot_item"] = 8}
	local cook = {_id = "cook", _villages_food = 2}
	local eaten = supply.feed_keeper(cook, chests)
	assert(#eaten == 2 and cook._villages_food == 10 and cook._villages_dined_day == day, "two baked potatoes")
	assert(inventories[key(pantry_chest)]["mcl_farming:potato_item_baked"] == 1 and inventories[key(pantry_chest)]["mcl_farming:carrot_item"] == 8)
	cook._villages_food = 0
	assert(#supply.feed_keeper(cook, chests) == 0, "once a day")
	day = day + 1
	inventories[key(pantry_chest)] = {["mcl_farming:carrot_item"] = 8}
	cook._villages_food = 6
	assert(#supply.feed_keeper(cook, chests) == 0, "no dish, and hungry is not starving")
	cook._villages_food = 0
	eaten = supply.feed_keeper(cook, chests)
	assert(#eaten == 8 and cook._villages_food == 8, "starving: all eight carrots, short of above EAT_AT")
	day = day + 1
	cook._villages_food = 12
	assert(#supply.feed_keeper(cook, chests) == 0, "fed")
end

-- A few of every dish it heard offered (ticket 35): up to MIN_DISHES in the pantry, 0 when
-- it has enough; none for a dish forgotten. The baked potato and cooked beef too (ticket
-- 39g): it has no fixed inputs, and the butcher bakes.
do
	local keeper = dofile("keeper.lua")
	local CHICKEN, SALMON, PIE = "mcl_mobitems:cooked_chicken", "mcl_fishing:salmon_cooked", "mcl_farming:pumpkin_pie"
	local knower = {_id = "kn", _villages_keeper = true, _villages_known_dishes = {
		[CHICKEN] = day, [SALMON] = day, [PIE] = day - keeper.KNOWN_DAYS,
		["mcl_mobitems:cooked_beef"] = day, ["mcl_farming:potato_item_baked"] = day}}
	pantry.put(chests, SALMON, 5)
	local wants = supply.dish_wants(knower, chests, day)
	assert(wants[CHICKEN] == keeper.MIN_DISHES and wants[SALMON] == 0, tostring(wants[SALMON]))
	assert(wants[PIE] == nil and knower._villages_known_dishes[PIE] == nil, "forgotten after a week")
	assert(wants["mcl_mobitems:cooked_beef"] == keeper.MIN_DISHES and wants["mcl_farming:potato_item_baked"] == keeper.MIN_DISHES)
	-- A dish off the old menu counts as a meal, is shelved, and the keeper may eat it.
	local meals = supply.meals(chests)
	pantry.put(chests, CHICKEN, 2)
	assert(supply.meals(chests) == meals + 2)
	local buyer = {_id = "kn2", _villages_keeper = true, _villages_belongings = {[CHICKEN] = 1}}
	assert(supply.shelve(buyer, chests) == 1 and pantry.count(chests, CHICKEN) == 3)
	assert(supply.dish_wants(knower, chests, day)[CHICKEN] == 0)
end

-- The plate cost (ticket 39b): the average cost of the dishes the pantry holds, raw food
-- left out (ticket 45: raw potatoes are no dish), at what each cost the keeper.
do
	local plater = {_id = "plater", _villages_keeper = true,
		_villages_dish_cost = {["mcl_farming:potato_item_baked"] = 1, ["mcl_fishing:fish_cooked"] = 5}}
	inventories[key(pantry_chest)] = {["mcl_farming:potato_item"] = 12 + RESERVE, ["mcl_farming:potato_item_baked"] = 6,
		["mcl_fishing:fish_cooked"] = 2}
	local counts = supply.dish_counts(chests)
	assert(counts["mcl_farming:potato_item_baked"] == 6 and counts["mcl_fishing:fish_cooked"] == 2)
	assert(counts["mcl_farming:potato_item"] == nil)
	assert(math.abs(supply.price_plate(plater, chests) - (6 * 1 + 2 * 5) / 8) < 1e-9)
	assert(plater._villages_plate_cost == 2)
	-- An empty pantry keeps the last plate cost.
	inventories[key(pantry_chest)] = {}
	assert(supply.price_plate(plater, chests) == nil and plater._villages_plate_cost == 2)
end

-- Raw potatoes it fetches only for the raw plates' reserve (ticket 45): it bakes none, so
-- neither tonight's demand, bread on the way nor dishes heard offered or held change that.
do
	local fetcher = {_id = "fe", _villages_keeper = true}
	inventories[key(pantry_chest)] = {}
	assert(supply.potatoes_wanted(fetcher, chests) == RESERVE)
	inventories[key(pantry_chest)] = {["mcl_farming:potato_item"] = RESERVE - 5}
	assert(supply.potatoes_wanted(fetcher, chests) == 5)
	inventories[key(pantry_chest)] = {["mcl_farming:potato_item"] = RESERVE + 30}
	assert(supply.potatoes_wanted(fetcher, chests) == 0)
	assert(supply.potatoes_wanted(fetcher, nil) == math.huge)
	inventories[key(pantry_chest)] = {}
end

-- Ticket 44: its float tops up from the purse in its pouch when the pantry has no money.
do
	local possessions = dofile("possessions.lua")
	local stock = dofile("farm_stock.lua")
	inventories[key(pantry_chest)] = {}
	local kip = {_id = "kip44", _villages_keeper = true, _villages_belongings = {["mcl_core:emerald"] = 5}}
	stock.add(kip, "mcl_core:emerald", 900)
	assert(supply.float(kip, chests) == supply.FLOAT - 5)
	assert(possessions.emeralds(kip) == supply.FLOAT and stock.count(kip, "mcl_core:emerald") == 900 - (supply.FLOAT - 5))
	-- The pantry's money first.
	local kit = {_id = "kit44", _villages_keeper = true, _villages_belongings = {}}
	stock.add(kit, "mcl_core:emerald", 900)
	pantry.put(chests, "mcl_core:emerald", 10)
	assert(supply.float(kit, chests) == supply.FLOAT)
	assert(pantry.count(chests, "mcl_core:emerald") == 0 and stock.count(kit, "mcl_core:emerald") == 900 - (supply.FLOAT - 10))
	inventories[key(pantry_chest)] = {}
end

print("keeper_supply.lua: ok")
