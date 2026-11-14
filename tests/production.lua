-- Run with: lua tests/production.lua
local now, day, time = 1000, 5, 9000 / 24000
local settings = {}
local logs = {}

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
}

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	get_day_count = function() return day end,
	get_timeofday = function() return time end,
	get_item_group = function() return 0 end,
	registered_nodes = {},
	settings = {
		get = function(_, name) return settings[name] end,
		get_bool = function(_, name, default)
			if settings[name] == nil then return default end
			return settings[name]
		end,
	},
	log = function(_, message) logs[#logs + 1] = message end,
	pos_to_string = function(p) return "(" .. p.x .. "," .. p.y .. "," .. p.z .. ")" end,
	get_objects_inside_radius = function() return {} end,
}

local production = dofile("production.lua")
local possessions = dofile("possessions.lua")
local tables = dofile("trade_tables.lua")
local recipes = dofile("recipes.lua")

-- Every output is sold by its profession, goes into another of its own recipes, is what
-- its trade table buys (the cartographer's paper), or is what the keeper buys for the
-- tavern (the butcher's cooked beef, ticket 11e), or is food.
local ledger_inputs = dofile("ledger.lua").inputs
local keeper_buys = ledger_inputs("keeper", 1)
local foods = dofile("food.lua").POINTS
for profession, list in pairs(recipes) do
	local entry = tables.professions[profession]
	assert(entry, profession .. " has a trade table")
	local sold, used = {}, {}
	local bought = {}
	for _, trade in ipairs(entry.trades) do
		sold[trade.offered[1].item] = true
		if #trade.wanted == 1 then bought[trade.wanted[1].item] = true end
	end
	for _, recipe in ipairs(list) do
		for _, input in ipairs(recipe.from) do used[input[1]] = true end
	end
	for _, recipe in ipairs(list) do
		-- Food sells to any hungry villager (goods.lua's food category, ticket 15).
		assert(sold[recipe.makes] or used[recipe.makes] or bought[recipe.makes] or keeper_buys[recipe.makes] or foods[recipe.makes],
			profession .. " neither sells nor uses " .. recipe.makes)
		assert(recipe.count >= 1 and #recipe.from >= 1 and recipe.tier >= 1)
	end
end

local function smith(fields)
	local pos = {x = 0, y = 1, z = 0}
	local v = {_id = "tobias", _profession = "tool_smith", _jobsite = {x = 1, y = 1, z = 0}, _villages_food = 10}
	for k, value in pairs(fields or {}) do v[k] = value end
	v.object = {get_pos = function() return pos end}
	v.move_to = function(p) pos = p end
	return v
end
local function count(v, item) return possessions.count(v, item) end

-- With nothing to craft with it makes nothing, banks nothing, and holds its restock.
local idle = smith()
assert(production.choose(idle) == nil)
assert(production.work(idle, 600) == 0 and idle._villages_craft == nil)
assert(production.restock_held(idle) == "nothing to craft with")
assert(production.status(idle) == "nothing to craft with")

-- With cobble and sticks: every stone tool sells for an emerald, so the one that takes
-- least, the shovel (1 cobble), adds the most.
local tobias = smith()
possessions.add(tobias, "mcl_core:cobble", 7)
possessions.add(tobias, "mcl_core:stick", 6)
assert(production.restock_held(tobias) == nil)
assert(production.choose(tobias).makes == "mcl_tools:shovel_stone")
-- Heard of a farmer that needs a hoe, at more than its own value: it makes that first.
tobias._villages_market_news = {{kind = "needs", item = "mcl_farming:hoe_stone", count = 1, who = "farmer1",
	price = 150, heard = now, hops = 1}}
assert(production.choose(tobias).makes == "mcl_farming:hoe_stone")
-- An ask below its own value changes nothing.
tobias._villages_market_news[1].price = 1
assert(production.choose(tobias).makes == "mcl_tools:shovel_stone")
tobias._villages_market_news = nil
-- 100 s banks toward 120; 30 more makes one, carrying 10 over.
assert(production.work(tobias, 100) == 0 and tobias._villages_craft == 100)
assert(production.work(tobias, 30) == 1 and tobias._villages_craft == 10)
assert(count(tobias, "mcl_tools:shovel_stone") == 1 and count(tobias, "mcl_core:cobble") == 6)
assert(logs[#logs]:find("made 1 mcl_tools:shovel_stone", 1, true))
-- A long gap makes several, up to what the inputs allow: 4 sticks make two more.
assert(production.work(tobias, 1000) == 2)
assert(count(tobias, "mcl_core:stick") == 0 and tobias._villages_craft == nil, "nothing left: nothing banked")

-- Hungry works at half the rate; starving at a quarter (ticket 18), and holds its restock.
local hungry = smith({_villages_food = 2})
possessions.add(hungry, "mcl_core:cobble", 3)
possessions.add(hungry, "mcl_core:stick", 2)
assert(production.work(hungry, 200) == 0 and hungry._villages_craft == 100)
local starving = smith({_villages_food = 0})
possessions.add(starving, "mcl_core:cobble", 3)
possessions.add(starving, "mcl_core:stick", 2)
assert(production.work(starving, 400) == 0 and starving._villages_craft == 100)
assert(production.work(starving, 80) == 1, "slowly, but it makes one")
assert(production.restock_held(starving) == "starving")

-- Fuel: a lump is 8 smelts, charcoal burned first, the rest kept for the next item.
-- (With over 5 dinners' emeralds it wants two days' food, 8 points: one porkchop's 6 leave
-- it wanting a second, tickets 15 and 17.)
local bram = smith({_id = "bram", _profession = "butcher", _villages_food = 4})
possessions.add(bram, "mcl_core:emerald", 100)
possessions.add(bram, "mcl_mobitems:porkchop", 2)
possessions.add(bram, "mcl_core:coal_lump", 1)
possessions.add(bram, "mcl_core:charcoal_lump", 1)
assert(production.work(bram, 240) == 2)
assert(count(bram, "mcl_mobitems:cooked_porkchop") == 2 and count(bram, "mcl_core:coal_lump") == 1)
assert(count(bram, "mcl_core:charcoal_lump") == 0 and bram._villages_fuel == 6)
-- Any fuel will do (ticket 15): planks burn 1.5 smelts each, and the butcher cooks fish.
local planker = smith({_id = "planker", _profession = "butcher", _villages_food = 4})
possessions.add(planker, "mcl_core:emerald", 100)
possessions.add(planker, "mcl_fishing:fish_raw", 2)
possessions.add(planker, "mcl_core:wood", 3)
assert(production.work(planker, 240) == 2, "cooks both fish")
assert(count(planker, "mcl_fishing:fish_cooked") == 2 and count(planker, "mcl_core:wood") == 1)
assert(math.abs((planker._villages_fuel or 0) - 1) < 1e-9, planker._villages_fuel)
-- Any species will do (ticket 15): a cartographer with birch logs and white wool splits
-- them into birch planks, sticks from those, and a banner.
do
	local carto = smith({_id = "carto", _profession = "cartographer", _villages_food = 20, _max_trade_tier = 4})
	possessions.add(carto, "mcl_core:birchtree", 1)
	possessions.add(carto, "mcl_wool:white", 6)
	local made = 0
	for _ = 1, 6 do
		local recipe = production.choose(carto)
		if not recipe then break end
		assert(production.make(carto, recipe))
		made = made + 1
	end
	-- Log to four birch planks, two batches of sticks, then the banner.
	assert(made == 4 and count(carto, "mcl_core:birchtree") == 0 and count(carto, "mcl_core:wood") == 0)
	assert(count(carto, "mcl_banners:banner_item_white") == 1 and count(carto, "mcl_wool:white") == 0, "a banner")
	assert(logs[#logs - 3]:find("made 4 mcl_core:birchwood"), "birch planks, not oak")
	-- A spruce plank is planks: the bookshelf recipe's oak planks take it.
	assert(production.have("mcl_core:wood", function(i) return ({["mcl_core:sprucewood"] = 6})[i] end) == 6)
end
-- A cartographer makes its own paper from a forager's cane (ColonyFood, day 113), and so
-- wants the cane.
do
	local carto = smith({_id = "carto2", _profession = "cartographer", _villages_food = 20})
	assert((ledger_inputs("cartographer")["mcl_core:reeds"] or 0) > 0, "it wants cane")
	possessions.add(carto, "mcl_core:reeds", 3)
	local recipe = production.choose(carto)
	assert(recipe and recipe.makes == "mcl_core:paper", "paper from cane")
	assert(production.make(carto, recipe))
	assert(count(carto, "mcl_core:paper") == 3 and count(carto, "mcl_core:reeds") == 0)
end
-- No fuel and no lump: raw meat stays raw.
local cold = smith({_id = "cold", _profession = "butcher"})
possessions.add(cold, "mcl_mobitems:chicken", 3)
assert(production.choose(cold) == nil and production.restock_held(cold) == "nothing to craft with")

-- A full stock of an output: it stops making that one.
local full = smith()
possessions.add(full, "mcl_core:cobble", 1)
possessions.add(full, "mcl_core:stick", 2)
possessions.add(full, "mcl_tools:shovel_stone", production.STOCK)
assert(production.choose(full) == nil)

-- Nobody wants a tool it already holds one of: it keeps its cobble and sticks until
-- someone asks, then makes that one past the first.
local idle = smith({_id = "idle"})
possessions.add(idle, "mcl_core:cobble", 6)
possessions.add(idle, "mcl_core:stick", 4)
for _, tool in ipairs({"mcl_tools:pick_stone", "mcl_tools:axe_stone", "mcl_tools:shovel_stone", "mcl_farming:hoe_stone"}) do
	possessions.add(idle, tool, production.UNASKED_STOCK)
end
assert(production.choose(idle, nil, nil, {}) == nil, "makes nothing nobody wants")
assert(production.choose(idle, nil, nil, {["mcl_farming:hoe_stone"] = 1}).makes == "mcl_farming:hoe_stone")
-- Holding none, it still makes one.
local fresh = smith({_id = "fresh"})
possessions.add(fresh, "mcl_core:cobble", 1)
possessions.add(fresh, "mcl_core:stick", 2)
assert(production.choose(fresh, nil, nil, {}).makes == "mcl_tools:shovel_stone")

-- Outputs that feed another recipe: a librarian with cane and leather makes paper, then books.
local lena = smith({_id = "lena", _profession = "librarian"})
possessions.add(lena, "mcl_core:reeds", 3)
possessions.add(lena, "mcl_mobitems:leather", 1)
assert(production.choose(lena).makes == "mcl_core:paper")
assert(production.work(lena, 360) == 1 and count(lena, "mcl_core:paper") == 3)
assert(production.choose(lena).makes == "mcl_books:book")

-- Clock time counts only at work by the jobsite.
local walker = smith()
possessions.add(walker, "mcl_core:cobble", 3)
possessions.add(walker, "mcl_core:stick", 2)
assert(production.at_work(walker))
walker.move_to({x = 10, y = 1, z = 0})
assert(not production.at_work(walker), "away from the jobsite")
walker.move_to({x = 0, y = 1, z = 0})
time = 0.9
assert(not production.at_work(walker), "not the work stage")
time = 9000 / 24000

-- The restock guard: a vanilla call that set order "work" and unlocked trades is undone
-- for a villager that can make nothing; one with inputs keeps its restock.
local function vanilla_arrives(self)
	self.order = "work"
	self._trades = "unlocked"
end
local def = {do_custom = function(self) vanilla_arrives(self) end}
production.install(def)
local stuck = smith({_trades = "locked"})
def.do_custom(stuck, 0.1)
assert(stuck._trades == "locked" and stuck.order == "work", "restock held back")
assert(logs[#logs]:find("did not restock: nothing to craft with"))
local supplied = smith({_trades = "locked"})
possessions.add(supplied, "mcl_core:cobble", 3)
possessions.add(supplied, "mcl_core:stick", 2)
def.do_custom(supplied, 0.1)
assert(supplied._trades == "unlocked", "restocked")
-- Already at work: nothing to undo.
local working = smith({_trades = "locked", order = "work"})
def.do_custom(working, 0.1)
assert(working._trades == "unlocked")
-- Not a crafting profession: vanilla restocks.
local cleric = smith({_profession = "cleric", _trades = "locked"})
def.do_custom(cleric, 0.1)
assert(cleric._trades == "unlocked" and production.status(cleric) == "not a crafting profession")

-- Tiers from village supply: three days with a craft from belongings at the tier raise it.
minetest.serialize = function(v) return v end
minetest.deserialize = function(v) return v end
local texture = "mobs_mc_villager_toolsmith.png^mobs_mc_stone.png"
local tier_smith = smith({_id = "tier", _max_trade_tier = 1, _trades = {{tier = 1}, {tier = 1}, {tier = 2}, {tier = 3}}})
tier_smith.object.get_properties = function() return {textures = {texture}} end
tier_smith.object.set_properties = function(_, p) texture = p.textures[1] end
possessions.add(tier_smith, "mcl_core:cobble", 30)
possessions.add(tier_smith, "mcl_core:stick", 30)
local shovel = recipes.tool_smith[3]
assert(production.supplied(tier_smith, shovel))
assert(production.make(tier_smith, shovel) and production.make(tier_smith, shovel))
assert(tier_smith._villages_tier_supply.days == 1, "one day, however many crafts")
assert(production.tier_status(tier_smith) == "tier 1, 1/3 days of village supply", production.tier_status(tier_smith))
-- Each craft is in its tally: the shovels made, the cobble and sticks used.
assert(tier_smith._villages_tally.made["mcl_tools:shovel_stone"] == 2)
assert(tier_smith._villages_tally.used["mcl_core:cobble"] == 2 and tier_smith._villages_tally.used["mcl_core:stick"] == 4)
day = day + 1
production.make(tier_smith, shovel)
day = day + 1
production.make(tier_smith, shovel)
assert(tier_smith._max_trade_tier == 2 and tier_smith._max_tradenum == 3, "up a tier, and its trades with it")
assert(texture == "mobs_mc_villager_toolsmith.png^mobs_mc_iron.png", texture)
assert(tier_smith._villages_tier_supply == nil and logs[#logs]:find("rose to tier 2"))
-- From the stash it does not count: what a player left there is not village supply.
local stash_smith = smith({_id = "stash", _max_trade_tier = 1})
assert(not production.supplied(stash_smith, shovel))
-- Fuel counts too: smelts left over, or a lump in its belongings.
local smelter = smith({_id = "smelter", _profession = "butcher", _villages_fuel = 3})
possessions.add(smelter, "mcl_mobitems:porkchop", 1)
assert(production.supplied(smelter, recipes.butcher[1]))
-- A lump burned is in the tally as used.
possessions.add(smelter, "mcl_mobitems:porkchop", 1)
possessions.add(smelter, "mcl_core:charcoal_lump", 1)
smelter._villages_fuel = nil
assert(production.make(smelter, recipes.butcher[1]))
assert(smelter._villages_tally.used["mcl_core:charcoal_lump"] == 1 and smelter._villages_tally.used["mcl_mobitems:porkchop"] == 1)
possessions.add(smelter, "mcl_mobitems:porkchop", 1)
smelter._villages_fuel = 3
smelter._villages_fuel = nil
assert(not production.supplied(smelter, recipes.butcher[1]))
-- Tier 5 is the top.
local master = smith({_max_trade_tier = 5})
assert(production.tier_status(master) == "tier 5 (top)")
-- The Builder is a mason to vanilla, but crafts nothing.
assert(production.recipes(smith({_profession = "mason", _villages_builder = true})) == nil)
assert(not production.count_supply(master) and master._villages_tier_supply == nil)

-- With the economy off, nothing is installed and nothing is held.
settings.living_villages_economy = false
assert(production.restock_held(starving) == nil)
local off = {do_custom = function() end}
local plain = off.do_custom
production.install(off)
assert(off.do_custom == plain)

print("production.lua: ok")
