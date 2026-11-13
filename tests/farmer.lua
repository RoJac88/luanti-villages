-- Run with: lua tests/farmer.lua
local support = dofile("tests/support/farm_world.lua")
local world, def, farmer_module, farmer

local job = {x = 0, y = 2, z = 0}
-- Set to false for the cases that predate the economy: everyone fed free.
local economy

-- A fresh world, with a claimed composter and a farmer beside it.
local function setup(fields)
	world = support.new()
	if economy ~= nil then world.settings.living_villages_economy = economy end
	support.claim(world, job, "farmer-1")
	def = {do_custom = function() end}
	farmer_module = dofile("farmer.lua")
	farmer_module.install(def)
	farmer = support.farmer(world, {x = 1, y = 2, z = 0}, fields)
	farmer._jobsite = job
	-- Fed, so that a test about something else does not see it eat its pouch.
	farmer._villages_food = farmer._villages_food or 12
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

-- With seeds and nothing left to sow, it tills beside its field and then sows that.
setup({_villages_farm_pouch = {["mcl_farming:wheat_seeds"] = 1}})
plot(1, 1, "mcl_farming:wheat_2")
world.set({x = 1, y = 1, z = 2}, "mcl_core:dirt")
world.set({x = 3, y = 1, z = 1}, "mcl_core:water_source")
step()
assert(world.name({x = 1, y = 1, z = 2}) == "mcl_farming:soil")
step()
assert(world.name({x = 1, y = 2, z = 2}) == "mcl_farming:wheat_1" and pouch("mcl_farming:wheat_seeds") == 0)

-- With no seeds it does not open up ground it cannot sow.
setup()
plot(1, 1, "mcl_farming:wheat_2")
world.set({x = 1, y = 1, z = 2}, "mcl_core:dirt")
world.set({x = 3, y = 1, z = 1}, "mcl_core:water_source")
step(2)
assert(world.name({x = 1, y = 1, z = 2}) == "mcl_core:dirt")

-- Three wheat make a loaf at the composter, one step at a time; nothing is lost.
setup({_villages_farm_pouch = {["mcl_farming:wheat_item"] = 7}})
step(2)
assert(pouch("mcl_farming:bread") == 2 and pouch("mcl_farming:wheat_item") == 1)
step(3)
assert(pouch("mcl_farming:bread") == 2 and pouch("mcl_farming:wheat_item") == 1, "not enough for another")

