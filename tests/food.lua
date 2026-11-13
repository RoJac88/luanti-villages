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

-- Becoming a parent depends on food owned (possessions.can_parent); the setting stands.
assert(food.births_need_food())
world.settings["living_villages_births_need_food"] = false
assert(not food.births_need_food())

-- Raw food is eaten only when starving; the rest is dinner.
assert(food.is_prepared("mcl_farming:bread") and food.is_prepared("mcl_mobitems:cooked_beef"))
assert(not food.is_prepared("mcl_core:apple") and not food.is_prepared("mcl_farming:potato_item"))
assert(not food.is_prepared("mcl_core:cobble"))

-- Every food the farmer offers has a value.
for _, item in ipairs(food.FOODS) do
	local eater = {_villages_food = 0}
	assert(food.receive(eater, item) and eater._villages_food > 0, item)
end

-- Hunger: points fall by 4 a game day of the villager's economic clock (a game day is
-- 1200 s at the default time_speed of 72), never below 0, worked out when read.
local hungry = {_villages_food = 12, _villages_econ_clock = 0}
assert(food.points(hungry) == 12 and food.state(hungry) == "full")
hungry._villages_econ_clock = 600
assert(math.abs(food.points(hungry) - 10) < 1e-9, "half a day: 2 points")
assert(food.state(hungry) == "fed")
hungry._villages_econ_clock = 600 + 1200 * 2
assert(math.abs(food.points(hungry) - 2) < 1e-9 and food.state(hungry) == "hungry")
hungry._villages_econ_clock = 600 + 1200 * 10
assert(food.points(hungry) == 0 and food.state(hungry) == "starving", "never below 0")
assert(food.receive(hungry, "mcl_farming:bread") and food.points(hungry) == 4, "eating starts from now")
-- The clock standing still (no player near) leaves the points alone.
assert(food.points(hungry) == 4)
-- Tavern foods have values.
assert(food.receive(hungry, "mcl_farming:pumpkin_pie") and food.points(hungry) == 10)

-- A villager first seen has nothing taken for time before it was.
local newcomer = {_villages_food = 8, _villages_econ_clock = 5000}
assert(food.points(newcomer) == 8)

-- A faster day takes more per clock second; time standing still takes nothing.
world.settings.time_speed = 144
hungry._villages_econ_clock = hungry._villages_econ_clock + 300
assert(math.abs(food.points(hungry) - 8) < 1e-9, "a quarter of a 600 s day")
world.settings.time_speed = 0
hungry._villages_econ_clock = hungry._villages_econ_clock + 3000
assert(math.abs(food.points(hungry) - 8) < 1e-9)
world.settings.time_speed = nil

-- The rate is a setting; 0, or the economy off, turns hunger off.
world.settings.living_villages_hunger_per_day = "0"
hungry._villages_econ_clock = hungry._villages_econ_clock + 1200
assert(math.abs(food.points(hungry) - 8) < 1e-9)
world.settings.living_villages_hunger_per_day = nil
world.settings.living_villages_economy = false
hungry._villages_econ_clock = hungry._villages_econ_clock + 1200
assert(math.abs(food.points(hungry) - 8) < 1e-9)
world.settings.living_villages_economy = nil

-- Children do not get hungry.
child._villages_econ_clock = 100000
assert(food.state(child) == "fed" and not child._villages_food)

print("food.lua: ok")
