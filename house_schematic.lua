-- Gives each bed of a newly generated house a chest beside it, for its villager's stash
-- (possessions.lua). No stock house has a chest, so without this no generated villager
-- would have anywhere to keep its things. Like tavern_schematic.lua, this edits the
-- stock schematics in memory.
--
-- Each chest stands against a wall beside its bed, nearer that bed than any other
-- chest, leaving the cells beside the bed and a way to each jobsite open:
--   small house (9 x 9 x 8): the corner by the door, (5, 2, 3);
--   medium house (9 x 9 x 12): at the foot of each bed, between it and the barrel or
--     the fletching table, (4, 2, 3) and (4, 2, 8);
--   large house (12 x 10 x 12): in place of a carpet beside the ground floor bed,
--     (7, 2, 8), and of one in the loft, (9, 5, 6).
--
-- The village generator fills every chest it places with loot (settlements.fill_chest).
-- A chest beside a bed is a villager's own and starts empty, so houses do not each
-- gain a loot chest.
local core = minetest

-- param2 0 faces -z (as a player facing +z places it), 1 faces -x, 2 faces +z.
local HOUSES = {
	{name = "small_house", size = {x = 9, y = 9, z = 8}, chests = {
		{x = 5, y = 2, z = 3, expected = "air", param2 = 2},
	}},
	{name = "medium_house", size = {x = 9, y = 9, z = 12}, chests = {
		{x = 4, y = 2, z = 3, expected = "air", param2 = 2},
		{x = 4, y = 2, z = 8, expected = "air", param2 = 0},
	}},
	{name = "large_house", size = {x = 12, y = 10, z = 12}, chests = {
		{x = 7, y = 2, z = 8, expected = "mcl_wool:green_carpet", param2 = 0},
		{x = 9, y = 5, z = 6, expected = "mcl_wool:light_blue_carpet", param2 = 1},
	}},
}
local BED_REACH = 2

local function index(size, x, y, z)
	return z * size.y * size.x + y * size.x + x + 1
end

local function same_size(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end

-- Adds the chests to whichever stock house this is. False if it is none, or its layout changed.
local function furnish(schematic)
	for _, house in ipairs(HOUSES) do
		if same_size(schematic.size, house.size) then
			for _, chest in ipairs(house.chests) do
				local cell = schematic.data[index(house.size, chest.x, chest.y, chest.z)]
				if not cell or cell.name ~= chest.expected then return false end
			end
			for _, chest in ipairs(house.chests) do
				schematic.data[index(house.size, chest.x, chest.y, chest.z)] =
					{name = "mcl_chests:chest", prob = 255, param2 = chest.param2}
			end
			return true
		end
	end
	return false
end

-- Empties the loot from a chest the generator just filled, if it stands beside a bed.
local function empty_house_chest(pos)
	if not core.find_node_near(pos, BED_REACH, {"group:bed"}) then return false end
	local inv = core.get_meta(pos):get_inventory()
	if inv:get_size("main") == 0 then return false end
	inv:set_list("main", {})
	return true
end

local M = {furnish = furnish, empty_house_chest = empty_house_chest, HOUSES = HOUSES}

-- Like the other furnishers, the furnish function first (tests/support/stock_scene.lua).
if not settlements or not settlements.schematic_table then return furnish, M end

local wanted = {}
for _, house in ipairs(HOUSES) do wanted[house.name] = true end
for _, building in ipairs(settlements.schematic_table) do
	if wanted[building.name] then
		local serialized = core.serialize_schematic(building.mts, "lua", {
			lua_use_comments = false, lua_num_indent_spaces = 0,
		})
		local schematic = serialized and loadstring(serialized .. " return schematic")()
		if schematic and furnish(schematic) then
			building.mts = schematic
		else
			core.log("warning", "[living_villages] stock " .. building.name .. " layout changed; its chests were not added")
		end
	end
end

if settlements.fill_chest then
	local original_fill = settlements.fill_chest
	settlements.fill_chest = function(pos, ...)
		local result = original_fill(pos, ...)
		empty_house_chest(pos)
		return result
	end
end

return furnish, M
