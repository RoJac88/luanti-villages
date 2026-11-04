-- The Builder's data on the real engine, for what the stubbed tests cannot show. After a
-- village is built this waits for the house's ABM and records: the bench, the double chest
-- and their inventories; any item a stock building costs that is not registered; and, for
-- every building of the village, each cell where what building_template.lua predicts
-- differs from what the generator placed, so that the rotated cells a Builder works from
-- are known to be the real ones. Only runs when lv_probe_builder is set.
local core = minetest

local builder = {}

local WAIT_SECONDS = 30
local SAMPLES = 8

function builder.enabled()
	return (tonumber(core.settings:get("lv_probe_builder")) or 0) > 0
end

local function modules()
	local path = core.get_modpath("living_villages")
	return dofile(path .. "/builder_materials.lua"), dofile(path .. "/building_template.lua")
end

local function entry_of(name)
	for _, entry in ipairs(settlements.schematic_table) do
		if entry.name == name then return entry end
	end
end

local function pos_text(pos) return core.pos_to_string(pos) end

-- Costs that name no registered item, over every building and surface.
local function unknown_items(materials, template)
	local unknown, seen = {}, {}
	for _, entry in ipairs(settlements.schematic_table) do
		for surface in pairs(settlements.surface_mat) do
			local schematic = template.prepare_schematic(entry, surface)
			for _, cell in ipairs(schematic and schematic.data or {}) do
				if not seen[cell.name] then
					seen[cell.name] = true
					if cell.name ~= "air" and not core.registered_nodes[materials.placed(cell.name)] then
						unknown["node " .. materials.placed(cell.name)] = cell.name
					end
					for item in pairs(materials.cost(cell.name) or {}) do
						if not core.registered_items[item] then unknown[item] = cell.name end
					end
					for item in pairs(materials.returns(cell.name) or {}) do
						if not core.registered_items[item] then unknown[item] = cell.name end
					end
				end
			end
		end
	end
	for item in pairs(materials.SALES) do
		if not core.registered_items[item] then unknown[item] = "on sale" end
	end
	return unknown
end

-- Each cell of a building where the prediction and the map differ.
local function compare_building(building, template)
	local entry = entry_of(building.name)
	if not entry then return {error = "no schematic_table entry"} end
	local schematic = template.prepare_schematic(entry, building.surface_mat)
	if not schematic then return {error = "cannot read the schematic"} end
	local cells = template.world_cells(schematic, building.pos, building.rotat)
	if not cells then return {error = "cannot place it on a VoxelManip"} end
	local result = {name = building.name, rotat = building.rotat, cells = #cells, wrong = 0, wrong_param2 = 0, kinds = {}, samples = {}}
	for _, cell in ipairs(cells) do
		local node = core.get_node(cell.pos)
		-- The generator swaps ground in and out per building (ground_layer.lua, loomless_house.lua).
		if cell.pos.y ~= building.pos.y then
			if node.name ~= cell.name then
				result.wrong = result.wrong + 1
				local kind = cell.name .. " -> " .. node.name
				result.kinds[kind] = (result.kinds[kind] or 0) + 1
			elseif node.param2 ~= cell.param2 then
				result.wrong_param2 = result.wrong_param2 + 1
				local kind = cell.name .. " param2"
				result.kinds[kind] = (result.kinds[kind] or 0) + 1
				if #result.samples < SAMPLES then
					result.samples[#result.samples + 1] = pos_text(cell.pos) .. " " .. cell.name
						.. " wants " .. cell.param2 .. " has " .. node.param2
				end
			end
		end
	end
	return result
end

-- The Builder's house: the bench, and each chest near it with its inventory.
local function check_houses(info)
	local houses = {}
	local minp, maxp
	for _, building in ipairs(info) do
		local low, high = vector.offset(building.pos, -2, -2, -2), vector.offset(building.pos, 16, 16, 16)
		minp = minp and {x = math.min(minp.x, low.x), y = math.min(minp.y, low.y), z = math.min(minp.z, low.z)} or low
		maxp = maxp and {x = math.max(maxp.x, high.x), y = math.max(maxp.y, high.y), z = math.max(maxp.z, high.z)} or high
	end
	for _, bench in ipairs(core.find_nodes_in_area(minp, maxp, {"living_villages:builder_block"})) do
		local chests = {}
		local low, high = vector.offset(bench, -6, -2, -6), vector.offset(bench, 6, 2, 6)
		for _, pos in ipairs(core.find_nodes_in_area(low, high, {"mcl_chests:chest_small", "mcl_chests:chest_left", "mcl_chests:chest_right"})) do
			local node = core.get_node(pos)
			chests[#chests + 1] = {
				pos = pos_text(pos), name = node.name, param2 = node.param2,
				size = core.get_meta(pos):get_inventory():get_size("main"),
			}
		end
		houses[#houses + 1] = {bench = pos_text(bench), chests = chests}
	end
	return houses
end

function builder.run(_, info, emit, done)
	local materials, template = modules()
	core.after(WAIT_SECONDS, function()
		local record = {
			probe = "builder",
			houses = check_houses(info),
			unknown = unknown_items(materials, template),
			buildings = {},
		}
		local wrong = 0
		for _, building in ipairs(info) do
			local result = compare_building(building, template)
			record.buildings[#record.buildings + 1] = result
			wrong = wrong + (result.wrong or 0) + (result.wrong_param2 or 0)
		end
		core.log("action", string.format("[lv_builder] %d houses, %d buildings, %d cells differ",
			#record.houses, #record.buildings, wrong))
		emit(record)
		done()
	end)
end

return builder
