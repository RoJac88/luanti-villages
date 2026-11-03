-- Run with: lua tests/farm_field.lua
local world = dofile("tests/support/farm_world.lua").new()
local field = dofile("farm_field.lua")

local job = {x = 0, y = 2, z = 0}
local function plot(x, z, crop)
	world.set({x = x, y = 1, z = z}, "mcl_farming:soil_wet")
	if crop then world.set({x = x, y = 2, z = z}, crop) end
	return {x = x, y = 2, z = z}
end

local mature = plot(1, 1, "mcl_farming:wheat")
local growing = plot(2, 1, "mcl_farming:beetroot_1")
local empty = plot(3, 1)
plot(9, 1, "mcl_farming:wheat") -- out of range

local farm = field.scan(job)
assert(#farm.mature == 1 and farm.mature[1].x == mature.x)
assert(#farm.growing == 1 and farm.growing[1].pos.x == growing.x and farm.growing[1].stage == 1)
assert(#farm.empty == 1 and farm.empty[1].x == empty.x and farm.empty[1].y == 2)
assert(#farm.soil == 3)

-- Protected plots are not the farmer's to touch.
world.protected["1,2,1"] = true
assert(#field.scan(job).mature == 0)
assert(field.harvest(mature) == nil and world.name(mature) == "mcl_farming:wheat")
world.protected["1,2,1"] = nil

-- A harvest yields the node's own drops, and takes the crop.
local drops = field.harvest(mature)
assert(#drops == 3 and world.name(mature) == "air")
assert(field.harvest(mature) == nil, "already gone")

-- Planting keeps the plant's mesh option, which the old replant lost.
assert(field.plant(empty, "mcl_farming:wheat_seeds"))
assert(world.node(empty).name == "mcl_farming:wheat_1" and world.node(empty).param2 == 3)
assert(not field.plant(empty, "mcl_farming:wheat_seeds"), "already planted")
assert(not field.plant({x = 5, y = 2, z = 5}, "mcl_farming:wheat_seeds"), "no soil under it")
assert(not field.plant(mature, "mcl_core:stone"), "not a seed")
assert(field.is_seed("mcl_farming:potato_item") and not field.is_seed("mcl_farming:bread"))

-- Beetroot starts at stage 0, unlike the others.
assert(field.plant(mature, "mcl_farming:beetroot_seeds") and world.name(mature) == "mcl_farming:beetroot_0")

-- Seed choice: most stock wins, unless that crop is next door and another will do.
local counts = {}
local function count_of(name) return counts[name] or 0 end
local lone = plot(5, 5)
assert(field.choose_seed(lone, count_of) == nil, "no seeds")
counts = {["mcl_farming:carrot_item"] = 2, ["mcl_farming:wheat_seeds"] = 5}
assert(field.choose_seed(lone, count_of) == "mcl_farming:wheat_seeds")
plot(6, 5, "mcl_farming:wheat_3")
assert(field.choose_seed(lone, count_of) == "mcl_farming:carrot_item")
plot(4, 5, "mcl_farming:carrot")
assert(field.choose_seed(lone, count_of) == "mcl_farming:wheat_seeds", "both next door: most stock")

print("farm_field.lua: ok")
