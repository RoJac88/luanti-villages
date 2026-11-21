-- What a seller asks for its spare goods: a posted price, the same to every buyer, found
-- by selling (run of 2026-11-13). Pure but for the villager it is handed.
--
-- Trades used to settle at the midpoint of the seller's and the buyer's values, and a
-- buyer's value folds in its urgency (ledger.lua) and its price beliefs (prices.lua): a
-- hungry village valued a cooked salmon at four times what its butcher did, the
-- midpoint gave the butcher half of that, and a keeper with less than the midpoint
-- bought nothing at all from a seller who would have taken a third of it.
--
-- Since ticket 21b the seller asks its reference price (prices.lua) times its own short-run
-- factor for the item (`_villages_asks`, {[item] = factor}, 1 when unset), and a buyer that
-- values the item at least that much pays it. The factor moves with how the item sells:
--
-- * a sale moves the seller's reference price LEARN_TRADE of the way to the price paid
--   (prices.learn), and pulls the factor back toward 1 by the same share, so a lasting
--   rise lives in the reference price and is not counted twice; then the factor rises by
--   MARKUP (M.sold);
-- * each game day the seller held some spare and sold less than SLOW_SHARE of it, it falls
--   by MARKDOWN, and by MARKDOWN again if the seller holds less than ledger.CUSHION: one
--   short of money cuts its price faster (M.daily, from possessions.lua's step). It used to
--   fall only on a day with no sale at all: a leatherworker that sold the butcher 2 beef
--   now and then kept asking near MAX while 26 more piled up (ColonyFood, 2026-11-14);
-- * it stays within MIN and MAX.
--
-- An ask never falls below the seller's reservation price for the item (ticket 43b,
-- M.reservation, docs/villager-economy-design.md), the larger of:
--
-- * what it costs to replace (M.replacement): what it paid, for a good bought (its cost
--   book, cost_book.lua); PROFIT times its inputs at that cost and its fuel, for a good its
--   trade makes, an input it raised or gathered itself at GATHER_SHARE of its base price;
--   GATHER_SHARE of the base price, for a good grown, gathered, caught or raised; an
--   alchemist's goods at their cost times its MARGIN (ticket 30);
-- * with its view, for an item it holds no spare of, its value with no money in it.
--
-- It replaces six floors that each fixed one case: its own value, which the money factor
-- raised for the rich (a leatherworker at λ 0.18 valued its 290 spare beef at 4.62 each
-- against an ask of 0.42) and lowered for the poor; none for food its trade made (40a), so
-- markdowns and the reference price learning from them pulled each other down to 1/64 of
-- base (the butcher sold 3 cooked salmon for an emerald, ColonyFood, 2026-11-21); a cook's
-- dish at its bought inputs only (42), so cooked beef from its own herd sold at 0.25 while
-- raw beef was asked at 0.34; the cleric's leather at its flesh cost and an emerald over
-- (37b); and the alchemist's (ticket 30). A peddler (labour.lua) still never asks less
-- than its bid for its lot. An item with no base price has no ask: exchange.lua falls back
-- to the midpoint for it.
--
-- A comfort (comforts.lua) is asked at no less than BID_SHARE of the best bid for it the
-- seller heard in the last BID_DAYS game days (market news "needs" entries, a bid capped
-- at its bidder's emeralds): ticket 23d. Its reference price and factor found it slowly,
-- one 5% markup a sale, and comforts sell a few a day, so labourers sold barrels for 28
-- to buyers who valued them at 374 and armor stands for 31 against bids near 200
-- (ColonyFood, 2026-11-15): the buyer kept most of the bid, and little money moved. The
-- bid ages out with its news, so the ask falls back once the bidder has its comfort. A
-- bid made to its face counts too (M.with_bid: exchange.lua, trade_trips.lua), since a
-- buyer tells only its top needs. Not a flower or an apple (food).
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local prices = dofile(core.get_modpath("living_villages") .. "/prices.lua")
local comforts = dofile(core.get_modpath("living_villages") .. "/comforts.lua")
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local alchemist = dofile(core.get_modpath("living_villages") .. "/alchemist.lua")
local recipes = dofile(core.get_modpath("living_villages") .. "/recipes.lua")
local cost_book = dofile(core.get_modpath("living_villages") .. "/cost_book.lua")
local COAL = "mcl_core:coal_lump"
local SMELTS_PER_LUMP = 8
-- What a good grown, gathered, caught or raised costs to replace, as a share of its base
-- price (ticket 43b): a potato 0.12, raw fish 0.21, beef 0.32, cobble 0.13, a log 0.8.
local GATHER_SHARE = 0.05
-- How deep a made good's inputs are costed (a carved stone from stone from cobble).
local MAX_DEPTH = 4

local MIN, MAX = 0.25, 4
local MARKUP, MARKDOWN = 1.05, 0.9
local SLOW_SHARE = 0.25
local NEAR_ONE = 0.01
local BID_SHARE = 0.5
local BID_DAYS = 2
-- Materials asked at the bids heard for them too (ticket 28): stone, logs, planks and
-- fuel, so an alchemist that bids more for them raises their price, not only what it
-- buys. They had no bid in their ask, and fell to 0.02 of their base price in a glut
-- (ColonyFood, 2026-11-20). Not at a bid made to the seller's face (M.with_bid).
local BID_CATEGORIES = {stone = true, log = true, planks = true, fuel = true}
local DEFAULT_TIME_SPEED = 72

-- A good the seller makes is asked at no less than this times what it costs to make
-- (M.replacement, ticket 43b).
local PROFIT = 1.25
local M = {PROFIT = PROFIT, GATHER_SHARE = GATHER_SHARE, MIN = MIN, MAX = MAX, MARKUP = MARKUP, MARKDOWN = MARKDOWN, SLOW_SHARE = SLOW_SHARE,
	BID_SHARE = BID_SHARE, BID_DAYS = BID_DAYS}

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

-- Whether the item is asked at the bids for it (ticket 23d): a comfort, but not a flower
-- (told as its category, and cheap) or a food (an apple: a hungry buyer's bid is for a
-- meal, and food has its own pricing, ticket 22b).
local function comfort_bid_priced(item)
	local comfort = comforts.by_item[item]
	return comfort ~= nil and not comfort.category and goods.category_of(item) ~= "food"
end
-- A comfort, or a material at a bid heard in the news (ticket 28).
local function bid_priced(item)
	return BID_CATEGORIES[goods.category_of(item)] == true or comfort_bid_priced(item)
end
M.bid_priced = bid_priced

-- The best bid for a comfort the seller heard in the last BID_DAYS game days, at most its
-- bidder's emeralds; 0 for none, or for an item no comfort is (flowers are told as their
-- category, and fetch little).
function M.best_bid(seller, item, now)
	if not bid_priced(item) or not seller._villages_market_news then return 0 end
	local speed = core.settings and tonumber(core.settings:get("time_speed")) or DEFAULT_TIME_SPEED
	if speed <= 0 then speed = DEFAULT_TIME_SPEED end
	local oldest = (now or (core.get_gametime and core.get_gametime()) or 0) - BID_DAYS * 86400 / speed
	local best = 0
	for _, entry in ipairs(seller._villages_market_news or {}) do
		if entry.kind == "needs" and entry.who ~= seller._id and (entry.heard or 0) >= oldest and entry.price then
			local bid
			if entry.group then
				-- A category's need (a material's), priced per unit: this member at its units.
				local told, units = goods.units(entry.group, entry.item), goods.units(entry.group, item)
				if told and units then bid = entry.price / told * units end
			elseif entry.item == item then
				bid = entry.price
			end
			if bid then best = math.max(best, math.min(bid, entry.budget or bid)) end
		end
	end
	return best
