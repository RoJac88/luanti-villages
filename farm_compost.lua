-- The farmer's side of VoxeLibre's composter. Its own right-click handlers need
-- a player, so this goes in through the hopper hooks, which do not.
--
-- A composter a farmer has put compost in is marked. Vanilla's employ only takes
-- the empty node, so one left part full by a farmer that died or moved on could
-- never be anyone's jobsite again: the ABM below empties it once it is unclaimed.
-- A composter only a player has used has no mark and is left alone.
local core = minetest

local EMPTY = "mcl_composters:composter"
local READY = "mcl_composters:composter_ready"
local MARK = "villages_farmer_compost"
local BONE_MEAL = "mcl_bone_meal:bone_meal"
local RESET_INTERVAL = 60

local M = {MARK = MARK}

M.fill_nodes = {READY}
for level = 1, 7 do table.insert(M.fill_nodes, "mcl_composters:composter_" .. level) end

-- Empties a marked composter nobody holds. Returns whether it did.
function M.reset_abandoned(pos, node)
	local meta = core.get_meta(pos)
	if meta:get_string(MARK) == "" or meta:get_string("villager") ~= "" then return false end
	meta:set_string(MARK, "")
	core.swap_node(pos, {name = EMPTY})
	if node.name == READY then core.add_item(pos, BONE_MEAL) end
	return true
end

if core.register_abm then
	core.register_abm({
		label = "Living Villages abandoned composters",
		nodenames = M.fill_nodes,
		interval = RESET_INTERVAL,
		chance = 1,
		action = function(pos, node) M.reset_abandoned(pos, node) end,
	})
end

return M
