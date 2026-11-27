local core = minetest
-- Emeralds from the ground and in blocks at the economy's scale. Ticket 11h multiplied every
-- price and the money supply by ledger.SCALE (64) and let the emerald stack to 4096, but
-- emerald ore still gave vanilla's 1 and a block still took 9, so a mined emerald was a
-- 64th of the vanilla one and a block was worth half a dinner. With the economy on:
-- * Emerald ore, stone and deepslate, gives SCALE emeralds for every one vanilla would,
--   Fortune included. VoxeLibre's handle_node_drops spawns one entity per item counted, so
--   the drops are not raised: while it runs on an emerald ore node, each emerald it adds to
--   the world is added as one entity holding SCALE.
-- * Smelting the ore gives SCALE, as mining it would.
-- * A block takes SCALE emeralds in each of its nine slots, and breaks back into 9 * SCALE.
--   The engine takes one from each slot, so a craft predicted with fewer than SCALE in any
--   slot shows nothing, and a craft takes SCALE - 1 more from each.
-- Off with the economy, and nothing is saved: a world played with it on keeps what was
-- mined, and blocks broken after turning it off give 9.
local SCALE = dofile(core.get_modpath("living_villages") .. "/ledger.lua").SCALE
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")

local EMERALD = "mcl_core:emerald"
local BLOCK = "mcl_core:emeraldblock"
local ORES = {"mcl_core:stone_with_emerald", "mcl_deepslate:deepslate_with_emerald"}

local M = {SCALE = SCALE, EMERALD = EMERALD, BLOCK = BLOCK, ORES = ORES}

local is_ore = {}
for _, ore in ipairs(ORES) do is_ore[ore] = true end

local function is_block_grid(grid)
	local emeralds = 0
	for _, stack in ipairs(grid) do
		local name = stack:get_name()
		if name == EMERALD then
			emeralds = emeralds + 1
		elseif name ~= "" then
			return false
		end
	end
	return emeralds == 9
end

-- Whether every emerald slot of a block's grid holds SCALE.
function M.grid_pays(grid)
	for _, stack in ipairs(grid) do
		if stack:get_name() == EMERALD and stack:get_count() < SCALE then return false end
	end
	return true
end

-- craft_predict: no block shown unless every slot pays.
function M.predict(itemstack, _, old_grid)
	if itemstack:get_name() ~= BLOCK or not is_block_grid(old_grid) then return end
	if not M.grid_pays(old_grid) then return ItemStack("") end
end

-- on_craft: the engine has taken one from each slot; take the rest of SCALE.
function M.on_craft(itemstack, _, old_grid, craft_inv)
	if itemstack:get_name() ~= BLOCK or not is_block_grid(old_grid) then return end
	if not M.grid_pays(old_grid) then
		-- Predict should have stopped it; put the grid back rather than sell a block for 9.
		craft_inv:set_list("craft", old_grid)
		return ItemStack("")
	end
	for i, stack in ipairs(old_grid) do
		if stack:get_name() == EMERALD then
			local left = ItemStack(stack)
			left:set_count(stack:get_count() - SCALE)
			craft_inv:set_stack("craft", i, left)
		end
	end
end

-- Wraps handle_node_drops so an emerald ore's emeralds come SCALE to an entity.
function M.wrap_drops(handle_node_drops)
	return function(pos, drops, digger)
		local node = core.get_node(pos)
		if not is_ore[node.name] then return handle_node_drops(pos, drops, digger) end
		local add_item = core.add_item
		core.add_item = function(at, item)
			local stack = ItemStack(item)
			if stack:get_name() == EMERALD then
				stack:set_count(stack:get_count() * SCALE)
				return add_item(at, stack)
			end
			return add_item(at, item)
		end
		local ok, err = pcall(handle_node_drops, pos, drops, digger)
		core.add_item = add_item
		if not ok then error(err, 0) end
	end
end

function M.install()
	if not clock.enabled() or not core.clear_craft then return false end
	-- Smelting and breaking a block: every recipe that makes emeralds, made again scaled.
	core.clear_craft({output = EMERALD})
	core.register_craft({type = "shapeless", output = EMERALD .. " " .. (9 * SCALE), recipe = {BLOCK}})
	for _, ore in ipairs(ORES) do
		if core.registered_nodes[ore] then
			core.register_craft({type = "cooking", output = EMERALD .. " " .. SCALE, recipe = ore, cooktime = 10})
		end
	end
	core.register_craft_predict(M.predict)
	core.register_on_craft(M.on_craft)
	if core.registered_items[BLOCK] then
		core.override_item(BLOCK, {_doc_items_usagehelp = string.format(
			"Takes %d emeralds in each of the nine crafting slots, and breaks back into %d.", SCALE, 9 * SCALE)})
	end
	-- VoxeLibre's mcl_item_entity replaces handle_node_drops; wrap whichever is last.
	core.register_on_mods_loaded(function()
		core.handle_node_drops = M.wrap_drops(core.handle_node_drops)
	end)
	return true
end

return M
