-- Run with: lua tests/farm_compost.lua
local support = dofile("tests/support/farm_world.lua")
local world = support.new()
local abms = {}
minetest.register_abm = function(abm) table.insert(abms, abm) end
local nodes, metas, dropped = world.nodes, {}, world.dropped

local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
local function fields(pos, values) world.meta(pos).fields = values end

local compost = dofile("farm_compost.lua")
local pos = {x = 1, y = 2, z = 3}

-- The ABM watches every fill level and not the empty node.
assert(#abms == 1 and #abms[1].nodenames == 8)
for _, name in ipairs(abms[1].nodenames) do assert(name ~= "mcl_composters:composter") end

-- A composter only a player has used is never touched.
nodes[key(pos)] = {name = "mcl_composters:composter_3"}
assert(not compost.reset_abandoned(pos, nodes[key(pos)]))
assert(nodes[key(pos)].name == "mcl_composters:composter_3")

-- Nor is a marked one its farmer still holds.
fields(pos, {[compost.MARK] = "1", villager = "farmer-1"})
assert(not compost.reset_abandoned(pos, nodes[key(pos)]))
assert(nodes[key(pos)].name == "mcl_composters:composter_3")

-- Marked and unclaimed: emptied, so the job can be taken, and no bone meal appears.
fields(pos, {[compost.MARK] = "1", villager = ""})
assert(compost.reset_abandoned(pos, nodes[key(pos)]))
assert(nodes[key(pos)].name == "mcl_composters:composter")
assert(world.meta(pos).fields[compost.MARK] == "" and #dropped == 0)

-- A ready one gives up its bone meal rather than losing it.
nodes[key(pos)] = {name = "mcl_composters:composter_ready"}
fields(pos, {[compost.MARK] = "1", villager = ""})
assert(compost.reset_abandoned(pos, nodes[key(pos)]))
assert(#dropped == 1 and dropped[1].item == "mcl_bone_meal:bone_meal")

-- Adding an item: a generated composter may have no lists yet, and the claim survives.
world = support.new()
compost = dofile("farm_compost.lua")
support.claim(world, pos, "farmer-1")
assert(world.meta(pos).inv:get_size("src") == 0)
assert(compost.add_item(pos, "mcl_farming:wheat_seeds"))
assert(world.name(pos) == "mcl_composters:composter_1" and #world.composted == 1)
assert(world.meta(pos).fields[compost.MARK] == "1", "marked as a farmer's")
assert(world.meta(pos).fields.villager == "farmer-1")
assert(world.meta(pos).inv:get_stack("src", 1):is_empty(), "the item is used up")

-- Which levels take an item.
assert(compost.takes_items("mcl_composters:composter") and compost.takes_items("mcl_composters:composter_6"))
assert(not compost.takes_items("mcl_composters:composter_7") and not compost.takes_items("mcl_composters:composter_ready"))
assert(compost.is_ready("mcl_composters:composter_ready") and not compost.is_ready("mcl_composters:composter_7"))

-- Collecting: only when ready, and the claim stays while the mark goes.
assert(compost.collect(pos) == nil)
world.swap = nil
minetest.swap_node(pos, {name = "mcl_composters:composter_ready"})
assert(compost.collect(pos) == "mcl_bone_meal:bone_meal")
assert(world.name(pos) == "mcl_composters:composter")
assert(world.meta(pos).fields.villager == "farmer-1", "the job is still held")
assert(world.meta(pos).fields[compost.MARK] == "", "empty again, so nothing to reset")

-- A lost timer at level 7 is restarted; a running one is left.
minetest.swap_node(pos, {name = "mcl_composters:composter_7"})
compost.nudge(pos, "mcl_composters:composter_7")
assert(world.meta(pos).timer == true)
world.meta(pos).timer = nil
compost.nudge(pos, "mcl_composters:composter_3")
assert(world.meta(pos).timer == nil)

-- With no hopper hook (a future VoxeLibre) it declines rather than fails.
world.defs["mcl_composters:composter"]._mcl_hoppers_on_after_push = nil
minetest.swap_node(pos, {name = "mcl_composters:composter"})
assert(not compost.add_item(pos, "mcl_farming:wheat_seeds"))

print("farm_compost.lua: ok")
