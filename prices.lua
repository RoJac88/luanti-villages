-- What a villager thinks things trade for (docs/villager-economy-design.md, Price
-- discovery, ticket 21b; it replaced ticket 13's multipliers). Pure: it touches no engine
-- state but the villager it is handed.
--
-- Each villager keeps a reference price per item: what it thinks the item trades for. It is
-- kept as a factor on the item's base price (ledger.lua), `_villages_prices` ({[key] =
-- factor}, a key at 1 left out), so the base price only seeds it. A category's members
-- (goods.lua: logs, planks, wool, stone, food, fuel) share one factor, under
-- "group:<category>" (goods.category_of, the first category an item is in), so a loaf and
-- a potato stay in line. A factor stays within 1 / SPAN and SPAN, a safety rail and not a
-- working range; at most KEEP keys are kept, those furthest from 1.
--
-- A reference price moves in log space toward evidence, and with none it stays where it
-- is: there is no pull back toward the base price.
--
-- * A trade it made, as buyer or seller (exchange.lua, trade_trips.lua, through
--   asks.sold for a seller): LEARN_TRADE of the way to the price paid each (M.learn).
-- * What it heard (M.daily, once a game day, at its first finished conversation): each
--   entry's `ref`, the teller's own price signal (market_news.lua): for what it has, its
--   reference price times its ask factor, so a glut shows; for what it needs, its
--   reference price. Weighted by 1 / (1 + hops), toward their weighted geometric mean by
--   LEARN_NEWS times the weight, at most LEARN_NEWS. Not the entry's `price`: a need's is
--   its value, urgency and the money factor in it, and learning from that ran an
--   untraded good's prices up to SPAN, each villager's bid raising the next one's
--   (tests/price_sim.lua).
-- * A buy it passed up because the ask was over its value (exchange.quote, M.missed):
--   LEARN_MISS of the way up to the dearest such ask, at the day's move.
-- * The day's balance of what it heard needed and offered, and its own needs and spare
--   (M.balance): times IMBALANCE_DAY ^ imbalance, imbalance = (demand - supply) /
--   (demand + supply + DAMP). A need counts only as far as its villager can pay. A small
--   term now: heard prices carry most of the weight. Counts alone take a price no further
--   than COUNT_SPAN either way from its base price: a need nobody can meet ran a
--   fletcher's planks to SPAN in a simulated season (tests/price_sim.lua). Trades and heard
--   prices may take it further.
-- * In every finished conversation its members' factors move SHARE of the way toward
--   their geometric mean (M.share), so prices spread by gossip as news does.
local core = minetest
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local EMERALD = "mcl_core:emerald"

local SPAN = 64
local MIN, MAX = 1 / SPAN, SPAN
local KEEP = 64
local LEARN_TRADE = 0.3
local LEARN_NEWS = 0.1
local LEARN_MISS = 0.05
local IMBALANCE_DAY = 1.15
local COUNT_SPAN = 4
local RATE = math.log(IMBALANCE_DAY)
-- Counts added to the imbalance's denominator, so one villager's single want moves a
-- price less than a village's.
local DAMP = 4
local SHARE = 0.25
-- A factor this close to 1 is dropped.
local NEAR_ONE = 0.01

local M = {SPAN = SPAN, MIN = MIN, MAX = MAX, KEEP = KEEP, LEARN_TRADE = LEARN_TRADE, LEARN_NEWS = LEARN_NEWS,
	LEARN_MISS = LEARN_MISS, IMBALANCE_DAY = IMBALANCE_DAY, COUNT_SPAN = COUNT_SPAN, DAMP = DAMP, SHARE = SHARE}

-- The base prices are ledger.lua's; loaded when first asked, since ledger.lua loads this
-- file's neighbours.
local ledger
local function base(item)
	ledger = ledger or dofile(core.get_modpath("living_villages") .. "/ledger.lua")
	return ledger.price(item)
end

local function clamp(factor)
	return math.min(MAX, math.max(MIN, factor))
end

-- The key an item's reference price is kept under.
function M.key(item)
	local category = goods.category_of(item)
	return category and "group:" .. category or item
end

