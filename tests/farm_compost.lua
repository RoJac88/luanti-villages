-- Run with: lua tests/farm_compost.lua
local nodes, metas, dropped, abms = {}, {}, {}, {}

local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end

minetest = {
	get_modpath = function() return "." end,
	get_meta = function(pos)
		local fields = metas[key(pos)] or {}
		metas[key(pos)] = fields
		return {
			get_string = function(_, field) return fields[field] or "" end,
			set_string = function(_, field, value) fields[field] = value end,
		}
	end,
	swap_node = function(pos, node) nodes[key(pos)] = node end,
	add_item = function(pos, item) table.insert(dropped, {pos = pos, item = item}) end,
	register_abm = function(abm) table.insert(abms, abm) end,
}

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
metas[key(pos)] = {[compost.MARK] = "1", villager = "farmer-1"}
assert(not compost.reset_abandoned(pos, nodes[key(pos)]))
assert(nodes[key(pos)].name == "mcl_composters:composter_3")

-- Marked and unclaimed: emptied, so the job can be taken, and no bone meal appears.
metas[key(pos)] = {[compost.MARK] = "1", villager = ""}
assert(compost.reset_abandoned(pos, nodes[key(pos)]))
assert(nodes[key(pos)].name == "mcl_composters:composter")
assert(metas[key(pos)][compost.MARK] == "" and #dropped == 0)

-- A ready one gives up its bone meal rather than losing it.
nodes[key(pos)] = {name = "mcl_composters:composter_ready"}
metas[key(pos)] = {[compost.MARK] = "1", villager = ""}
assert(compost.reset_abandoned(pos, nodes[key(pos)]))
assert(#dropped == 1 and dropped[1].item == "mcl_bone_meal:bone_meal")

print("farm_compost.lua: ok")
