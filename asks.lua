-- What a seller asks for its spare goods: a posted price, the same to every buyer, found
-- by selling (run of 2026-11-13). Pure but for the villager it is handed.
--
-- Trades used to settle at the midpoint of the seller's and the buyer's values, and a
-- buyer's value folds in its urgency (ledger.lua) and its price beliefs (prices.lua): a
-- hungry village valued a cooked salmon at four times what its butcher did, the
-- midpoint gave the butcher half of that, and a keeper with less than the midpoint
-- bought nothing at all from a seller who would have taken a third of it.
--
-- Now the seller asks the item's base price (ledger.price) times its own factor for the
-- item (`_villages_asks`, {[item] = factor}, 1 when unset), and a buyer that values the
-- item at least that much pays it. The factor moves with how the item sells:
--
-- * each sale raises it by MARKUP (M.sold);
-- * each game day the seller held some spare and sold less than SLOW_SHARE of it, it falls
--   by MARKDOWN (M.daily, from possessions.lua's step). It used to fall only on a day with
--   no sale at all: a leatherworker that sold the butcher 2 beef now and then kept asking
--   near MAX while 26 more piled up (ColonyFood, 2026-11-14);
-- * it stays within MIN and MAX.
--
-- A seller that believes an item worth less than its base price (its price multiplier
-- under 1, prices.lua) asks that much less: a market that heard of a glut valued beef at
-- an eighth of its price while the leatherworker asked near twice it, so the butcher
-- bought none and the beef piled up (ColonyFood, 2026-11-14). A belief over 1 leaves the
-- ask to its sales, so demand is not counted twice.
--
-- A peddler (labour.lua) never asks less than it paid for its lot. An item with no base
-- price has no ask: exchange.lua falls back to the midpoint for it.
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local prices = dofile(core.get_modpath("living_villages") .. "/prices.lua")
local alchemist = dofile(core.get_modpath("living_villages") .. "/alchemist.lua")

local MIN, MAX = 0.5, 2
local MARKUP, MARKDOWN = 1.05, 0.9
local SLOW_SHARE = 0.25
local NEAR_ONE = 0.01

local M = {MIN = MIN, MAX = MAX, MARKUP = MARKUP, MARKDOWN = MARKDOWN, SLOW_SHARE = SLOW_SHARE}

local function clamp(factor)
	return math.min(MAX, math.max(MIN, factor))
end

-- Its factor for the item: 1 when it has none.
function M.factor(seller, item)
	local asks = seller._villages_asks
	return asks and asks[item] or 1
end

local function set_factor(seller, item, factor)
	factor = clamp(factor)
	local asks = seller._villages_asks or {}
	if math.abs(math.log(factor)) < NEAR_ONE then asks[item] = nil else asks[item] = factor end
	seller._villages_asks = next(asks) and asks or nil
end

-- What the seller asks for one, or nil for an item with no base price.
function M.ask(seller, item)
	local base = ledger.price(item)
	if not base or base <= 0 then return nil end
	local ask = base * M.factor(seller, item) * math.min(prices.factor(seller._villages_prices, item), 1)
	local peddle = seller._villages_peddle
	if peddle and peddle.item == item and not peddle.buying and peddle.bid then ask = math.max(ask, peddle.bid) end
	-- An alchemist never asks less for its goods than their inputs cost (ticket 20).
	if seller._villages_alchemist and alchemist.GOODS[item] then ask = math.max(ask, base) end
	return ask
end

-- `_villages_ask_sold` is {[item] = {day, count}}: the last day it sold the item, and how
-- many since its last daily look. A bare day is a save from before counts were kept.
local function sale(sold, item)
	local entry = sold[item]
	if type(entry) == "number" then return {day = entry, count = math.huge} end
	return entry
end

-- A sale of count (1 if not given) of the item on `day`: the ask rises.
function M.sold(seller, item, day, count)
	set_factor(seller, item, M.factor(seller, item) * MARKUP)
	local sold = seller._villages_ask_sold or {}
	local entry = sale(sold, item) or {count = 0}
	sold[item] = {day = day, count = entry.count + (count or 1)}
	seller._villages_ask_sold = sold
end

-- Once a game day: every item of `surplus` (item -> count) it sold less than SLOW_SHARE of
-- since the last time is asked for less. Returns whether it ran today.
function M.daily(seller, surplus, day)
	if not day or seller._villages_asks_day == day then return false end
	local since = seller._villages_asks_day
	seller._villages_asks_day = day
	if not since then return true end
	local sold = seller._villages_ask_sold or {}
	for item, count in pairs(surplus or {}) do
		local entry = sale(sold, item)
		local moved = entry and entry.day >= since and entry.count or 0
		if count > 0 and ledger.price(item) and moved < count * SLOW_SHARE then
			set_factor(seller, item, M.factor(seller, item) * MARKDOWN)
		end
	end
	-- Each day's count starts afresh; what sold before the last day is forgotten.
	local kept = {}
	for item in pairs(sold) do
		local entry = sale(sold, item)
		if entry.day >= since then kept[item] = {day = entry.day, count = 0} end
	end
	seller._villages_ask_sold = next(kept) and kept or nil
	return true
end

return M
