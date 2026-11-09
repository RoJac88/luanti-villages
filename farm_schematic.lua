-- Gives newly generated farms a chest beside the composter. A farmer stores its surplus
-- in the chest nearest its composter (farm_stock.lua, #26), and the stock farm has none,
-- so it carried its harvest to whatever chest stood nearest: often the tavern's pantry
-- (keeper_supply.lua) or a house's loot chest. With its own chest the farm keeps its
-- goods, and the keeper fetches food from it for the tavern.
--
-- The stock farm is 9 x 8 x 7: a field round a water channel, ringed by logs at y 1,
-- with the composter on the ring at (4, 2, 0). The chest stands on the ring beside it at
-- (5, 2, 0), facing out of the field. Like tavern_schematic.lua, this edits the stock
-- schematic in memory.
--
-- The village generator fills every chest it places with loot (settlements.fill_chest).
-- A farm's chest holds seeds instead: a chest beside a composter is emptied and given
-- STARTING_SEEDS.
local core = minetest

local CHEST = {x = 5, y = 2, z = 0}
local COMPOSTER = {x = 4, y = 2, z = 0}
-- Facing -z, out of the field, as a player facing +z places it.
local CHEST_PARAM2 = 0
local STARTING_SEEDS = {
	{"mcl_farming:wheat_seeds", 12}, {"mcl_farming:potato_item", 4}, {"mcl_farming:carrot_item", 4},
}
local COMPOSTERS = {"mcl_composters:composter", "mcl_composters:composter_ready"}
for level = 1, 7 do COMPOSTERS[#COMPOSTERS + 1] = "mcl_composters:composter_" .. level end

local function index(size, x, y, z)
	return z * size.y * size.x + y * size.x + x + 1
end

local function furnish(schematic)
	local size = schematic.size
	if size.x ~= 9 or size.y ~= 8 or size.z ~= 7 then return false end
	local function at(p) return schematic.data[index(size, p.x, p.y, p.z)] end
	local composter, seat = at(COMPOSTER), at(CHEST)
	local below = at({x = CHEST.x, y = CHEST.y - 1, z = CHEST.z})
	if not composter or composter.name ~= "mcl_composters:composter" then return false end
	if not seat or seat.name ~= "air" or not below or below.name == "air" then return false end
	schematic.data[index(size, CHEST.x, CHEST.y, CHEST.z)] = {name = "mcl_chests:chest", prob = 255, param2 = CHEST_PARAM2}
	return true
end

-- Swaps the loot in a chest the generator just filled for seeds, if it is a farm's.
local function seed_farm_chest(pos)
	if not core.find_node_near(pos, 1, COMPOSTERS) then return false end
	local inv = core.get_meta(pos):get_inventory()
	if inv:get_size("main") == 0 then return false end
	inv:set_list("main", {})
	for _, entry in ipairs(STARTING_SEEDS) do inv:add_item("main", entry[1] .. " " .. entry[2]) end
	core.log("action", "[living_villages] seeded a new farm chest at " .. core.pos_to_string(pos))
	return true
end

local M = {furnish = furnish, seed_farm_chest = seed_farm_chest, STARTING_SEEDS = STARTING_SEEDS}

-- Like the other furnishers, the furnish function first (tests/support/stock_scene.lua).
if not settlements or not settlements.schematic_table then return furnish, M end

for _, building in ipairs(settlements.schematic_table) do
	if building.name == "farm" then
		local serialized = core.serialize_schematic(building.mts, "lua", {
			lua_use_comments = false, lua_num_indent_spaces = 0,
		})
		local schematic = serialized and loadstring(serialized .. " return schematic")()
		if schematic and furnish(schematic) then
			building.mts = schematic
		else
			core.log("warning", "[living_villages] stock farm layout changed; its chest was not added")
		end
		break
	end
end

if settlements.fill_chest then
	local original_fill = settlements.fill_chest
	settlements.fill_chest = function(pos, ...)
		local result = original_fill(pos, ...)
		seed_farm_chest(pos)
		return result
	end
end

return furnish, M
