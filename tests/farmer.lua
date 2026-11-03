-- Run with: lua tests/farmer.lua
local support = dofile("tests/support/farm_world.lua")
local world, def, farmer_module, farmer

local job = {x = 0, y = 2, z = 0}

-- A fresh world, with a claimed composter and a farmer beside it.
local function setup(fields)
	world = support.new()
	support.claim(world, job, "farmer-1")
	def = {do_custom = function() end}
	farmer_module = dofile("farmer.lua")
	farmer_module.install(def)
	farmer = support.farmer(world, {x = 1, y = 2, z = 0}, fields)
	farmer._jobsite = job
end

local function plot(x, z, crop)
	world.set({x = x, y = 1, z = z}, "mcl_farming:soil_wet")
	if crop then world.set({x = x, y = 2, z = z}, crop) end
	return {x = x, y = 2, z = z}
end

-- One do_custom, one game second on.
local function step(count)
	local result
	for _ = 1, count or 1 do
		world.now = world.now + 1
		result = def.do_custom(farmer, 0.1)
	end
	return result
end

local function pouch(name) return (farmer._villages_farm_pouch or {})[name] or 0 end

-- A mature crop in reach becomes real items, then a new plant from the pouch.
setup()
local crop = plot(1, 1, "mcl_farming:wheat")
step()
assert(world.name(crop) == "air", "harvested")
assert(pouch("mcl_farming:wheat_seeds") == 2 and pouch("mcl_farming:wheat_item") == 1)
assert(#world.dropped == 0, "nothing on the ground for villagers to eat")
assert(farmer_module.activity_override(farmer, "work") == "farm", "not called back mid-job")
assert(step() == false, "do_states would turn it away")
assert(world.name(crop) == "mcl_farming:wheat_1", "replanted")
assert(pouch("mcl_farming:wheat_seeds") == 1, "the seed was spent")
assert(farmer.order == "stand", "held still while working")

-- With the work done it goes back to vanilla, and to its trades.
step(3)
assert(farmer_module.activity_override(farmer, "work") == nil)
assert(farmer.order == nil)
assert(farmer_module.activity_override(farmer, "putter") == nil)

-- Out of reach: it walks there and does the job on arrival, without a route per plot.
setup()
local far = plot(6, 6, "mcl_farming:potato")
local near_far = plot(6, 7, "mcl_farming:carrot")
step()
assert(#farmer.walks == 1 and farmer.walks[1].x == far.x and farmer.walks[1].z == far.z)
assert(farmer_module.activity_override(farmer, "work") == "farm")
assert(farmer._villages_farm_target == nil, "cleared on arrival")
step(2)
assert(world.name(far) == "air" and world.name(near_far) == "air")
assert(#farmer.walks == 1, "both were in reach of one walk")

-- No seeds and an empty plot: nothing to do, and no plant from nowhere.
setup()
local bare = plot(1, 1)
step(3)
assert(world.name(bare) == "air" and #farmer.walks == 0)
assert(farmer_module.activity_override(farmer, "work") == nil)

-- A full pouch leaves the crop standing, so nothing is lost.
setup({_villages_farm_pouch = {["mcl_core:stone"] = 128}})
local standing = plot(1, 1, "mcl_farming:wheat")
step(3)
assert(world.name(standing) == "mcl_farming:wheat" and pouch("mcl_core:stone") == 128)

-- A plot it cannot walk to is passed over for a while, then tried again.
setup({fail_walks = true})
plot(6, 6, "mcl_farming:wheat")
step()
assert(#farmer.walks == 1 and farmer._villages_farm_target == nil)
step(5)
assert(#farmer.walks == 1, "not retried at once")
world.now = world.now + 60
step(2)
assert(#farmer.walks == 2)

-- A route the planner gave up on counts the same.
setup()
local unreachable = plot(6, 6, "mcl_farming:wheat")
farmer._villages_farm_target = unreachable
farmer._villages_farm_route = {status = "retry", retry_at = world.now + 500}
step()
assert(farmer._villages_farm_target == nil and #farmer.walks == 0)

-- While a route is planned it waits and starts nothing else.
setup()
local queued = plot(6, 6, "mcl_farming:wheat")
farmer._villages_farm_target = queued
farmer._villages_farm_route = {status = "planning"}
step(3)
assert(farmer._villages_farm_target == queued and #farmer.walks == 0)

-- Only in the work stage, and only a farmer holding its composter.
local function untouched(label)
	local here = plot(1, 1, "mcl_farming:wheat")
	step(2)
	assert(world.name(here) == "mcl_farming:wheat", label)
end
setup(); world.time = 0.7; untouched("after work")
setup({_profession = "fisherman"}); untouched("another job")
setup({child = true}); untouched("a child")
setup({following = true}); untouched("following a player")
setup({_trading_players = {someone = true}}); untouched("trading")
setup(); world.meta(job).fields.villager = "someone-else"; untouched("lost the claim")

-- Compost in the composter does not end the job, at any fill level.
for _, name in ipairs({"mcl_composters:composter_1", "mcl_composters:composter_7", "mcl_composters:composter_ready"}) do
	setup()
	world.nodes["0,2,0"] = {name = name}
	local here = plot(1, 1, "mcl_farming:wheat")
	step()
	assert(world.name(here) == "air", name)
end

-- Fill levels are the same jobsite, and stay out of the job search, since vanilla's
-- employ cannot take them.
local common = dofile("common.lua")
for _, name in ipairs({"mcl_composters:composter_1", "mcl_composters:composter_7", "mcl_composters:composter_ready"}) do
	assert(common.is_composter_node(name) and common.is_workstation_node(name))
	assert(common.workstation_profession(name) == "farmer")
	for _, searched in ipairs(common.workstation_search_nodes()) do assert(searched ~= name) end
end
local searched_empty = false
for _, searched in ipairs(common.workstation_search_nodes()) do
	searched_empty = searched_empty or searched == "mcl_composters:composter"
end
assert(searched_empty)
assert(not common.is_composter_node("mcl_barrels:barrel_closed"))

-- Its goods drop when it dies, and vanilla's own death still runs.
setup({_villages_farm_pouch = {["mcl_farming:wheat_item"] = 3}})
local vanilla_died = false
def = {do_custom = function() end, on_die = function() vanilla_died = true end}
farmer_module.install(def)
def.on_die(farmer, {x = 1, y = 2, z = 0}, {})
assert(vanilla_died and #world.dropped == 1 and world.dropped[1].item == "mcl_farming:wheat_item 3")

print("farmer.lua: ok")