end

-- What one of the item costs the seller to replace, with no profit on it (ticket 43b), or nil
-- for an item with no base price: what it paid (its cost book, cost_book.lua); else, made by
-- a recipe of its trade, its inputs at this cost and its fuel, by the cheapest recipe; else,
-- a conversion's product its trade makes, its source's cost over the ratio; else grown,
-- gathered, caught or raised, GATHER_SHARE of its base price. `depth` stops a loop.
local function unit_cost(seller, item, depth)
	local paid = cost_book.cost(seller, item)
	if paid then return paid, "paid" end
	depth = depth or 0
	local trade = cost_book.trade_of(seller)
	if trade and depth < MAX_DEPTH then
		local best
		for _, recipe in ipairs(recipes[trade] or {}) do
			if recipe.makes == item then
				local cost = 0
				for _, input in ipairs(recipe.from) do cost = cost + (unit_cost(seller, input[1], depth + 1) or 0) * input[2] end
				cost = (cost + (recipe.fuel or 0) / SMELTS_PER_LUMP * M.fuel_cost(seller)) / (recipe.count or 1)
				if not best or cost < best then best = cost end
			end
		end
		for _, conversion in ipairs(goods.CONVERSIONS[trade] or {}) do
			if conversion.to == item then
				local source = unit_cost(seller, conversion.from, depth + 1)
				local cost = source and source / conversion.ratio
				if cost and (not best or cost < best) then best = cost end
			end
		end
		if best then return best, "made" end
	end
	local base = ledger.price(item)
	return base and base * GATHER_SHARE, "gathered"
