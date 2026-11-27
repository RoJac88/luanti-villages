-- What a villager made and used, today and yesterday (docs/villager-economy-design.md,
-- What the player sees, Visibility; ticket 10), for the Builder's bench Economy tab
-- (economy_report.lua). It lives on the villager, in `_villages_tally`:
--
--   {day, made = {item = count}, used = {item = count}, money = {kind = emeralds},
--    last = {day, made, used, money}}
--
-- `money` (ticket 37b) is what crossed between players and the village: `premium_in`, paid
-- for premium goods (trade_window.lua), and `flesh_out`, the cleric's pay for rotten flesh.
-- `paid` (ticket 48b) is what the villager paid other villagers for goods and services, the
-- village's trade volume for the pulpit (`M.paid`): a sale in person (exchange.lua), a buy
-- from a stash or a farm chest (trade_trips.lua, keeper_supply.lua), a meal at the tavern
-- (meal.lua) and a commission (trade_trips.lua). Rent, alms, donations and a porter's purse
-- and change move money without trade, so they are left out.
--
-- `last` is the day before `day`, kept when the day turns; anything older is dropped.
-- production.lua notes crafts (output made, inputs and fuel used), labour.lua gathering
-- and charcoal, possessions.lua meals. No state is kept here, so every dofile of it is
-- the same.
local core = minetest

local M = {}

local function add(list, item, count)
	list[item] = (list[item] or 0) + count
end

-- Today's tally, a new one when the day turned.
local function today(self, day)
	day = day or (core.get_day_count and core.get_day_count()) or 0
	local tally = self._villages_tally
	if not tally or tally.day ~= day then
		local last
		if tally and tally.day == day - 1 then
			last = {day = tally.day, made = tally.made, used = tally.used, money = tally.money}
		end
		tally = {day = day, made = {}, used = {}, last = last}
		self._villages_tally = tally
	end
	return tally
end

-- Notes what it made and used: {item = count} each, either may be nil.
function M.note(self, made, used, day)
	local tally = today(self, day)
	for item, count in pairs(made or {}) do add(tally.made, item, count) end
	for item, count in pairs(used or {}) do add(tally.used, item, count) end
end

-- Notes emeralds of a kind of money flow (`premium_in`, `flesh_out`).
function M.money(self, kind, amount, day)
	local tally = today(self, day)
	tally.money = tally.money or {}
	add(tally.money, kind, amount)
end

-- Notes emeralds it paid another villager in trade (ticket 48b). Nothing for none.
function M.paid(self, amount, day)
	if not amount or amount <= 0 then return end
	M.money(self, "paid", amount, day)
end

-- What it made and used on `day`, and its money flows, or nil for each.
function M.on(self, day)
	local tally = self._villages_tally
	if not tally then return nil, nil, nil end
	if tally.day == day then return tally.made, tally.used, tally.money end
	if tally.last and tally.last.day == day then return tally.last.made, tally.last.used, tally.last.money end
	return nil, nil, nil
end

local function list_text(list)
	local parts = {}
	for item, count in pairs(list or {}) do parts[#parts + 1] = count .. " " .. item:gsub("^.*:", "") end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

-- Today's made and used, for the inspector.
function M.status(self, day)
	local made, used = M.on(self, day or (core.get_day_count and core.get_day_count()) or 0)
	return "made " .. list_text(made) .. "; used " .. list_text(used)
end

return M
