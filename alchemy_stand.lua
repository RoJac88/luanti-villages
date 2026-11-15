-- The alchemist's stand (docs/villager-economy-design.md, ticket 20), the block a villager
-- claims to become an alchemist (alchemist.lua). A brewing stand in shape, recoloured, but
-- no brewing stand: no inventory, no formspec, no timer, and not an mcl_brewing node, so
-- a vanilla cleric never looks for it. Registered at load time, not from
-- register_on_mods_loaded: register_node checks the current mod name.
--
-- Never generated with a village. A player crafts one from the four elements, read with the
-- top of the grid as north: a feather (air) north, a nautilus shell (water) east, a
-- stone-tier block (earth, group:cobble, as stone tools take) south and a blaze rod (fire)
-- west, the centre empty.
local core = minetest

local NAME = "living_villages:alchemy_stand"
local TINT = "^[multiply:#7fd6c2"

local stand = core.registered_nodes["mcl_brewing:stand_000"]
if not stand then
	core.log("warning", "[living_villages] mcl_brewing:stand_000 is missing; the alchemist's stand was not registered")
	return NAME
end

local def = table.copy(stand)
for _, field in ipairs({"name", "mod_origin", "type", "on_construct", "on_destruct", "on_timer", "on_receive_fields",
	"on_rotate", "allow_metadata_inventory_take", "allow_metadata_inventory_put", "allow_metadata_inventory_move",
	"on_metadata_inventory_put", "on_metadata_inventory_take", "on_metadata_inventory_move",
	"_mcl_hoppers_on_try_push", "_mcl_hoppers_on_try_pull", "_mcl_hoppers_on_after_push",
	"_mcl_hoppers_on_after_pull", "_doc_items_usagehelp"}) do
	def[field] = nil
end
def.description = "Alchemist's Stand"
def._tt_help = "A villager who claims it becomes an alchemist"
def._doc_items_longdesc = "A villager out of work who claims an alchemist's stand becomes an alchemist: "
	.. "it buys stone and logs and turns them into iron, flint, glass and gold."
def.groups = table.copy(stand.groups or {})
def.groups.container, def.groups.brewitem = nil, nil
def.tiles = {}
for i, tile in ipairs(stand.tiles or {}) do
	def.tiles[i] = type(tile) == "string" and tile .. TINT or tile
end
def.drop = NAME
core.register_node(NAME, def)

core.register_craft({
	output = NAME,
	recipe = {
		{"", "mcl_mobitems:feather", ""},
		{"mcl_mobitems:blaze_rod", "", "mcl_mobitems:nautilus_shell"},
		{"", "group:cobble", ""},
	},
})

return NAME
