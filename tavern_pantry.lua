-- The tavern's pantry (docs/villager-economy-design.md, ticket 1): the chests within
-- RADIUS of a jukebox. Where a tavern has one, dinner is real: meal.lua serves only
-- what the pantry holds, takes each plate out of it, feeds the villager guest, and a
-- player pays for the meal into it. The pantry is the keeper's till as well as its
-- larder, so the emeralds stay in the world where anyone can see them.
--
-- Every generated tavern has one: the stock schematic's chest stands 3 behind the
-- jukebox. The keeper keeps it stocked from the farms and cooks in it
-- (keeper_supply.lua). A tavern with no chest, a player's own, serves as it always
-- has: a display that feeds no villager and costs no player anything.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")

local RADIUS = 6
local EMERALD = "mcl_core:emerald"

local M = {RADIUS = RADIUS, EMERALD = EMERALD}

local function inventory(pos)
	local inv = core.get_meta(pos):get_inventory()
	if not inv.get_size or inv:get_size("main") == 0 then return nil end
	return inv
end

-- The pantry's chests, nearest the jukebox first, or nil if the tavern has none or
-- the economy is off.
function M.chests(jukebox)
	if not jukebox or not clock.enabled() then return nil end
	local chests = stock.find_chests(jukebox, RADIUS)
	if #chests == 0 then return nil end
	return chests
end

function M.count(chests, name)
	local total = 0
	for _, pos in ipairs(chests) do total = total + stock.chest_count(pos, name) end
	return total
end

-- Which of `items` the pantry holds, in their order.
function M.available(chests, items)
	local found = {}
	for _, item in ipairs(items) do
		if M.count(chests, item) > 0 then table.insert(found, item) end
	end
	return found
end

-- Takes one of the item out. Returns whether there was one.
function M.take(chests, name)
	for _, pos in ipairs(chests) do
		local inv = inventory(pos)
		if inv and inv:remove_item("main", name .. " 1"):get_count() == 1 then return true end
	end
	return false
end

-- Whether count of the item would fit in one chest.
function M.has_room(chests, name, count)
	for _, pos in ipairs(chests) do
		local inv = inventory(pos)
		if inv and inv:room_for_item("main", name .. " " .. count) then return true end
	end
	return false
end

-- Puts count of the item in the first chest it fits. Returns whether it did.
function M.put(chests, name, count)
	for _, pos in ipairs(chests) do
		local inv = inventory(pos)
		if inv and inv:room_for_item("main", name .. " " .. count) then
			inv:add_item("main", name .. " " .. count)
			return true
		end
	end
	return false
end

return M
