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
-- * each game day the seller held some spare and sold none of it, it falls by MARKDOWN
--   (M.daily, from possessions.lua's step);
-- * it stays within MIN and MAX.
--
-- A peddler (labour.lua) never asks less than it paid for its lot. An item with no base
-- price has no ask: exchange.lua falls back to the midpoint for it.
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")

local MIN, MAX = 0.5, 2
local MARKUP, MARKDOWN = 1.05, 0.9
local NEAR_ONE = 0.01

local M = {MIN = MIN, MAX = MAX, MARKUP = MARKUP, MARKDOWN = MARKDOWN}

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
	local ask = base * M.factor(seller, item)
	local peddle = seller._villages_peddle
	if peddle and peddle.item == item and not peddle.buying and peddle.bid then ask = math.max(ask, peddle.bid) end
	return ask
end

-- A sale of the item on `day`: the ask rises.
function M.sold(seller, item, day)
	set_factor(seller, item, M.factor(seller, item) * MARKUP)
	local sold = seller._villages_ask_sold or {}
	sold[item] = day
	seller._villages_ask_sold = sold
end

-- Once a game day: every item of `surplus` (item -> count) it sold none of since the last
-- time is asked for less. Returns whether it ran today.
function M.daily(seller, surplus, day)
	if not day or seller._villages_asks_day == day then return false end
	local since = seller._villages_asks_day
	seller._villages_asks_day = day
	if not since then return true end
	local sold = seller._villages_ask_sold or {}
	for item, count in pairs(surplus or {}) do
		if count > 0 and ledger.price(item) and (sold[item] or -math.huge) < since then
			set_factor(seller, item, M.factor(seller, item) * MARKDOWN)
		end
	end
	-- What sold before the last day is forgotten; only the day matters.
	for item, at in pairs(sold) do
		if at < since then sold[item] = nil end
	end
	seller._villages_ask_sold = next(sold) and sold or nil
	return true
end

return M