-- Drops factors near 1 and, past KEEP, those nearest it.
local function tidy(beliefs)
	local list = {}
	for key, factor in pairs(beliefs or {}) do
		factor = clamp(factor)
		if math.abs(math.log(factor)) >= NEAR_ONE then list[#list + 1] = {key = key, factor = factor} end
	end
	if #list > KEEP then
		table.sort(list, function(a, b)
			local da, db = math.abs(math.log(a.factor)), math.abs(math.log(b.factor))
			if da ~= db then return da > db end
			return a.key < b.key
		end)
	end
	local out = {}
	for i = 1, math.min(#list, KEEP) do out[list[i].key] = list[i].factor end
	return next(out) and out or nil
end

-- Its factor for an item: its category's, or 1.
function M.factor(beliefs, item)
	if not beliefs then return 1 end
	return beliefs[M.key(item)] or beliefs[item] or 1
end

-- Its reference price for an item, in emeralds; nil for an item with no base price.
function M.price(beliefs, item)
	local price = base(item)
	if not price or price <= 0 then return nil end
	return price * M.factor(beliefs, item)
end

-- Saves from before 21b kept a factor per item, a category's members too: they are folded
-- into their category's key, at their geometric mean. Returns the beliefs.
function M.migrate(beliefs)
	if not beliefs then return nil end
	local sums, counts, out = {}, {}, {}
	for key, factor in pairs(beliefs) do
		local category = not key:find("^group:") and goods.category_of(key)
		if category then
			local group = "group:" .. category
			sums[group] = (sums[group] or 0) + math.log(factor)
			counts[group] = (counts[group] or 0) + 1
		else
			out[key] = factor
		end
	end
	for group, sum in pairs(sums) do
		if not out[group] then out[group] = math.exp(sum / counts[group]) end
	end
	return tidy(out)
end

-- Moves one key's factor `share` of the way, in log space, toward `target`.
local function toward(beliefs, key, target, share)
	beliefs = beliefs or {}
	local factor = beliefs[key] or 1
	beliefs[key] = clamp(factor * (target / factor) ^ share)
	return beliefs
end

-- A trade at `unit` emeralds each: its reference price moves `share` (LEARN_TRADE) of the
-- way there.
function M.learn(self, item, unit, share)
	local price = base(item)
	if not price or price <= 0 or not unit or unit <= 0 or item == EMERALD then return end
	self._villages_prices = tidy(toward(self._villages_prices, M.key(item), unit / price, share or LEARN_TRADE))
end

-- A buy it passed up at `ask` each: remembered, the dearest of the day, for the day's move.
function M.missed(self, item, ask)
	if not ask or ask <= 0 or item == EMERALD then return end
	local missed = self._villages_prices_missed or {}
	if ask > (missed[item] or 0) then missed[item] = ask end
	self._villages_prices_missed = missed
end

-- Demand and supply per item from what it heard ({kind, item, count, group}) and its own
-- view's needs and surplus: {[item] = {demand = n, supply = n}}. The members of a
-- category share one entry, counted in its units.

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
		local category = group or goods.category_of(item)
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

-- The day's move from `balance` (M.balance), on the keys: returns the new beliefs.
function M.drift(beliefs, balance)
	local out = {}
	for key, factor in pairs(beliefs or {}) do out[key] = factor end
	local seen = {}
	for item, entry in pairs(balance) do
		local key = M.key(item)
		if not seen[key] then
			seen[key] = true
			local imbalance = (entry.demand - entry.supply) / (entry.demand + entry.supply + DAMP)
			local factor = out[key] or 1
			local moved = factor * math.exp(RATE * imbalance)
			-- No further than COUNT_SPAN on counts alone, nor back past where it was.
			if moved > factor then moved = math.max(factor, math.min(moved, COUNT_SPAN))
			elseif moved < factor then moved = math.min(factor, math.max(moved, 1 / COUNT_SPAN)) end
			out[key] = clamp(moved)
		end
	end
	return tidy(out)
end

-- The day's move toward the prices it heard (each entry's `ref`), weighted by hops.
function M.hear(beliefs, heard)
	local sums, weights = {}, {}
	for _, entry in ipairs(heard or {}) do
		local price = entry.ref and base(entry.item)
		if price and price > 0 and entry.ref > 0 and entry.item ~= EMERALD
			and (entry.kind == "has" or entry.kind == "needs") then
			local key = M.key(entry.item)
			local weight = 1 / (1 + (entry.hops or 0))
			sums[key] = (sums[key] or 0) + weight * math.log(entry.ref / price)
			weights[key] = (weights[key] or 0) + weight
		end
	end
	for key, weight in pairs(weights) do
		beliefs = toward(beliefs, key, math.exp(sums[key] / weight), LEARN_NEWS * math.min(weight, 1))
	end
	return tidy(beliefs)
end

-- The day's move up toward the asks it passed up ({item = ask}).
local function misses(beliefs, missed)
	for item, ask in pairs(missed or {}) do
		local price = base(item)
		if price and price > 0 then
			local key = M.key(item)
			local target = ask / price
			if target > ((beliefs or {})[key] or 1) then beliefs = toward(beliefs, key, target, LEARN_MISS) end
		end
	end
	return tidy(beliefs)
end

-- Moves each of a list of beliefs (nil for none) SHARE of the way toward their
-- geometric mean, key by key. Returns the new list, in order.
function M.share(list, n)
	n = n or #list
	local keys = {}
	for i = 1, n do
		for key in pairs(list[i] or {}) do keys[key] = true end
	end
	local out = {}
	for i = 1, n do out[i] = {} end
	for key in pairs(keys) do
		local sum = 0
		for i = 1, n do sum = sum + math.log((list[i] or {})[key] or 1) end
		local mean = sum / n
		for i = 1, n do
			local own = math.log((list[i] or {})[key] or 1)
			out[i][key] = math.exp(own + (mean - own) * SHARE)
		end
	end
	for i = 1, n do out[i] = tidy(out[i]) end
	return out
end

-- The day's move for a villager, once a day: from what it heard, the buys it passed up,
-- and its view. Returns whether it moved.
function M.daily(self, heard, view, day, own)
	if self._villages_prices_day == day then return false end
	self._villages_prices_day = day
	local beliefs = M.migrate(self._villages_prices)
	beliefs = M.drift(beliefs, M.balance(heard, view, own))
	beliefs = M.hear(beliefs, heard)
	beliefs = misses(beliefs, self._villages_prices_missed)
	self._villages_prices_missed = nil
	self._villages_prices = beliefs
	return true
end

-- Its furthest-moved factors, at most n, for the log and the inspector:
-- "apple x2.3, food x0.4".
function M.describe(beliefs, n)
	local list = {}
	for key, factor in pairs(beliefs or {}) do list[#list + 1] = {key = key, factor = factor} end
	table.sort(list, function(a, b)
		local da, db = math.abs(math.log(a.factor)), math.abs(math.log(b.factor))
		if da ~= db then return da > db end
		return a.key < b.key
	end)
	local parts = {}
	for i = 1, math.min(n or 3, #list) do
		parts[i] = string.format("%s x%.2g", list[i].key:gsub("^.*:", ""), list[i].factor)
	end
	return #parts > 0 and table.concat(parts, ", ") or "base prices"
end

return M
