-- What a Builder pays for each node of a building. A node name is not an item: a
-- door is two nodes from one item, a stair changes name with its shape, a wall with
-- its connections, and water only comes in a bucket. Three questions, one rule table:
--
-- - cost(name): the items a node takes, or nil for one that costs nothing.
-- - identity(name): what makes two nodes the same thing built, so an open door, a
--   grown crop or a lit furnace counts as the door, crop or furnace it was.
-- - placed(name): the node to set, since a mature crop starts as a young one and a
--   schematic's lever is on.
--
-- Profession blocks are left out of a copy for the player to add (excluded), and a
-- few awkward items can be bought from the Builder (SALES), only as a project needs them.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")

local M = {}

local DIRT = "mcl_core:dirt"
M.DIRT = DIRT
M.EMPTY_BUCKET = "mcl_buckets:bucket_empty"

-- Ground a Builder may break for a site, and that a schematic's ground layer can stand
-- for. Each of these yields plain dirt. A sand or snow surface is not in the list.
local DIRT_FAMILY = {
	[DIRT] = true,
	["mcl_core:dirt_with_grass"] = true,
	["mcl_core:dirt_with_grass_snow"] = true,
	["mcl_core:coarse_dirt"] = true,
	["mcl_core:podzol"] = true,
	["mcl_core:mycelium"] = true,
}

function M.is_dirt(name)
	return DIRT_FAMILY[name] == true
end

-- Jobsites vanilla's table does not know: the keeper's (keeper.lua), the cleric's
-- (cleric.lua) and the Builder's own.
local EXCLUDED = {
	["mcl_jukebox:jukebox"] = true,
	["living_villages:pulpit"] = true,
	["living_villages:builder_block"] = true,
}

function M.excluded(name)
	return EXCLUDED[name] == true or common.is_workstation_node(name) == true
end

-- Liquids come in a bucket, and the empty bucket is the Builder's to return.
local LIQUIDS = {
	["mcl_core:water_source"] = "mcl_buckets:bucket_water",
	["mcl_core:lava_source"] = "mcl_buckets:bucket_lava",
}

-- A crop is planted young from what it grows from; every stage is the same crop.
local CROPS = {
	wheat = "mcl_farming:wheat_seeds",
	carrot = "mcl_farming:carrot_item",
	potato = "mcl_farming:potato_item",
}

-- Second halves, paid for with their first half.
local function is_free_half(name)
	return name:match("^mcl_doors:.*_door_t_%d$") ~= nil or name:match("^mcl_beds:bed_.*_top$") ~= nil
end

function M.is_top_half(name)
	return is_free_half(name)
end

function M.is_bottom_half(name)
	return name:match("^mcl_doors:.*_door_b_%d$") ~= nil or name:match("^mcl_beds:bed_.*_bottom$") ~= nil
end

-- The crop a node is a stage of, or nil.
local function crop_of(name)
	local crop = name:match("^mcl_farming:(%a+)$") or name:match("^mcl_farming:(%a+)_%d+$")
	return crop and CROPS[crop] and crop or nil
end

-- The item a node comes from, in the one shape a chest holds it, or the node itself.
local function base_item(name)
	if name == "mcl_villages:stonebrickcarved" then return "mcl_core:stonebrickcarved" end
	if DIRT_FAMILY[name] or name == "mcl_farming:soil" or name == "mcl_farming:soil_wet" then return DIRT end

	local door = name:match("^(mcl_doors:.*_door)_[bt]_%d$")
	if door then return door end
	local trapdoor = name:match("^(mcl_doors:.*trapdoor)_open$")
	if trapdoor then return trapdoor end
	local stair = name:match("^(mcl_stairs:stair_.*)_outer$") or name:match("^(mcl_stairs:stair_.*)_inner$")
	if stair then return stair end
	local slab = name:match("^(mcl_stairs:slab_.*)_top$") or name:match("^(mcl_stairs:slab_.*)_double$")
	if slab then return slab end
	local wall = name:match("^(mcl_walls:.*)_%d+$")
	if wall then return wall end
	local gate = name:match("^(mcl_fences:.*gate)_open$")
	if gate then return gate end
	local plate = name:match("^(mesecons_pressureplates:pressure_plate_.*)_on$")
	if plate then return plate .. "_off" end

	if name == "mcl_torches:torch_wall" then return "mcl_torches:torch" end
	if name == "mesecons_walllever:wall_lever_on" then return "mesecons_walllever:wall_lever_off" end
	if name == "mcl_furnaces:furnace_active" then return "mcl_furnaces:furnace" end
	if name:match("^mcl_chests:chest_") then return "mcl_chests:chest" end
	-- A pane's item is its flat form, whatever shape it has connected into.
	if name:match("^xpanes:") and not name:match("_flat$") then return name .. "_flat" end
	return name
end

function M.identity(name)
	local crop = crop_of(name)
	if crop then return "crop:" .. crop end
	-- A door's two halves share an item but are not the same cell.
	if name:match("^mcl_doors:.*_door_t_%d$") then return base_item(name) .. ":top" end
	return base_item(name)
end

-- item name -> count, or nil if the node costs nothing.
function M.cost(name)
	if name == "air" or is_free_half(name) or M.excluded(name) then return nil end
	if LIQUIDS[name] then return {[LIQUIDS[name]] = 1} end
	local crop = crop_of(name)
	if crop then return {[CROPS[crop]] = 1} end
	local flower = name:match("^mcl_flowerpots:flower_pot_(.+)$")
	if flower then return {["mcl_flowerpots:flower_pot"] = 1, ["mcl_flowers:" .. flower] = 1} end
	if name:match("^mcl_stairs:slab_.*_double$") then return {[base_item(name)] = 2} end
	return {[base_item(name)] = 1}
end

-- What placing it hands back, as item name -> count, or nil.
function M.returns(name)
	return LIQUIDS[name] and {[M.EMPTY_BUCKET] = 1} or nil
end

function M.placed(name)
	local crop = crop_of(name)
	if crop then return "mcl_farming:" .. crop .. "_1" end
	-- What a schematic's mcl_chests:chest becomes; set_node then gives it an inventory.
	if name == "mcl_chests:chest" then return "mcl_chests:chest_small" end
	if name == "mesecons_walllever:wall_lever_on" then return "mesecons_walllever:wall_lever_off" end
	return name
end

-- What the Builder sells, in emeralds, for items hard to come by. Everything here is
-- on sale only while a project lacks it (builder_status.lua).
M.EMERALD = "mcl_core:emerald"
M.SALES = {
	["mcl_buckets:bucket_water"] = 1,
	["mcl_buckets:bucket_lava"] = 2,
	["mcl_flowers:allium"] = 1,
	["mcl_flowers:azure_bluet"] = 1,
	["mcl_flowers:blue_orchid"] = 1,
	["mcl_flowers:oxeye_daisy"] = 1,
	["mcl_flowers:tulip_orange"] = 1,
	["mcl_flowers:tulip_white"] = 1,
	["mcl_ocean:sea_lantern"] = 4,
	["mcl_bells:bell"] = 16,
}

return M
