-- A villager inside a tree trunk steps out of it rather than suffocating.
--
-- A sapling on a grove spot can grow while a woodcutter stands on it, and the trunk
-- fills the cell its feet are in: mcl_mobs' do_env_damage (physics.lua) then suffocates
-- it. In lv_pair runs e11b and e12 (2026-11-23) the same unemployed woodcutter died so,
-- on its grove spot, in every run of one branch.
--
-- Before that check, a villager whose feet are in a node of group "tree" is moved to
-- the nearest neighbouring cell it can stand in: the four sides first, then the
-- corners, at its feet' level, then one up, then one down. With none free it is left
-- where it is, and suffocates as before.
local core = minetest
local cells = dofile(core.get_modpath("living_villages") .. "/cells.lua")

-- Where mcl_mobs samples the feet: the collision box's base plus a quarter node.
local FEET_OFFSET = 0.01 + 0.25
-- An entity standing on a floor at feet - 1 sits this far under its feet node's centre.
local STAND_OFFSET = 0.49

local SIDES = {
	{1, 0}, {-1, 0}, {0, 1}, {0, -1},
	{1, 1}, {1, -1}, {-1, 1}, {-1, -1},
}

local function round(value)
	return math.floor(value + 0.5)
end

local M = {}

-- The position next to `pos` it can stand in, or nil.
function M.free_neighbour(pos)
	local x, z, feet = round(pos.x), round(pos.z), round(pos.y + FEET_OFFSET)
	for _, dy in ipairs({0, 1, -1}) do
		for _, side in ipairs(SIDES) do
			local at = {x = x + side[1], y = feet + dy - STAND_OFFSET, z = z + side[2]}
			if cells.has_standing_space(at) then return at end
		end
	end
	return nil
end

-- The tree node its feet are in, or nil.
function M.in_tree(pos)
	local node = core.get_node_or_nil({x = round(pos.x), y = round(pos.y + FEET_OFFSET), z = round(pos.z)})
	if node and core.get_item_group(node.name, "tree") > 0 then return node.name end
	return nil
end

-- Moves it out of a trunk if it is in one; true if it was moved.
function M.rescue(self)
	local object = self.object
	local pos = object and object:get_pos()
	if not pos or object:get_attach() then return false end
	local tree = M.in_tree(pos)
	if not tree then return false end
	local to = M.free_neighbour(pos)
	if not to then return false end
	object:set_pos(to)
	object:set_velocity({x = 0, y = 0, z = 0})
	core.log("action", string.format("[living_villages] villager %s was inside %s at (%.1f,%.1f,%.1f); stepped out to (%d,%d,%d)",
		tostring(self._id), tree, pos.x, pos.y, pos.z, to.x, round(to.y), to.z))
	return true
end

function M.install(def)
	local original = def.do_env_damage
	if not original then return end
	def.do_env_damage = function(self, ...)
		M.rescue(self)
		return original(self, ...)
	end
end

return M
