-- What a farm is made of: which crops a farmer tends, what is around its
-- composter, and the changes it makes to the plots. Farmer behaviour is in
-- farmer.lua; this only reads and writes nodes.
--
-- VoxeLibre's own place_seed and hoe handlers need a player, so plots are written
-- directly, the way those handlers write them.
local core = minetest

local FARM_RADIUS = 8
local FARM_HEIGHT = 2
local SOIL_NODES = {"mcl_farming:soil", "mcl_farming:soil_wet"}
-- The farmland ABM's own box for water (mcl_farming/soil.lua): 4 across, level or one up.
local HYDRATION_RADIUS = 4
local DEFAULT_MAX_PLOTS = 40

local CROPS = {
	{id = "wheat", mature = "mcl_farming:wheat", seed = "mcl_farming:wheat_seeds", prefix = "mcl_farming:wheat_", first = 1, last = 7},
	{id = "potato", mature = "mcl_farming:potato", seed = "mcl_farming:potato_item", prefix = "mcl_farming:potato_", first = 1, last = 7},
	{id = "carrot", mature = "mcl_farming:carrot", seed = "mcl_farming:carrot_item", prefix = "mcl_farming:carrot_", first = 1, last = 7},
	{id = "beetroot", mature = "mcl_farming:beetroot", seed = "mcl_farming:beetroot_seeds", prefix = "mcl_farming:beetroot_", first = 0, last = 2},
}

local mature_crops, growing_crops, seed_crops = {}, {}, {}
local mature_names, growing_names = {}, {}
for _, crop in ipairs(CROPS) do
	crop.plant = crop.prefix .. crop.first
	mature_crops[crop.mature] = crop
	seed_crops[crop.seed] = crop
	table.insert(mature_names, crop.mature)
	for stage = crop.first, crop.last do
		local name = crop.prefix .. stage
		growing_crops[name] = {crop = crop, stage = stage - crop.first}
		table.insert(growing_names, name)
	end
end

local M = {RADIUS = FARM_RADIUS, HEIGHT = FARM_HEIGHT}

local function crop_of(name)
	if mature_crops[name] then return mature_crops[name] end
	return growing_crops[name] and growing_crops[name].crop
end

local function above(pos) return {x = pos.x, y = pos.y + 1, z = pos.z} end
local function below(pos) return {x = pos.x, y = pos.y - 1, z = pos.z} end

local function is_soil(name)
	return name == SOIL_NODES[1] or name == SOIL_NODES[2]
end

local function node_sound(pos, name, kind)
	local def = core.registered_nodes[name]
	local sound = def and def.sounds and def.sounds[kind]
	if sound then core.sound_play(sound, {pos = pos, max_hear_distance = 16}, true) end
end

M.is_seed = function(name) return seed_crops[name] ~= nil end

-- Everything around the composter a farmer can work on. Positions are always the
-- cell the crop stands in, so a plot and the crop on it are one target.
function M.scan(job)
	local minp = {x = job.x - FARM_RADIUS, y = job.y - FARM_HEIGHT, z = job.z - FARM_RADIUS}
	local maxp = {x = job.x + FARM_RADIUS, y = job.y + FARM_HEIGHT, z = job.z + FARM_RADIUS}
	local result = {mature = {}, growing = {}, empty = {}, soil = {}}
	for _, pos in ipairs(core.find_nodes_in_area(minp, maxp, mature_names)) do
		if not core.is_protected(pos, "") then table.insert(result.mature, pos) end
	end
	for _, pos in ipairs(core.find_nodes_in_area(minp, maxp, growing_names)) do
		if not core.is_protected(pos, "") then
			local node = core.get_node_or_nil(pos)
			local growing = node and growing_crops[node.name]
			if growing then table.insert(result.growing, {pos = pos, stage = growing.stage}) end
		end
	end
	local soil_min = {x = minp.x, y = minp.y - 1, z = minp.z}
	local soil_max = {x = maxp.x, y = maxp.y - 1, z = maxp.z}
	for _, pos in ipairs(core.find_nodes_in_area(soil_min, soil_max, SOIL_NODES)) do
		table.insert(result.soil, pos)
		local cell = above(pos)
		local node = core.get_node_or_nil(cell)
		if node and node.name == "air" and not core.is_protected(cell, "") then
			table.insert(result.empty, cell)
		end
	end
	return result
end

local function max_plots()
	return tonumber(core.settings and core.settings:get("living_villages_farm_max_plots")) or DEFAULT_MAX_PLOTS
end

local function is_water(name)
	return core.get_item_group(name, "water") > 0
end

local function can_till(pos)
	local node = core.get_node_or_nil(pos)
	local over = core.get_node_or_nil(above(pos))
	-- VoxeLibre's hoe also takes a grass path, but a path is where villagers walk.
	return node and over and over.name == "air" and node.name ~= "mcl_core:grass_path"
		and core.get_item_group(node.name, "cultivatable") == 2
		and not core.is_protected(pos, "") and not core.is_protected(above(pos), "")
