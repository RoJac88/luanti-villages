-- The woodcutter's chopping block (ticket 16), the block a villager claims to become a
-- woodcutter (woodcutter.lua). An oak stump in looks, but no log: not in the `tree`
-- group, so it makes no planks, is never felled, and is no wild tree to a labourer
-- (labour.lua), and an axe does not strip it. Registered at load time, not from
-- register_on_mods_loaded: register_node checks the current mod name.
--
-- A player crafts one from any log and a stone axe; some generated small houses have
-- one where the loom stood (loomless_house.lua).
local core = minetest

local NAME = "living_villages:chopping_block"
local TINT = "^[multiply:#d8b48a"

local log = core.registered_nodes["mcl_core:tree"]
if not log then
	core.log("warning", "[living_villages] mcl_core:tree is missing; the chopping block was not registered")
	return NAME
end

local def = table.copy(log)
for _, field in ipairs({"name", "mod_origin", "type", "after_destruct", "_mcl_stripped_variant", "on_place",
	"on_rotate"}) do
	def[field] = nil
end
def.description = "Chopping Block"
def._tt_help = "A villager who claims it becomes a woodcutter"
def._doc_items_longdesc = "A villager out of work who claims a chopping block becomes the village's woodcutter: "
	.. "it plants a grove around the block, fells what grows and sells the logs."
def._doc_items_usagehelp = nil
def.paramtype2 = nil
def.groups = table.copy(log.groups or {})
def.groups.tree = nil
def.tiles = {}
for i, tile in ipairs(log.tiles or {}) do
	def.tiles[i] = type(tile) == "string" and (i <= 2 and tile .. TINT or tile) or tile
end
def.drop = NAME
core.register_node(NAME, def)

core.register_craft({
	type = "shapeless",
	output = NAME,
	recipe = {"group:tree", "mcl_tools:axe_stone"},
})

core.register_craft({
	type = "fuel",
	recipe = NAME,
	burntime = 15,
})

return NAME
