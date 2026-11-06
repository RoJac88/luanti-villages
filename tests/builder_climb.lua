-- Run with: lua tests/builder_climb.lua
-- A villager up a column of scaffolding: where its feet go, and the blocks it places and takes.
minetest = {get_modpath = function() return "." end}
local climb = dofile("builder_climb.lua")
local SCAFFOLD = climb.SCAFFOLD

local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
local engine = {registered_nodes = {
	air = {buildable_to = true}, ["mcl_core:stone"] = {}, [SCAFFOLD] = {},
	["mcl_core:water_source"] = {buildable_to = true, liquidtype = "source"},
}}

-- A villager stood on stone at y 0, so its feet are at 0.5, by a map of its own.
local function world()
	local map = {}
	local villager = {pos = {x = 3, y = 0.5, z = -2}}
	villager.object = {
		get_pos = function() return villager.pos end,
		set_pos = function(_, pos) villager.pos = pos end,
		set_velocity = function(_, v) villager.velocity = v end,
		set_acceleration = function(_, a) villager.acceleration = a end,
	}
	villager.set_animation = function(self, name) self.animation = name end
	villager.set_yaw = function(self, yaw) self.yaw = yaw end
	local stub = setmetatable({
		get_node_or_nil = function(pos)
			if pos.y > 40 then return nil end
			return {name = map[key(pos)] or (pos.y <= 0 and "mcl_core:stone" or "air")}
		end,
		set_node = function(pos, node) map[key(pos)] = node.name end,
		-- remove_node would run scaffolding's on_destruct, which drops every block above as an item.
		remove_node = function() error("removed, not swapped") end,
		swap_node = function(pos, node)
			local above = {x = pos.x, y = pos.y + 1, z = pos.z}
			assert(map[key(above)] ~= SCAFFOLD, "taken from the top down")
			map[key(pos)] = node.name
		end,
	}, {__index = engine})
	return villager, map, stub
end

local function run(villager, stub, seconds)
	for _ = 1, seconds * 10 do climb.step(villager, 0.1, stub) end
end

-- Up four levels: a block placed under it for each, its feet on the top one, held still.
do
	local villager, map, stub = world()
	climb.start(villager, 4)
	assert(not climb.arrived(villager))
	run(villager, stub, 2)
	assert(villager.pos.y > 0.5 and villager.pos.y < 4.5, "it climbs at its own pace")
	assert(villager.animation == "walk")
	run(villager, stub, 3)
	assert(climb.arrived(villager))
	assert(villager.pos.x == 3 and villager.pos.z == -2 and villager.pos.y == 4.5, "on the fourth block")
	for y = 1, 4 do assert(map[key({x = 3, y = y, z = -2})] == SCAFFOLD, "block " .. y) end
	assert(map[key({x = 3, y = 5, z = -2})] == nil, "nothing over its head")
	assert(villager.animation == "stand")
	assert(villager.velocity.y == 0 and villager.acceleration.y == 0 and villager.acc.y == 0, "held")
	-- It stays there.
	run(villager, stub, 5)
	assert(villager.pos.y == 4.5)
	-- It can't let go up there.
	assert(climb.release(villager) == false and climb.of(villager))

	-- Down again, taking the column with it, twice as fast as it went up.
	villager._villages_climb.dismantle = true
	climb.go_to(villager, 0)
	run(villager, stub, 1)
	assert(villager.pos.y > 0.5 and villager.pos.y < 2, "down at its own pace: " .. villager.pos.y)
	run(villager, stub, 1)
	assert(climb.arrived(villager) and villager.pos.y == 0.5)
	for y = 1, 4 do assert(map[key({x = 3, y = y, z = -2})] == "air", "taken " .. y) end
	assert(climb.release(villager) and not climb.of(villager))
	-- And no longer held.
	assert(climb.step(villager, 0.1, stub) == false)
end

-- Down part way, leaving the column, and up again on the blocks already there.
do
	local villager, map, stub = world()
	climb.start(villager, 5)
	run(villager, stub, 5)
	climb.go_to(villager, 2)
	run(villager, stub, 3)
	assert(climb.arrived(villager) and villager.pos.y == 2.5)
	assert(map[key({x = 3, y = 5, z = -2})] == SCAFFOLD, "the column stays")
	local placed = 0
	local set_node = stub.set_node
	stub.set_node = function(pos, node) placed = placed + 1 set_node(pos, node) end
	climb.go_to(villager, 5)
	run(villager, stub, 1)
	assert(villager.pos.y > 3 and villager.pos.y < 5.5, "faster up what stands: " .. villager.pos.y)
	run(villager, stub, 1)
	assert(climb.arrived(villager) and villager.pos.y == 5.5 and placed == 0, "climbs what stands")

	-- Taking it down from part way takes what stands above too, so nothing is left in the air.
	climb.go_to(villager, 2)
	run(villager, stub, 3)
	villager._villages_climb.dismantle = true
	climb.go_to(villager, 1)
	run(villager, stub, 2)
	assert(climb.arrived(villager) and villager.pos.y == 1.5)
	assert(map[key({x = 3, y = 1, z = -2})] == SCAFFOLD, "it still stands on one")
	for y = 2, 5 do assert(map[key({x = 3, y = y, z = -2})] == "air", "taken " .. y) end
end

-- A column left behind, taken down from the ground.
do
	local _, map, stub = world()
	for y = 1, 3 do map[key({x = 0, y = y, z = 0})] = SCAFFOLD end
	assert(climb.take_down({x = 0, y = 1, z = 0}, stub) == 3)
	for y = 1, 3 do assert(map[key({x = 0, y = y, z = 0})] == "air") end
	assert(climb.take_down({x = 0, y = 1, z = 0}, stub) == 0, "nothing left to take")
end

-- Something over its head, or in the way of the next block: it stops below, and says where.
do
	local villager, map, stub = world()
	map[key({x = 3, y = 5, z = -2})] = "mcl_core:stone"
	climb.start(villager, 6)
	run(villager, stub, 6)
	assert(villager.pos.y == 2.5, "stops with its head under the stone")
	local blocked = climb.of(villager).blocked
	assert(blocked and blocked.y == 5)
	assert(map[key({x = 3, y = 3, z = -2})] == nil, "no block it can't stand on")

	villager, map, stub = world()
	map[key({x = 3, y = 2, z = -2})] = "mcl_core:water_source"
	climb.start(villager, 3)
	run(villager, stub, 4)
	assert(villager.pos.y == 1.5 and climb.of(villager).blocked.y == 2, "no scaffolding in water")
	-- Sent elsewhere, it tries again.
	climb.go_to(villager, 0)
	assert(climb.of(villager).blocked == nil)
end

-- An unloaded block is not clear.
do
	local villager, _, stub = world()
	villager.pos.y = 37.5
	climb.start(villager, 4)
	run(villager, stub, 4)
	assert(villager.pos.y == 38.5, "stops where it cannot see")
end

-- Facing a block to place it.
do
	local villager, _, stub = world()
	climb.start(villager, 1)
	climb.face(villager, {x = 3, y = 1, z = 5})
	climb.step(villager, 0.1, stub)
	assert(math.abs(villager.yaw) < 1e-9, "towards +z")
	climb.face(villager, {x = 10, y = 1, z = -2})
	climb.step(villager, 0.1, stub)
	assert(math.abs(villager.yaw + math.pi / 2) < 1e-9, "towards +x")
end

print("builder_climb: ok")
