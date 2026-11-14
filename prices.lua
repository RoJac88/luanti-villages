-- What a villager thinks things are worth (docs/villager-economy-design.md, ticket 13).
-- Pure: it touches no engine state but the villager it is handed.
--
-- ledger.lua's base prices come from VoxeLibre's trade tables and never move. Each
-- villager keeps its own multiplier on them, `_villages_prices` ({[item] = factor}, an
-- item at 1 left out), and values an item at base price times its multiplier times its
-- own urgency (ledger.assess's `prices`). There is no village-wide price (Principle 3):
-- what a villager believes comes from what it hears.
--
-- Once a game day, at the first conversation it finishes (market_news.exchange), its
-- multipliers move with the market news it has heard and its own needs and spare:
--
-- * an item it heard needed more than offered rises, one offered more than needed
--   falls: times exp(RATE * imbalance), imbalance = (demand - supply) / (demand +
--   supply + DAMP), the counts summed over the villagers it heard of and itself. A
--   category's members (goods.lua, ticket 15: food, fuel, logs, planks) are summed in its
--   units and all move with its imbalance, so food in short supply dears every food. At
--   full imbalance that is RATE_DAY times a day, so a good nobody makes reaches MAX in
--   about five days;
-- * a need counts only as far as its villager can pay for it at its own value: a need
--   heard carries the needer's emeralds (`budget`, market_news.lua), and its own needs
--   are held to its own emeralds. Hungry villagers with an emerald each kept bread at
--   MAX, eight times its price, so farmers asked some 250 a loaf (ColonyFood,
--   2026-11-14). Since the value includes the multiplier, a price that runs ahead of
--   what buyers have cuts its own demand;
-- * a farmer counts the food in its work chest past the keeper's reserve as its supply
--   too (farm_stock.food_for_sale): it takes it to sell any day;
-- * an item it heard nothing of drifts back toward 1 (its multiplier to the power
--   FORGET), so a shortage that ended is forgotten;
-- * every multiplier stays within MIN and MAX.
--
-- In every finished conversation its members' multipliers also move SHARE of the way
-- toward their geometric mean, so prices spread by gossip as news does, and villagers
-- who rarely talk can still disagree. Trades do not move them: a trade's price folds
-- in both sides' urgency, and learning from it would turn a buyer's need into a lasting
-- belief.
--
-- The emerald amounts that do not move anchor the rest: the dinner (ledger.DINNER),
-- rent, a porter's fee and a new adult's emeralds. Prices move against each other and
-- an emerald keeps its worth.
local core = minetest
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local EMERALD = "mcl_core:emerald"

local MIN, MAX = 1 / 8, 8
local RATE_DAY = 1.5
local RATE = math.log(RATE_DAY)
-- Counts added to the imbalance's denominator, so one villager's single want moves a
-- price less than a village's.
local DAMP = 4
local FORGET = 0.8
local SHARE = 0.25
-- A multiplier this close to 1 is dropped.
local NEAR_ONE = 0.01

local M = {MIN = MIN, MAX = MAX, RATE_DAY = RATE_DAY, DAMP = DAMP, FORGET = FORGET, SHARE = SHARE}

local function clamp(factor)
	return math.min(MAX, math.max(MIN, factor))
end

local function tidy(beliefs)
	local out = {}
	for item, factor in pairs(beliefs) do
		if math.abs(math.log(factor)) >= NEAR_ONE then out[item] = clamp(factor) end
	end
	return next(out) and out or nil
end

-- Its multiplier for an item: 1 when it has none.
function M.factor(beliefs, item)
	return beliefs and beliefs[item] or 1
end

-- Demand and supply per item from what it heard ({kind, item, count, group}) and its own
-- view's needs and surplus: {[item] = {demand = n, supply = n}}. The members of a
-- category share one entry, counted in its units.
local function category_of(item)
	for _, category in ipairs(goods.ORDER) do
		if goods.CATEGORIES[category][item] then return category end
	end
	return nil
end

-- How much of a need of count it can pay for at price each with budget emeralds: all of
-- it when either is not known (news from before budgets were told).
local function affordable(count, price, budget)
	if not budget or not price or price <= 0 then return count end
	return math.min(count, budget / price)
end

-- own, optional: {budget = its emeralds, stock = {item = count} more it can sell}.
function M.balance(heard, view, own)
	local buckets = {}
	local function add(key, side, amount)
		if not amount or amount <= 0 then return end
		local entry = buckets[key] or {demand = 0, supply = 0}
		entry[side] = entry[side] + amount
		buckets[key] = entry
	end
	local function add_item(item, side, count, group)
		if item == EMERALD or not count then return end
		local category = group or category_of(item)
		local units = category and goods.units(category, item)
		if units then add("group:" .. category, side, count * units) else add(item, side, count) end
	end
	for _, entry in ipairs(heard or {}) do
		if entry.kind == "needs" then
			add_item(entry.item, "demand", affordable(entry.count, entry.price, entry.budget), entry.group)
		elseif entry.kind == "has" then add_item(entry.item, "supply", entry.count) end
	end
	local budget = own and own.budget
	local value = view and view.value
	local group = view and view.group or {}
	for item, count in pairs(view and view.needs or {}) do
		if not group[item] then add_item(item, "demand", affordable(count, value and value(item), budget)) end
	end
	-- A category's need at the cheapest member per unit.
	local per_unit = {}
	for item, category in pairs(group) do
		local price = value and value(item)
		local units = goods.units(category, item)
		if price and units and units > 0 then
			local per = price / units
			if not per_unit[category] or per < per_unit[category] then per_unit[category] = per end
		end
	end
	for category, state in pairs(view and view.categories or {}) do
		add("group:" .. category, "demand", affordable(state.short, per_unit[category], budget))
	end
	for item, count in pairs(view and view.surplus or {}) do add_item(item, "supply", count) end
	for item, count in pairs(own and own.stock or {}) do add_item(item, "supply", count) end
	local out = {}
	for key, entry in pairs(buckets) do
		local category = key:match("^group:(.+)$")
		if category then
			for item in pairs(goods.CATEGORIES[category]) do out[item] = entry end
		else
			out[key] = entry
		end
	end
	return out
end

-- A day's move from `balance` (M.balance). Returns the new beliefs, or nil for none.
function M.drift(beliefs, balance)
	local out = {}
	for item, factor in pairs(beliefs or {}) do
		if not balance[item] then out[item] = factor ^ FORGET end
	end
	for item, entry in pairs(balance) do
		local imbalance = (entry.demand - entry.supply) / (entry.demand + entry.supply + DAMP)
		out[item] = clamp(M.factor(beliefs, item) * math.exp(RATE * imbalance))
	end
	return tidy(out)
end

-- Moves each of a list of beliefs (nil for none) SHARE of the way toward their
-- geometric mean, item by item. Returns the new list, in order.
function M.share(list, n)
	n = n or #list
	local items = {}
	for i = 1, n do
		for item in pairs(list[i] or {}) do items[item] = true end
	end
	local out = {}
	for i = 1, n do out[i] = {} end
	for item in pairs(items) do
		local sum = 0
		for i = 1, n do sum = sum + math.log(M.factor(list[i], item)) end
		local mean = sum / n
		for i = 1, n do
			local own = math.log(M.factor(list[i], item))
			out[i][item] = math.exp(own + (mean - own) * SHARE)
		end
	end
	for i = 1, n do out[i] = tidy(out[i]) end
	return out
end

-- The day's move for a villager, once a day: from what it heard and its view. Returns
-- whether it moved.
function M.daily(self, heard, view, day, own)
	if self._villages_prices_day == day then return false end
	self._villages_prices_day = day
	self._villages_prices = M.drift(self._villages_prices, M.balance(heard, view, own))
	return true
end

-- Its furthest-moved multipliers, at most n, for the log and the inspector:
-- "apple x2.3, salmon x0.4".
function M.describe(beliefs, n)
	local list = {}
	for item, factor in pairs(beliefs or {}) do list[#list + 1] = {item = item, factor = factor} end
	table.sort(list, function(a, b)
		local da, db = math.abs(math.log(a.factor)), math.abs(math.log(b.factor))
		if da ~= db then return da > db end
		return a.item < b.item
	end)
	local parts = {}
	for i = 1, math.min(n or 3, #list) do
		parts[i] = string.format("%s x%.2g", list[i].item:gsub("^.*:", ""), list[i].factor)
	end
	return #parts > 0 and table.concat(parts, ", ") or "base prices"
end

return M
