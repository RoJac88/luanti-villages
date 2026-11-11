-- What things are worth to one villager (docs/villager-economy-design.md, ticket 3). Pure:
-- it reads trade_tables.lua and what the caller passes, and touches no engine state.
--
-- Base prices, in emeralds, come from VoxeLibre's own trade tables. A villager buying N
-- of an item for E emeralds prices it at E/N; one selling N for E emeralds (and perhaps
-- a second ingredient, priced where known) at the same. An item both bought and sold
-- somewhere is priced at the geometric mean of the two, since vanilla buys cheap and
-- sells dear. Items in no table (logs, cobble, seeds) are priced in HAND_PRICES,
-- consistent with what crafting makes of them. Every price is then multiplied by SCALE
-- (ticket 11h): at vanilla's prices an emerald is 32 sticks, so a sale of a few cheap
-- goods came to a fraction of one and could not be paid. Every emerald amount in the
-- mod scales with it; a stick is worth 2.
--
-- A profession's inputs are what its trade table buys, less what it makes itself (a
-- farmer buys crops from players but grows them); its outputs are what it sells. That is
-- the dependency graph between professions.
--
-- A crafting profession (recipes.lua) also wants what its recipes take, CRAFT_BATCH
-- crafts' worth, and coal for those that smelt; what it makes counts among its outputs.
-- Some needs are for a purpose rather than an item (goods.lua, ticket 15): food by its
-- points, fuel by burn seconds (coal, charcoal, and logs, planks and sticks it does not
-- need as such), logs and planks of any species. Such a need and its spare are reckoned
-- on the category, and the need is listed under every member it could take, in that
-- member's count (`group` names the category), so any of them fills it.
--
-- assess() turns one villager's state into targets (what it wants to hold), needs,
-- surplus and a value for any item: base price times urgency, which rises from 1 toward
-- 3 as a need nears its whole target and falls toward 0.5 the further a holding runs
-- past its target and reserve.
local core = minetest
local tables = dofile(core.get_modpath("living_villages") .. "/trade_tables.lua")
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local recipes = dofile(core.get_modpath("living_villages") .. "/recipes.lua")

local EMERALD = "mcl_core:emerald"
-- Emeralds now per emerald at vanilla's prices.
local SCALE = 64
-- A dinner at the tavern, in emeralds: what a villager pays, what a meal's worth of food
-- earns its producer, and the default for a player. Near a loaf's worth (SCALE / 6) and
-- a little more for the keeper's cooking; at a vanilla emerald (64) it took six loaves'
-- worth for one loaf, and money piled up in the pantry.
local DINNER = 18
-- Days of food a villager wants to have by it.
local FOOD_DAYS = 3
-- The most of one input a villager wants at once.
local INPUT_CAP = 32
-- Of a target, this share is never sold.
local RESERVE_SHARE = 0.25
local MAX_URGENCY, MIN_URGENCY = 3, 0.5
-- Crafts' worth of each recipe input it wants to hold, and lumps of fuel.
local CRAFT_BATCH = 4
local FUEL_BATCH = 4
local COAL = "mcl_core:coal_lump"

local HAND_PRICES = {
	-- A log is four planks, a plank two sticks (the fletcher buys 32 sticks for one).
	["mcl_core:tree"] = 0.25,
	["mcl_core:wood"] = 0.0625,
	["mcl_core:sapling"] = 0.05,
	-- A little under stone, which the mason buys at 20 for one.
	["mcl_core:cobble"] = 0.04,
	-- Coal's price: the smiths take it in coal's place.
	["mcl_core:charcoal_lump"] = 1 / 15,
	-- Sugar cane makes paper one for one (the librarian buys 24 paper for one).
	["mcl_core:reeds"] = 1 / 24,
	["mcl_farming:wheat_seeds"] = 0.01,
	["mcl_farming:beetroot_seeds"] = 0.01,
	-- Prepared foods: what goes in, and a little for the cooking.
	["mcl_farming:potato_item_baked"] = 0.06,
	-- The butcher's cooked beef, at its cooked porkchop's price (ticket 11e).
	["mcl_mobitems:cooked_beef"] = 0.2,
	["mcl_mushrooms:mushroom_brown"] = 0.05,
	["mcl_mushrooms:mushroom_red"] = 0.05,
	-- A flower makes a dye (12 for one at the shepherd).
	["mcl_flowers:poppy"] = 1 / 12,
	["mcl_flowers:dandelion"] = 1 / 12,
	["mcl_flowers:tulip_red"] = 1 / 12,
	["mcl_flowers:allium"] = 1 / 12,
	["mcl_flowers:azure_bluet"] = 1 / 12,
	["mcl_flowers:blue_orchid"] = 1 / 12,
	["mcl_flowers:oxeye_daisy"] = 1 / 12,
	["mcl_flowers:tulip_orange"] = 1 / 12,
	["mcl_flowers:tulip_white"] = 1 / 12,
	["mcl_flowers:tulip_pink"] = 1 / 12,
	["mcl_flowers:cornflower"] = 1 / 12,
}
-- Every single-trunk species' logs and saplings at oak's prices (labour.lua grows them).
for _, species in ipairs({"acacia", "spruce", "birch", "jungle"}) do
	HAND_PRICES["mcl_core:" .. species .. "tree"] = HAND_PRICES["mcl_core:tree"]
	HAND_PRICES["mcl_core:" .. species .. "sapling"] = HAND_PRICES["mcl_core:sapling"]
