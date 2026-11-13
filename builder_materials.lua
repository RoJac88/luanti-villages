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

-- The ground as a building's floor finds it: dirt, or a path villagers have worn into the
-- grass, which they will do across a site while it waits for its floor.
function M.is_ground(name)
	return DIRT_FAMILY[name] == true or name == "mcl_core:grass_path"
end

-- Jobsites vanilla's table does not know: the keeper's (keeper.lua), the cleric's
-- (cleric.lua), the woodcutter's (woodcutter.lua) and the Builder's own.
local EXCLUDED = {
	["mcl_jukebox:jukebox"] = true,
	["living_villages:pulpit"] = true,
	["living_villages:chopping_block"] = true,
	["living_villages:builder_block"] = true,
}

function M.excluded(name)
	return EXCLUDED[name] == true or common.is_workstation_node(name) == true
end

-- What a villager comes to claim: a job block (a stock building leaves those out), or a bed.
function M.draws_villagers(name)
	return M.excluded(name) or name:match("^mcl_beds:bed_") ~= nil
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

-- A door's "b"ottom or "t"op half. Several mods register doors: mcl_bamboo, mcl_crimson...
function M.is_door_half(name, half)
	return name:match("^[%w_]+:.*_door_" .. half .. "_%d$") ~= nil
end

-- Second halves, paid for with their first half.
local function is_free_half(name)
	return M.is_door_half(name, "t") or name:match("^mcl_beds:bed_.*_top$") ~= nil
end

function M.is_top_half(name)
	return is_free_half(name)
end

function M.is_bottom_half(name)
	return M.is_door_half(name, "b") or name:match("^mcl_beds:bed_.*_bottom$") ~= nil
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

	local door = name:match("^([%w_]+:.*_door)_[bt]_%d$")
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
	-- No one holds an unlit campfire: the item is the lit one. A banner's look is in its
	-- metadata, which a schematic does not keep, so any banner will do; a white one.
	if name == "mcl_campfires:campfire" then return "mcl_campfires:campfire_lit" end
	-- A hanging lantern is the standing one, placed under a block.
	local lantern = name:match("^(mcl_lanterns:.*lantern)_ceiling$")
	if lantern then return lantern .. "_floor" end
	if name == "mcl_banners:hanging_banner" or name == "mcl_banners:standing_banner" then
		return "mcl_banners:banner_item_white"
	end
	if name:match("^mcl_chests:chest_") then return "mcl_chests:chest" end
	-- A pane's item is its flat form, whatever shape it has connected into.
	if name:match("^xpanes:") and not name:match("_flat$") then return name .. "_flat" end
	return name
end

function M.identity(name)
	local crop = crop_of(name)
	if crop then return "crop:" .. crop end
	-- A door's two halves share an item but are not the same cell.
	if M.is_door_half(name, "t") then return base_item(name) .. ":top" end
	return base_item(name)
end

-- Kelp and seagrass are no blocks of their own: placed under water, either turns the block it
-- is placed on into one node of both (mcl_ocean:kelp_sand), which no one holds and digging does
-- not drop. It costs the block and the plant. A kelp taller than one costs the one kelp still.
local PLANTED_ON = {dirt = "mcl_core:dirt", sand = "mcl_core:sand", redsand = "mcl_core:redsand",
	gravel = "mcl_core:gravel"}

-- The plant and the block it grows from, or nil for any other node.
local function planted_parts(name)
	local plant, surface = name:match("^mcl_ocean:(%a+)_(%a+)$")
	if (plant == "kelp" or plant == "seagrass") and PLANTED_ON[surface] then
		return "mcl_ocean:" .. plant, PLANTED_ON[surface]
	end
end

-- The block a water plant grows from, or nil. Out of water the plant drops off and leaves
-- that block, so a Builder plants after the water is in, and puts the plant back on the block.
function M.planted_on(name)
	local _, surface = planted_parts(name)
	return surface
end

local function planted(name)
	local plant, surface = planted_parts(name)
	if plant then return {[surface] = 1, [plant] = 1} end
end

local function items_for(name)
	if LIQUIDS[name] then return {[LIQUIDS[name]] = 1} end
	local plant = planted(name)
	if plant then return plant end
	local crop = crop_of(name)
	if crop then return {[CROPS[crop]] = 1} end
	local flower = name:match("^mcl_flowerpots:flower_pot_(.+)$")
	if flower then return {["mcl_flowerpots:flower_pot"] = 1, ["mcl_flowers:" .. flower] = 1} end
	if name:match("^mcl_stairs:slab_.*_double$") then return {[base_item(name)] = 2} end
	return {[base_item(name)] = 1}
end

-- item name -> count, or nil if the node costs nothing.
function M.cost(name)
	if name == "air" or is_free_half(name) or M.excluded(name) then return nil end
	return items_for(name)
end

-- An item a player can hold: registered, and not one of the variants hidden from the
-- creative inventory, such as a wall sign or a composter's fill level.
local function holdable(item, engine)
	local def = engine.registered_items and engine.registered_items[item] or engine.registered_nodes[item]
	if not def then return false end
	return not (def.groups and (def.groups.not_in_creative_inventory or 0) > 0)
end

-- The one item a node always drops, or nil. Random or empty drops say nothing.
local function sure_drop(def)
	local drop = def and def.drop
	if type(drop) == "table" and drop.items and #drop.items == 1 and not drop.items[1].rarity then
		drop = drop.items[1].items and #drop.items[1].items == 1 and drop.items[1].items[1]
	end
	return type(drop) == "string" and drop:match("^%S+") or nil
end

-- Farmland: dirt worked with a hoe, which dries back to dirt with nothing growing on it.
function M.is_soil(name)
	return name == "mcl_farming:soil" or name == "mcl_farming:soil_wet"
end

-- What a node of a player's schematic costs: the rule table above was written for stock
-- buildings, so it is checked against what exists here. Job blocks are built and paid for,
-- since a player who put one in a schematic wants it. Soil is free: it is the ground
-- worked, and a bed can dry out and need doing again before its water is in. Returns item name -> count, nil for
-- a node that costs nothing, or nil and "no_item" for one no player can supply.
function M.custom_cost(name, engine)
	engine = engine or core
	local def = engine.registered_nodes[name]
	if name == "air" or is_free_half(name) or M.is_soil(name) or (def and def.liquidtype == "flowing") then return nil end
	local cost = {}
	for item, count in pairs(items_for(name)) do
		if not holdable(item, engine) then
			item = sure_drop(engine.registered_nodes[item] or def)
			if not item or not holdable(item, engine) then return nil, "no_item" end
		end
		cost[item] = (cost[item] or 0) + count
	end
	return cost
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

-- What the Builder asks for an item on sale, or nil: SALES, times ledger.SCALE with
-- the economy on (ticket 11h), when every emerald amount scales.
local clock, scale
function M.sale_price(item)
	local price = M.SALES[item]
	if not price then return nil end
	clock = clock or dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
	if not clock.enabled() then return price end
	scale = scale or dofile(core.get_modpath("living_villages") .. "/ledger.lua").SCALE
	return price * scale
end

return M
