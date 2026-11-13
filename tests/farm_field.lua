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

-- A harvest yields the node's own drops, and takes the crop. Wheat yields twice its one
-- wheat (farm output, 2026-11-13): the second comes as a drop of its own.
local drops = field.harvest(mature)
assert(#drops == 4 and drops[4] == "mcl_farming:wheat_item 1" and world.name(mature) == "air")
assert(field.harvest(mature) == nil, "already gone")

-- Planting keeps the plant's mesh option, which the old replant lost.
assert(field.plant(empty, "mcl_farming:wheat_seeds"))
assert(world.node(empty).name == "mcl_farming:wheat_1" and world.node(empty).param2 == 3)
assert(not field.plant(empty, "mcl_farming:wheat_seeds"), "already planted")
assert(not field.plant({x = 5, y = 2, z = 5}, "mcl_farming:wheat_seeds"), "no soil under it")
assert(not field.plant(mature, "mcl_core:stone"), "not a seed")
assert(field.is_seed("mcl_farming:potato_item") and not field.is_seed("mcl_farming:bread"))

-- Only wheat and potatoes are sown: carrots and beetroot already growing are harvested,
-- never sown again.
assert(not field.plant(mature, "mcl_farming:beetroot_seeds") and not field.plant(mature, "mcl_farming:carrot_item"))
assert(not field.is_seed("mcl_farming:carrot_item"))

-- Seed choice: most stock wins, unless that crop is next door and another will do.
local counts = {}
local function count_of(name) return counts[name] or 0 end
local lone = plot(5, 5)
assert(field.choose_seed(lone, count_of) == nil, "no seeds")
counts = {["mcl_farming:potato_item"] = 2, ["mcl_farming:wheat_seeds"] = 5, ["mcl_farming:carrot_item"] = 9}
assert(field.choose_seed(lone, count_of) == "mcl_farming:wheat_seeds", "carrots are never sown")
plot(6, 5, "mcl_farming:wheat_3")
assert(field.choose_seed(lone, count_of) == "mcl_farming:potato_item")
plot(4, 5, "mcl_farming:potato")
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

-- Ticket 18. A hoe's yield multiplies the product, never the seeds: the whole part of the
-- extra always, the rest by chance. Wheat's own doubling multiplies with the hoe's.
do
	local real_random = math.random
	local wheat = plot(-3, -3, "mcl_farming:wheat")
	math.random = function() return 0.4 end
	local got = field.harvest(wheat, 1.25)
	assert(#got == 4 and got[4] == "mcl_farming:wheat_item 2", "2.5 in all: a half over, one more on a roll under 0.5")
	wheat = plot(-3, -3, "mcl_farming:wheat")
	math.random = function() return 0.6 end
	got = field.harvest(wheat, 1.25)
	assert(#got == 4 and got[4] == "mcl_farming:wheat_item 1", "and none over it")
	local potato = plot(-3, -4, "mcl_farming:potato")
	got = field.harvest(potato, 2.5)
	assert(got[2] == "mcl_farming:potato_item 3", "two potatoes at 2.5: three more")
	wheat = plot(-3, -3, "mcl_farming:wheat")
	assert(#field.harvest(wheat, 1) == 4 and #field.harvest(plot(-3, -5, "mcl_farming:wheat")) == 4, "no hoe: wheat's own doubling only")
	got = field.harvest(plot(-3, -6, "mcl_farming:potato"))
	assert(#got == 1, "no hoe, no extra potato")
	-- Tending grows a crop one stage on a roll under its chance; the last stage ripens.
	local young = plot(-4, -3, "mcl_farming:wheat_3")
	math.random = function() return 0.5 end
	assert(not field.tend(young, 0.4) and world.name(young) == "mcl_farming:wheat_3")
	assert(field.tend(young, 0.6) and world.name(young) == "mcl_farming:wheat_4")
	local late = plot(-4, -4, "mcl_farming:wheat_7")
	assert(field.tend(late, 1) and world.name(late) == "mcl_farming:wheat")
	local beet = plot(-4, -5, "mcl_farming:beetroot_2")
	assert(field.tend(beet, 1) and world.name(beet) == "mcl_farming:beetroot")
	assert(not field.tend(plot(-4, -6, "mcl_farming:wheat"), 1), "a ripe crop is not tended")
	math.random = real_random
end

-- What a harvest is worth by what the village asks: a potato's 1.5 net at a baked
-- potato's ask, wheat's 2 at a third of bread's. Crops never sown have no worth.
do
	local asked = {["mcl_farming:bread"] = 30, ["mcl_farming:potato_item_baked"] = 10, ["mcl_farming:carrot_item"] = 4}
	local worth = field.harvest_worth(function(item) return asked[item] end)
	assert(worth["mcl_farming:wheat_seeds"] == 20 and worth["mcl_farming:potato_item"] == 15)
	assert(worth["mcl_farming:carrot_item"] == nil and worth["mcl_farming:beetroot_seeds"] == nil)
	-- Sowing follows the worth, still passing over a crop next door where another will do.
	local spot = {x = -10, y = 2, z = 10}
	local stock_of = function() return 8 end
	assert(field.choose_seed(spot, stock_of, worth) == "mcl_farming:wheat_seeds")
	world.set({x = -9, y = 2, z = 10}, "mcl_farming:wheat_3")
	assert(field.choose_seed(spot, stock_of, worth) == "mcl_farming:potato_item", "the next best beside wheat")
end

-- Two composters' fields: each counts and tills only the cells nearer its own.
do
	local a, b = {x = 40, y = 2, z = 0}, {x = 46, y = 2, z = 0}
	local others = {a, b}
	assert(field.is_own(a, {x = 42, y = 1, z = 0}, others) and not field.is_own(b, {x = 42, y = 1, z = 0}, others))
	assert(field.is_own(b, {x = 44, y = 1, z = 3}, others) and not field.is_own(a, {x = 44, y = 1, z = 3}, others))
	-- Halfway: the first by position.
	assert(field.is_own(a, {x = 43, y = 1, z = 0}, others) and not field.is_own(b, {x = 43, y = 1, z = 0}, others))
	assert(field.is_own(a, {x = 50, y = 1, z = 0}, {a}), "alone, all of it")
	for x = 41, 45 do world.set({x = x, y = 1, z = 1}, "mcl_farming:soil_wet") end
	local scanned = field.scan(a, others)
	local own = 0
	for _, pos in ipairs(scanned.soil) do if pos.x >= 41 and pos.x <= 45 and pos.z == 1 then own = own + (field.is_own(a, pos, others) and 1 or 0) end end
	assert(#scanned.own_soil < #scanned.soil and own == 3, own)
end

print("farm_field.lua: ok")
