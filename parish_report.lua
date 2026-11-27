-- What a church's pulpit says about its village (ticket 48, the parish register;
-- docs/villager-economy-design.md). The village is the pulpit's radius, so a hand-built
-- church with a crafted pulpit reports as a generated one does: nothing here reads the
-- village record or needs a Builder. Each pulpit reports on its own radius.
--
-- 48a reads the loaded villagers around the pulpit when a player looks: the day of the
-- week, the people, the trades present and those missing for five stars, idle hands, the
-- food states and the alms fund. This file is pure: pulpit_menu.lua gathers the villagers
-- and the church and draws the page.
--
-- Five stars needs every profession in COUNTED, which is all of VoxeLibre's but the
-- fisherman. No stock building holds a tool smith's, weapon smith's or mason's jobsite
-- (economy_report.BUILDINGS), so the page names what is missing for a player to place.
-- The keeper, a Builder and an alchemist count by their role, as economy_report.present
-- has them, so a Builder (a mason to vanilla) is not the village's mason, nor an
-- alchemist (a cleric) its cleric.
local core = minetest
local economy_report = dofile(core.get_modpath("living_villages") .. "/economy_report.lua")

local COUNTED = {
	"farmer", "shepherd", "fletcher", "librarian", "cartographer", "cleric",
	"armorer", "butcher", "leatherworker", "tool_smith", "weapon_smith", "mason",
}
-- The order the page lists trades in: the counted ones, the fisherman, then the roles.
local ORDER = {}
for _, name in ipairs(COUNTED) do ORDER[#ORDER + 1] = name end
for _, name in ipairs({"fisherman", "keeper", "builder", "alchemist"}) do ORDER[#ORDER + 1] = name end
local NOT_TRADES = {nitwit = true, unemployed = true}
local FOOD_STATES = {"full", "fed", "hungry", "starving"}

local M = {COUNTED = COUNTED, ORDER = ORDER, FOOD_STATES = FOOD_STATES}

-- {name, count} for each trade present, in ORDER, then any other, by name.
function M.trades(present)
	local list, listed = {}, {}
	for _, name in ipairs(ORDER) do
		if present[name] then
			list[#list + 1] = {name = name, count = present[name]}
			listed[name] = true
		end
	end
	local others = {}
	for name, count in pairs(present) do
		if not listed[name] and not NOT_TRADES[name] then others[#others + 1] = {name = name, count = count} end
	end
	table.sort(others, function(a, b) return a.name < b.name end)
	for _, entry in ipairs(others) do list[#list + 1] = entry end
	return list
end

-- The COUNTED professions with none present, in order.
function M.missing(present)
	local list = {}
	for _, name in ipairs(COUNTED) do
		if not present[name] then list[#list + 1] = name end
	end
	return list
end

-- The report. `adults` and `children` are the villagers around the pulpit; `opts`:
--   day, weekday (index), weekday_name,
--   state(villager): its food state (food.state),
--   economy: whether the village economy is on,
--   church: {claimed = whether a cleric holds the pulpit, here = that cleric is loaded,
--            fund, target (nil before its first service)}.
function M.build(adults, children, opts)
	local present = economy_report.present(adults)
	local idle = economy_report.idle(adults, opts.day)
	local labouring = 0
	for _, entry in ipairs(idle) do
		if entry.activity then labouring = labouring + 1 end
	end
	local food = {}
	for _, state in ipairs(FOOD_STATES) do food[state] = 0 end
	for _, villager in ipairs(adults) do
		local state = opts.state(villager)
		food[state] = (food[state] or 0) + 1
	end
	return {
		day = opts.day, weekday = opts.weekday, weekday_name = opts.weekday_name,
		adults = #adults, children = #children,
		trades = M.trades(present), missing = M.missing(present),
		idle = #idle, labouring = labouring,
		food = food,
		economy = opts.economy,
		church = opts.church or {},
	}
end

return M