end

-- What a profession makes for itself, so never needs to buy.
local MAKES = {
	farmer = {
		["mcl_farming:wheat_item"] = true, ["mcl_farming:potato_item"] = true, ["mcl_farming:carrot_item"] = true,
		["mcl_farming:beetroot_item"] = true, ["mcl_farming:pumpkin"] = true, ["mcl_farming:melon"] = true,
	},
	fisherman = {
		["mcl_fishing:fish_raw"] = true, ["mcl_fishing:salmon_raw"] = true,
		["mcl_fishing:clownfish_raw"] = true, ["mcl_fishing:pufferfish_raw"] = true,
	},
	shepherd = {},
	-- Its herd's (herd.lua, ticket 11e).
	leatherworker = {["mcl_mobitems:leather"] = true, ["mcl_mobitems:beef"] = true},
}
for name in pairs({white = 1, brown = 1, black = 1, grey = 1}) do MAKES.shepherd["mcl_wool:" .. name] = true end

-- Roles this mod adds, which have no vanilla table of their own.
local ROLES = {
	keeper = {
		-- Cooked beef, from the butcher, is its second dish (ticket 11e).
		inputs = {["mcl_farming:wheat_item"] = 9, ["mcl_farming:potato_item"] = 6, ["mcl_fishing:fish_raw"] = 6,
			["mcl_mobitems:cooked_beef"] = 6},
		outputs = {
			["mcl_farming:bread"] = true, ["mcl_farming:potato_item_baked"] = true, ["mcl_fishing:fish_cooked"] = true,
			["mcl_mushrooms:mushroom_stew"] = true, ["mcl_farming:pumpkin_pie"] = true,
		},
	},
}

-- Small wants a villager has for its own sake, one or two picked by its _id.
local PREFERENCES = {
	"mcl_flowers:poppy", "mcl_flowers:dandelion", "mcl_books:book", "mcl_cake:cake",
	"mcl_core:apple", "mcl_farming:cookie", "mcl_wool:white", "mcl_mobitems:leather",
}

local M = {
	EMERALD = EMERALD, SCALE = SCALE, DINNER = DINNER, FOOD_DAYS = FOOD_DAYS, MAX_URGENCY = MAX_URGENCY, MIN_URGENCY = MIN_URGENCY,
	PREFERENCES = PREFERENCES, COAL = COAL, version = tables.version,
}

local function mean(spec) return (spec.min + spec.max) / 2 end

-- Base prices.

local prices
local function derive()
	local bought, sold = {}, {}
	local function note(list, item, price)
		list[item] = list[item] or {}
		table.insert(list[item], price)
	end
	local compound = {}
	for _, profession in pairs(tables.professions) do
		for _, trade in ipairs(profession.trades) do
			local wanted, offered = trade.wanted, trade.offered[1]
			if offered.item == EMERALD and #wanted == 1 then
				note(bought, wanted[1].item, mean(offered) / mean(wanted[1]))
			elseif wanted[1].item == EMERALD and offered.item ~= EMERALD then
				if #wanted == 1 then
					note(sold, offered.item, mean(wanted[1]) / mean(offered))
				else
					table.insert(compound, trade)
				end
			end
		end
	end
	local function average(list)
		local total = 0
		for _, p in ipairs(list) do total = total + p end
		return total / #list
	end
	local function combine(item)
		local b, s = bought[item], sold[item]
		if b and s then return math.sqrt(average(b) * average(s)) end
		return (b and average(b)) or (s and average(s))
	end
	local result = {}
	for item, price in pairs(HAND_PRICES) do result[item] = price end
	for item in pairs(bought) do result[item] = combine(item) end
	for item in pairs(sold) do result[item] = combine(item) end
	-- Emeralds and a second ingredient: the second at its own price, where known.
	for _, trade in ipairs(compound) do
		local extra = trade.wanted[2]
		local extra_price = result[extra.item]
		if extra_price then
			note(sold, trade.offered[1].item,
				(mean(trade.wanted[1]) + mean(extra) * extra_price) / mean(trade.offered[1]))
			result[trade.offered[1].item] = combine(trade.offered[1].item)
		end
	end
	-- Every species' logs and planks, at oak's where nothing else prices them (ticket 15:
	-- a need for logs takes any species).
	for log, planks in pairs(goods.SPECIES) do
		result[log] = result[log] or result["mcl_core:tree"]
		result[planks] = result[planks] or result["mcl_core:wood"]
	end
	for item, price in pairs(result) do result[item] = price * SCALE end
	result[EMERALD] = 1
	return result
