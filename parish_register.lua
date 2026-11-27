-- The pulpit's register of days (ticket 48c): a snapshot of its village noted once a day,
-- the last KEEP days, so the page can show averages and trends and not only what is loaded
-- when a player looks.
--
-- pulpit_menu.lua notes it: the pulpit's node timer, every TIMER_SECONDS while its block is
-- loaded, and a player opening the page, note a day once it has turned (`due`). Each entry
-- is for the day that ended (`day`): the emeralds paid that day (economy_tally keeps
-- yesterday) and the tavern's meals that evening, with the people, food states and alms fund
-- as they stand at the turn. A day the pulpit was not loaded is a gap: averages count only
-- the days noted, and `span` says how many days they cover.
--
-- It lives in the pulpit's meta (META), serialized. Pure but for that meta.
local core = minetest

local META = "villages_parish_register"
local KEEP = 7
local TIMER_SECONDS = 20
-- The latest days against the earlier ones, for a trend: a change past this share either way.
local TREND_SHARE = 0.15

local M = {META = META, KEEP = KEEP, TIMER_SECONDS = TIMER_SECONDS, TREND_SHARE = TREND_SHARE}

-- The entry a report gives for the day before `day` (the day that just ended).
function M.entry(report, day)
	return {
		day = day - 1,
		adults = report.adults, children = report.children,
		starving = report.food and report.food.starving or 0,
		hungry = report.food and report.food.hungry or 0,
		paid = report.paid_yesterday or 0,
		diners = report.diners,
		fund = report.church and report.church.fund,
	}
end

-- `list` with `entry` noted: a day already there is replaced, oldest dropped past KEEP.
function M.push(list, entry)
	local out = {}
	for _, old in ipairs(list or {}) do
		if old.day ~= entry.day then out[#out + 1] = old end
	end
	out[#out + 1] = entry
	table.sort(out, function(a, b) return a.day < b.day end)
	while #out > KEEP do table.remove(out, 1) end
	return out
end

-- Whether a day has turned since the register last noted one.
function M.due(list, day)
	local last = list and list[#list]
	return not last or last.day < day - 1
end

-- The mean of `field` over the entries that have it, and how many did; nil with none.
function M.average(list, field)
	local sum, count = 0, 0
	for _, entry in ipairs(list or {}) do
		if entry[field] then
			sum, count = sum + entry[field], count + 1
		end
	end
	if count == 0 then return nil, 0 end
	return sum / count, count
end

-- "rising", "falling" or "steady": the latest half of the entries against the earlier
-- half, by TREND_SHARE. Nil with fewer than 4 entries.
function M.trend(list, field)
	local values = {}
	for _, entry in ipairs(list or {}) do
		if entry[field] then values[#values + 1] = entry[field] end
	end
	if #values < 4 then return nil end
	local half = math.floor(#values / 2)
	local early, late = 0, 0
	for i = 1, half do early = early + values[i] end
	for i = #values - half + 1, #values do late = late + values[i] end
	early, late = early / half, late / half
	if early <= 0 then return late > 0 and "rising" or "steady" end
	if late > early * (1 + TREND_SHARE) then return "rising" end
	if late < early * (1 - TREND_SHARE) then return "falling" end
	return "steady"
end

-- The population now against the register's oldest day: the change and the days between,
-- or nil with nothing noted.
function M.growth(list, adults, children, day)
	local first = list and list[1]
	if not first then return nil end
	return adults + children - (first.adults + first.children), day - first.day
end

-- The days the entries cover, first to last.
function M.span(list)
	if not list or #list == 0 then return 0 end
	return list[#list].day - list[1].day + 1
end

-- What the page shows from the register, beside a report of now:
-- {paid_avg, paid_days, paid_trend, growth, growth_days, last_day}.
function M.summary(list, report)
	local paid_avg, paid_days = M.average(list, "paid")
	local growth, growth_days = M.growth(list, report.adults, report.children, report.day)
	return {
		paid_avg = paid_avg, paid_days = paid_days, paid_trend = M.trend(list, "paid"),
		growth = growth, growth_days = growth_days,
		last_day = list[#list] and list[#list].day,
	}
end

function M.load(pos)
	return core.deserialize(core.get_meta(pos):get_string(META)) or {}
end

function M.save(pos, list)
	core.get_meta(pos):set_string(META, core.serialize(list))
end

return M
