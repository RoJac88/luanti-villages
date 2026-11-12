-- This mod's own village buildings (schematics/), in place of some stock ones. The stock
-- villages are small for this mod: most of their buildings have no bed, so a village
-- has few villagers, and a Builder collects rent only from buildings with a bed.
--
--   blacksmith  the stock smithy with a bedroom upstairs
--   butcher     a kitchen with a smoker and a bedroom upstairs
--   library     with a bedroom and a room of its own for the leatherworker's cauldron
--   tavern      with a bedroom, a pantry the keeper can reach and its chest, and no
--               barrel (tavern_schematic.lua's furniture is in it already)
--   greenhouse  in place of the farm: a walled field round two composters, two beds
--               and a chest beside each composter (farm_schematic.lua seeds them)
--   duplex      a new two-storey house of four beds
--   fisherman_hut  a small hut with the fisherman's barrel, a chest and a bed
--   woodcutter_shed  a shed with the woodcutter's chopping block, a chest and a bed
--   tower_house  a stone house with a bed and two chests
--
-- They are exported with schemedit as built, so each is fitted to the generator's
-- conventions as it is read (`prepare`):
--   - A stock schematic stands on a slice of dirt, the ground row the building replaces
--     (ground_layer.lua turns it to sand in a sandy village). One that starts at its floor
--     gets that slice under it; without it the building sits a node low, and the open
--     cells of its bottom slice (round a porch, say) would be holes in the ground.
--   - The generator gives only `mcl_chests:chest` an inventory (mcl_villages
--     init_nodes), and a schematic's `chest_small` is a chest with none. Trapped chests
--     become plain ones too: no villager uses a trapped chest (farm_stock.lua).
--
-- A building's other nodes with an inventory, which the generator never constructs
-- (a hopper, a campfire), are constructed once it is placed (`construct`).
--
-- Each entry takes the stock entry's place in settlements.schematic_table (its share and
-- pseudobiome rule), or is added; `replaces` removes the stock one it stands for.
-- Loaded after the furnishing modules: they edit the stock schematics, and this then
-- swaps the whole building, so `living_villages_village_buildings = false` puts the
-- furnished stock ones back.
local core = minetest
local unpack = table.unpack or unpack

local M = {}

M.SETTING = "living_villages_village_buildings"

-- hsize is how far another building's corner must stay from this one's
-- (settlements.check_distance); the site planner also keeps footprints apart.
M.BUILDINGS = {
	{name = "blacksmith", hsize = 13},
	{name = "butcher", hsize = 13},
	{name = "library", hsize = 14},
	{name = "tavern", hsize = 15},
	{name = "greenhouse", replaces = "farm", max_num = 0.08, hsize = 16},
	{name = "duplex", max_num = 0.08, hsize = 13},
	{name = "fisherman_hut", max_num = 0.05, hsize = 12},
	{name = "woodcutter_shed", max_num = 0.05, hsize = 12},
	{name = "tower_house", max_num = 0.08, hsize = 12},
}

local DIRT = "mcl_core:dirt"
local CHEST = "mcl_chests:chest"
local CHESTS = {["mcl_chests:chest_small"] = true, ["mcl_chests:trapped_chest_small"] = true}

-- Nodes with an inventory or a timer from on_construct, which a schematic does not run.
M.CONSTRUCT = {"mcl_hoppers:hopper", "mcl_campfires:campfire"}

local function index(size, x, y, z)
	return z * size.y * size.x + y * size.x + x + 1
end

local function has_ground(schematic)
	local size = schematic.size
	for z = 0, size.z - 1 do
		for x = 0, size.x - 1 do
			local cell = schematic.data[index(size, x, 0, z)]
			if cell and cell.name == DIRT then return true end
		end
	end
	return false
end

-- Fits a schematic table read from one of these files to the generator, in place (see
-- the top of this file). Returns it, and what changed: {ground = bool, chests = n}.
function M.prepare(schematic)
	local changed = {ground = false, chests = 0}
	if not has_ground(schematic) then
		local size, data = schematic.size, {}
		local taller = {x = size.x, y = size.y + 1, z = size.z}
		for z = 0, size.z - 1 do
			for y = 0, taller.y - 1 do
				for x = 0, size.x - 1 do
					data[index(taller, x, y, z)] = y == 0 and {name = DIRT, prob = 255, param2 = 0}
						or schematic.data[index(size, x, y - 1, z)]
				end
			end
		end
		schematic.size, schematic.data, schematic.yslice_prob = taller, data, nil
		changed.ground = true
	end
	for _, cell in ipairs(schematic.data) do
		if CHESTS[cell.name] then
			cell.name = CHEST
			changed.chests = changed.chests + 1
		end
	end
	return schematic, changed