end

-- An item's base price in emeralds, or nil if nothing prices it.
function M.price(item)
	prices = prices or derive()
	return prices[item]
end

-- The dependency graph.

-- What a profession buys to work, as item to the batch it wants, up to max_tier.
function M.inputs(profession, max_tier)
	local role = ROLES[profession]
	if role then return role.inputs end
	local found = {}
	local entry = tables.professions[profession]
	if not entry then return found end
	local makes = MAKES[profession] or {}
	for _, trade in ipairs(entry.trades) do
		local offered = trade.offered[1]
		if trade.tier <= (max_tier or 5) and offered.item == EMERALD and #trade.wanted == 1 then
			local item = trade.wanted[1].item
			if not makes[item] then found[item] = math.min(math.max(found[item] or 0, trade.wanted[1].min), INPUT_CAP) end
		end
	end
	for _, recipe in ipairs(recipes[profession] or {}) do
		for _, input in ipairs(recipe.from) do
			found[input[1]] = math.max(found[input[1]] or 0, math.min(input[2] * CRAFT_BATCH, INPUT_CAP))
		end
		if recipe.fuel then found[COAL] = math.max(found[COAL] or 0, FUEL_BATCH) end
	end
	return found
end

-- What a profession makes or sells, as a set, up to max_tier.
function M.outputs(profession, max_tier)
	local role = ROLES[profession]
	if role then return role.outputs end
	local found = {}
	for item in pairs(MAKES[profession] or {}) do found[item] = true end
	for _, recipe in ipairs(recipes[profession] or {}) do found[recipe.makes] = true end
	local entry = tables.professions[profession]
	for _, trade in ipairs(entry and entry.trades or {}) do
		local offered = trade.offered[1]
		if trade.tier <= (max_tier or 5) and offered.item ~= EMERALD then found[offered.item] = true end
	end
	return found
end