end

-- What a lump of coal costs a recipe: its reference price, no less than GATHER_SHARE of its
-- base price, since that reference has fallen to 1/64 of base in a glut.
function M.fuel_cost(seller)
	local base = ledger.price(COAL) or 0
	return math.max(prices.price(seller._villages_prices, COAL) or base, base * GATHER_SHARE)
end

-- What one of the item costs the seller to replace (ticket 43b, rule 1): an alchemist's
-- good at its cost times its MARGIN (ticket 30, alchemist.stock_cost); one bought, what it
-- paid, to sell on at no loss; one it makes, PROFIT times its unit cost; one grown or
-- gathered, GATHER_SHARE of its base price. Nil for an item with no base price.
function M.replacement(seller, item)
	if seller._villages_alchemist and alchemist.GOODS[item] then
		return alchemist.stock_cost(seller, item) * alchemist.MARGIN
	end
	local cost, how = unit_cost(seller, item)
	if not cost then return nil end
	return how == "made" and cost * PROFIT or cost
end

-- The least the seller asks for one (ticket 43b): the larger of what it costs to replace
-- (M.replacement) and, with its view, for an item it wants and holds no spare of (within
-- its targets and their reserve, ledger.assess), its value with no money in it (the view's
-- `real`). Spare
-- has no use value to it: a rich leatherworker's 290th beef is worth what it cost. Nil for
-- an item with neither.
-- Whether the view wants the item at all: a target for it, or for a category it is in.
local function wanted(view, item)
	local target = view.targets and view.targets[item]
	if target then return target > 0 end
	for name, category in pairs(view.categories or {}) do
		if category.target > 0 and goods.CATEGORIES[name] and goods.CATEGORIES[name][item] then return true end
	end
	return false
end

function M.reservation(seller, item, view)
	local floor = M.replacement(seller, item)
	if view and view.real and not (view.surplus and view.surplus[item]) and wanted(view, item) then
		local own = view.real(item)
		if own and (not floor or own > floor) then floor = own end
	end
	return floor
end

-- What the seller asks for one, or nil for an item with no base price: its reference price
-- times its factor, never under its reservation price (given its view, M.reservation); a
-- comfort or material never less than BID_SHARE of the best bid it heard; a peddler's lot
-- never under its bid.
function M.ask(seller, item, view)
	local reference = prices.price(seller._villages_prices, item)
	if not reference then return nil end
	local ask = reference * M.factor(seller, item)
	local floor = M.reservation(seller, item, view)
	if floor then ask = math.max(ask, floor) end
	ask = math.max(ask, BID_SHARE * M.best_bid(seller, item))
	local peddle = seller._villages_peddle
	if peddle and peddle.item == item and not peddle.buying and peddle.bid then ask = math.max(ask, peddle.bid) end
	return ask
