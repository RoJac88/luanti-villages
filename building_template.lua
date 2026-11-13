-- A building as the steps that make it. A Builder's progress is never saved: each
-- look compares these steps with the world, so a reload, or a player taking a wall
-- down again, needs no special handling.
--
-- The cells come from the schematic the village generator would place, with its name
-- swaps (copied from mcl_villages/buildings.lua place_schematics, where they are
-- inline), rotated by the engine itself onto a VoxelManip that is never written back.
-- That is the one way to get the rotated param2 exactly as a generated building has it.
--
-- The steps go in passes, so nothing is set before what it hangs on:
-- 0 earthwork and clearing, 1 solid nodes bottom-up, 2 attached nodes and pairs,
-- 3 liquids, which would run out of unfinished walls; in a player's schematic,
-- 4 soil, which dries out without its water, and 5 what grows in it or under the water; and last,
-- 6 job blocks and beds, which bring villagers in to claim them.
local core = minetest
local materials = dofile(core.get_modpath("living_villages") .. "/builder_materials.lua")

local M = {}

local PASS_CLEAR, PASS_SOLID, PASS_ATTACHED, PASS_LIQUID, PASS_SOIL, PASS_ROOTED = 0, 1, 2, 3, 4, 5
-- A villager who claims a job block or a bed in an unfinished building works or sleeps in
-- the way, and wears paths across it.
local PASS_CLAIMED = 6
M.PASS_CLEAR, M.PASS_SOLID, M.PASS_ATTACHED, M.PASS_LIQUID = PASS_CLEAR, PASS_SOLID, PASS_ATTACHED, PASS_LIQUID

local AIR = "air"
-- facedir 0..3: which way a bed's top half lies from its bottom half.
local FACING = {[0] = {x = 0, z = 1}, {x = 1, z = 0}, {x = 0, z = -1}, {x = -1, z = 0}}

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

-- One node name as place_schematics rewrites it. These are its gsubs in its order, and
-- like them they match anywhere in the name, which is why stonebrickcarved goes first.
function M.swap_name(name, surface_mat, replace_wall)
	local surface = surface_mat or "mcl_core:dirt_with_grass"
	local function swap(from, to) name = name:gsub(from, to) end
	swap("mcl_core:stonebrickcarved", "mcl_villages:stonebrickcarved")
	if replace_wall then
		if surface == "mcl_core:snow" or surface == "mcl_core:dirt_with_grass_snow" or surface == "mcl_core:podzol" then
			swap("mcl_core:tree", "mcl_core:sprucetree")
			swap("mcl_core:wood", "mcl_core:sprucewood")
		elseif surface == "mcl_core:sand" or surface == "mcl_core:redsand" then
			swap("mcl_core:tree", "mcl_core:sandstonecarved")
			swap("mcl_core:cobble", "mcl_core:sandstone")
			swap("mcl_core:wood", "mcl_core:sandstonesmooth")
			swap("mcl_core:brick_block", "mcl_core:redsandstone")
		end
	end
	swap("mcl_core:dirt_with_grass", surface)
	swap("mcl_stairs:stair_wood_outer", "mcl_stairs:slab_wood")
	swap("mcl_stairs:stair_stone_rough_outer", AIR)
	return name
end

-- A copy of a schematic_table entry's schematic with the generator's swaps made. The
-- entry's mts is a file name or, once this mod has furnished it, a table.
function M.prepare_schematic(entry, surface_mat, engine)
	engine = engine or core
	local serialized = engine.serialize_schematic(entry.mts, "lua", {
		lua_use_comments = false, lua_num_indent_spaces = 0,
	})
	local loader = serialized and loadstring(serialized .. " return schematic")
	local schematic = loader and loader()
	if not (schematic and schematic.size and schematic.data) then return nil end
	for _, cell in ipairs(schematic.data) do
		cell.name = M.swap_name(cell.name, surface_mat, entry.rplc)
	end
	return schematic
end

-- The rolls of a player's schematic. Its probabilities would otherwise be rolled afresh at
-- each placement, and what is left to build is worked out by placing it, so a restart would
-- find a different building half done. A project's seed makes them once and for all: each cell
-- and slice ends up always (255) or never (0). A read schematic's probs run 0..254, in twos.
local function roll_probabilities(schematic, seed)
	local state = seed % 4294967296
	local function settled(prob)
		prob = prob or 255
		if prob >= 254 then return 255 end
		if prob <= 0 then return 0 end
		state = (state * 1664525 + 1013904223) % 4294967296
		return math.floor(state / 65536) % 254 < prob and 255 or 0
	end
	for _, cell in ipairs(schematic.data) do cell.prob = settled(cell.prob) end
	for _, slice in ipairs(schematic.yslice_prob or {}) do slice.prob = settled(slice.prob) end
