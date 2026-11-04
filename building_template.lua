-- A building as the steps that make it. A Builder's progress is never saved: each
-- look compares these steps with the world, so a reload, or a player taking a wall
-- down again, needs no special handling.
--
-- The cells come from the schematic the village generator would place, with its name
-- swaps (copied from mcl_villages/buildings.lua place_schematics, where they are
-- inline), rotated by the engine itself onto a VoxelManip that is never written back.
-- That is the one way to get the rotated param2 exactly as a generated building has it.
--
-- The steps go in four passes, so nothing is set before what it hangs on:
-- 0 earthwork and clearing, 1 solid nodes bottom-up, 2 attached nodes and pairs,
-- 3 liquids, which would run out of unfinished walls.
local core = minetest
local materials = dofile(core.get_modpath("living_villages") .. "/builder_materials.lua")

local M = {}

local PASS_CLEAR, PASS_SOLID, PASS_ATTACHED, PASS_LIQUID = 0, 1, 2, 3
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

-- The size a schematic takes up at a rotation ("0", "90", "180", "270").
function M.rotated_size(size, rotation)
	if rotation == "90" or rotation == "270" then return {x = size.z, y = size.y, z = size.x} end
	return {x = size.x, y = size.y, z = size.z}
end

-- Every cell of the schematic at pos (its minimum corner, as a generated building's
-- pos is), as the engine would place it. Nothing reaches the map: the VoxelManip is
-- read and dropped. Returns a list of {pos, name, param2}, or nil if it cannot be placed.
function M.world_cells(schematic, pos, rotation, engine)
	engine = engine or core
	local size = M.rotated_size(schematic.size, rotation)
	local p2 = {x = pos.x + size.x - 1, y = pos.y + size.y - 1, z = pos.z + size.z - 1}
	local vm = engine.get_voxel_manip()
	local emin, emax = vm:read_from_map(pos, p2)
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
	if cell.name:find("^mcl_doors:") then
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
function M.plan(cells, options, engine)
	engine = engine or core
	local floor_y, surface_mat = options.floor_y, options.surface_mat
	local by_pos = {}
	for _, cell in ipairs(cells) do by_pos[key(cell.pos)] = cell end

	local steps, wanted_dirt = {}, {}
	for _, cell in ipairs(cells) do
		local name, on_floor = cell.name, cell.pos.y == floor_y
		if materials.identity(name) == materials.DIRT then wanted_dirt[key(cell.pos)] = true end
		if materials.excluded(name) or name == "ignore" or (on_floor and is_ground_cell(name, surface_mat)) then
			-- Nothing to do here.
		elseif name == AIR then
			steps[#steps + 1] = {kind = "clear", pos = cell.pos, pass = PASS_CLEAR}
		elseif not materials.is_top_half(name) then
			local pass = pass_of(name, engine)
			local step = {
				kind = "place",
				pos = cell.pos,
				pass = pass,
				-- The generator resets water for its biome colour (fix_village_water): a
				-- schematic's param2 is not what a generated source ends up with.
				node = {name = materials.placed(name), param2 = pass == PASS_LIQUID and 0 or cell.param2},
				cost = materials.cost(name),
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

local function matches(wanted, found)
	return materials.identity(wanted) == materials.identity(found)
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
			else
				local top_found = step.top and get_name(step.top.pos)
				if not matches(step.node.name, found) then
					local ground = materials.is_dirt(found) or found == plan.surface_mat
					local replaceable = is_open(found, engine) or (step.on_floor and ground)
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