end

function M.enabled(engine)
	engine = engine or core
	return not engine.settings or engine.settings:get_bool(M.SETTING, true)
end

function M.path(name, engine)
	engine = engine or core
	return engine.get_modpath("living_villages") .. "/schematics/" .. name .. ".mts"
end

-- Puts the buildings in settlements.schematic_table. `read(name)` returns a building's
-- schematic table, or nil. A building with a stock entry takes its share and pseudobiome
-- rule; a new one takes the small house's rule. Returns the entries placed, by name.
function M.apply(schematic_table, read, log)
	log = log or function() end
	local placed = {}
	for _, building in ipairs(M.BUILDINGS) do
		local schematic = read(building.name)
		if not schematic then
			log("warning", "[living_villages] cannot read schematics/" .. building.name
				.. ".mts; the village generator keeps its own " .. (building.replaces or building.name))
		else
			M.prepare(schematic)
			local stock_index, rplc
			for i, entry in ipairs(schematic_table) do
				if entry.name == building.name or entry.name == building.replaces then stock_index = i end
				if entry.name == "small_house" then rplc = entry.rplc end
			end
			local stock = stock_index and schematic_table[stock_index]
			if stock and stock.rplc ~= nil then rplc = stock.rplc end
			local entry = {
				name = building.name,
				mts = schematic,
				hwidth = schematic.size.x,
				hdepth = schematic.size.z,
				hheight = schematic.size.y,
				hsize = building.hsize,
				max_num = building.max_num or (stock and stock.max_num) or 0,
				rplc = rplc,
				living_villages = true,
			}
			if stock then
				schematic_table[stock_index] = entry
			else
				table.insert(schematic_table, entry)
			end
			placed[building.name] = entry
		end
	end
	return placed
end

-- Runs on_construct for every node of M.CONSTRUCT in the box that has no inventory yet.
function M.construct(p1, p2, engine)
	engine = engine or core
	for _, pos in ipairs(engine.find_nodes_in_area(p1, p2, M.CONSTRUCT)) do
		local def = engine.registered_nodes[engine.get_node(pos).name]
		if def and def.on_construct and engine.get_meta(pos):get_inventory():get_size("main") == 0 then
			def.on_construct(pos)
		end
	end
end

local wrappers = setmetatable({}, {__mode = "k"})

-- While settlements.place_schematics runs, each building's after-placement callback is
-- followed by `construct` over its box.
local function wrap_placement(settlements, structures, engine)
	if wrappers[settlements.place_schematics] then return end
	local original = settlements.place_schematics
	local wrapper = function(...)
		local place = structures.place_schematic
		structures.place_schematic = function(pos, schematic, rotation, replacements, force, flags, callback, ...)
			if type(callback) ~= "function" then
				return place(pos, schematic, rotation, replacements, force, flags, callback, ...)
			end
			return place(pos, schematic, rotation, replacements, force, flags, function(p1, p2, ...)
				callback(p1, p2, ...)
				if p1 and p2 then M.construct(p1, p2, engine) end
			end, ...)
		end
		local results = {pcall(original, ...)}
		structures.place_schematic = place
		if not results[1] then error(results[2], 0) end
		return unpack(results, 2)
	end
	wrappers[wrapper] = true
	settlements.place_schematics = wrapper
end

-- Returns the entries placed by name, or nil when off or there is no generator.
function M.install(settlements, structures, engine)
	engine = engine or core
	if not M.enabled(engine) then return nil end
	if type(settlements) ~= "table" or type(settlements.schematic_table) ~= "table" then return nil end
	local placed = M.apply(settlements.schematic_table, function(name)
		return engine.read_schematic(M.path(name, engine), {write_yslice_prob = "none"})
	end, engine.log)
	if type(structures) == "table" and type(structures.place_schematic) == "function"
			and type(settlements.place_schematics) == "function" then
		wrap_placement(settlements, structures, engine)
	end
	return placed
end

return M