end

-- A player's schematic as a project builds it: with its own names, since it is what the
-- player made, and its rolls settled by `seed`.
function M.prepare_custom(path, seed, engine)
	engine = engine or core
	local schematic = engine.read_schematic(path, {write_yslice_prob = "low"})
	if not (schematic and schematic.size and schematic.data) then return nil end
	roll_probabilities(schematic, seed)
	return schematic
end

-- The size a schematic takes up at a rotation ("0", "90", "180", "270").
function M.rotated_size(size, rotation)
	if rotation == "90" or rotation == "270" then return {x = size.z, y = size.y, z = size.x} end
	return {x = size.x, y = size.y, z = size.z}
end

-- Every cell of the schematic at pos (its minimum corner, as a generated building's
-- pos is), as the engine would place it. Nothing reaches the map: the VoxelManip is
-- read and dropped. Returns a list of {pos, name, param2}, or nil if it cannot be placed.
-- With `blank`, what the schematic does not place reads as "ignore", which a plan leaves
-- alone. Otherwise a void would read as whatever happens to be there.
function M.world_cells(schematic, pos, rotation, engine, blank)
	engine = engine or core
	local size = M.rotated_size(schematic.size, rotation)
	local p2 = {x = pos.x + size.x - 1, y = pos.y + size.y - 1, z = pos.z + size.z - 1}
	local vm = engine.get_voxel_manip()
	local emin, emax = vm:read_from_map(pos, p2)
	if blank then
		local cleared = vm:get_data()
		for i = 1, #cleared do cleared[i] = engine.CONTENT_IGNORE end
		vm:set_data(cleared)
	end
	if not engine.place_schematic_on_vmanip(vm, pos, schematic, rotation, nil, true) then return nil end
	local data, param2 = vm:get_data(), vm:get_param2_data()
	local nx, ny = emax.x - emin.x + 1, emax.y - emin.y + 1
	local cells = {}
	for z = pos.z, p2.z do
		for y = pos.y, p2.y do
			for x = pos.x, p2.x do
				local i = (z - emin.z) * ny * nx + (y - emin.y) * nx + (x - emin.x) + 1
				cells[#cells + 1] = {
					pos = {x = x, y = y, z = z},
					name = engine.get_name_from_content_id(data[i]),
					param2 = param2[i],
				}
			end
		end
	end
	return cells
end

local function pass_of(name, engine)
	local def = engine.registered_nodes[name]
	if def and (def.liquidtype or "none") ~= "none" then return PASS_LIQUID end
	if materials.is_bottom_half(name) or materials.is_top_half(name) then return PASS_ATTACHED end
	if engine.get_item_group(name, "attached_node") > 0 then return PASS_ATTACHED end
	return PASS_SOLID
end

-- The cell holding a bottom half's other half, or nil.
local function top_half_of(cell, by_pos)
	if not materials.is_bottom_half(cell.name) then return nil end
	local pos = cell.pos
	if materials.is_door_half(cell.name, "b") then
		return by_pos[key({x = pos.x, y = pos.y + 1, z = pos.z})]
	end
	local facing = FACING[cell.param2 % 4]
	return by_pos[key({x = pos.x + facing.x, y = pos.y, z = pos.z + facing.z})]
end

local function is_ground_cell(name, surface_mat)
	return name == AIR or materials.is_dirt(name) or name == surface_mat
end

