-- Run with: lua tests/food.lua
local support = dofile("tests/support/farm_world.lua")
local world = support.new()
local food = dofile("food.lua")

local adult = support.farmer(world, {x = 0, y = 0, z = 0})
local child = support.farmer(world, {x = 1, y = 0, z = 0}, {child = true, hornytimer = 10})

-- Points: a loaf is worth 4, a crop 1, and anything else is no food.
assert(food.wants(adult) and food.points(adult) == 0)
assert(food.receive(adult, "mcl_farming:bread") and food.points(adult) == 4)
assert(food.receive(adult, "mcl_farming:carrot_item") and food.points(adult) == 5)
assert(not food.receive(adult, "mcl_farming:wheat_item") and food.points(adult) == 5)
adult._villages_food = 12
assert(not food.wants(adult))
adult._villages_food = 11
assert(food.wants(adult))
adult._villages_sleeping = true
assert(not food.wants(adult), "not woken for it")
adult._villages_sleeping = nil

-- Food heals, up to the maximum.
adult.health = 10
food.receive(adult, "mcl_farming:bread")
assert(adult.health == 14)
adult.health = 19
food.receive(adult, "mcl_farming:bread")
assert(adult.health == 20)

-- A child takes no points: vanilla's tenth of what is left, once a day.
assert(food.wants(child))
food.receive(child, "mcl_farming:bread")
assert(child.hornytimer == 15 and not child._villages_food)
assert(not food.wants(child))
world.day = world.day + 1
assert(food.wants(child))

-- Becoming a parent.
assert(food.births_need_food())
adult._villages_food = 11
assert(not food.can_parent(adult))
adult._villages_food = 13
assert(food.can_parent(adult))
food.spend_on_birth(adult)
assert(adult._villages_food == 1)
world.settings["living_villages_births_need_food"] = false
assert(not food.births_need_food() and food.can_parent(adult))
food.spend_on_birth(adult)
assert(adult._villages_food == 1, "nothing spent with the setting off")

-- Every food the farmer offers has a value.
for _, item in ipairs(food.FOODS) do
	local eater = {_villages_food = 0}
	assert(food.receive(eater, item) and eater._villages_food > 0, item)
end

print("food.lua: ok")
