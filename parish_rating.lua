-- The village's rating, 1 to 5 stars, and the pulpit's sermon (ticket 48d). Pure: it reads
-- a parish report (parish_report.lua) with its register summary (parish_register.lua).
--
-- Each part scores 0 to 1 (PARTS):
--   fed       1 - (hungry / 2 + starving) / adults
--   trades    the COUNTED professions present, of 12
--   employed  adults with a trade or today's labour, of all
--   trade     emeralds paid per adult per day (the register's average, else yesterday's)
--             over a dinner (the posted price, else the villagers' reference for one)
--   safety    the alms fund over its target; nothing with no cleric
--   growth    1/2 + the change in population over the register's days / 10
-- With the economy off, trade and safety have no meaning and the rest are weighed alone.
-- Stars are 1 + 4 x the weighted sum, rounded, then capped (the user's rules, 2026-11-27):
-- five needs no one starving and every COUNTED profession; one starving caps at four, two
-- or more at three.
--
-- The sermon is one line about the worst part, the cap first when one applies, picked from
-- a few by the day so it changes. At five stars it gives thanks. The cleric preaches it;
-- with no cleric it is a note left on the pulpit.
local core = minetest
local S = core.get_translator and core.get_translator("living_villages") or function(message) return message end

local PARTS = {
	{name = "fed", weight = 0.30},
	{name = "trades", weight = 0.20},
	{name = "employed", weight = 0.15},
	{name = "trade", weight = 0.15, economy = true},
	{name = "safety", weight = 0.10, economy = true},
	{name = "growth", weight = 0.10},
}
local COUNTED_TOTAL = 12
local GROWTH_SPAN = 10

local M = {PARTS = PARTS}

local function clamp(value)
	return math.max(0, math.min(1, value))
end

-- Each part's score, 0 to 1, by name; trade and safety only with the economy on.
function M.scores(report)
	local adults = report.adults or 0
	local food = report.food or {}
	local summary = report.register or {}
	local scores = {}
	if adults > 0 then
		scores.fed = clamp(1 - ((food.hungry or 0) / 2 + (food.starving or 0)) / adults)
		scores.employed = clamp((adults - (report.idle or 0) + (report.labouring or 0)) / adults)
	else
		scores.fed, scores.employed = 0, 0
	end
	scores.trades = clamp((COUNTED_TOTAL - #(report.missing or {})) / COUNTED_TOTAL)
	scores.growth = summary.growth and clamp(0.5 + summary.growth / GROWTH_SPAN) or 0.5
	if report.economy then
		local per_day = summary.paid_avg or report.paid_yesterday or 0
		local dinner = report.dinner_price or report.dinner_ref
		scores.trade = (adults > 0 and dinner and dinner > 0) and clamp(per_day / adults / dinner) or 0
		local church = report.church or {}
		if not church.claimed then
			scores.safety = 0
		elseif church.target and church.target > 0 then
			scores.safety = clamp((church.fund or 0) / church.target)
		else
			-- Away, or before its first service: the fund is not known against a target.
			scores.safety = 0.5
		end
	end
	return scores
end

-- The cap the starving put on the stars, and the reason: 4 for one, 3 for two or more.
local function starving_cap(report)
	local starving = report.food and report.food.starving or 0
	if starving >= 2 then return 3 end
	if starving == 1 then return 4 end
	return 5
end

-- {stars, scores, weighted, cap, cap_reason ("starving1", "starving2", "missing" or nil), worst}. `worst` names the part the sermon speaks of:
-- "starving" when the starving cap the stars, "missing" when a missing trade alone keeps
-- them from five, else the lowest-scoring part; nil at five stars.
function M.rate(report)
	local scores = M.scores(report)
	local sum, weights = 0, 0
	local lowest, lowest_score
	for _, part in ipairs(PARTS) do
		local score = scores[part.name]
		if score then
			sum, weights = sum + score * part.weight, weights + part.weight
			if not lowest_score or score < lowest_score then lowest, lowest_score = part.name, score end
		end
	end
	local weighted = weights > 0 and sum / weights or 0
	local stars = math.floor(1 + 4 * weighted + 0.5)
	local cap = starving_cap(report)
	local cap_reason = cap == 3 and "starving2" or cap == 4 and "starving1" or nil
	if #(report.missing or {}) > 0 and cap > 4 then cap, cap_reason = 4, "missing" end
	local capped = stars > cap
	stars = math.max(1, math.min(stars, cap))
	-- No adults, no village: the parts that count trades or growth say nothing then.
	if (report.adults or 0) == 0 then stars = 1 end
	local worst
	if (report.food and report.food.starving or 0) > 0 then
		worst = "starving"
	elseif stars < 5 and capped and #(report.missing or {}) > 0 then
		worst = "missing"
	elseif stars < 5 then
		worst = lowest
	end
	return {stars = stars, scores = scores, weighted = weighted, cap = cap, cap_reason = cap_reason, worst = worst}
end

local function trade_name(name)
	local names = {tool_smith = S("tool smith"), weapon_smith = S("weapon smith")}
	return names[name] or (name:gsub("_", " "))
end

local function number_word(n)
	local words = {S("one"), S("two"), S("three"), S("four"), S("five"), S("six"), S("seven"), S("eight"),
		S("nine"), S("ten")}
	return words[n] or tostring(n)
end

-- The lines for each worst part, translated when used; @1 is filled in where a line has it.
local LINES = {
	starving = {
		"The parish prays for bread: @1 of us went hungry to bed.",
		"Share your bread. Hunger has come to @1 of our homes.",
		"No feast is blessed while even one of us starves.",
	},
	missing = {
		"We have no @1 among us. Who will take up the trade?",
		"The @1's trade is missing from our village.",
		"Pray that someone here takes up the work of the @1.",
	},
	fed = {
		"Our bellies grumble louder than the choir.",
		"Bring the harvest in, for the larders are thin.",
		"Give us this day our daily bread, and a little more.",
	},
	trades = {
		"Many trades are missing from our streets.",
		"We cannot make all we need. Our workshops stand empty.",
	},
	employed = {
		"Idle hands wait on work.",
		"Too many of us have nothing to do.",
		"The fields and workshops call, but few answer.",
	},
	trade = {
		"The market square is quiet.",
		"Coins sit in purses that ought to be changing hands.",
		"Buy from your neighbour, and your neighbour will buy from you.",
	},
	safety = {
		"The alms box is near empty.",
		"Give what you can spare: the poor have little to fall back on.",
		"Charity is thin in this parish.",
	},
	growth = {
		"We are fewer than we were.",
		"The cradles stand empty.",
		"Our numbers dwindle. Pray for new families.",
	},
	blessed = {
		"The Lord has blessed this village.",
		"Every table is full and every trade is here. Give thanks.",
		"May we be as fortunate next week as we are today.",
	},
}
M.LINES = LINES

-- The sermon's line for a rating, picked by `day`.
function M.sermon(rating, report, day)
	local key = rating.worst or "blessed"
	local lines = LINES[key] or LINES.blessed
	local line = lines[(day or 0) % #lines + 1]
	if key == "starving" then
		return S(line, number_word(report.food.starving))
	elseif key == "missing" then
		return S(line, trade_name(report.missing[(day or 0) % #report.missing + 1]))
	end
	return S(line)
end

return M
