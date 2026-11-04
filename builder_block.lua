-- The Builder's bench, the block a villager claims to become a Builder. It looks like
-- a tinted crafting table and does nothing itself. Registered at load time, not from
-- register_on_mods_loaded: register_node checks the current mod name.
--
-- A generated builder's house needs a double chest, and placing a schematic gives one
-- no inventory: place_schematics only constructs mcl_chests:chest, as single chests,
-- and it places asynchronously (mcl_structures.place_schematic emerges first), so there
-- is nothing to call afterwards either. The schematic holds two chest_small nodes
-- instead, and the ABM below sets them up. A chest_left or chest_right cannot be made
-- directly, since only chest_small's on_construct creates the inventory, and it merges
-- with a neighbouring chest_small as soon as it runs. So both are cleared and set again in
-- turn, the way a player places a double chest.
local core = minetest

local M = {}

M.NAME = "living_villages:builder_block"
M.SMALL_CHEST = "mcl_chests:chest_small"
-- From the bench to the furthest chest of its house.
local SETUP_RADIUS = 6
local TINT = "^[multiply:#c8a27a"

local function chests_without_inventory(pos, engine)
	local found = {}
	local minp = {x = pos.x - SETUP_RADIUS, y = pos.y - 2, z = pos.z - SETUP_RADIUS}
	local maxp = {x = pos.x + SETUP_RADIUS, y = pos.y + 2, z = pos.z + SETUP_RADIUS}
	for _, chest in ipairs(engine.find_nodes_in_area(minp, maxp, {M.SMALL_CHEST})) do
		if engine.get_meta(chest):get_inventory():get_size("main") == 0 then
			found[#found + 1] = {pos = chest, param2 = engine.get_node(chest).param2}
		end
	end
	return found
end

-- Gives the chests of a freshly generated house their inventories, once. A chest with
-- an inventory is left alone, so this cannot touch a player's chest. Returns how many.
function M.setup_house(pos, engine)
	engine = engine or core
	local meta = engine.get_meta(pos)
	if meta:get_int("villages_house_ready") == 1 then return 0 end
	local chests = chests_without_inventory(pos, engine)
	for _, chest in ipairs(chests) do engine.remove_node(chest.pos) end
	for _, chest in ipairs(chests) do
		engine.set_node(chest.pos, {name = M.SMALL_CHEST, param2 = chest.param2})
	end
	meta:set_int("villages_house_ready", 1)
	if #chests > 0 then
		engine.log("action", string.format("[living_villages] set up %d chests of the builder's house at %s",
			#chests, engine.pos_to_string(pos)))
	end
	return #chests
end

local function tinted(tiles)
	local copy = {}
	for i, tile in ipairs(tiles) do
		copy[i] = type(tile) == "string" and tile .. TINT or tile
	end
	return copy
end

local bench = core.registered_nodes["mcl_crafting_table:crafting_table"]
if not bench then
	core.log("warning", "[living_villages] mcl_crafting_table:crafting_table is missing; the builder's bench was not registered")
	return M
end

local def = table.copy(bench)
for _, field in ipairs({"name", "mod_origin", "type", "on_rightclick"}) do def[field] = nil end
def.description = "Builder's Bench"
def._tt_help = "A villager who claims it builds for the village"
def._doc_items_longdesc = "A villager who claims a builder's bench becomes a Builder, and adds buildings to its village from the materials in nearby chests."
def._doc_items_usagehelp = nil
def.tiles = tinted(def.tiles)
def.drop = M.NAME
core.register_node(M.NAME, def)

core.register_craft({
	type = "shapeless",
	output = M.NAME,
	recipe = {"mcl_crafting_table:crafting_table", "mcl_core:brick_block"},
})

-- A generated house can land in a block that is already active, which an LBM would miss.
core.register_abm({
	label = "Set up the chests of a generated builder's house",
	nodenames = {M.NAME},
	interval = 5,
	chance = 1,
	catch_up = false,
	action = function(pos) M.setup_house(pos) end,
})

return M
