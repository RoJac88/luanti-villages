-- Run with: lua tests/village_buildings.lua
-- This mod's own village buildings: fitted to the generator as read, and put in its list.
local logged = {}
minetest = {
	get_modpath = function() return "." end,
	log = function(level, message) logged[#logged + 1] = level .. ": " .. message end,
}
local buildings = dofile("village_buildings.lua")

local function schematic_of(name)
	local fixture = dofile("tests/fixtures/buildings/village_" .. name .. ".lua")
	local data = {}
	for i, id in ipairs(fixture.ids) do
		data[i] = {name = fixture.names[id + 1], prob = 255, param2 = fixture.param2[i]}
	end
	return {size = {x = fixture.size.x, y = fixture.size.y, z = fixture.size.z}, data = data}
end

local function at(schematic, x, y, z)
	local size = schematic.size
	return schematic.data[z * size.y * size.x + y * size.x + x + 1]
end

-- Each building gets a dirt slice under it, keeps every cell one up, and has only plain chests.
local CHESTS = {blacksmith = 2, butcher = 2, duplex = 4, fisherman_hut = 1, greenhouse = 4, library = 2, tavern = 2,
	woodcutter_shed = 1, tower_house = 2}
for _, entry in ipairs(buildings.BUILDINGS) do
	local name = entry.name
	local original = schematic_of(name)
	local prepared, changed = buildings.prepare(schematic_of(name))
	assert(changed.ground, name .. " gets a ground slice")
	assert(changed.chests == CHESTS[name], name .. ": " .. changed.chests .. " chests")
	local size = original.size
	assert(prepared.size.x == size.x and prepared.size.y == size.y + 1 and prepared.size.z == size.z, name)
	assert(#prepared.data == size.x * (size.y + 1) * size.z, name)
	for z = 0, size.z - 1 do
		for x = 0, size.x - 1 do
			assert(at(prepared, x, 0, z).name == "mcl_core:dirt", name .. ": the ground slice is dirt")
			for y = 0, size.y - 1 do
				local before, after = at(original, x, y, z), at(prepared, x, y + 1, z)
				local expected = before.name:match("chest_small$") and "mcl_chests:chest" or before.name
				assert(after.name == expected and after.param2 == before.param2, name .. ": cells move up one")
			end
		end
	end
	for _, cell in ipairs(prepared.data) do
		assert(not cell.name:match("chest_small$"), name .. " keeps a " .. cell.name)
	end
	-- Preparing twice changes nothing more.
	local again, twice = buildings.prepare(prepared)
	assert(not twice.ground and twice.chests == 0 and again.size.y == size.y + 1, name)
end

-- The generator's list, as mcl_villages const.lua has it (shapes only).
local function stock_table()
	return {
		{name = "belltower", mts = "belltower.mts", hwidth = 5, hdepth = 5, hheight = 9, hsize = 14, max_num = 0, rplc = true},
		{name = "large_house", mts = "large_house.mts", hwidth = 12, hdepth = 12, hheight = 9, hsize = 14, max_num = 0.08, rplc = true},
		{name = "blacksmith", mts = "blacksmith.mts", hwidth = 8, hdepth = 11, hheight = 13, hsize = 13, max_num = 0.055, rplc = true},
		{name = "butcher", mts = "butcher.mts", hwidth = 12, hdepth = 8, hheight = 10, hsize = 14, max_num = 0.03, rplc = true},
		{name = "church", mts = "church.mts", hwidth = 13, hdepth = 13, hheight = 14, hsize = 15, max_num = 0.04, rplc = true},
		{name = "farm", mts = "farm.mts", hwidth = 9, hdepth = 7, hheight = 13, hsize = 13, max_num = 0.1, rplc = true},
		{name = "lamp", mts = "lamp.mts", hwidth = 3, hdepth = 4, hheight = 13, hsize = 10, max_num = 0.1, rplc = false},
		{name = "library", mts = "library.mts", hwidth = 12, hdepth = 12, hheight = 8, hsize = 13, max_num = 0.04, rplc = true},
		{name = "small_house", mts = "small_house.mts", hwidth = 9, hdepth = 8, hheight = 8, hsize = 13, max_num = 0.7, rplc = true},
		{name = "tavern", mts = "tavern.mts", hwidth = 12, hdepth = 10, hheight = 10, hsize = 13, max_num = 0.05, rplc = true},
	}
end

local function find(list, name)
	for i, entry in ipairs(list) do
		if entry.name == name then return entry, i end
	end
end

do
	local list = stock_table()
	local placed = buildings.apply(list, schematic_of)
	assert(list[1].name == "belltower", "the belltower stays first")
	assert(not find(list, "farm"), "the farm is gone")
	local greenhouse, index = find(list, "greenhouse")
	assert(greenhouse and index == 6, "the greenhouse takes the farm's place")
	assert(greenhouse.max_num == 0.08 and greenhouse.hsize == 16 and greenhouse.rplc == true)
	assert(greenhouse.hwidth == 20 and greenhouse.hdepth == 11 and greenhouse.hheight == 9)
	local tavern = find(list, "tavern")
	assert(tavern == placed.tavern and tavern.max_num == 0.05, "a replaced building keeps its share")
	assert(type(tavern.mts) == "table" and tavern.hwidth == 16 and tavern.hsize == 15)
	local stock_count = #stock_table() - 1 -- less the farm, replaced in place
	local duplex, duplex_at = find(list, "duplex")
	assert(duplex and duplex_at > stock_count and duplex.max_num == 0.08 and duplex.rplc == true, "the duplex is added")
	local hut, hut_at = find(list, "fisherman_hut")
	assert(hut and hut_at > stock_count and hut.max_num == 0.05 and hut.hsize == 12, "the fisherman's hut is added")
	local shed, shed_at = find(list, "woodcutter_shed")
	assert(shed and shed_at > stock_count and shed.max_num == 0.05, "the woodcutter's shed is added")
	local tower, tower_at = find(list, "tower_house")
	assert(tower and tower_at > stock_count and tower.max_num == 0.08, "the tower house is added")
	assert(#list == stock_count + 5, "the greenhouse replaces the farm; the duplex, hut, shed and tower house are new")
	assert(find(list, "lamp").mts == "lamp.mts" and find(list, "small_house").mts == "small_house.mts")
	for _, entry in ipairs(buildings.BUILDINGS) do
		assert(find(list, entry.name).living_villages, entry.name)
	end
end

-- A building that cannot be read leaves the stock one, and says so.
do
	logged = {}
	local list = stock_table()
	buildings.apply(list, function(name) return name ~= "tavern" and name ~= "greenhouse" and schematic_of(name) or nil end,
		minetest.log)
	assert(find(list, "tavern").mts == "tavern.mts" and find(list, "farm") and not find(list, "greenhouse"))
	local all = table.concat(logged, "\n")
	assert(#logged == 2 and all:find("schematics/tavern.mts", 1, true) and all:find("its own farm", 1, true))
end

-- Off, nothing changes.
do
	local list = stock_table()
	local engine = {
		settings = {get_bool = function(_, key, default) if key == buildings.SETTING then return false end return default end},
	}
	assert(buildings.install({schematic_table = list}, nil, engine) == nil)
	assert(find(list, "farm") and find(list, "tavern").mts == "tavern.mts")
end

-- Placing: after the generator's callback, nodes it never constructs get their inventory.
do
	local nodes = {
		["1,1,1"] = {name = "mcl_hoppers:hopper", size = 0},
		["2,1,1"] = {name = "mcl_campfires:campfire", size = 4},
	}
	local constructed, order = {}, {}
	local engine = {
		find_nodes_in_area = function() return {{x = 1, y = 1, z = 1}, {x = 2, y = 1, z = 1}} end,
		get_node = function(pos) return nodes[pos.x .. "," .. pos.y .. "," .. pos.z] end,
		get_meta = function(pos)
			local node = nodes[pos.x .. "," .. pos.y .. "," .. pos.z]
			return {get_inventory = function() return {get_size = function() return node.size end} end}
		end,
		registered_nodes = {
			["mcl_hoppers:hopper"] = {on_construct = function(pos)
				constructed[#constructed + 1] = pos.x
				order[#order + 1] = "construct"
			end},
			["mcl_campfires:campfire"] = {on_construct = function() error("has its inventory already") end},
		},
		read_schematic = function() return nil end,
		get_modpath = function() return "." end,
		log = function() end,
	}
	local structures = {}
	function structures.place_schematic(pos, schematic, rotation, replacements, force, flags, callback)
		callback({x = 0, y = 0, z = 0}, {x = 4, y = 4, z = 4})
		return true
	end
	local settlements = {schematic_table = stock_table()}
	function settlements.place_schematics()
		structures.place_schematic({x = 0, y = 0, z = 0}, "x", "0", nil, true, nil, function()
			order[#order + 1] = "callback"
		end)
		return "placed"
	end
	local original_place = structures.place_schematic
	buildings.install(settlements, structures, engine)
	assert(settlements.place_schematics() == "placed")
	assert(#constructed == 1 and constructed[1] == 1, "the hopper is constructed, the campfire left")
	assert(order[1] == "callback" and order[2] == "construct", "after the generator's own callback")
	assert(structures.place_schematic == original_place, "place_schematic is put back")
	-- Installing twice wraps once.
	local wrapped = settlements.place_schematics
	buildings.install(settlements, structures, engine)
	assert(settlements.place_schematics == wrapped)
end

print("village_buildings: ok")