-- The professions whose outputs include the item, sorted.
function M.producers(item)
	local found = {}
	local names = {}
	for name in pairs(tables.professions) do names[#names + 1] = name end
	for name in pairs(ROLES) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		if M.outputs(name)[item] then found[#found + 1] = name end
	end
	return found
end

-- One villager.

-- From 1 with no need toward MAX_URGENCY as the need nears the whole target; below 1
-- toward MIN_URGENCY as the holding runs past the target and its reserve.
function M.urgency(held, target)
	if target > 0 and held < target then
		return 1 + (MAX_URGENCY - 1) * (target - held) / target
	end
	local keep = target + math.ceil(target * RESERVE_SHARE)
	if held <= keep then return 1 end
	return MIN_URGENCY + (1 - MIN_URGENCY) * keep / held
end

local function roll(id, salt, n)
	local text = tostring(id) .. salt
	local sum = 0
	for i = 1, #text do sum = sum + text:byte(i) * i end
	return sum % n
end

function M.preferences(id)
	local first = roll(id, "a", #PREFERENCES) + 1
	local chosen = {[PREFERENCES[first]] = 1 + roll(id, "c", 2)}
	if roll(id, "b", 2) == 1 then
		local second = (first + roll(id, "d", #PREFERENCES - 1)) % #PREFERENCES + 1
		chosen[PREFERENCES[second]] = 1
	end
	return chosen
end

-- input: {id, profession, max_tier, held = {item = count}, food_points, hunger_per_day,
-- foods = {item = points} (food.POINTS), extra = {item = count} (a Builder's missing
-- materials, goods that wear out), worth = {item = emeralds} (the most an item is worth
-- to it whatever its need: what a good that wears out brings over its life, wants.lua),
-- least = {item = emeralds} (the least it will take for an item: a peddler's stock is
-- worth what it paid, labour.lua, ticket 12), prices = {item = factor} (its own
-- multiplier on the base price, prices.lua, ticket 13)}.
-- Returns {targets, needs, surplus, value = function(item), urgency = function(item)}:
-- urgency is the need's own (M.urgency), before `worth` caps the value, so a good that
-- wears out, wanted whole, is still as urgent as any other need (trade_trips.lua).
function M.assess(input)
	local targets, wanted = {}, {}
	local function want(item, count)
		if count > (targets[item] or 0) then targets[item] = count end
	end
	-- A category's amount, in its units: alternatives, so the largest ask stands.
	local function want_category(category, amount)
		if amount > (wanted[category] or 0) then wanted[category] = amount end
	end
	-- Food: enough points for FOOD_DAYS, from any food.
	local food_need = math.max((input.hunger_per_day or 0) * FOOD_DAYS - (input.food_points or 0), 0)
	if food_need > 0 then want_category("food", food_need) end
	for item, batch in pairs(M.inputs(input.profession, input.max_tier)) do
		local category = goods.target_category(item)
		if category then want_category(category, batch * goods.units(category, item)) else want(item, batch) end
	end
	for item, count in pairs(M.preferences(input.id)) do want(item, count) end
	for item, count in pairs(input.extra or {}) do targets[item] = (targets[item] or 0) + count end

	local raw = input.held or {}
	-- The category an item counts toward: none when it is wanted for itself.
	local function category_of(item)
		if targets[item] then return nil end
		return goods.active(item, wanted)
	end
	local held_units = {}
	for item, count in pairs(raw) do
		local category = category_of(item)
		if category then held_units[category] = (held_units[category] or 0) + count * goods.units(category, item) end
	end

	local needs, surplus, group = {}, {}, {}
	for item, target in pairs(targets) do
		local short = target - (raw[item] or 0)
		if short > 0 then needs[item] = short end
	end
	local categories = {}
	for category, amount in pairs(wanted) do
		local have = held_units[category] or 0
		categories[category] = {target = amount, held = have, short = math.max(amount - have, 0)}
		if amount > have then
			for item, units in pairs(goods.CATEGORIES[category]) do
				if M.price(item) and category_of(item) == category then
					needs[item] = math.ceil((amount - have) / units)
					group[item] = category
				end
			end
		end
	end
	-- Spare: past the target and its reserve; for a category, the members held most of.
	local members = {}
	for item, count in pairs(raw) do
		if item ~= EMERALD then
			local category = category_of(item)
			if category then
				members[category] = members[category] or {}
				table.insert(members[category], item)
			else
				local target = targets[item] or 0
				local spare = count - target - math.ceil(target * RESERVE_SHARE)
				if spare > 0 then surplus[item] = spare end
			end
		end
	end
	for category, list in pairs(members) do
		local amount = wanted[category] or 0
		local spare_units = (held_units[category] or 0) - amount - math.ceil(amount * RESERVE_SHARE)
		table.sort(list, function(a, b)
			if raw[a] ~= raw[b] then return raw[a] > raw[b] end
			return a < b
		end)
		for _, item in ipairs(list) do
			local units = goods.units(category, item)
			local spare = math.min(raw[item], math.floor(spare_units / units))
			if spare > 0 then
				surplus[item] = spare
				spare_units = spare_units - spare * units
			end
		end
	end

	local function urgency(item)
		local category = category_of(item)
		if category then return M.urgency(held_units[category] or 0, wanted[category] or 0) end
		return M.urgency(raw[item] or 0, targets[item] or 0)
	end
	local function value(item)
		local price = M.price(item)
		if not price then return nil end
		if item == EMERALD then return 1 end
		local factor = input.prices and input.prices[item] or 1
		local value = price * factor * urgency(item)
		local most = input.worth and input.worth[item]
		if most then value = math.min(value, most) end
		local least = input.least and input.least[item]
		return least and math.max(value, least) or value
	end
	return {targets = targets, needs = needs, surplus = surplus, value = value, urgency = urgency,
		categories = categories, group = group}
end

-- The items with the largest need or surplus first, by value, for news and the inspector.
function M.top(list, value, n)
	local items = {}
	for item, count in pairs(list) do items[#items + 1] = {item = item, count = count, worth = count * (value(item) or 0)} end
	table.sort(items, function(a, b)
		if a.worth ~= b.worth then return a.worth > b.worth end
		return a.item < b.item
	end)
	local out = {}
	for i = 1, math.min(n or #items, #items) do out[i] = items[i] end
	return out
end

return M
