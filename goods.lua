-- Goods by purpose (docs/villager-economy-design.md, ticket 15): the categories a need
-- can be for, where any member serves, and the few goods a job turns into another when
-- it sells to a villager. Data and pure functions; it reads only what it is handed.
--
-- Categories. A need for food is for food points, and any food gives them; a need for
-- fuel is for burn seconds; a need for logs or planks takes any species. A category's
-- amount is in its units: an item gives `units` of them. ledger.assess reckons a need
-- and its spare on the category, and lists the need under every member in that member's
-- own count, so a seller of any of them can fill it.
--
-- Every coal need today comes from smelting (recipes' fuel, the smiths' trade tables),
-- so coal and charcoal are fuel. So is the dried kelp block vanilla's butcher buys for its
-- smoker: wanted as itself, nobody made it, and the butcher's 10 crowded its news while
-- the unemployed held some 30 charcoal each (ColonyFood, 2026-11-14). Logs, planks and sticks burn too, but count as fuel only
-- for a villager that does not need them as such (M.active).
--
-- Conversions. When a villager sells to a villager (exchange.lua), a job can hand over a
-- good it makes from its spare stock on the spot: instantly and for free, and sparingly,
-- a short list a job. A few are anyone's (ANYONE): a lily of the valley or bone meal (a
-- farmer's spare, farmer.lua) sells as the white dye it crafts into, one for one, for the
-- shepherd to dye grey wool white (19h). None is for food: the butcher cooks (recipes.lua). Player trades
-- convert nothing. Each gives `ratio` of its product per source, `takes` sources at a
-- time (1 unless set): two wool make three carpets.
local core = minetest
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")

local COAL, CHARCOAL, STICK = "mcl_core:coal_lump", "mcl_core:charcoal_lump", "mcl_core:stick"
local KELP_BLOCK = "mcl_ocean:dried_kelp_block"
local STRING = "mcl_mobitems:string"

-- Log to the planks it splits into.
local SPECIES = {
	["mcl_core:tree"] = "mcl_core:wood",
	["mcl_core:birchtree"] = "mcl_core:birchwood",
	["mcl_core:sprucetree"] = "mcl_core:sprucewood",
	["mcl_core:jungletree"] = "mcl_core:junglewood",
	["mcl_core:acaciatree"] = "mcl_core:acaciawood",
	["mcl_core:darktree"] = "mcl_core:darkwood",
	["mcl_mangrove:mangrove_tree"] = "mcl_mangrove:mangrove_wood",
	["mcl_cherry_blossom:cherrytree"] = "mcl_cherry_blossom:cherrywood",
}
local WOOL_COLOURS = {"white", "grey", "silver", "black", "red", "yellow", "green", "cyan", "blue", "magenta",
	"orange", "purple", "brown", "pink", "lime", "light_blue"}
-- Burn seconds, as VoxeLibre's furnaces take them.
local BURN = {[COAL] = 80, [CHARCOAL] = 80, [STICK] = 5, [KELP_BLOCK] = 200}

local categories = {food = {}, fuel = {}, log = {}, planks = {}}
for item, points in pairs(food.POINTS) do categories.food[item] = points end
for item, seconds in pairs(BURN) do categories.fuel[item] = seconds end
for log, planks in pairs(SPECIES) do
	categories.log[log], categories.planks[planks] = 1, 1
	categories.fuel[log], categories.fuel[planks] = 15, 15
end
-- Which category a member belongs to first, when it is in two (a log is fuel too).
local ORDER = {"log", "planks", "food", "fuel"}

local conversions = {
	shepherd = {},
	woodcutter = {},
	mason = {{from = "mcl_core:stone", to = "mcl_core:stonebrickcarved", ratio = 1}},
}
for _, colour in ipairs(WOOL_COLOURS) do
	table.insert(conversions.shepherd, {from = "mcl_wool:" .. colour, to = STRING, ratio = 4})
	-- Two wool make three carpets (ticket 19c): `takes` sources at a time.
	table.insert(conversions.shepherd, {from = "mcl_wool:" .. colour, to = "mcl_wool:" .. colour .. "_carpet",
		ratio = 1.5, takes = 2})
end
for log, planks in pairs(SPECIES) do table.insert(conversions.woodcutter, {from = log, to = planks, ratio = 4}) end
local ANYONE = {
	{from = "mcl_bone_meal:bone_meal", to = "mcl_dye:white", ratio = 1},
	{from = "mcl_flowers:lily_of_the_valley", to = "mcl_dye:white", ratio = 1},
}
for _, list in pairs(conversions) do
	table.sort(list, function(a, b) return a.from < b.from end)
end

local M = {CATEGORIES = categories, ORDER = ORDER, SPECIES = SPECIES, CONVERSIONS = conversions, BURN = BURN,
	COAL = COAL, CHARCOAL = CHARCOAL, STRING = STRING}

-- How many of a category's units one item gives, or nil if it is no member.
function M.units(category, item)
	local members = categories[category]
	return members and members[item]
end

-- The category a target item names, so a need for it is a need for the category: coal,
-- charcoal and kelp blocks are fuel, any log or planks is logs or planks. Food targets are set as a
-- category already (ledger.assess). Nil for an item wanted for itself.
function M.target_category(item)
	if item == COAL or item == CHARCOAL or item == KELP_BLOCK then return "fuel" end
	if categories.log[item] then return "log" end
	if categories.planks[item] then return "planks" end
	return nil
end

-- The category an item counts toward for a villager with these category targets
-- ({category = amount}): the first in ORDER that holds it and is wanted. Nil for none.
function M.active(item, targets)
	for _, category in ipairs(ORDER) do
		if categories[category][item] and (targets[category] or 0) > 0 then return category end
	end
	return nil
end

-- Whether `item` fills a "needs" news entry: the entry's own item, or any member of its
-- category (entry.group).
function M.fills(entry, item)
	if entry.item == item then return true end
	return entry.group ~= nil and categories[entry.group] ~= nil and categories[entry.group][item] ~= nil
end

-- What a villager's job turns into another at a sale: a list of {from, to, ratio}. A
-- profession's, or a labourer's activity's (labour.lua's `_villages_labour`).
function M.conversions(villager)
	local list = conversions[villager._profession]
	if not list then
		local labour = villager._villages_labour
		list = labour and conversions[labour.activity] or {}
	end
	local out = {}
	for _, conversion in ipairs(list) do out[#out + 1] = conversion end
	for _, conversion in ipairs(ANYONE) do out[#out + 1] = conversion end
	return out
end

return M
