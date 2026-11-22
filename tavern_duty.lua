-- The tavern's place in the food trade (ticket 48, experiment E2).
--
-- The tavern is the village's place to eat. The butcher cooks every dish and sells them
-- to the keeper alone while a keeper serves a tavern within SERVICE_RADIUS of it: nobody
-- else buys a dish from the butcher, face to face, at a stall or from its stash, and its
-- dishes on offer are told as for the keeper only (market news' `keeper_only`). A diner
-- buys a dish or two to take home after dinner instead (meal.lua's takeaway), so food for
-- a birth (possessions.can_parent) is still to be had. With no keeper serving, anyone
-- buys from the butcher as before. In the lv_pair run (2026-11-22) the butcher sold every
-- dish to diners one at a time at about the dinner price, the keeper bought none, and the
-- tavern served three diners a night.
--
-- A keeper that misses MISSED_LIMIT dinners in a row, never at its jukebox through
-- service, gives the tavern up (keeper.lua), so another may take it: one lost in a cave
-- held it for good. Each day it staffs the tavern is kept on the keeper and in the
-- jukebox's meta (STAFFED); a jukebox whose keeper missed that many is vacant to anyone
-- seeking one, even with the old keeper unloaded far away.
local core = minetest
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")

local JUKEBOX = "mcl_jukebox:jukebox"
local M = {
	MISSED_LIMIT = 2,
	SERVICE_RADIUS = 64,
	-- The keeper's staff stage ends at 18500 ticks (common.lua's KEEPER_SCHEDULE).
	SERVICE_END = 18500,
	STAFFED = "villages_keeper_staffed",
	CHECK_SECONDS = 30,
}

local function today() return core.get_day_count() end

local function service_over(tod)
	tod = tod or (core.get_timeofday and core.get_timeofday()) or 0
	return tod * 24000 >= M.SERVICE_END
end

-- Dinners missed by a keeper last at its jukebox on day `staffed`, today being `day`:
-- today's counts once its service is over.
function M.missed(staffed, day, over)
	return day - staffed - (over and 0 or 1)
end

-- Whether a keeper last at its tavern on day `staffed` has missed too many dinners.
function M.absent(staffed, day, over)
	if staffed == nil then return false end
	if day == nil then day = today() end
	if over == nil then over = service_over() end
	return M.missed(staffed, day, over) >= M.MISSED_LIMIT
end

local function staffed_of(meta)
	local text = meta:get_string(M.STAFFED)
	return text ~= "" and tonumber(text) or nil
end

-- Whether a jukebox's keeper has stayed away too long (none claimed: no).
function M.stale(jukebox)
	local meta = core.get_meta(jukebox)
	return meta:get_string("villager") ~= "" and M.absent(staffed_of(meta))
end

-- Whether anyone seeking a jukebox may take this one: unclaimed, or its keeper absent.
function M.vacant(jukebox)
	local meta = core.get_meta(jukebox)
	return meta:get_string("villager") == "" or M.absent(staffed_of(meta))
end

-- A keeper at its jukebox through service: today is its last day staffed.
function M.note(self, jukebox)
	local day = today()
	self._villages_keeper_staffed = day
	if jukebox then core.get_meta(jukebox):set_string(M.STAFFED, tostring(day)) end
end

-- Whether a keeper serves a tavern within SERVICE_RADIUS of `pos`: a jukebox claimed and
-- its keeper not absent.
function M.keeper_serves(pos)
	if not pos or not core.find_nodes_in_area then return false end
	local r = M.SERVICE_RADIUS
	for _, jukebox in ipairs(core.find_nodes_in_area({x = pos.x - r, y = pos.y - r, z = pos.z - r},
			{x = pos.x + r, y = pos.y + r, z = pos.z + r}, {JUKEBOX})) do
		if not M.vacant(jukebox) then return true end
	end
	return false
end

local serves_cache = setmetatable({}, {__mode = "k"})

-- Whether the villager's dish is for the keeper alone: a butcher (never the keeper, a
-- butcher underneath) selling a prepared food while a keeper serves near its bed.
function M.keeper_only(seller, item)
	if not seller or seller._villages_keeper or seller._profession ~= "butcher" or not food.is_prepared(item) then
		return false
	end
	local now = core.get_gametime and core.get_gametime() or 0
	local cached = serves_cache[seller]
	if cached and now < cached.until_time then return cached.serves end
	local pos = seller._bed or seller._jobsite or (seller.object and seller.object:get_pos())
	local serves = M.keeper_serves(pos)
	serves_cache[seller] = {serves = serves, until_time = now + M.CHECK_SECONDS}
	return serves
end

-- Whether `seller` may sell `item` to `buyer`.
function M.may_sell(seller, buyer, item)
	return (buyer and buyer._villages_keeper) or not M.keeper_only(seller, item)
end

return M