end

-- Its ask for a comfort raised to BID_SHARE of a bid made to its face (a buyer in its
-- conversation, or come on a trade trip), at most the buyer's emeralds: a buyer tells
-- only its top needs as news, so a leatherworker's barrel bid of 374 never reached the
-- weapon smith that sold it one for 18 (ColonyFood, 2026-11-15). Never over the bid, so
-- the sale still goes ahead. Any other item's ask stands.
-- A material's ask follows only the bids in the news, the standing demand an alchemist's
-- budget makes (ticket 28): to its face, an urgent buyer would hand over most of its value.
function M.with_bid(item, ask, bid)
	if not ask or not bid or not comfort_bid_priced(item) then return ask end
	return math.max(ask, BID_SHARE * bid)
end

-- What the seller asks for one of a conversion's product (goods.lua): no more than its ask
-- for the sources one takes, so an ingot is never dearer than nine nuggets (ticket 15).
-- The product's own ask stands only when it is lower. A product the seller never holds
-- keeps its seed price (nothing marks it down), while the source it does hold falls until
-- it sells: since 21b an alchemist asked 115 for an ingot while it valued a nugget at 0.8.
-- It never goes under the product's reservation price (M.reservation): the cleric's leather,
-- from flesh it paid for, never sells at a loss (ticket 37b).
function M.converted(seller, conversion, view)
	local own = M.ask(seller, conversion.to, view)
	local source = M.ask(seller, conversion.from, view)
	local floor = M.reservation(seller, conversion.to, view)
	if not source then return own end
	local via = source / conversion.ratio
	local ask = own and math.min(own, via) or via
	return floor and math.max(ask, floor) or ask
end

-- `_villages_ask_sold` is {[item] = {day, count}}: the last day it sold the item, and how
-- many since its last daily look. A bare day is a save from before counts were kept.
local function sale(sold, item)
	local entry = sold[item]
	if type(entry) == "number" then return {day = entry, count = math.huge} end
	return entry
end

-- A sale of count (1 if not given) of the item on `day`, at `unit` emeralds each if known:
-- its reference price learns the price, and the ask rises.
function M.sold(seller, item, day, count, unit)
	local factor = M.factor(seller, item)
	if unit and unit > 0 then
		prices.learn(seller, item, unit, prices.LEARN_TRADE)
		factor = factor ^ (1 - prices.LEARN_TRADE)
		-- What an alchemist's good last sold for, for its bids (alchemist.floors, ticket 28b).
		if seller._villages_alchemist then
			seller._villages_sold_at = seller._villages_sold_at or {}
			seller._villages_sold_at[item] = unit
		end
	end
	set_factor(seller, item, factor * MARKUP)
	local sold = seller._villages_ask_sold or {}
	local entry = sale(sold, item) or {count = 0}
	sold[item] = {day = day, count = entry.count + (count or 1)}
	seller._villages_ask_sold = sold
end

-- Once a game day: every item of `surplus` (item -> count) it sold less than SLOW_SHARE of
-- since the last time is asked for less, twice as fast with `money` under the cushion.
-- Returns whether it ran today.
function M.daily(seller, surplus, day, money)
	if not day or seller._villages_asks_day == day then return false end
	local since = seller._villages_asks_day
	seller._villages_asks_day = day
	if not since then return true end
	local sold = seller._villages_ask_sold or {}
	for item, count in pairs(surplus or {}) do
		local entry = sale(sold, item)
		local moved = entry and entry.day >= since and entry.count or 0
		if count > 0 and ledger.price(item) and moved < count * SLOW_SHARE then
			local short = money and money < ledger.CUSHION
			set_factor(seller, item, M.factor(seller, item) * MARKDOWN * (short and MARKDOWN or 1))
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
