-- Run with: lua tests/tree_rescue.lua
-- A villager inside a tree trunk steps out to a free neighbouring cell; with none it stays.
local world, logs = {}, {}
local function key(x, y, z) return x .. ":" .. y .. ":" .. z end
local function put(x, y, z, name) world[key(x, y, z)] = name end
local TREE, STONE = "mcl_core:tree", "mcl_core:stone"
minetest = {
	registered_nodes = {air = {walkable = false}, [STONE] = {walkable = true}, [TREE] = {walkable = true}},
	get_modpath = function() return "." end,
	get_node_or_nil = function(pos) return {name = world[key(pos.x, pos.y, pos.z)] or "air"} end,
	get_item_group = function(name, group)
		if name == TREE and group == "tree" then return 1 end
		return 0
	end,
	log = function(_, text) logs[#logs + 1] = text end,
}
local rescue = dofile("tree_rescue.lua")

-- Flat stone floor at y = 8, a trunk two high at (0, 9, 0) and (0, 10, 0).
local function reset()
	world = {}
	for x = -3, 3 do for z = -3, 3 do put(x, 8, z, STONE) end end
	put(0, 9, 0, TREE)
	put(0, 10, 0, TREE)
end

local function villager(pos)
	local self = {_id = "w"}
	self.object = {
		get_pos = function() return {x = pos.x, y = pos.y, z = pos.z} end,
		set_pos = function(_, to) pos = to; self.moved = to end,
		set_velocity = function() end,
		get_attach = function() return nil end,
	}
	return self
end

-- Standing in the trunk (entity at feet - 0.49, as on a floor): out to a side, on the floor.
reset()
local stuck = villager({x = 0.1, y = 8.51, z = -0.2})
assert(rescue.in_tree(stuck.object:get_pos()) == TREE)
assert(rescue.rescue(stuck), "moved out")
assert(stuck.moved.x == 1 and stuck.moved.z == 0 and math.abs(stuck.moved.y - 8.51) < 1e-9, "the first side")
assert(rescue.in_tree(stuck.moved) == nil)
assert(logs[#logs]:find("villager w was inside mcl_core:tree"))

-- The sides blocked: a corner.
reset()
for _, side in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do put(side[1], 9, side[2], STONE) end
local cornered = villager({x = 0, y = 8.51, z = 0})
assert(rescue.rescue(cornered) and cornered.moved.x == 1 and cornered.moved.z == 1, "a corner")

-- Walled in at its level but the wall's top open: up onto it.
reset()
for _, side in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}) do
	put(side[1], 9, side[2], STONE)
end
local walled = villager({x = 0, y = 8.51, z = 0})
assert(rescue.rescue(walled) and math.abs(walled.moved.y - 9.51) < 1e-9, "one up")

-- No free cell anywhere: left where it is.
reset()
for x = -1, 1 do for z = -1, 1 do for y = 7, 11 do
	if not (x == 0 and z == 0 and (y == 9 or y == 10)) then put(x, y, z, STONE) end
end end end
local buried = villager({x = 0, y = 8.51, z = 0})
assert(not rescue.rescue(buried) and buried.moved == nil, "nowhere to go")

-- Not in a tree: nothing done, and damage is still dealt through the wrapper.
reset()
local free = villager({x = 2, y = 8.51, z = 2})
assert(not rescue.rescue(free) and free.moved == nil)
local def, dealt = {do_env_damage = function() return "dealt" end}, nil
rescue.install(def)
dealt = def.do_env_damage(stuck)
assert(dealt == "dealt")
local stuck2 = villager({x = 0, y = 8.51, z = 0})
def.do_env_damage(stuck2)
assert(stuck2.moved, "rescued before the damage check")

print("tree_rescue tests passed")
