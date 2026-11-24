-- What each crafting profession makes at its jobsite (docs/villager-economy-design.md,
-- ticket 8). Pure data, read by production.lua, which does the making, and ledger.lua,
-- which turns the inputs into what the profession wants to hold.
--
-- One list per profession, in no order: production.lua picks by value. Each recipe:
--
-- * makes, count: the item and how many one craft gives. Every output is something the
--   profession sells in VoxeLibre 0.92.3's trade table (trade_tables.lua), or an input
--   of one of its own recipes (paper, books, planks for the librarian), or a good that
--   wears out (wants.lua: picks, hoes, fishing rods): a test checks it.
-- * from: {item, count} pairs, from the real crafting recipe (mcl_core/crafting.lua,
--   mcl_tools, mcl_armor, mcl_bows, mcl_books, mcl_stonecutter's registrations).
-- * fuel: furnace smelts it takes, where the real item is smelted (bricks, glass, cooked
--   meat: one each, as in a furnace), and one per ingot for the smiths, who work iron
--   at a forge. A coal or charcoal lump is 8 smelts (its burntime 80 over cooktime 10).
-- * seconds: banked seconds an item, where not living_villages_craft_seconds (the
--   butcher's cooking, a furnace's smelt, ticket 39f).
-- * demand: its inputs follow what the profession hears asked for of its output
--   (production.input_demand, ticket 39f), not one batch.
-- * tier: the tier of the trade that sells it, for tier advancement (ticket 9). A
--   villager makes every recipe in its list whatever its tier: the list holds only plain
--   goods a village can supply, never enchanted ones.
--
-- Left out, so they restock as vanilla does: the farmer and fisherman, whose work loops
-- make their goods, and the shepherd's wool (flock.lua); the cleric's trade goods, which have no recipe
-- (it makes only the clock, a comfort, ticket 29). The cartographer
-- makes banners (ticket 12), for stalls (market_stall.lua), and the paper its trade
-- table buys: its map needs a compass a village cannot make. Fletching flint from
-- gravel is one for one, where a player digging gets flint one time in ten: the
-- fletcher's table sells it that way.
local COBBLE, STICK = "mcl_core:cobble", "mcl_core:stick"
local IRON, LEATHER = "mcl_core:iron_ingot", "mcl_mobitems:leather"
local TORCH = "mcl_torches:torch"

return {
	-- The shepherd dyes its grey wool white (19h): nobody bought grey, and three shepherds
	-- starved holding it while the cartographer wanted 14 white for banners (ColonyFood,
	-- 2026-11-14). VoxeLibre dyes only white wool; Minecraft dyes any, as here. Its white
	-- dye comes from a lily of the valley or a farmer's bone meal (goods.lua's conversions).
	shepherd = {
		{makes = "mcl_wool:white", count = 1, tier = 1, from = {{"mcl_wool:grey", 1}, {"mcl_dye:white", 1}}},
	},
	tool_smith = {
		{makes = "mcl_tools:pick_stone", count = 1, tier = 1, from = {{COBBLE, 3}, {STICK, 2}}},
		{makes = "mcl_tools:axe_stone", count = 1, tier = 1, from = {{COBBLE, 3}, {STICK, 2}}},
		{makes = "mcl_tools:shovel_stone", count = 1, tier = 1, from = {{COBBLE, 1}, {STICK, 2}}},
		{makes = "mcl_farming:hoe_stone", count = 1, tier = 1, from = {{COBBLE, 2}, {STICK, 2}}},
		-- Wooden ones, while no quarrier sells cobble (ticket 19d): its first picks start one.
		{makes = "mcl_tools:pick_wood", count = 1, tier = 1, from = {{"mcl_core:wood", 3}, {STICK, 2}}},
		{makes = "mcl_farming:hoe_wood", count = 1, tier = 1, from = {{"mcl_core:wood", 2}, {STICK, 2}}},
		-- Its own sticks, from a woodcutter's logs (ticket 11d): no villager sells sticks.
		{makes = STICK, count = 4, tier = 1, from = {{"mcl_core:wood", 2}}},
		{makes = "mcl_core:wood", count = 4, tier = 1, from = {{"mcl_core:tree", 1}}},
		-- What a quarrier asks for (wants.lua, ticket 29), from the alchemist's ingots.
		{makes = "mcl_tools:pick_iron", count = 1, tier = 1, from = {{IRON, 3}, {STICK, 2}}, fuel = 3},
		-- What a farmer asks for (ticket 29); the woodcutter's iron axe is the weapon smith's.
		{makes = "mcl_farming:hoe_iron", count = 1, tier = 1, from = {{IRON, 2}, {STICK, 2}}, fuel = 2},
	},
	weapon_smith = {
		{makes = "mcl_tools:axe_iron", count = 1, tier = 1, from = {{IRON, 3}, {STICK, 2}}, fuel = 3},
		-- The base of its premium sword (ticket 37d, premium.lua), from journeyman up.
		{makes = "mcl_tools:sword_iron", count = 1, tier = 3, from = {{IRON, 2}, {STICK, 1}}, fuel = 2},
	},
	armorer = {
		{makes = "mcl_armor:helmet_iron", count = 1, tier = 1, from = {{IRON, 5}}, fuel = 5},
		{makes = "mcl_armor:chestplate_iron", count = 1, tier = 1, from = {{IRON, 8}}, fuel = 8},
		{makes = "mcl_armor:leggings_iron", count = 1, tier = 1, from = {{IRON, 7}}, fuel = 7},
		{makes = "mcl_armor:boots_iron", count = 1, tier = 1, from = {{IRON, 4}}, fuel = 4},
		-- A comfort (comforts.lua, ticket 29): its armour found no buyer.
		{makes = "mcl_cauldrons:cauldron", count = 1, tier = 1, from = {{IRON, 7}}, fuel = 7},
	},
	-- Cooking takes `seconds` an item, a furnace's smelt (10), not a craft's 120 (ticket
	-- 39f): at 120 the butcher's 425 s working day cooked 3 or 4 dishes, against a tavern
	-- serving 20 (ColonyFood, 2026-11-21: 29 dishes in 44 days). Its raw inputs follow the
	-- dishes it hears asked for (`demand`, production.lua's input_demand). A smoker cooks
	-- in half a furnace's time on the same burn, so half the fuel a dish (experiment E6):
	-- in lv_pair e5 the butcher paid 593 emeralds for logs to burn against 150 for fish
	-- and meat.
	butcher = {
		{makes = "mcl_mobitems:cooked_porkchop", count = 1, tier = 2, from = {{"mcl_mobitems:porkchop", 1}}, fuel = 0.5, seconds = 10, demand = true},
		{makes = "mcl_mobitems:cooked_chicken", count = 1, tier = 2, from = {{"mcl_mobitems:chicken", 1}}, fuel = 0.5, seconds = 10, demand = true},
		-- The leatherworker's herd's beef (herd.lua, ticket 11e), for the tavern.
		{makes = "mcl_mobitems:cooked_beef", count = 1, tier = 1, from = {{"mcl_mobitems:beef", 1}}, fuel = 0.5, seconds = 10, demand = true},
		-- The fishermen's catch (ticket 15): raw fish is no food, and nobody else cooks it.
		{makes = "mcl_fishing:fish_cooked", count = 1, tier = 1, from = {{"mcl_fishing:fish_raw", 1}}, fuel = 0.5, seconds = 10, demand = true},
		{makes = "mcl_fishing:salmon_cooked", count = 1, tier = 1, from = {{"mcl_fishing:salmon_raw", 1}}, fuel = 0.5, seconds = 10, demand = true},
		-- The farmers' potatoes, baked for the tavern (ticket 39f): the keeper bakes none
		-- (keeper_supply.lua, ticket 45).
		{makes = "mcl_farming:potato_item_baked", count = 1, tier = 1, from = {{"mcl_farming:potato_item", 1}}, fuel = 0.5, seconds = 10, demand = true},
	},
	-- White wool from the shepherd, sticks of its own (mcl_banners' recipe: six wool, a stick).
	-- Paper from cane, as the librarian's: the paper it wants (its trade table buys it)
	-- was the librarian's to make, and the librarian bound it all into books, so a
	-- forager's cane found no buyer the cartographer could pay (ColonyFood, day 113).
	cartographer = {
		{makes = "mcl_core:paper", count = 3, tier = 1, from = {{"mcl_core:reeds", 3}}},
		{makes = "mcl_banners:banner_item_white", count = 1, tier = 4, from = {{"mcl_wool:white", 6}, {STICK, 1}}},
		-- A comfort (ticket 19c), and a second buyer for the leatherworker's leather.
		{makes = "mcl_itemframes:frame", count = 1, tier = 4, from = {{STICK, 8}, {LEATHER, 1}}},
		{makes = STICK, count = 4, tier = 1, from = {{"mcl_core:wood", 2}}},
		{makes = "mcl_core:wood", count = 4, tier = 1, from = {{"mcl_core:tree", 1}}},
	},
	fletcher = {
		{makes = "mcl_bows:arrow", count = 4, tier = 1,
			from = {{"mcl_core:flint", 1}, {STICK, 1}, {"mcl_mobitems:feather", 1}}},
		{makes = "mcl_core:flint", count = 1, tier = 1, from = {{"mcl_core:gravel", 1}}},
		{makes = "mcl_bows:bow", count = 1, tier = 2, from = {{STICK, 3}, {"mcl_mobitems:string", 3}}},
		-- For the fishermen, whose rods wear out (wants.lua, ticket 19c), from the shepherd's string.
		{makes = "mcl_fishing:fishing_rod", count = 1, tier = 1, from = {{STICK, 3}, {"mcl_mobitems:string", 2}}},
		-- Its own sticks, as the tool smith's: no villager sells sticks.
		{makes = STICK, count = 4, tier = 1, from = {{"mcl_core:wood", 2}}},
		{makes = "mcl_core:wood", count = 4, tier = 1, from = {{"mcl_core:tree", 1}}},
	},
	-- The leatherworker's clothes (ticket 24), comforts, from its herd's leather (herd.lua,
	-- ticket 11e): vanilla's armour recipes. Its leather still sells to the librarian and the
	-- cartographer when that pays better (production by margin, ticket 21d).
	leatherworker = {
		{makes = "mcl_armor:helmet_leather", count = 1, tier = 2, from = {{LEATHER, 5}}},
		{makes = "mcl_armor:chestplate_leather", count = 1, tier = 1, from = {{LEATHER, 8}}},
		{makes = "mcl_armor:leggings_leather", count = 1, tier = 1, from = {{LEATHER, 7}}},
		{makes = "mcl_armor:boots_leather", count = 1, tier = 2, from = {{LEATHER, 4}}},
	},
	librarian = {
		{makes = "mcl_core:paper", count = 3, tier = 1, from = {{"mcl_core:reeds", 3}}},
		{makes = "mcl_books:book", count = 1, tier = 1, from = {{"mcl_core:paper", 3}, {LEATHER, 1}}},
		{makes = "mcl_core:wood", count = 4, tier = 1, from = {{"mcl_core:tree", 1}}},
		{makes = "mcl_books:bookshelf", count = 1, tier = 1, from = {{"mcl_core:wood", 6}, {"mcl_books:book", 3}}},
		{makes = "mcl_core:glass", count = 1, tier = 3, from = {{"mcl_core:sand", 1}}, fuel = 1},
		-- A book and quill (ticket 32), a comfort: a use for the butcher's feathers beyond the
		-- fletcher's arrows. VoxeLibre's takes black dye too, from an ink sac or a wither rose,
		-- neither of which a village has, so here a book and a feather make one, as the
		-- shepherd dyes grey wool. Its trade table buys them (tier 4).
		{makes = "mcl_books:writable_book", count = 1, tier = 4, from = {{"mcl_books:book", 1}, {"mcl_mobitems:feather", 1}}},
	},
	-- A clock, a comfort (comforts.lua, ticket 29), from one of the alchemist's gold ingots
	-- and one iron ingot: cheaper than a player's craft (four gold and a redstone), which
	-- stays as it is, so the village has a use for gold. An alchemist has its own list.
	cleric = {
		{makes = "mcl_clock:clock", count = 1, tier = 1, from = {{"mcl_core:gold_ingot", 1}, {IRON, 1}}},
		-- The base of its premium goods (ticket 37b, premium.lua), from journeyman up.
		{makes = "mcl_potions:glass_bottle", count = 3, tier = 3, from = {{"mcl_core:glass", 3}}},
	},
	-- The alchemist (ticket 20): a role over a cleric, at its stand (alchemist.lua). Its
	-- recipes are no vanilla craft, so none is checked against a trade table. Each takes
	-- `share` of its working day (10500 ticks of the clock, production.lua) rather than
	-- living_villages_craft_seconds, so a whole day gives 72 glass, 12 flint or 36 nuggets
	-- (ticket 30, twice what it was), and it makes the first by `rank` that it may: glass
	-- while it holds fewer than `upto` (alchemist.lua's GLASS_KEEP plus one), flint up to
	-- FLINT_KEEP, then nuggets up to NUGGET_KEEP. A nugget takes stone or cobble: an input's third field names a category
	-- (goods.lua) any member of which serves.
	alchemist = {
		-- Each burns half a lump of fuel (ticket 28c): a buyer for the village's charcoal and logs.
		{makes = "mcl_core:glass", count = 1, tier = 1, from = {{"mcl_core:stone", 2}}, share = 1 / 72, rank = 1, upto = 13,
			fuel = 4},
		{makes = "mcl_core:flint", count = 1, tier = 1, from = {{"mcl_core:tree", 4}}, share = 1 / 12, rank = 2, upto = 32,
			fuel = 4},
		{makes = "mcl_core:iron_nugget", count = 1, tier = 1, from = {{"mcl_core:cobble", 1, "stone"}}, share = 1 / 36,
			rank = 3, upto = 192, fuel = 4},
	},
	mason = {
		{makes = "mcl_core:brick", count = 1, tier = 1, from = {{"mcl_core:clay_lump", 1}}, fuel = 1},
		-- Smelted from a quarrier's cobble (ticket 19d), for its carved stone and to sell.
		{makes = "mcl_core:stone", count = 1, tier = 1, from = {{"mcl_core:cobble", 1}}, fuel = 1},
		{makes = "mcl_core:stonebrickcarved", count = 1, tier = 2, from = {{"mcl_core:stone", 1}}},
		{makes = "mcl_core:andesite_smooth", count = 4, tier = 3, from = {{"mcl_core:andesite", 4}}},
		{makes = "mcl_core:granite_smooth", count = 4, tier = 3, from = {{"mcl_core:granite", 4}}},
		{makes = "mcl_core:diorite_smooth", count = 4, tier = 3, from = {{"mcl_core:diorite", 4}}},
	},
	-- Labourers (ticket 23a): no profession, but every villager labouring (labour.lua)
	-- crafts from this list at home while its activity has nothing for it, by margin as at
	-- a jobsite (production.labour_step). Comforts from the cobble, logs and charcoal they
	-- gather, so the richest pay the poorest for work. Vanilla's recipes, but the flower
	-- pot: vanilla's takes bricks from clay no village can get, so here 3 stone or cobble,
	-- or 3 planks. A barrel's 2 wood slabs are a plank (3 planks make 6), an armor stand's
	-- stone slab half a stone, rounded up. None is checked against a trade table.
	labour = {
		{makes = "mcl_core:wood", count = 4, tier = 1, from = {{"mcl_core:tree", 1}}},
		{makes = STICK, count = 4, tier = 1, from = {{"mcl_core:wood", 2}}},
		{makes = TORCH, count = 4, tier = 1, from = {{STICK, 1}, {"mcl_core:charcoal_lump", 1}}},
		{makes = TORCH, count = 4, tier = 1, from = {{STICK, 1}, {"mcl_core:coal_lump", 1}}},
		{makes = "mcl_flowerpots:flower_pot", count = 1, tier = 1, from = {{"mcl_core:cobble", 3, "stone"}}},
		{makes = "mcl_flowerpots:flower_pot", count = 1, tier = 1, from = {{"mcl_core:wood", 3}}},
		{makes = "mcl_paintings:painting", count = 1, tier = 1, from = {{STICK, 8}, {"mcl_wool:white", 1, "wool"}}},
		{makes = "mcl_barrels:barrel_closed", count = 1, tier = 1, from = {{"mcl_core:wood", 7}}},
		{makes = "mcl_armor_stand:armor_stand", count = 1, tier = 1, from = {{STICK, 6}, {"mcl_core:cobble", 1, "stone"}}},
		{makes = "mcl_lanterns:lantern_floor", count = 1, tier = 1, from = {{"mcl_core:iron_nugget", 8}, {TORCH, 1}}},
	},
}
