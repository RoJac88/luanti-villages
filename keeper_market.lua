-- The keeper at market (ticket 51, experiment E5). On a market day (a holiday, when the
-- sellers keep stalls about the bell, market.lua) the keeper spends the market hours,
-- OPEN to CLOSE, going round the stalls instead of fetching from the farms: it walks to
-- each open stall showing a food it wants (a dish, or bread) and buys there
-- (market_stall.sell), once per stall a day. It shops for the days until the next market:
-- keeper_supply.update_wants stocks to the evening's demand times STOCK_DAYS on a market
-- day, and its float is the whole pantry's money (keeper_supply.float). Markets come every
-- four days; between them it buys from the butcher and the farms as before.
local core = minetest
local market_stall = dofile(core.get_modpath("living_villages") .. "/market_stall.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")

local M = {
	OPEN = 10500,
	-- market.lua's SETUP_CUTOFF: stalls pack up from 14750; the keeper's staff stage
	-- starts at 14500 on a holiday.
	CLOSE = 14500,
	-- Days it stocks for at market: to the next market, four days on.
	STOCK_DAYS = 4,
	RADIUS = 64,
	REACH = 4,
	CHECK_SECONDS = 5,
}

local function ticks()
	return (core.get_timeofday and core.get_timeofday() or 0) * 24000
end

-- Whether now is the keeper's market time: a holiday, in the market hours.
function M.open(holiday, tod_ticks)
	local t = tod_ticks or ticks()
	return holiday and t >= M.OPEN and t < M.CLOSE
end

-- A food the keeper buys at market: a prepared dish (bread among them).
local function wanted_food(item)
	return food.is_prepared(item)
end

-- The open stalls near `pos` showing a food it wants that it has not visited today,
-- nearest first: {seller, items}.
function M.stalls(self, pos, day)
	local visited = self._villages_market_visited
	if not visited or visited.day ~= day then
		visited = {day = day}
		self._villages_market_visited = visited
	end
	local out = {}
	for _, object in ipairs(core.get_objects_inside_radius(pos, M.RADIUS)) do
		local seller = object:get_luaentity()
		local session = seller and seller._villages_market_session
		if seller ~= self and session and session.stall and session.goods and seller._id
			and not visited[seller._id] then
			local foods = {}
			for _, item in ipairs(session.goods) do
				if wanted_food(item) then foods[#foods + 1] = item end
			end
			if #foods > 0 then
				local at = object:get_pos()
				out[#out + 1] = {seller = seller, items = foods, distance = at and vector.distance(pos, at) or math.huge}
			end
		end
	end
	table.sort(out, function(a, b) return a.distance < b.distance end)
	return out
end

local next_check = setmetatable({}, {__mode = "k"})

-- One step at market. Returns true while it has a stall to go to (keeper_supply skips its
-- farm run), false with none: on the first market day of lv_pair e5 no stall showed food,
-- and it stood the market hours out with the pantry empty.
-- `go(self, target, arrive)` walks it.
function M.step(self, now, day, go)
	if now < (next_check[self] or 0) then return self._villages_market_busy == true end
	next_check[self] = now + M.CHECK_SECONDS
	local pos = self.object and self.object:get_pos()
	if not pos then return false end
	local stall = M.stalls(self, pos, day)[1]
	self._villages_market_busy = stall ~= nil or nil
	if not stall then return false end
	local seller = stall.seller
	local at = M.front(seller) or seller.object:get_pos()
	if not at then return true end
	local function buy(entity)
		entity._villages_market_visited[seller._id] = true
		local here = entity.object:get_pos()
		local there = seller.object and seller.object:get_pos()
		if not here or not there or vector.distance(here, there) > M.REACH + 1 then
			core.log("action", string.format("[living_villages] keeper %s could not reach %s's stall",
				tostring(entity._id):sub(1, 6), tostring(seller._id):sub(1, 6)))
			return
		end
		local trade = market_stall.sell(seller, entity, stall.items)
		if not trade then
			core.log("action", string.format("[living_villages] keeper %s bought nothing at %s's stall (%s)",
				tostring(entity._id):sub(1, 6), tostring(seller._id):sub(1, 6), table.concat(stall.items, ", ")))
		end
	end
	if vector.distance(pos, at) <= M.REACH then
		buy(self)
	elseif go(self, at, buy) == false then
		buy(self)
	end
	return true
end

-- The cell a customer stands on at a stall: past its tables, away from the seller
-- (market_site's layout: the seller stands at first - outward). A whole cell, as gopath
-- wants: e5 run 2 walked to the seller's own position, between cells, and every walk
-- failed ("could not reach" each stall).
function M.front(seller)
	local session = seller._villages_market_session
	local layout = session and session.layout
	local first, outward = layout and layout.first, layout and layout.outward
	if not first or not outward then return nil end
	return {x = first.x + outward.x, y = first.y, z = first.z + outward.z}
end

-- Walks the keeper to `target`, then `arrive(entity)`. "wait" while gopath cannot answer
-- (an earlier failed walk's cooldown, or a walk under way: market.lua's
-- start_market_walk), false when it refuses outright.
function M.go(self, target, arrive)
	if (self.ready_to_path and not self:ready_to_path(true)) or self.state == "gowp" then
		return "wait"
	end
	local previous = self._villages_goto_route
	if previous and previous.status == "retry" then self._villages_goto_route = nil end
	local started = self:gopath(target, arrive, true)
	if started == false or started == nil then return false end
	return true
end

return M
