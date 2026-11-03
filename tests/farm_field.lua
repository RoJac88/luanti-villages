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

-- Tilling. A fresh world: dirt at y 1 around a composter at y 2.
world = dofile("tests/support/farm_world.lua").new()
field = dofile("farm_field.lua")
local function ground(x, z, name) world.set({x = x, y = 1, z = z}, name or "mcl_core:dirt") end
local function has(cells, x, z)
	for _, cell in ipairs(cells) do
		if cell.x == x and cell.z == z then assert(cell.y == 2); return true end
	end
	return false
end
for x = -8, 8 do for z = -8, 8 do ground(x, z) end end

-- Dry land with no field: nothing, however much dirt there is.
assert(#field.tillable(job, {}) == 0)

-- A composter by water with no field starts one against the water.
ground(3, 3, "mcl_core:water_source")
local start = field.tillable(job, {})
assert(#start == 4 and has(start, 2, 3) and has(start, 4, 3) and has(start, 3, 2) and has(start, 3, 4))

-- A field grows from itself and only while the ground will stay wet.
ground(2, 3, "mcl_farming:soil_wet")
local soil = field.scan(job).soil
local grown = field.tillable(job, soil)
assert(has(grown, 1, 3) and has(grown, 2, 2) and has(grown, 2, 4))
assert(not has(grown, 4, 3), "the water's other side does not touch this field")
ground(-1, 3, "mcl_farming:soil")
soil = field.scan(job).soil
grown = field.tillable(job, soil)
assert(has(grown, -1, 2), "4 from the water")
assert(not has(grown, -2, 3), "5 from the water, so it would dry out")

-- Never a path, nor coarse dirt, nor under anything, nor anything protected.
ground(1, 3, "mcl_core:grass_path")
ground(2, 2, "mcl_core:coarse_dirt")
world.set({x = 2, y = 2, z = 4}, "mcl_core:stone")
world.protected["-1,2,2"] = true
grown = field.tillable(job, field.scan(job).soil)
assert(not has(grown, 1, 3) and not has(grown, 2, 2) and not has(grown, 2, 4) and not has(grown, -1, 2))
world.set({x = 2, y = 2, z = 4}, "air")
world.protected["-1,2,2"] = nil

-- Tilling makes farmland, and not on a cell that changed since the list was made.
local cell = {x = -1, y = 2, z = 2}
assert(field.till(cell, 2) and world.name({x = -1, y = 1, z = 2}) == "mcl_farming:soil")
assert(not field.till(cell, 3), "already farmland")
assert(not field.till({x = 1, y = 2, z = 3}, 3), "a path")

-- The size cap holds, both in the list and at the moment of tilling.
world.settings["living_villages_farm_max_plots"] = "3"
assert(#field.tillable(job, field.scan(job).soil) == 0)
assert(not field.till({x = 2, y = 2, z = 4}, 3))
world.settings["living_villages_farm_max_plots"] = "4"
assert(#field.tillable(job, field.scan(job).soil) > 0)

-- The stock farm (tests/fixtures/buildings/farm.lua): its kerb keeps the field to its
-- bed though the lawn outside is in range and wet, and only a lost plot is tilled.
world = dofile("tests/support/farm_world.lua").new()
field = dofile("farm_field.lua")
local composter = {x = 4, y = 2, z = 0}
for x = -4, 12 do
	for z = -6, 12 do world.set({x = x, y = 1, z = z}, "mcl_core:dirt_with_grass") end
end
for x = 1, 7 do
	for z = 0, 6 do world.set({x = x, y = 1, z = z}, "mcl_core:stone") end
end
for z = 1, 5 do
	for _, x in ipairs({2, 3, 5, 6}) do world.set({x = x, y = 1, z = z}, "mcl_farming:soil_wet") end
	world.set({x = 4, y = 1, z = z}, "mcl_core:water_source")
end
assert(#field.tillable(composter, field.scan(composter).soil) == 0, "a whole stock farm has nothing to till")
world.set({x = 2, y = 1, z = 3}, "mcl_core:dirt")
local lost = field.tillable(composter, field.scan(composter).soil)
assert(#lost == 1 and lost[1].x == 2 and lost[1].z == 3, "only the lost plot")

print("farm_field.lua: ok")
