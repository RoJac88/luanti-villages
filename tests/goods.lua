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

-- Conversions, a short list a job: none for food.
local shepherd = goods.conversions({_profession = "shepherd"})
assert(#shepherd == 16)
for _, c in ipairs(shepherd) do assert(c.to == goods.STRING and c.ratio == 4) end
local woodcutter = goods.conversions({_profession = "nitwit", _villages_labour = {activity = "woodcutter"}})
assert(#woodcutter == 8 and woodcutter[1].ratio == 4)
assert(#goods.conversions({_profession = "mason"}) == 1)
assert(#goods.conversions({_profession = "farmer"}) == 0)
for _, list in pairs(goods.CONVERSIONS) do
	for _, c in ipairs(list) do assert(not food.POINTS[c.to] and not food.POINTS[c.from], "no food conversions") end
end

print("goods.lua: ok")