-- Beyond the keep, surplus goes in the composter until it is ready, then it takes
-- the bone meal, which is real, and then uses it on the crop furthest from ripe.
setup({_villages_farm_pouch = {["mcl_farming:wheat_seeds"] = 16}})
world.set({x = 1, y = 1, z = 1}, "mcl_farming:soil_wet")
world.set({x = 1, y = 2, z = 1}, "mcl_farming:wheat_5")
world.set({x = 2, y = 1, z = 1}, "mcl_farming:soil_wet")
world.set({x = 2, y = 2, z = 1}, "mcl_farming:wheat_2")
step(9)
assert(pouch("mcl_farming:wheat_seeds") == 9, "seven in; level 7 takes no more")
assert(world.name(job) == "mcl_composters:composter_7" and #world.composted == 7)
assert(world.meta(job).timer == true)
world.nodes["0,2,0"] = {name = "mcl_composters:composter_ready"} -- the node timer fires
farmer_module.sessions[farmer].next_at = 0 -- it had gone idle, and looks again in a few seconds
step()
assert(world.name(job) == "mcl_composters:composter", "collected")
assert(world.meta(job).fields.villager == "farmer-1", "and still its job")
assert(pouch("mcl_bone_meal:bone_meal") == 1 and #world.dropped == 0)
step()
assert(pouch("mcl_bone_meal:bone_meal") == 0)
assert(world.bone_mealed.x == 2, "the least grown")
assert(world.name({x = 2, y = 2, z = 1}) == "mcl_farming:wheat_3")
step(4)
assert(pouch("mcl_farming:wheat_seeds") == 8, "the keep is kept")

-- Bread is for villagers, never for the composter.
setup({_villages_farm_pouch = {["mcl_farming:bread"] = 12}})
step(3)
assert(pouch("mcl_farming:bread") == 12 and #world.composted == 0)

-- Plenty of bone meal: the surplus stays, for villagers and storage.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 32, ["mcl_farming:carrot_item"] = 20}})
step(3)
assert(#world.composted == 0 and pouch("mcl_farming:carrot_item") == 20)

-- A composter stuck at level 7 waits for its timer rather than taking more.
setup({_villages_farm_pouch = {["mcl_farming:wheat_seeds"] = 16}})
world.nodes["0,2,0"] = {name = "mcl_composters:composter_7"}
step(2)
assert(#world.composted == 0 and world.meta(job).timer == true)

-- Well over what it keeps, it stores the excess in a chest in range and keeps the rest.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 4, ["mcl_farming:carrot_item"] = 30}})
support.chest(world, {x = 2, y = 2, z = 0})
step()
assert(pouch("mcl_farming:carrot_item") == 16)
assert(world.meta({x = 2, y = 2, z = 0}).inv:get_stack("main", 1):to_string() == "mcl_farming:carrot_item 14")
assert(#world.composted == 0, "with a chest and bone meal in hand, it stores rather than composts")

-- It walks to a chest that is further off.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 4, ["mcl_farming:carrot_item"] = 30}})
support.chest(world, {x = 20, y = 2, z = 0})
step()
assert(#farmer.walks == 1 and farmer.walks[1].x == 20)
step()
assert(pouch("mcl_farming:carrot_item") == 16)

-- Stood at its composter with room for more bone meal, it still goes to the chest
-- first: the composter must not swallow the surplus on the way.
setup({_villages_farm_pouch = {["mcl_farming:carrot_item"] = 40}})
local store = support.chest(world, {x = 20, y = 2, z = 0})
step()
assert(#world.composted == 0 and #farmer.walks == 1 and farmer.walks[1].x == 20)
step()
assert(pouch("mcl_farming:carrot_item") == 16)
assert(store:get_stack("main", 1):to_string() == "mcl_farming:carrot_item 24")

-- A hungry child out of reach comes before the composter too.
setup({_villages_farm_pouch = {["mcl_farming:carrot_item"] = 40}})
local customer = support.farmer(world, {x = 20, y = 2, z = 0})
customer._id, customer._profession, customer.child = "customer", "mason", true
step()
assert(#world.composted == 0 and #farmer.walks == 1)

-- Plots in reach still come first, so one walk works a whole patch.
setup({_villages_farm_pouch = {["mcl_farming:carrot_item"] = 40}})
support.chest(world, {x = 20, y = 2, z = 0})
local on_the_way = plot(1, 1, "mcl_farming:wheat")
step()
assert(world.name(on_the_way) == "air" and #farmer.walks == 0)

-- A small excess is not worth a trip.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 4, ["mcl_farming:carrot_item"] = 20}})
support.chest(world, {x = 20, y = 2, z = 0})
step(3)
assert(#farmer.walks == 0 and pouch("mcl_farming:carrot_item") == 20)

-- A full chest is left alone for a while, and nothing is lost to it.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 4, ["mcl_farming:carrot_item"] = 30}})
local full = support.chest(world, {x = 2, y = 2, z = 0})
for i = 1, 27 do full:set_stack("main", i, "mcl_core:stone 64") end
step(3)
assert(pouch("mcl_farming:carrot_item") == 30)

-- Its surplus goes to the chest nearest its composter, not the one nearest itself, so a
-- player can move it off a chest such as a Builder's by placing one nearer.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 4, ["mcl_farming:carrot_item"] = 30}})
local builders = support.chest(world, {x = 7, y = 2, z = 0})
local placed = support.chest(world, {x = -6, y = 2, z = 0})
step()
assert(#farmer.walks == 1 and farmer.walks[1].x == -6, "the chest nearer the composter")
step()
assert(placed:get_stack("main", 1):to_string() == "mcl_farming:carrot_item 14")
assert(builders:get_stack("main", 1):is_empty(), "the other chest is left alone")

-- That chest full, it waits rather than fill another.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 4, ["mcl_farming:carrot_item"] = 30}})
builders = support.chest(world, {x = 8, y = 2, z = 0})
placed = support.chest(world, {x = -6, y = 2, z = 0})
for i = 1, 27 do placed:set_stack("main", i, "mcl_core:stone 64") end
step(6)
assert(builders:get_stack("main", 1):is_empty() and pouch("mcl_farming:carrot_item") == 30)

