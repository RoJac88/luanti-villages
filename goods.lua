-- Goods by purpose (docs/villager-economy-design.md, ticket 15): the categories a need
-- can be for, where any member serves, and the few goods a job turns into another when
-- it sells to a villager. Data and pure functions; it reads only what it is handed.
--
-- Categories. A need for food is for food points, and any food gives them; a need for
-- fuel is for burn seconds; a need for logs or planks takes any species, and one for
-- wool any colour (a Builder's for the red beds it makes, builder_market.lua), and one for
-- stone either stone or cobble (an alchemist's, ticket 20). A category's
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
-- shepherd to dye grey wool white (19h); a bone (a forager picks up a skeleton's) as the
-- three bone meal or three white dye it makes, whichever the buyer wants; a poppy or a
-- red tulip as a red dye, for the Builder's red beds (19i). None is for food: the butcher cooks (recipes.lua). Player trades
-- convert nothing. Each gives `ratio` of its product per source, `takes` sources at a
-- time (1 unless set): two wool make three carpets. One with `reserve` spends only the
-- sources held past that many: the alchemist's gold (ticket 20).
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

local categories = {food = {}, fuel = {}, log = {}, planks = {}, wool = {}, stone = {}, flower = {}, carpet = {}}
for item, points in pairs(food.POINTS) do categories.food[item] = points end
for item, seconds in pairs(BURN) do categories.fuel[item] = seconds end
for log, planks in pairs(SPECIES) do
	categories.log[log], categories.planks[planks] = 1, 1
	categories.fuel[log], categories.fuel[planks] = 15, 15
end
for _, colour in ipairs(WOOL_COLOURS) do categories.wool["mcl_wool:" .. colour] = 1 end
-- Stone or cobble, either for an alchemist's iron nuggets (ticket 20). Like wool, no job's
-- target category: a mason's stone and a tool smith's cobble stay needs for that very item.
categories.stone["mcl_core:stone"], categories.stone["mcl_core:cobble"] = 1, 1
-- Any flower, for a comfort or the flower in a pot (comforts.lua, ticket 23b): like wool
-- and stone, no job's target category. Its members share one reference price.
for _, flower in ipairs({"poppy", "dandelion", "tulip_red", "allium", "azure_bluet", "blue_orchid", "oxeye_daisy",
	"tulip_orange", "tulip_white", "tulip_pink", "cornflower", "lily_of_the_valley"}) do
	categories.flower["mcl_flowers:" .. flower] = 1
end
-- Any carpet, for a comfort (comforts.lua, ticket 24), so a shepherd's grey, black or
-- brown wool sells as carpet as well as its white. Like flowers, no job's target category.
for _, colour in ipairs(WOOL_COLOURS) do categories.carpet["mcl_wool:" .. colour .. "_carpet"] = 1 end
-- Which category a member belongs to first, when it is in two (a log is fuel too).
local ORDER = {"log", "planks", "wool", "stone", "flower", "carpet", "food", "fuel"}

local conversions = {
	shepherd = {},
	woodcutter = {},
	mason = {{from = "mcl_core:stone", to = "mcl_core:stonebrickcarved", ratio = 1}},
	-- The cleric's leather from rotten flesh players sell it (ticket 37b), three to one, never
	-- below what the flesh cost it (`cost`, its average paid per flesh; asks.cost_floor).
	cleric = {{from = "mcl_mobitems:rotten_flesh", to = "mcl_mobitems:leather", ratio = 1 / 3, takes = 3,
		cost = "_villages_flesh_cost"}},
	-- The alchemist's (ticket 20): an ingot from nine nuggets, a gold nugget from eighteen
	-- (two ingots) and a gold ingot from 162 (nine gold nuggets), gold only from the nuggets
	-- past `reserve`; a pane from a glass, so both come from two stone.
	alchemist = {
		{from = "mcl_core:iron_nugget", to = "mcl_core:iron_ingot", ratio = 1 / 9, takes = 9},
		{from = "mcl_core:iron_nugget", to = "mcl_core:gold_nugget", ratio = 1 / 18, takes = 18, reserve = 24},
		{from = "mcl_core:iron_nugget", to = "mcl_core:gold_ingot", ratio = 1 / 162, takes = 162, reserve = 24},
		{from = "mcl_core:glass", to = "xpanes:pane_natural_flat", ratio = 1},
	},
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
	{from = "mcl_mobitems:bone", to = "mcl_bone_meal:bone_meal", ratio = 3},
	{from = "mcl_mobitems:bone", to = "mcl_dye:white", ratio = 3},
	{from = "mcl_flowers:lily_of_the_valley", to = "mcl_dye:white", ratio = 1},
	{from = "mcl_flowers:poppy", to = "mcl_dye:red", ratio = 1},
	{from = "mcl_flowers:tulip_red", to = "mcl_dye:red", ratio = 1},
}
for _, list in pairs(conversions) do
	table.sort(list, function(a, b) return a.from < b.from end)
end

-- Whole products from `sources` of a conversion's source: whole batches of `takes`, each
-- giving takes × ratio (rounded, so 9 nuggets at a ninth give exactly one ingot), past its
-- reserve. Returns the products and the sources they take.
local function batch(conversion)
	local takes = conversion.takes or 1
	return takes, math.floor(takes * conversion.ratio + 0.5)
end

local function yield(conversion, sources)
	local takes, gives = batch(conversion)
	local batches = math.floor(math.max(sources - (conversion.reserve or 0), 0) / takes)
	return batches * gives, batches * takes
end

-- The sources `count` products take, rounded up to whole batches, and the products they give.
local function sources_for(conversion, count)
	local takes, gives = batch(conversion)
	local batches = math.ceil(count / gives)
	return batches * takes, batches * gives
end

local M = {CATEGORIES = categories, yield = yield, sources_for = sources_for, ORDER = ORDER, SPECIES = SPECIES, CONVERSIONS = conversions, ANYONE = ANYONE, BURN = BURN,
	COAL = COAL, CHARCOAL = CHARCOAL, STRING = STRING}

-- How many of a category's units one item gives, or nil if it is no member.
function M.units(category, item)
	local members = categories[category]
	return members and members[item]
end

-- The first category in ORDER an item belongs to, whatever anyone wants: the one its
-- reference price is kept under (prices.lua, ticket 21b). Nil for none.
function M.category_of(item)
	for _, category in ipairs(ORDER) do
		if categories[category][item] then return category end
	end
	return nil
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
	local list = villager._villages_alchemist and conversions.alchemist or conversions[villager._profession]
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
