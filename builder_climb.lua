-- A Builder up a column of scaffolding. mcl_mobs has no climbing: a mob in a climbable node
-- falls as it would anywhere else. So a climb is driven from here, the way a sleeper is held in
-- its bed (init.lua): each tick the villager is put where the climb says, with no velocity,
-- acceleration or steering left for physics to act on, and vanilla's own AI is not run.
--
-- A column stands on the ground, one scaffolding block per level, and the villager stands on top
-- of it: at level n its feet are on the n-th block, n cells above the ground cell it started
-- from. Going up it places the block it is about to stand on, in the cell it stands in, then
-- rises onto it; going down it sinks into the block below and, when told to, takes away the one
-- it left, and anything left standing above it. Its body needs two clear cells above the block it stands on.
--
-- The climb lives in self._villages_climb, which mcl_mobs saves with the rest of self
-- (api.lua's get_staticdata), so a villager unloaded up a column comes back on it, not under it.
-- mcl_mobs counts a fall from the last height the villager stood still at, and a held villager
-- is still at every tick, so one let go on the ground has nothing to fall from.
local core = minetest

local M = {}

M.SCAFFOLD = "mcl_bamboo:scaffolding"
-- Nodes a second, a little slower than walking, putting each block in on the way up; twice that
-- up blocks already standing, and on the way down.
M.SPEED = 1.5
M.FAST_SPEED = 3

local function is_clear(name, engine)
	if name == "air" then return true end
	local def = engine.registered_nodes[name]
	return def ~= nil and def.buildable_to == true and (def.liquidtype or "none") == "none"
end

-- The ground cell under a villager standing at `pos`: its feet are on that cell's top face.
local function ground_under(pos)
	return math.floor(pos.y + 0.5) - 1
end

local function feet_y(climb, level)
	return climb.ground + level + 0.5
end

-- Starts a climb of the column at the villager's own x and z, and sends it to `level`. It must be
-- standing on the ground there. `options.dismantle` takes the column away on the way down.
function M.start(self, level, options)
	local pos = self.object:get_pos()
	local climb = {
		x = math.floor(pos.x + 0.5), z = math.floor(pos.z + 0.5), ground = ground_under(pos),
		level = 0, y = nil, target = level, dismantle = options and options.dismantle or nil,
	}
	climb.y = feet_y(climb, 0)
	self._villages_climb = climb
	return climb
end

function M.of(self)
	return self._villages_climb
end

-- Sends a climbing villager to another level, up or down.
function M.go_to(self, level)
	local climb = self._villages_climb
	if not climb then return false end
	climb.target = math.max(0, level)
	climb.blocked = nil
	return true
end

-- Whether it is where it was sent, and still.
function M.arrived(self)
	local climb = self._villages_climb
	return climb ~= nil and climb.level == climb.target and climb.y == feet_y(climb, climb.level)
end

-- Faces a position, for placing a block there.
function M.face(self, pos)
	local climb = self._villages_climb
	if not climb then return end
	climb.yaw = math.atan2(climb.x - pos.x, pos.z - climb.z)
end

-- Ends a climb back on the ground. Returns whether it did: a villager up a column stays on it.
function M.release(self)
	local climb = self._villages_climb
	if not climb then return true end
	if climb.level ~= 0 or climb.y ~= feet_y(climb, 0) then return false end
	self._villages_climb = nil
	return true
end

-- Takes away a column from `base` up, top first. Swapped out, not removed: scaffolding's own
-- on_destruct (mcl_bamboo) breaks every block above the one removed and drops each as an item,
-- and the Builder's scaffolding is its own, not the player's. Returns how many it took.
function M.take_down(base, engine)
	engine = engine or core
	local blocks = {}
	for y = base.y, base.y + 255 do
		local node = engine.get_node_or_nil({x = base.x, y = y, z = base.z})
		if not node or node.name ~= M.SCAFFOLD then break end
		blocks[#blocks + 1] = {x = base.x, y = y, z = base.z}
	end
	for i = #blocks, 1, -1 do engine.swap_node(blocks[i], {name = "air"}) end
	return #blocks
end

-- One step of the climb, worked out without moving anything: where the feet go, and the column's
-- changes, as {place = pos} or {remove = pos}. `get_name(pos)` reads the map.
function M.advance(climb, dtime, get_name, engine)
	local changes = {}
	local resting = feet_y(climb, climb.level)
	if climb.level == climb.target and climb.y == resting then return changes, false end
	if climb.target > climb.level or climb.y > resting then
		-- Upward: onto the block in its own cell, once that block is there and its head has room.
		local next_level = climb.level + 1
		local block = {x = climb.x, y = climb.ground + next_level, z = climb.z}
		if climb.y == resting and climb.target > climb.level then
			local head = {x = climb.x, y = block.y + 2, z = climb.z}
			-- Its own column, left standing from an earlier climb, is no obstacle: it climbs through it.
			local room = get_name(head)
			if not (room and (room == M.SCAFFOLD or is_clear(room, engine))) then
				climb.blocked = head
				return changes, false
			end
			local below = get_name(block)
			climb.fast = below == M.SCAFFOLD or nil
			if not climb.fast then
				if not (below and is_clear(below, engine)) then
					climb.blocked = block
					return changes, false
				end
				changes[#changes + 1] = {place = block}
			end
		end
		local top = feet_y(climb, next_level)
		climb.y = math.min(top, climb.y + (climb.fast and M.FAST_SPEED or M.SPEED) * dtime)
		if climb.y == top then climb.level = next_level end
	else
		-- Downward, into the block below, and that block's top is the next one down.
		local next_level = climb.level - 1
		local bottom = feet_y(climb, next_level)
		climb.y = math.max(bottom, climb.y - M.FAST_SPEED * dtime)
		if climb.y == bottom then
			if climb.dismantle then
				local left = {x = climb.x, y = climb.ground + climb.level, z = climb.z}
				if get_name(left) == M.SCAFFOLD then changes[#changes + 1] = {remove = left} end
			end
			climb.level = next_level
		end
	end
	return changes, true
end

-- Holds a climbing villager where its climb puts it, for one tick. Returns whether it is
-- climbing, in which case nothing else should move it this tick.
function M.step(self, dtime, engine)
	engine = engine or core
	local climb = self._villages_climb
	if not climb then return false end
	local function get_name(pos)
		local node = engine.get_node_or_nil(pos)
		return node and node.name
	end
	local changes, moving = M.advance(climb, dtime, get_name, engine)
	for _, change in ipairs(changes) do
		if change.place then
			engine.set_node(change.place, {name = M.SCAFFOLD})
		else
			M.take_down(change.remove, engine)
		end
	end
	local object = self.object
	object:set_pos({x = climb.x, y = climb.y, z = climb.z})
	object:set_velocity({x = 0, y = 0, z = 0})
	object:set_acceleration({x = 0, y = 0, z = 0})
	-- mcl_mobs adds this to the velocity every tick (api.lua).
	self.acc = {x = 0, y = 0, z = 0}
	self.state = "stand"
	if climb.yaw and self.set_yaw then self:set_yaw(climb.yaw) end
	if self.set_animation then self:set_animation(moving and "walk" or "stand") end
	return true
end

return M
