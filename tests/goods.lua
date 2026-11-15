-- Run with: lua tests/goods.lua
minetest = {get_modpath = function() return "." end}

local goods = dofile("goods.lua")
local food = dofile("food.lua")

-- Categories: food in points, fuel in burn seconds, logs and planks any species.
assert(goods.units("food", "mcl_farming:bread") == food.POINTS["mcl_farming:bread"])
assert(goods.units("fuel", "mcl_core:coal_lump") == 80 and goods.units("fuel", "mcl_core:wood") == 15)
assert(goods.units("log", "mcl_core:birchtree") == 1 and goods.units("planks", "mcl_core:sprucewood") == 1)
assert(goods.units("food", "mcl_core:stone") == nil and goods.units("nothing", "mcl_core:stone") == nil)

-- A target names its category: coal is fuel, a log any log.
assert(goods.target_category("mcl_core:coal_lump") == "fuel")
assert(goods.target_category("mcl_core:charcoal_lump") == "fuel")
assert(goods.target_category("mcl_core:tree") == "log" and goods.target_category("mcl_core:wood") == "planks")
assert(goods.target_category("mcl_core:iron_ingot") == nil)

-- A log counts as a log where logs are wanted, else as fuel where fuel is.
assert(goods.active("mcl_core:tree", {log = 4, fuel = 80}) == "log")
assert(goods.active("mcl_core:tree", {fuel = 80}) == "fuel")
assert(goods.active("mcl_core:tree", {}) == nil)
assert(goods.active("mcl_core:apple", {food = 10}) == "food")

-- A need entry is filled by its item, or any member of its group.
assert(goods.fills({item = "mcl_core:apple"}, "mcl_core:apple"))
assert(not goods.fills({item = "mcl_core:apple"}, "mcl_farming:bread"))
assert(goods.fills({item = "mcl_core:apple", group = "food"}, "mcl_farming:bread"))
assert(not goods.fills({item = "mcl_core:apple", group = "food"}, "mcl_core:stone"))

-- Conversions, a short list a job: none for food. Everyone's (19h): a lily of the valley
-- or bone meal sells as white dye, one for one, for the shepherd's wool.
local LILY, BONE_MEAL, WHITE_DYE = "mcl_flowers:lily_of_the_valley", "mcl_bone_meal:bone_meal", "mcl_dye:white"
local function anyone(list, from)
	local found
	for _, c in ipairs(list) do if c.from == (from or LILY) then found = c end end
	return found
end
local shepherd = goods.conversions({_profession = "shepherd"})
local lily = anyone(shepherd)
assert(lily and lily.to == WHITE_DYE and lily.ratio == 1, "anyone's")
local bone_meal = anyone(shepherd, BONE_MEAL)
assert(bone_meal and bone_meal.to == WHITE_DYE and bone_meal.ratio == 1, "bone meal too")
-- A bone sells as three bone meal or three white dye, whichever the buyer needs.
local from_bone = {}
for _, c in ipairs(shepherd) do if c.from == "mcl_mobitems:bone" then from_bone[c.to] = c.ratio end end
assert(from_bone[BONE_MEAL] == 3 and from_bone[WHITE_DYE] == 3)
-- Each wool colour to string, four a wool, and to its carpet, three for two (ticket 19c).
-- A poppy or a red tulip sells as a red dye, for the Builder's red beds (19i).
local reds = {}
for _, c in ipairs(shepherd) do if c.to == "mcl_dye:red" then reds[c.from] = c.ratio end end
assert(reds["mcl_flowers:poppy"] == 1 and reds["mcl_flowers:tulip_red"] == 1)
assert(#shepherd == 38)
local strings, carpets = 0, 0
for _, c in ipairs(shepherd) do
	if c.to == WHITE_DYE or c.to == BONE_MEAL or c.to == "mcl_dye:red" then
		-- anyone's, counted above
	elseif c.to == goods.STRING then
		assert(c.ratio == 4 and not c.takes)
		strings = strings + 1
	else
		assert(c.to == c.from .. "_carpet" and c.ratio == 1.5 and c.takes == 2)
		carpets = carpets + 1
	end
end
assert(strings == 16 and carpets == 16)
local woodcutter = goods.conversions({_profession = "nitwit", _villages_labour = {activity = "woodcutter"}})
assert(#woodcutter == 14 and woodcutter[1].ratio == 4 and anyone(woodcutter))
assert(#goods.conversions({_profession = "mason"}) == 7)
local farmer = goods.conversions({_profession = "farmer"})
assert(#farmer == 6 and anyone(farmer) and anyone(farmer, BONE_MEAL), "a farmer sells its bone meal as dye")
assert(#goods.CONVERSIONS.shepherd == 32, "the job's own list is untouched")
for _, list in pairs(goods.CONVERSIONS) do
	for _, c in ipairs(list) do assert(not food.POINTS[c.to] and not food.POINTS[c.from], "no food conversions") end
end

-- Wool of any colour is a category, one unit a wool (the Builder's beds, 19i); it is no
-- job's target category, so the shepherd's grey and the cartographer's white stay their own.
assert(goods.units("wool", "mcl_wool:grey") == 1 and goods.units("wool", "mcl_wool:light_blue") == 1)
assert(not goods.units("wool", "mcl_wool:grey_carpet"))
assert(goods.target_category("mcl_wool:white") == nil)
assert(goods.active("mcl_wool:red", {wool = 3}) == "wool" and goods.active("mcl_wool:red", {}) == nil)
-- Stone or cobble is a category, one unit each (the alchemist's nuggets, ticket 20); it is
-- no job's target category, so a mason's stone and a tool smith's cobble stay their own.
assert(goods.units("stone", "mcl_core:stone") == 1 and goods.units("stone", "mcl_core:cobble") == 1)
assert(not goods.units("stone", "mcl_core:stonebrick"))
assert(goods.target_category("mcl_core:stone") == nil and goods.target_category("mcl_core:cobble") == nil)
assert(goods.active("mcl_core:cobble", {stone = 72}) == "stone" and goods.active("mcl_core:cobble", {}) == nil)
print("goods.lua: ok")