-- Both halves of a double chest are its own.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 4, ["mcl_farming:carrot_item"] = 30}})
local near_half = support.chest(world, {x = 2, y = 2, z = 0}, "mcl_chests:chest_left")
local far_half = support.chest(world, {x = 3, y = 2, z = 0}, "mcl_chests:chest_right")
builders = support.chest(world, {x = 4, y = 2, z = 0})
for i = 1, 27 do near_half:set_stack("main", i, "mcl_core:stone 64") end
step(6)
assert(far_half:get_stack("main", 1):to_string() == "mcl_farming:carrot_item 14")
assert(builders:get_stack("main", 1):is_empty())

-- With no chest it never places one and leaves no food on the ground: surplus goes to the composter, and a full pouch waits with the crop standing.
setup({_villages_farm_pouch = {["mcl_farming:carrot_item"] = 116, ["mcl_farming:wheat_seeds"] = 8}})
local waiting = plot(1, 1, "mcl_farming:wheat")
step()
assert(world.name(waiting) == "mcl_farming:wheat", "no room for the harvest")
assert(#world.composted == 1, "the composter makes room")
assert(#world.dropped == 0 and #farmer.walks == 0)
for _, node in pairs(world.nodes) do assert(not node.name:find("chest"), "no chest placed") end
step(7)
assert(world.name(waiting) ~= "mcl_farming:wheat", "room made, so it harvests")

-- A chest placed later is found on its next look.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 32, ["mcl_farming:carrot_item"] = 30}})
step(2)
assert(pouch("mcl_farming:carrot_item") == 30, "nowhere for it to go")
support.chest(world, {x = 2, y = 2, z = 0})
world.now = world.now + 61
step(2)
assert(pouch("mcl_farming:carrot_item") == 16)

