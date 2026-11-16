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
-- An ask never falls below the seller's own value for the item (given its view): one
-- with a glut or no money values it little, a rich one more. A peddler (labour.lua)
-- never asks less than it paid for its lot. Nothing else floors it: the alchemist's floor
-- at its inputs' cost went with ticket 21b (ColonyFood, 2026-11-15: broke, it held 30
-- flint it could not sell at cost to a fletcher with one emerald). An item with no base
-- price has no ask: exchange.lua falls back to the midpoint for it.
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

local MIN, MAX = 0.25, 4
local MARKUP, MARKDOWN = 1.05, 0.9
local SLOW_SHARE = 0.25
local NEAR_ONE = 0.01
local BID_SHARE = 0.5
local BID_DAYS = 2
local DEFAULT_TIME_SPEED = 72

local M = {MIN = MIN, MAX = MAX, MARKUP = MARKUP, MARKDOWN = MARKDOWN, SLOW_SHARE = SLOW_SHARE,
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
local function bid_priced(item)
	local comfort = comforts.by_item[item]
	return comfort ~= nil and not comfort.category and goods.category_of(item) ~= "food"
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
		if entry.kind == "needs" and entry.item == item and not entry.group and entry.who ~= seller._id
			and (entry.heard or 0) >= oldest and entry.price then
			best = math.max(best, math.min(entry.price, entry.budget or entry.price))
		end
	end
	return best
end

-- What the seller asks for one, or nil for an item with no base price. With its view
-- (possessions.assess), never less than its own value for the item; a comfort never less
-- than BID_SHARE of the best bid it heard.
function M.ask(seller, item, view)
	local reference = prices.price(seller._villages_prices, item)
	if not reference then return nil end
	local ask = reference * M.factor(seller, item)
	local own = view and view.value(item)
	if own then ask = math.max(ask, own) end
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
function M.with_bid(item, ask, bid)
	if not ask or not bid or not bid_priced(item) then return ask end
	return math.max(ask, BID_SHARE * bid)
end

-- What the seller asks for one of a conversion's product (goods.lua): no more than its ask
-- for the sources one takes, so an ingot is never dearer than nine nuggets (ticket 15).
-- The product's own ask stands only when it is lower. A product the seller never holds
-- keeps its seed price (nothing marks it down), while the source it does hold falls until
-- it sells: since 21b an alchemist asked 115 for an ingot while it valued a nugget at 0.8.
function M.converted(seller, conversion, view)
	local own = M.ask(seller, conversion.to, view)
	local source = M.ask(seller, conversion.from, view)
	if not source then return own end
	local via = source / conversion.ratio
	return own and math.min(own, via) or via
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
