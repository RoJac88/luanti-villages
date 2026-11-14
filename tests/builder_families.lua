-- Run with: lua tests/builder_families.lua
-- Materials a Builder takes in place of one another (builder_families.lua).
local families = dofile("builder_families.lua")

-- A node's member and what follows its stem.
local function member_of(name)
	local member, rest = families.lookup(name)
	return member and member.item, rest
end

assert(member_of("mcl_stairs:stair_birchwood_outer") == "mcl_stairs:stair_birchwood")
assert(select(2, member_of("mcl_stairs:stair_birchwood_outer")) == "_outer")
assert(member_of("mcl_doors:dark_oak_door_t_2") == "mcl_doors:dark_oak_door")
assert(member_of("mcl_doors:wooden_door:top") == "mcl_doors:wooden_door")
assert(member_of("mcl_beds:bed_light_blue_top") == "mcl_beds:bed_light_blue_bottom")
assert(member_of("mcl_flowerpots:flower_pot_tulip_red") == "mcl_flowers:tulip_red")
assert(member_of("mcl_walls:stonebrickmossy_12") == "mcl_walls:stonebrickmossy")
assert(member_of("mesecons_pressureplates:pressure_plate_wood_on") == "mesecons_pressureplates:pressure_plate_wood_off")
assert(member_of("xpanes:pane_orange") == "xpanes:pane_orange_flat")
-- The longest stem wins, and a stem followed by anything but a shape is no member.
assert(member_of("mcl_core:tree_bark") == "mcl_core:tree_bark")
assert(member_of("mcl_fences:fence_gate_open") == "mcl_fences:fence_gate")
assert(member_of("mcl_stairs:stair_tree_bark") == nil)
assert(member_of("mcl_flowerpots:flower_pot") == nil)
-- Clear glass and panes, iron doors and carved bricks have no family.
assert(member_of("mcl_core:glass") == nil)
assert(member_of("xpanes:pane_natural_flat") == nil)
assert(member_of("mcl_doors:iron_door_b_1") == nil)
assert(member_of("mcl_core:stonebrickcarved") == nil)
assert(member_of("mcl_core:sandstone") == "mcl_core:sandstone")

-- Same thing built, whatever it is made of; not across shapes or families.
local kind = families.kind
assert(kind("mcl_stairs:stair_wood") == kind("mcl_stairs:stair_sprucewood"))
assert(kind("mcl_doors:wooden_door:top") == kind("mcl_doors:birch_door:top"))
assert(kind("mcl_doors:wooden_door:top") ~= kind("mcl_doors:birch_door"))
assert(kind("mcl_stairs:stair_wood") ~= kind("mcl_stairs:slab_wood"))
assert(kind("mcl_core:wood") ~= kind("mcl_core:tree"))
assert(kind("mcl_core:cobble") == kind("mcl_deepslate:deepslate_cobbled"))
assert(kind("mcl_wool:red_carpet") == kind("mcl_wool:white_carpet"))
assert(kind("mcl_wool:red_carpet") ~= kind("mcl_wool:red"))
assert(kind("mcl_colorblocks:hardened_clay") == kind("mcl_colorblocks:hardened_clay_red"))
assert(kind("mcl_core:glass") ~= kind("mcl_core:glass_red"))
assert(kind("mcl_flowerpots:flower_pot_allium") == kind("mcl_flowerpots:flower_pot_poppy"))
assert(kind("mcl_torches:torch") == "mcl_torches:torch")

-- The same node made of another member.
local variant = families.variant
assert(variant("mcl_stairs:stair_wood_outer", "mcl_stairs:stair_birchwood") == "mcl_stairs:stair_birchwood_outer")
assert(variant("mcl_stairs:slab_wood_top", "mcl_stairs:slab_mangrove_wood") == "mcl_stairs:slab_mangrove_wood_top")
assert(variant("mcl_doors:wooden_door_b_1", "mcl_doors:spruce_door") == "mcl_doors:spruce_door_b_1")
assert(variant("mcl_doors:wooden_door_t_1", "mcl_doors:spruce_door") == "mcl_doors:spruce_door_t_1")
assert(variant("mcl_doors:trapdoor_open", "mcl_cherry_blossom:cherry_trapdoor") == "mcl_cherry_blossom:cherry_trapdoor_open")
assert(variant("mcl_fences:fence_gate", "mcl_mangrove:mangrove_wood_fence_gate") == "mcl_mangrove:mangrove_wood_fence_gate")
assert(variant("mesecons_pressureplates:pressure_plate_wood_off", "mcl_cherry_blossom:pressure_plate_cherrywood_off")
	== "mcl_cherry_blossom:pressure_plate_cherrywood_off")