-- The steps for a building's cells. `options`: floor_y, the y of its ground layer;
-- surface_mat; and earthwork = {cuts = positions, fills = positions}, from the site.
--
-- A step is {kind, pos, pass, node = {name, param2}, top = {pos, node}, cost, returns}.
-- kind is "place" (node wanted here), "clear" (air wanted here), "cut" (dirt in the
-- way, gone for nothing) or "fill" (dirt from nothing, under the floor).
--
-- The ground layer stands in for the ground that is there, so it is neither built nor
-- paid for, unless it is more than ground (a belltower's posts). Profession blocks
-- are left out; the cell is not even kept clear, as the player may add one at any time.
--
-- With options.custom the cells are a player's schematic. Profession blocks are built, since
-- the player put them there, and flowing liquid is left to run from its source.
function M.plan(cells, options, engine)
	engine = engine or core
	local floor_y, surface_mat, custom = options.floor_y, options.surface_mat, options.custom
	local function skipped(name)
		if custom then
			local def = engine.registered_nodes[name]
			return def ~= nil and def.liquidtype == "flowing"
		end
		return materials.excluded(name)
	end
	local by_pos = {}
	for _, cell in ipairs(cells) do by_pos[key(cell.pos)] = cell end

	local steps, wanted_dirt = {}, {}
	for _, cell in ipairs(cells) do
		local name, on_floor = cell.name, cell.pos.y == floor_y
		if materials.identity(name) == materials.DIRT then wanted_dirt[key(cell.pos)] = true end
		if skipped(name) or name == "ignore" or (on_floor and is_ground_cell(name, surface_mat)) then
			-- Nothing to do here.
		elseif name == AIR then
			steps[#steps + 1] = {kind = "clear", pos = cell.pos, pass = PASS_CLEAR}
		elseif not materials.is_top_half(name) then
			local pass = pass_of(name, engine)
			-- Soil with no water by it soon dries to dirt, so a player's beds wait for their water,
			-- and what grows in them for the beds.
			if materials.draws_villagers(name) then
				pass = PASS_CLAIMED
			elseif custom and materials.is_soil(name) then
				pass = PASS_SOIL
			elseif materials.planted_on(name) then
				-- Kelp or seagrass out of water drops off its block within a second.
				pass = PASS_ROOTED
			elseif custom and pass == PASS_ATTACHED then
				local below = by_pos[key({x = cell.pos.x, y = cell.pos.y - 1, z = cell.pos.z})]
				if below and materials.is_soil(below.name) then pass = PASS_ROOTED end
			end
			-- A player's node can be free, where materials.cost would charge for it.
			local cost
			if custom then cost = materials.custom_cost(name, engine) else cost = materials.cost(name) end
			local step = {
				kind = "place",
				pos = cell.pos,
				pass = pass,
				-- The generator resets water for its biome colour (fix_village_water): a
				-- schematic's param2 is not what a generated source ends up with.
				node = {name = materials.placed(name), param2 = pass == PASS_LIQUID and 0 or cell.param2},
				cost = cost,
				custom = custom,
				returns = materials.returns(name),
				on_floor = on_floor or nil,
			}
			local top = top_half_of(cell, by_pos)
			if top then step.top = {pos = top.pos, node = {name = top.name, param2 = top.param2}} end
			steps[#steps + 1] = step
		end
	end

	local earthwork = options.earthwork or {}
	local cut_at = {}
	for _, pos in ipairs(earthwork.cuts or {}) do
		-- Dirt the building itself wants here is the job done already.
		if not wanted_dirt[key(pos)] then
			cut_at[key(pos)] = true
			steps[#steps + 1] = {kind = "cut", pos = pos, pass = PASS_CLEAR}
		end
	end
	for _, pos in ipairs(earthwork.fills or {}) do
		steps[#steps + 1] = {kind = "fill", pos = pos, pass = PASS_CLEAR, node = {name = materials.DIRT, param2 = 0}}
	end

	-- Cuts, then fills, bottom-up, then the rest of the clearing.
	local CLEAR_ORDER = {cut = 1, fill = 2, clear = 3, place = 4}
	table.sort(steps, function(a, b)
		if a.pass ~= b.pass then return a.pass < b.pass end
		if CLEAR_ORDER[a.kind] ~= CLEAR_ORDER[b.kind] then return CLEAR_ORDER[a.kind] < CLEAR_ORDER[b.kind] end
		if a.pos.y ~= b.pos.y then return a.pos.y < b.pos.y end
		if a.pos.z ~= b.pos.z then return a.pos.z < b.pos.z end
		return a.pos.x < b.pos.x
	end)
	return {steps = steps, floor_y = floor_y, surface_mat = surface_mat, cut_at = cut_at}
end

-- Item name -> count over a list of steps.
function M.bill(steps)
	local bill = {}
	for _, step in ipairs(steps) do
		for item, count in pairs(step.cost or {}) do bill[item] = (bill[item] or 0) + count end
	end
	return bill
end

-- Plants and snow, which building simply replaces, and flowing liquid.
local function is_open(name, engine)
	if name == AIR then return true end
	local def = engine.registered_nodes[name]
	return def ~= nil and def.buildable_to == true
end

-- A building's own source can run into a cell it wants empty. Clearing that would
-- never end, and the generator's copy would hold the same flow.
local function is_flowing(name, engine)
	local def = engine.registered_nodes[name]
	return def ~= nil and def.liquidtype == "flowing"
end

-- Ground the site search builds on (builder_site.lua counts any solid natural node a column's
-- ground): what the floor layer may replace, sand or stone as much as grass. A placed node
-- (is_ground_content false) is someone's work, and in the way.
local function natural_ground(name, engine)
	if materials.is_ground(name) then return true end
	local def = engine.registered_nodes[name]
	return def ~= nil and def.is_ground_content ~= false and def.walkable ~= false
		and (def.liquidtype or "none") == "none"
end

local function matches(wanted, found)
	return materials.identity(wanted) == materials.identity(found)
end

local function same_cost(a, b)
	if not a or not b then return false end
	for item, count in pairs(a) do
		if b[item] ~= count then return false end
	end
	for item in pairs(b) do
		if not a[item] then return false end
	end
	return true
end

-- Whether a step's node stands here. A player's schematic can hold states the rule table has
-- never met, a filling composter or a lit smoker: what costs the same is the same thing built.
local function stands(step, found, engine)
	if matches(step.node.name, found) then return true end
	return step.custom and same_cost(step.cost, materials.custom_cost(found, engine)) or false
end

local function is_solid(name, engine)
	local def = engine.registered_nodes[name]
	return def ~= nil and def.groups ~= nil and (def.groups.solid or 0) > 0
end

-- A player's soil has to be soil. Dirt counts as the same thing built in a stock building, where
-- soil stands above the ground and only ever dries, but a bed at floor level would then pass as
-- the grass already there, and the crops on it would die and be paid for again and again.
-- Returns whether it is done, and whether it can be done now. Dirt under something solid stays
-- dirt whatever is done to it, so it counts as done.
local function soil_state(step, found, get_name, engine)
	if materials.is_soil(found) then return true, true end
	if not (materials.is_ground(found) or is_open(found, engine)) then return false, false end
	local above = get_name({x = step.pos.x, y = step.pos.y + 1, z = step.pos.z})
	if materials.is_ground(found) and above and is_solid(above, engine) then return true, true end
	return false, true
end

-- Compares a plan with the world. `get_name(pos)` returns a node's name there, or nil
-- for an unloaded one. Returns what is left to do, in order, and the positions where
-- something foreign is in the way. Unloaded cells count as neither.
function M.compare(plan, get_name, engine)
	engine = engine or core
	local missing, blocked = {}, {}
	for _, step in ipairs(plan.steps) do
		local found = get_name(step.pos)
		if found then
			if step.kind == "cut" then
				if materials.is_dirt(found) then missing[#missing + 1] = step end
			elseif step.kind == "fill" then
				if is_open(found, engine) then missing[#missing + 1] = step end
			elseif step.kind == "clear" then
				if found ~= AIR and not is_flowing(found, engine) then
					-- A cut comes first and takes the dirt from a cell it shares with a clear.
					if is_open(found, engine) then
						missing[#missing + 1] = step
					elseif not (plan.cut_at[key(step.pos)] and materials.is_dirt(found)) then
						blocked[#blocked + 1] = step.pos
					end
				end
			elseif step.custom and materials.is_soil(step.node.name) then
				local done, possible = soil_state(step, found, get_name, engine)
				if not possible then
					blocked[#blocked + 1] = step.pos
				elseif not done then
					missing[#missing + 1] = step
				end
			else
				local top_found = step.top and get_name(step.top.pos)
				if not stands(step, found, engine) then
					local ground = found == plan.surface_mat or natural_ground(found, engine)
					local replaceable = is_open(found, engine) or (step.on_floor and ground)
						or found == materials.planted_on(step.node.name)
						or (plan.cut_at[key(step.pos)] and materials.is_dirt(found))
					if replaceable then
						missing[#missing + 1] = step
					else
						blocked[#blocked + 1] = step.pos
					end
				elseif step.top and top_found and not matches(step.top.node.name, top_found) then
					-- Half a pair stands, already paid for.
					if is_open(top_found, engine) then
						missing[#missing + 1] = {
							kind = "place", pos = step.top.pos, pass = step.pass, node = step.top.node,
						}
					else
						blocked[#blocked + 1] = step.top.pos
					end
				end
			end
		end
	end
	return missing, blocked
end

-- What to carry for the next steps, as item name -> count: as many steps in order as
-- `capacity` items pay for, so the pouch never fills with roof while walls wait.
function M.next_batch(missing, capacity)
	local batch, total = {}, 0
	for _, step in ipairs(missing) do
		local size = 0
		for _, count in pairs(step.cost or {}) do size = size + count end
		if total + size > capacity then break end
		for item, count in pairs(step.cost or {}) do batch[item] = (batch[item] or 0) + count end
		total = total + size
	end
	return batch, total
end

return M