end

local function is_hydrated_at(pos)
	local minp = {x = pos.x - HYDRATION_RADIUS, y = pos.y, z = pos.z - HYDRATION_RADIUS}
	local maxp = {x = pos.x + HYDRATION_RADIUS, y = pos.y + 1, z = pos.z + HYDRATION_RADIUS}
	return #core.find_nodes_in_area(minp, maxp, {"group:water"}) > 0
end

-- Which cells may be tilled, as the cell above each (like every other plot target).
-- Ground in the farm's range is not all farm: a hoe would take the whole village's
-- lawn. So a field only grows outward from itself, onto ground that will stay wet,
-- and a composter with no field yet starts one against its water. That also covers
-- a plot that has reverted to dirt, and a kerb around a field, as on the stock farm,
-- keeps it to its bed.
function M.tillable(job, soil)
	local room = max_plots() - #soil
	if room <= 0 then return {} end
	local minp = {x = job.x - FARM_RADIUS, y = job.y - FARM_HEIGHT - 1, z = job.z - FARM_RADIUS}
	local maxp = {x = job.x + FARM_RADIUS, y = job.y + FARM_HEIGHT - 1, z = job.z + FARM_RADIUS}
	local field_cells = {}
	for _, pos in ipairs(soil) do field_cells[pos.x .. "," .. pos.y .. "," .. pos.z] = true end
	local result = {}
	for _, pos in ipairs(core.find_nodes_in_area(minp, maxp, {"group:cultivatable"})) do
		local touches = false
		for _, offset in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
			local side = {x = pos.x + offset[1], y = pos.y, z = pos.z + offset[2]}
			if #soil > 0 then
				touches = field_cells[side.x .. "," .. side.y .. "," .. side.z] == true
			else
				local node = core.get_node_or_nil(side)
				touches = node ~= nil and is_water(node.name)
			end
			if touches then break end
		end
		if touches and can_till(pos) and is_hydrated_at(pos) then table.insert(result, above(pos)) end
	end
	return result
end

-- Turns the ground under the cell to farmland. Returns whether it did. The field's
-- size is checked again here, since the list it came from may be a tick old.
function M.till(cell, soil_count)
	local pos = below(cell)
	if soil_count >= max_plots() or not can_till(pos) then return false end
	core.set_node(pos, {name = SOIL_NODES[1]})
	core.sound_play("default_dig_crumbly", {pos = pos, gain = 0.5, max_hear_distance = 16}, true)
	return true
end

-- Lifts a mature crop and returns what it dropped, as item strings. Nil if it is
-- not there any more. The drops are the node's own, so this yields what a player
-- gets. They are never left on the ground: VoxeLibre's villagers treat food they
-- pick up as breeding input.
function M.harvest(pos)
	local node = core.get_node_or_nil(pos)
	if not node or not mature_crops[node.name] or core.is_protected(pos, "") then return nil end
	local drops = core.get_node_drops(node, "")
	core.remove_node(pos)
	node_sound(pos, node.name, "dug")
	return drops
end

-- Which seed to sow in the cell: the one the pouch has most of, passing over any
-- crop already next to it where another will do, since VoxeLibre halves the growth
-- of a crop with the same crop on both axes. Nil if the pouch has no seeds.
function M.choose_seed(pos, count_of)
	local seeds = {}
	for _, crop in ipairs(CROPS) do
		local count = count_of(crop.seed)
		if count > 0 then table.insert(seeds, {crop = crop, count = count}) end
	end
	if #seeds == 0 then return nil end
	table.sort(seeds, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.crop.id < b.crop.id
	end)
	local neighbours = {}
	for _, offset in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
		local node = core.get_node_or_nil({x = pos.x + offset[1], y = pos.y, z = pos.z + offset[2]})
		local crop = node and crop_of(node.name)
		if crop then neighbours[crop.id] = true end
	end
	for _, seed in ipairs(seeds) do
		if not neighbours[seed.crop.id] then return seed.crop.seed end
	end
	return seeds[1].crop.seed
end

-- Sows the seed in the cell. Returns whether it did; the caller spends the seed.
function M.plant(pos, seed)
	local crop = seed_crops[seed]
	local node = core.get_node_or_nil(pos)
	local soil = core.get_node_or_nil(below(pos))
	if not crop or not node or node.name ~= "air" or not soil or not is_soil(soil.name)
		or core.is_protected(pos, "") then
		return false
	end
	local def = core.registered_nodes[crop.plant]
	core.set_node(pos, {name = crop.plant, param2 = def and def.place_param2 or 0})
	node_sound(pos, crop.plant, "place")
	return true
end

return M
