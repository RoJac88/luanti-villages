-- Run with: lua tests/parish_rating.lua
-- The village's stars and the sermon (ticket 48d).
minetest = {
	get_modpath = function() return "." end,
	get_translator = function()
		return function(message, ...)
			local args = {...}
			return (message:gsub("@(%d)", function(i) return args[tonumber(i)] end))
		end
	end,
}
local rating = dofile("parish_rating.lua")

-- A thriving village: all fed, every trade, all at work, trade over a dinner a head, a
-- full alms fund, growing.
local function thriving()
	return {
		day = 100, adults = 20, children = 4, economy = true,
		food = {full = 10, fed = 10, hungry = 0, starving = 0},
		missing = {}, idle = 0, labouring = 0,
		paid_yesterday = 200, dinner_price = 3,
		church = {claimed = true, here = true, fund = 300, target = 300},
		register = {paid_avg = 90, paid_days = 7, growth = 3, growth_days = 6},
	}
end

do
	local report = thriving()
	local rated = rating.rate(report)
	assert(rated.stars == 5 and rated.cap == 5 and rated.worst == nil and rated.cap_reason == nil)
	assert(rated.scores.fed == 1 and rated.scores.trades == 1 and rated.scores.employed == 1)
	assert(rated.scores.trade == 1, "90 a day for 20 at 3 a dinner is 1.5 dinners a head")
	assert(rated.scores.safety == 1 and math.abs(rated.scores.growth - 0.8) < 1e-9)
	assert(rating.sermon(rated, report, 0) == "The Lord has blessed this village.")
	assert(rating.sermon(rated, report, 1) ~= rating.sermon(rated, report, 2), "picked by the day")
end

-- One starving caps at four, two or more at three, and the sermon speaks of them.
do
	local report = thriving()
	report.food.starving, report.food.full = 1, 9
	local rated = rating.rate(report)
	assert(rated.stars == 4 and rated.cap == 4 and rated.cap_reason == "starving1" and rated.worst == "starving")
	assert(rating.sermon(rated, report, 0) == "The parish prays for bread: one of us went hungry to bed.")
	report.food.starving, report.food.full = 2, 8
	rated = rating.rate(report)
	assert(rated.stars == 3 and rated.cap_reason == "starving2")
	assert(rating.sermon(rated, report, 1) == "Share your bread. Hunger has come to two of our homes.")
end

-- A missing trade blocks five but allows four; the fisherman is not counted (parish_report).
do
	local report = thriving()
	report.missing = {"mason"}
	local rated = rating.rate(report)
	assert(rated.stars == 4 and rated.cap_reason == "missing" and rated.worst == "missing")
	assert(rating.sermon(rated, report, 0) == "We have no mason among us. Who will take up the trade?")
	report.missing = {"tool_smith", "weapon_smith"}
	rated = rating.rate(report)
	assert(rating.sermon(rated, report, 1):find("weapon smith", 1, true), rating.sermon(rated, report, 1))
	-- Starving and missing: the starving cap speaks first.
	report.food.starving = 2
	rated = rating.rate(report)
	assert(rated.cap_reason == "starving2" and rated.worst == "starving")
end

-- A poor village: low stars, the sermon on its worst part.
do
	local report = thriving()
	report.idle, report.labouring = 14, 0
	report.missing = {"farmer", "shepherd", "fletcher", "librarian", "cartographer", "armorer"}
	report.register = {paid_avg = 4, paid_days = 7, growth = -4, growth_days = 6}
	report.church = {claimed = false}
	local rated = rating.rate(report)
	assert(rated.scores.safety == 0, "no cleric, no alms")
	assert(rated.stars <= 3, rated.stars)
	assert(rated.worst == "safety" or rated.worst == "trade", tostring(rated.worst))
	assert(math.abs(rated.scores.employed - 0.3) < 1e-9 and math.abs(rated.scores.growth - 0.1) < 1e-9)
	-- The lowest part: with the fund fine, trade is worst.
	report.church = {claimed = true, here = true, fund = 300, target = 300}
	rated = rating.rate(report)
	assert(rated.worst == "trade" and rating.sermon(rated, report, 0) == "The market square is quiet.")
end

-- Stars never under one; an empty village scores nothing.
do
	local rated = rating.rate({day = 1, adults = 0, children = 0, economy = true, food = {}, missing = {"farmer"},
		idle = 0, labouring = 0, church = {}})
	assert(rated.stars == 1 and rated.scores.fed == 0 and rated.scores.trade == 0)
end

-- The fund unknown against a target (cleric away, or before a service) is half.
do
	local report = thriving()
	report.church = {claimed = true, here = false}
	assert(rating.scores(report).safety == 0.5)
	report.church = {claimed = true, here = true, fund = 10}
	assert(rating.scores(report).safety == 0.5)
end

-- No register yet: trade from yesterday, growth neutral; no keeper: the villagers' reference.
do
	local report = thriving()
	report.register = {}
	report.dinner_price, report.dinner_ref = nil, 20
	local scores = rating.scores(report)
	assert(scores.growth == 0.5 and math.abs(scores.trade - 0.5) < 1e-9, scores.trade)
	report.dinner_ref = nil
	assert(rating.scores(report).trade == 0, "nothing to measure against")
end

-- The economy off: trade and safety are left out, the rest weighed alone.
do
	local report = thriving()
	report.economy = false
	local rated = rating.rate(report)
	assert(rated.scores.trade == nil and rated.scores.safety == nil)
	assert(rated.stars == 5, "a fed, staffed, busy, growing village is still five stars")
end

print("parish_rating tests passed")
