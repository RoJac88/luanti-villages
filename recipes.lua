-- What each crafting profession makes at its jobsite (docs/villager-economy-design.md,
-- ticket 8). Pure data, read by production.lua, which does the making, and ledger.lua,
-- which turns the inputs into what the profession wants to hold.
--
-- One list per profession, in no order: production.lua picks by value. Each recipe:
--
-- * makes, count: the item and how many one craft gives. Every output is something the
--   profession sells in VoxeLibre 0.92.3's trade table (trade_tables.lua), or an input
--   of one of its own recipes (paper, books, planks for the librarian): a test checks it.
-- * from: {item, count} pairs, from the real crafting recipe (mcl_core/crafting.lua,
--   mcl_tools, mcl_armor, mcl_bows, mcl_books, mcl_stonecutter's registrations).
-- * fuel: furnace smelts it takes, where the real item is smelted (bricks, glass, cooked
--   meat: one each, as in a furnace), and one per ingot for the smiths, who work iron
--   at a forge. A coal or charcoal lump is 8 smelts (its burntime 80 over cooktime 10).
-- * tier: the tier of the trade that sells it, for tier advancement (ticket 9). A
--   villager makes every recipe in its list whatever its tier: the list holds only plain
--   goods a village can supply, never enchanted ones.
--
-- Left out, so they restock as vanilla does: the farmer, fisherman and shepherd, whose
-- work loops make their goods; the cleric, whose goods have no recipe; the
-- cartographer, whose map needs a compass a village cannot make. Fletching flint from
-- gravel is one for one, where a player digging gets flint one time in ten: the
-- fletcher's table sells it that way.
local COBBLE, STICK = "mcl_core:cobble", "mcl_core:stick"
local IRON, LEATHER = "mcl_core:iron_ingot", "mcl_mobitems:leather"

return {
	tool_smith = {
		{makes = "mcl_tools:pick_stone", count = 1, tier = 1, from = {{COBBLE, 3}, {STICK, 2}}},
		{makes = "mcl_tools:axe_stone", count = 1, tier = 1, from = {{COBBLE, 3}, {STICK, 2}}},
		{makes = "mcl_tools:shovel_stone", count = 1, tier = 1, from = {{COBBLE, 1}, {STICK, 2}}},
		{makes = "mcl_farming:hoe_stone", count = 1, tier = 1, from = {{COBBLE, 2}, {STICK, 2}}},
	},
	weapon_smith = {
		{makes = "mcl_tools:axe_iron", count = 1, tier = 1, from = {{IRON, 3}, {STICK, 2}}, fuel = 3},
	},
	armorer = {
		{makes = "mcl_armor:helmet_iron", count = 1, tier = 1, from = {{IRON, 5}}, fuel = 5},
		{makes = "mcl_armor:chestplate_iron", count = 1, tier = 1, from = {{IRON, 8}}, fuel = 8},
		{makes = "mcl_armor:leggings_iron", count = 1, tier = 1, from = {{IRON, 7}}, fuel = 7},
		{makes = "mcl_armor:boots_iron", count = 1, tier = 1, from = {{IRON, 4}}, fuel = 4},
	},
	butcher = {
		{makes = "mcl_mobitems:cooked_porkchop", count = 1, tier = 2, from = {{"mcl_mobitems:porkchop", 1}}, fuel = 1},
		{makes = "mcl_mobitems:cooked_chicken", count = 1, tier = 2, from = {{"mcl_mobitems:chicken", 1}}, fuel = 1},
	},
	fletcher = {
		{makes = "mcl_bows:arrow", count = 4, tier = 1,
			from = {{"mcl_core:flint", 1}, {STICK, 1}, {"mcl_mobitems:feather", 1}}},
		{makes = "mcl_core:flint", count = 1, tier = 1, from = {{"mcl_core:gravel", 1}}},
		{makes = "mcl_bows:bow", count = 1, tier = 2, from = {{STICK, 3}, {"mcl_mobitems:string", 3}}},
	},
	librarian = {
		{makes = "mcl_core:paper", count = 3, tier = 1, from = {{"mcl_core:reeds", 3}}},
		{makes = "mcl_books:book", count = 1, tier = 1, from = {{"mcl_core:paper", 3}, {LEATHER, 1}}},
		{makes = "mcl_core:wood", count = 4, tier = 1, from = {{"mcl_core:tree", 1}}},
		{makes = "mcl_books:bookshelf", count = 1, tier = 1, from = {{"mcl_core:wood", 6}, {"mcl_books:book", 3}}},
		{makes = "mcl_core:glass", count = 1, tier = 3, from = {{"mcl_core:sand", 1}}, fuel = 1},
	},
	leatherworker = {
		{makes = "mcl_armor:helmet_leather", count = 1, tier = 2, from = {{LEATHER, 5}}},
		{makes = "mcl_armor:chestplate_leather", count = 1, tier = 1, from = {{LEATHER, 8}}},
		{makes = "mcl_armor:leggings_leather", count = 1, tier = 1, from = {{LEATHER, 7}}},
		{makes = "mcl_armor:boots_leather", count = 1, tier = 2, from = {{LEATHER, 4}}},
	},
	mason = {
		{makes = "mcl_core:brick", count = 1, tier = 1, from = {{"mcl_core:clay_lump", 1}}, fuel = 1},
		{makes = "mcl_core:stonebrickcarved", count = 1, tier = 2, from = {{"mcl_core:stone", 1}}},
		{makes = "mcl_core:andesite_smooth", count = 4, tier = 3, from = {{"mcl_core:andesite", 4}}},
		{makes = "mcl_core:granite_smooth", count = 4, tier = 3, from = {{"mcl_core:granite", 4}}},
		{makes = "mcl_core:diorite_smooth", count = 4, tier = 3, from = {{"mcl_core:diorite", 4}}},
	},
}