assert(variant("mcl_beds:bed_red_bottom", "mcl_beds:bed_blue_bottom") == "mcl_beds:bed_blue_bottom")
assert(variant("mcl_beds:bed_red_top", "mcl_beds:bed_blue_bottom") == "mcl_beds:bed_blue_top")
assert(variant("xpanes:pane_orange_flat", "xpanes:pane_gray_flat") == "xpanes:pane_gray_flat")
assert(variant("mcl_walls:cobble_6", "mcl_deepslate:deepslatecobbledwall") == "mcl_deepslate:deepslatecobbledwall_6")
assert(variant("mcl_flowerpots:flower_pot_allium", "mcl_flowers:poppy") == "mcl_flowerpots:flower_pot_poppy")
assert(variant("mcl_core:wood", "mcl_core:darkwood") == "mcl_core:darkwood")
-- Not of the family, or no such node.
assert(variant("mcl_stairs:stair_wood", "mcl_stairs:slab_birchwood") == nil)
assert(variant("mcl_core:glass", "mcl_core:glass_red") == nil)
assert(variant("mcl_core:wood", "mcl_core:darkwood", {registered_nodes = {}}) == nil)
assert(variant("mcl_core:wood", "mcl_core:darkwood", {registered_nodes = {["mcl_core:darkwood"] = {}}})
	== "mcl_core:darkwood")

-- Every member's item and every shape of a wood is listed once.
local seen = {}
for key, list in pairs(families.FAMILIES) do
	assert(#list >= 2, key .. " has one member")
	for _, member in ipairs(list) do
		assert(not seen[member.item], member.item)
		seen[member.item] = true
	end
end
assert(#families.FAMILIES.wood_planks == 11)
assert(#families.FAMILIES.wood_log == 10, "bamboo has no logs")
assert(#families.FAMILIES.bed == 16 and #families.FAMILIES.terracotta == 17)

-- Order: itself, the project's choice, then the most held.
do
	local held = {["mcl_core:birchwood"] = 5, ["mcl_core:sprucewood"] = 9}
	local function count(item) return held[item] or 0 end
	local order = families.order("mcl_core:wood", nil, count)
	assert(order[1] == "mcl_core:wood" and order[2] == "mcl_core:sprucewood" and order[3] == "mcl_core:birchwood")
	order = families.order("mcl_core:wood", {wood_planks = "mcl_core:birchwood"}, count)
	assert(order[2] == "mcl_core:birchwood" and order[3] == "mcl_core:sprucewood")
	assert(#families.order("mcl_core:glass", nil, count) == 1)
end

-- Cover: each item its own first, then its family's, never one block twice.
do
	local bill = {["mcl_wool:red_carpet"] = 5, ["mcl_wool:purple_carpet"] = 5, ["mcl_core:glass"] = 3}
	local swappable = {["mcl_wool:red_carpet"] = true, ["mcl_wool:purple_carpet"] = true}
	local have = {["mcl_wool:red_carpet"] = 2, ["mcl_wool:white_carpet"] = 6, ["mcl_core:glass_red"] = 9}
	local covered, used = families.cover(bill, swappable, have)
	assert(covered["mcl_wool:purple_carpet"] + covered["mcl_wool:red_carpet"] == 8, "two red and six white")
	assert(covered["mcl_core:glass"] == 0, "clear glass is exact")
	assert(used["mcl_wool:white_carpet"] == 6 and used["mcl_wool:red_carpet"] == 2)
	assert(used["mcl_core:glass_red"] == nil)
	-- An item that may not be swapped takes only itself, though it is in a family.
	covered = families.cover({["mcl_core:wood"] = 4}, {}, {["mcl_core:birchwood"] = 4})
	assert(covered["mcl_core:wood"] == 0)
	-- Its own first: the red carpets go to the red row, not the purple one.
	covered = families.cover({["mcl_wool:purple_carpet"] = 2, ["mcl_wool:red_carpet"] = 2}, swappable,
		{["mcl_wool:red_carpet"] = 2, ["mcl_wool:purple_carpet"] = 2})
	assert(covered["mcl_wool:purple_carpet"] == 2 and covered["mcl_wool:red_carpet"] == 2)
end

-- What to count for a bill.
do
	local related = families.related({["mcl_core:wood"] = 1, ["mcl_core:glass"] = 1}, {["mcl_core:wood"] = true})
	assert(related["mcl_core:wood"] and related["mcl_core:birchwood"] and related["mcl_core:glass"])
	assert(not related["mcl_core:glass_red"])
end

print("builder_families: ok")
