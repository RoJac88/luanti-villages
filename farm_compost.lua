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

local M = {MARK = MARK, BONE_MEAL = BONE_MEAL}

M.fill_nodes = {READY}
for level = 1, 7 do table.insert(M.fill_nodes, "mcl_composters:composter_" .. level) end

-- Whether one more item could raise the level. Level 7 is waiting on the node timer
-- that turns it ready.
function M.takes_items(name)
	return name == EMPTY or (name:match("^mcl_composters:composter_[1-6]$") ~= nil)
end

function M.is_ready(name)
	return name == READY
end

-- The composter's own step from 7 to ready runs off a node timer, which the block
-- unloading can lose. Start it again if so.
function M.nudge(pos, name)
	if name ~= "mcl_composters:composter_7" then return end
	local timer = core.get_node_timer(pos)
	if not timer:is_started() then timer:start(1) end
end

local warned

-- Puts one item in, by the hopper route, whose roll for a new layer is the same as
-- a player's. Returns whether the composter took it.
function M.add_item(pos, item)
	local node = core.get_node_or_nil(pos)
	local def = node and core.registered_nodes[node.name]
	local after_push = def and def._mcl_hoppers_on_after_push
	if not after_push then
		if not warned then
			warned = true
			core.log("warning", "[living_villages] " .. (node and node.name or "?")
				.. " has no hopper hook; farmers will not compost")
		end
		return false
	end
	local meta = core.get_meta(pos)
	local inv = meta:get_inventory()
	-- A generated composter may never have run its on_construct.
	if inv:get_size("src") == 0 then inv:set_size("src", 1) end
	if inv:get_size("dst") == 0 then inv:set_size("dst", 1) end
	inv:set_stack("src", 1, item .. " 1")
	meta:set_string(MARK, "1")
	after_push(pos)
	return true
end

-- Takes the bone meal from a ready composter. Returns its item name, or nil. Swaps
-- rather than sets the node, which would wipe the villager's claim with the metadata.
function M.collect(pos)
	local node = core.get_node_or_nil(pos)
	if not node or node.name ~= READY then return nil end
	local meta = core.get_meta(pos)
	local inv = meta:get_inventory()
	if inv:get_size("dst") > 0 then inv:set_stack("dst", 1, "") end
	meta:set_string(MARK, "")
	core.swap_node(pos, {name = EMPTY})
	return BONE_MEAL
end

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
