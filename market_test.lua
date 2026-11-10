-- A chat command for testing the market and labour by hand (ticket 12), so a tester
-- need not wait for a holiday, or for the next day's choice of work:
--
-- * `/living_villages_market open`: today becomes a holiday (common.lua's override),
--   the time jumps to the start of the bell stage, and every loaded villager may set
--   up a stall again today. Sellers then look for a stall site by the bell as on any
--   market day (market.lua, market_site.lua), and the log says why one finds none.
-- * `/living_villages_market work`: today becomes a working day, the time jumps to the
--   start of the work stage, and every loaded nitwit or unemployed villager chooses its
--   work afresh (labour.lua). The reply lists, for each, how much market news it has
--   heard and the best peddling deal in it, if any.
-- * `/living_villages_market clear`: drops the override; the moon decides again.
--
-- Needs the server privilege. With the economy off it still works but sells nothing.
local core = minetest
local labour = dofile(core.get_modpath("living_villages") .. "/labour.lua")
local news = dofile(core.get_modpath("living_villages") .. "/market_news.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")

local OVERRIDE = "living_villages_holiday_override"
local VILLAGER = "mobs_mc:villager"
-- A little past each stage's start (common.lua), in ticks.
local BELL_TICKS = 10600
local WORK_TICKS = 7100

local M = {}

local function villagers()
	local list = {}
	for _, entity in pairs(core.luaentities or {}) do
		if entity.name == VILLAGER and entity._id and not entity.child then list[#list + 1] = entity end
	end
	table.sort(list, function(a, b) return a._id < b._id end)
	return list
end

local function short_id(id)
	return tostring(id):sub(1, 6)
end

function M.open()
	local day = core.get_day_count()
	core.settings:set(OVERRIDE, day .. ":holiday")
	local count = 0
	for _, villager in ipairs(villagers()) do
		villager._villages_market_stock_day = nil
		villager._villages_market_attempted = nil
		count = count + 1
	end
	core.set_timeofday(BELL_TICKS / 24000)
	core.log("action", string.format("[living_villages] market test: day %d is a holiday, the market opens (%d villagers)",
		day, count))
	return string.format("Day %d is now a holiday and the bell stage has begun: %d loaded villagers may set up a stall. "
		.. "Watch debug.txt for 'market seller' and 'market:' lines.", day, count)
end

function M.work()
	local day = core.get_day_count()
	core.settings:set(OVERRIDE, day .. ":work")
	local lines = {}
	for _, villager in ipairs(villagers()) do
		if labour.eligible(villager) then
			villager._villages_labour = nil
			local heard = news.heard(villager)
			local deal = labour.deal(heard, possessions.emeralds(villager))
			lines[#lines + 1] = string.format("%s (%s): heard %d news, %d emeralds, %s", short_id(villager._id),
				tostring(villager._profession), #heard, possessions.emeralds(villager),
				deal and string.format("best deal %d %s, bid %.1f, need at %.1f", deal.count, deal.item, deal.bid, deal.sell_at)
					or "no peddling deal")
		end
	end
	core.set_timeofday(WORK_TICKS / 24000)
	core.log("action", string.format("[living_villages] market test: day %d is a working day, %d choose work again",
		day, #lines))
	if #lines == 0 then return string.format("Day %d is now a working day. No loaded nitwit or unemployed villager.", day) end
	return string.format("Day %d is now a working day; these choose their work again:\n%s", day, table.concat(lines, "\n"))
end

function M.clear()
	core.settings:set(OVERRIDE, "")
	return "The moon decides holidays again."
end

function M.install()
	if not core.register_chatcommand then return end
	core.register_chatcommand("living_villages_market", {
		params = "open | work | clear",
		description = "Test the market: open it now as on a holiday, start a working day with labour chosen afresh, or clear",
		privs = {server = true},
		func = function(_, param)
			param = (param or ""):match("^%s*(%S*)")
			if param == "open" then return true, M.open() end
			if param == "work" then return true, M.work() end
			if param == "clear" then return true, M.clear() end
			return false, "Usage: /living_villages_market open | work | clear"
		end,
	})
end

return M