-- Inedible drops: into the pouch with a chest to take them, on the ground without.
setup()
world.defs["mcl_farming:potato"].test_drops = {"mcl_farming:potato_item", "mcl_farming:potato_item_poison"}
plot(1, 1, "mcl_farming:potato")
step()
assert(pouch("mcl_farming:potato_item") == 1 and pouch("mcl_farming:potato_item_poison") == 0)
assert(#world.dropped == 1 and world.dropped[1].item == "mcl_farming:potato_item_poison")
setup()
support.chest(world, {x = 2, y = 2, z = 0})
world.defs["mcl_farming:potato"].test_drops = {"mcl_farming:potato_item_poison"}
plot(1, 1, "mcl_farming:potato")
step(2)
assert(#world.dropped == 0)
assert(world.meta({x = 2, y = 2, z = 0}).inv:get_stack("main", 1):to_string() == "mcl_farming:potato_item_poison 1")

-- Out of seeds with empty plots, it fetches some from a chest; only then.
setup()
local bare_plot = plot(1, 1)
local seed_chest = support.chest(world, {x = 2, y = 2, z = 0}, nil, {"mcl_farming:wheat_seeds 20", "mcl_core:iron_ingot 5"})
step()
assert(pouch("mcl_farming:wheat_seeds") == 8 and pouch("mcl_core:iron_ingot") == 0)
step()
assert(world.name(bare_plot) == "mcl_farming:wheat_1")
assert(seed_chest:get_stack("main", 2):to_string() == "mcl_core:iron_ingot 5", "nothing else is touched")

-- Deposit-only by setting.
setup()
world.settings["living_villages_farmer_chest_withdraw"] = false
plot(1, 1)
support.chest(world, {x = 2, y = 2, z = 0}, nil, {"mcl_farming:wheat_seeds 20"})
step(2)
assert(pouch("mcl_farming:wheat_seeds") == 0)

-- Handing out food with the economy off: everyone is fed free, all they want.
economy = false
-- Another villager, standing where a test wants it.
local function neighbour(x, z, fields)
	local other = support.farmer(world, {x = x, y = 2, z = z}, fields)
	other._id, other._profession = "other-" .. x .. "-" .. z, "mason"
	return other
end

-- Within reach: fed straight from the pouch, best food first, and nothing on the ground.
setup({_villages_farm_pouch = {["mcl_farming:bread"] = 2, ["mcl_farming:beetroot_item"] = 10}})
world.defs["mcl_farming:bread"] = {groups = {}, inventory_image = "bread.png"}
local hungry = neighbour(2, 1)
step()
assert(hungry._villages_food == 12, "8 from the loaves, 4 from beetroot")
assert(pouch("mcl_farming:bread") == 0 and pouch("mcl_farming:beetroot_item") == 6)
assert(#world.dropped == 0)

-- Further off: it walks there, then hands over.
setup({_villages_farm_pouch = {["mcl_farming:bread"] = 3}})
local distant = neighbour(20, 0)
step()
assert(#farmer.walks == 1 and farmer.walks[1].x == 20)
step()
assert(distant._villages_food == 12)

-- It keeps a few of the crops that are also its seed.
setup({_villages_farm_pouch = {["mcl_farming:carrot_item"] = 6}})
local peckish = neighbour(2, 1)
step(3)
assert(peckish._villages_food == 2 and pouch("mcl_farming:carrot_item") == 4)

-- Nobody beyond its range, nobody asleep, nobody full, and not itself by walking.
setup({_villages_farm_pouch = {["mcl_farming:bread"] = 3}})
local beyond = neighbour(40, 0)
local asleep = neighbour(2, 1, {_villages_sleeping = true})
local full = neighbour(1, 1, {_villages_food = 12})
step(2)
assert(not beyond._villages_food and not asleep._villages_food and full._villages_food == 12)
assert(#farmer.walks == 0 and pouch("mcl_farming:bread") == 3)

-- A hungry farmer feeds itself.
setup({_villages_food = 4, _villages_farm_pouch = {["mcl_farming:bread"] = 3}})
step()
assert(farmer._villages_food == 12 and pouch("mcl_farming:bread") == 1)

-- Ground waiting to be sown comes before eating its seed crops, its own or anyone's.
setup({_villages_food = 0, _villages_farm_pouch = {["mcl_farming:potato_item"] = 12}})
local to_sow = plot(1, 1)
local waiting_neighbour = neighbour(2, 1)
step()
assert(farmer._villages_food == 0 and not waiting_neighbour._villages_food, "sown first")
assert(world.name(to_sow) == "mcl_farming:potato_1" and pouch("mcl_farming:potato_item") == 11)
step()
assert(farmer._villages_food == 7, "and nothing left to sow, it eats down to the seed it keeps")
-- Food that is no seed is fair game even then.
setup({_villages_food = 8, _villages_farm_pouch = {["mcl_farming:bread"] = 1, ["mcl_farming:potato_item"] = 1}})
plot(1, 1)
step()
assert(farmer._villages_food == 12 and pouch("mcl_farming:bread") == 0)

-- A round stops after a few, and the next waits.
setup({_villages_farm_pouch = {["mcl_farming:bread"] = 8}})
local crowd = {}
for i = 1, 6 do crowd[i] = neighbour(1 + i % 2, i % 3 - 1, {_villages_food = 11}) end
step(6)
local fed = 0
for _, other in ipairs(crowd) do if other._villages_food == 15 then fed = fed + 1 end end
assert(fed == 4 and pouch("mcl_farming:bread") == 4, "four, then a wait")
world.now = world.now + 121
step(2)
fed = 0
for _, other in ipairs(crowd) do if other._villages_food == 15 then fed = fed + 1 end end
assert(fed == 6)

-- Nor does it chase forever one it cannot catch.
setup({_villages_farm_pouch = {["mcl_farming:bread"] = 3}, fail_walks = true})
neighbour(20, 0)
for _ = 1, 40 do step() end
assert(#farmer.walks <= 8, "gives up for a while")

-- Out of food with someone hungry: it fetches some from a chest; only then.
setup()
local larder = support.chest(world, {x = 2, y = 2, z = 0}, nil, {"mcl_farming:bread 20", "mcl_core:iron_ingot 3"})
local waiting_for_food = neighbour(1, 1)
step(2)
assert(pouch("mcl_farming:bread") == 5 and waiting_for_food._villages_food == 12)
assert(larder:get_stack("main", 2):to_string() == "mcl_core:iron_ingot 3")
setup()
support.chest(world, {x = 2, y = 2, z = 0}, nil, {"mcl_farming:bread 20"})
step(2)
assert(pouch("mcl_farming:bread") == 0, "nobody hungry, so it leaves the chest alone")
setup()
world.settings["living_villages_farmer_chest_withdraw"] = false
support.chest(world, {x = 2, y = 2, z = 0}, nil, {"mcl_farming:bread 20"})
neighbour(1, 1)
step(2)
assert(pouch("mcl_farming:bread") == 0, "deposit-only")
economy = nil

-- With the economy on, wheat over the keep goes to its belongings first, up to eight, for
-- sale to villagers (a leatherworker's herd); the rest goes in the chest.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 4, ["mcl_farming:bread"] = 12,
	["mcl_farming:wheat_item"] = 30}})
support.chest(world, {x = 2, y = 2, z = 0})
step()
assert(farmer._villages_belongings and farmer._villages_belongings["mcl_farming:wheat_item"] == 8)
assert(pouch("mcl_farming:wheat_item") == 3)
assert(world.meta({x = 2, y = 2, z = 0}).inv:get_stack("main", 1):to_string() == "mcl_farming:wheat_item 19")

-- Spare bread is worth a trip well short of the usual eight over the keep: its own
-- dinners and the keeper's fetches both wait on it (run of 2026-11-13).
setup({_villages_farm_pouch = {["mcl_farming:bread"] = 8}})
local bread_chest = support.chest(world, {x = 20, y = 2, z = 0})
step()
assert(#farmer.walks == 1 and farmer.walks[1].x == 20, "six loaves over the keep send it to the chest")
step()
assert(pouch("mcl_farming:bread") == 2 and farmer._villages_belongings["mcl_farming:bread"] == 4)
assert(bread_chest:get_stack("main", 1):to_string() == "mcl_farming:bread 2", "the rest for the keeper")
-- One loaf over is not.
setup({_villages_farm_pouch = {["mcl_farming:bread"] = 3}})
support.chest(world, {x = 20, y = 2, z = 0})
step(2)
assert(#farmer.walks == 0 and pouch("mcl_farming:bread") == 3)

-- With the economy on only children eat free: adults eat at the tavern, or alms when
-- broke (food loop, 2026-11-13). A neighbour, its spouse even, gets nothing, and no
-- emeralds change hands.
local function belongings(v, name) return (v._villages_belongings or {})[name] or 0 end
setup({_bed = {x = 0, y = 2, z = 10}, _villages_farm_pouch = {["mcl_farming:bread"] = 8}})
local spouse = neighbour(2, 1, {_bed = {x = 3, y = 2, z = 12}, _villages_food = 4,
	_villages_belongings = {["mcl_core:emerald"] = 128}})
local child = neighbour(1, 1, {child = true})
child._id = "child"
step(3)
assert(child._villages_fed_day == world.day, "children free")
assert(spouse._villages_food == 4 and belongings(spouse, "mcl_core:emerald") == 128, "no adult fed or sold to")
assert(belongings(farmer, "mcl_core:emerald") == 0)

-- Nor a starving one, and it walks to no adult.
setup({_villages_farm_pouch = {["mcl_farming:bread"] = 12}})
local starving = neighbour(1, 1, {_villages_food = 0})
local waiting = neighbour(20, 0, {_villages_food = 4, _villages_belongings = {["mcl_core:emerald"] = 64}})
step(3)
assert(starving._villages_food == 0 and pouch("mcl_farming:bread") == 12)
assert(#farmer.walks == 0 and belongings(waiting, "mcl_core:emerald") == 64)

-- Bread over the keep goes to its belongings first, up to four, for its dinner and to
-- sell; the rest goes in the chest, where the keeper fetches it.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 4, ["mcl_farming:bread"] = 20}})
support.chest(world, {x = 2, y = 2, z = 0})
step()
assert(belongings(farmer, "mcl_farming:bread") == 4, belongings(farmer, "mcl_farming:bread"))
assert(pouch("mcl_farming:bread") == 2)
assert(world.meta({x = 2, y = 2, z = 0}).inv:get_stack("main", 1):to_string() == "mcl_farming:bread 14")

-- Emeralds the keeper left in its chest go in its belongings when it next stores.
setup({_villages_farm_pouch = {["mcl_bone_meal:bone_meal"] = 4, ["mcl_farming:carrot_item"] = 30}})
local till = support.chest(world, {x = 2, y = 2, z = 0}, nil, {"mcl_core:emerald 3"})
step(3)
assert(belongings(farmer, "mcl_core:emerald") == 3 and till:get_stack("main", 1):get_name() ~= "mcl_core:emerald")

-- Ticket 18. A hoe multiplies the harvest: with a stone one (×1.5), a lucky roll makes
-- one wheat two.
do
	local real_random = math.random
	math.random = function() return 0 end
	setup({_villages_wants = {hoe = {item = "mcl_farming:hoe_stone", left = 64}}})
	plot(1, 1, "mcl_farming:wheat")
	step()
	assert(pouch("mcl_farming:wheat_item") == 2 and farmer._villages_wants.hoe.left == 63)
	-- With nothing else to do it tends a growing crop, which grows a stage; a plot tended
	-- lately waits its turn.
	setup({_villages_wants = {hoe = {item = "mcl_farming:hoe_iron", left = 128}}})
	local young = plot(1, 1, "mcl_farming:wheat_2")
	step()
	assert(world.name(young) == "mcl_farming:wheat_3", world.name(young))
	step(5)
	assert(world.name(young) == "mcl_farming:wheat_3", "tended lately")
	world.now = world.now + 121
	step()
	assert(world.name(young) == "mcl_farming:wheat_4")
	-- By hand it tends too, at a lower chance: a hoe is a bonus.
	setup()
	young = plot(1, 1, "mcl_farming:wheat_2")
	step()
	assert(world.name(young) == "mcl_farming:wheat_3", "a roll of 0 grows it by hand")
	setup()
	young = plot(1, 1, "mcl_farming:wheat_2")
	math.random = function() return 0.5 end
	step()
	assert(world.name(young) == "mcl_farming:wheat_2", "0.35 by hand: a roll of 0.5 does not")
	setup({_villages_wants = {hoe = {item = "mcl_farming:hoe_iron", left = 128}}})
	young = plot(1, 1, "mcl_farming:wheat_2")
	step()
	assert(world.name(young) == "mcl_farming:wheat_3", "0.7 with an iron hoe: it does")
	math.random = real_random
end

-- It sows what the village asks for: wheat when bread is wanted, though it holds as many
-- potatoes; potatoes when baked potatoes are asked for more.
do
	local function heard_need(item, price)
		return {item = item, who = "keeper", kind = "needs", count = 9, price = price, heard = world.now, hops = 1}
	end
	setup({_villages_farm_pouch = {["mcl_farming:wheat_seeds"] = 8, ["mcl_farming:potato_item"] = 8}})
	farmer._villages_market_news = {heard_need("mcl_farming:bread", 200)}
	local open = plot(1, 1)
	step()
	assert(world.name(open) == "mcl_farming:wheat_1", world.name(open))
	setup({_villages_farm_pouch = {["mcl_farming:wheat_seeds"] = 8, ["mcl_farming:potato_item"] = 8}})
	farmer._villages_market_news = {heard_need("mcl_farming:bread", 200), heard_need("mcl_farming:potato_item_baked", 100)}
	open = plot(1, 1)
	step()
	assert(world.name(open) == "mcl_farming:potato_1", world.name(open))
end

-- A second claimed composter nearby: it tills only its own side of the field.
do
	setup({_villages_farm_pouch = {["mcl_farming:wheat_seeds"] = 8}})
	support.claim(world, {x = 6, y = 2, z = 0}, "farmer-2")
	world.set({x = 0, y = 1, z = 2}, "mcl_core:water_source")
	for x = 1, 5 do world.set({x = x, y = 1, z = 1}, "mcl_farming:soil_wet") world.set({x = x, y = 2, z = 1}, "mcl_farming:wheat_1") end
	for x = 1, 5 do world.set({x = x, y = 1, z = 0}, "mcl_core:dirt") end
	step(20)
	assert(world.name({x = 1, y = 1, z = 0}) == "mcl_farming:soil" or world.name({x = 2, y = 1, z = 0}) == "mcl_farming:soil", "tills its side")
	assert(world.name({x = 4, y = 1, z = 0}) == "mcl_core:dirt" and world.name({x = 5, y = 1, z = 0}) == "mcl_core:dirt", "not the other's")
end

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

-- What the Lookup Tool shows.
setup({_villages_farm_pouch = {["mcl_farming:bread"] = 3, ["mcl_farming:wheat_seeds"] = 2}})
assert(farmer_module.status({_profession = "mason"}) == "not a farmer")
assert(farmer_module.status(farmer) == "not ticked yet")
assert(farmer_module.pouch_status(farmer) == "2 wheat_seeds, 3 bread")
assert(farmer_module.pouch_status({}) == "empty")
plot(1, 1, "mcl_farming:wheat")
step()
assert(farmer_module.status(farmer) == "working in its field")
world.time = 0.7
assert(farmer_module.status(farmer) == "off work")
world.meta(job).fields.villager = "someone-else"
assert(farmer_module.status(farmer) == "no claimed composter")

print("farmer.lua: ok")
