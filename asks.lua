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
-- with a glut or no money values it little, a rich one more. Not food its trade makes
-- (ticket 40a, M.stock_in_trade): that is priced by supply, its sales and the days it
-- sits unsold, as the farm chest's (39a). At a money factor of 0.18 a leatherworker
-- valued its 290 spare beef at 4.62 each and asked that, eleven times its ask of 0.42,
-- and the butcher, valuing cooked beef at 22.55, asked that of a keeper whose plates
-- earn 2 (ColonyFood, 2026-11-21). A peddler (labour.lua)
-- never asks less than it paid for its lot. Nothing else floors it: the alchemist's floor
-- at its inputs' cost went with ticket 21b (ColonyFood, 2026-11-15: broke, it held 30
-- flint it could not sell at cost to a fletcher with one emerald). An item with no base
-- price has no ask: exchange.lua falls back to the midpoint for it.
--
-- A cook's dish (a `demand` recipe's output, recipes.lua: the butcher's) is asked at no less
-- than PROFIT times what its raw inputs cost it, as bought (`_villages_input_cost`,
-- M.note_input), and its fuel at the cook's reference price for coal (M.dish_floor, ticket
-- 42). With no floor at its own value (40a) and 16 dishes unsold for days while the keeper
-- bought none, the butcher's asks fell to a quarter of its reference price and that price
-- followed its sales down: it sold 3 cooked salmon for an emerald, and 12 baked potatoes,
-- from fish and beef it paid 0.25 to 0.4 each for (ColonyFood, 2026-11-21). Not 37b's
-- extra emerald over cost, which would more than double a dish's price.
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
local COAL = "mcl_core:coal_lump"
local SMELTS_PER_LUMP = 8
-- What a cook's raw inputs cost it is an average over about this many bought (M.note_input).
local INPUT_KEEP = 8

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

-- A product made from sources the seller paid for sells for at least this much over their
-- cost, and at least an emerald over it (M.cost_floor, ticket 37b).
local PROFIT = 1.25
local M = {PROFIT = PROFIT, MIN = MIN, MAX = MAX, MARKUP = MARKUP, MARKDOWN = MARKDOWN, SLOW_SHARE = SLOW_SHARE,
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

-- What the seller asks for one, or nil for an item with no base price. With its view
-- (possessions.assess), never less than its own value for the item; a comfort never less
-- than BID_SHARE of the best bid it heard.
-- Whether the item is food, or cooks into food, that the seller's trade makes (ledger.outputs,
-- ledger.food_good): stock in trade, asked with no floor at its own value (ticket 40a).
function M.stock_in_trade(seller, item)
	if not ledger.food_good(item) then return false end
	local trade = seller._villages_alchemist and "alchemist" or (seller._villages_keeper and "keeper")
		or seller._profession
	return trade ~= nil and ledger.outputs(trade, seller._max_trade_tier)[item] == true
end

-- The demand recipes (recipes.lua) a cook makes `item` by, or an empty list: never the
-- keeper's, which cooks only as a last resort.
local function dish_recipes(seller, item)
	local found = {}
	if seller._villages_keeper or not seller._profession then return found end
	for _, recipe in ipairs(recipes[seller._profession] or {}) do
		if recipe.demand and (item == nil or recipe.makes == item) then found[#found + 1] = recipe end
	end
	return found
end

-- Notes `count` of an item bought for `paid` emeralds into a cook's average input cost
-- (ticket 42), if the item is an input of one of its demand recipes.
function M.note_input(buyer, item, count, paid)
	if not buyer or not count or count <= 0 or not paid or paid < 0 then return end
	local used = false
	for _, recipe in ipairs(dish_recipes(buyer)) do
		for _, input in ipairs(recipe.from) do used = used or input[1] == item end
	end
	if not used then return end
	local costs = buyer._villages_input_cost or {}
	local before = costs[item]
	costs[item] = before and (before * INPUT_KEEP + paid) / (INPUT_KEEP + count) or paid / count
	buyer._villages_input_cost = costs
end

-- The least a cook asks for one of a dish (ticket 42): PROFIT times its inputs at what they
-- cost it and its fuel at its reference price for coal, by its cheapest recipe for it. Nil
-- with no input cost known (its coop's chicken, raised not bought).
function M.dish_floor(seller, item)
	local costs = seller._villages_input_cost
	if not costs then return nil end
	local best
	for _, recipe in ipairs(dish_recipes(seller, item)) do
		local cost, known = 0, true
		for _, input in ipairs(recipe.from) do
			local unit = costs[input[1]]
			if unit then cost = cost + unit * input[2] else known = false end
		end
		if known then
			local coal = prices.price(seller._villages_prices, COAL) or 0
			cost = cost + (recipe.fuel or 0) / SMELTS_PER_LUMP * coal
			local floor = PROFIT * cost / (recipe.count or 1)
			if not best or floor < best then best = floor end
		end
	end
	return best
end

function M.ask(seller, item, view)
	local reference = prices.price(seller._villages_prices, item)
	if not reference then return nil end
	local ask = reference * M.factor(seller, item)
	-- An alchemist's goods at no less than their cost (ticket 30), not its own value: its
	-- money raised that to four times what it believed a nugget worth.
	local cost = alchemist.ask_floor(seller, item)
	local own = view and not M.stock_in_trade(seller, item) and view.value(item)
	if cost then ask = math.max(ask, cost)
	elseif own then ask = math.max(ask, own) end
	local dish = M.dish_floor(seller, item)
	if dish then ask = math.max(ask, dish) end
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
-- A product whose sources it paid for (`conversion.cost`, the seller's field holding what
-- one source cost it on average: the cleric's rotten flesh, ticket 37b) never sells at a
-- loss or break even: at least M.cost_floor.
function M.converted(seller, conversion, view)
	local own = M.ask(seller, conversion.to, view)
	local source = M.ask(seller, conversion.from, view)
	local floor = M.cost_floor(seller, conversion)
	if not source then return floor and math.max(own or floor, floor) or own end
	local via = source / conversion.ratio
	local ask = own and math.min(own, via) or via
	return floor and math.max(ask, floor) or ask
end

-- The least one of a conversion's product sells for, from the average cost of its sources
-- (`seller[conversion.cost]`): PROFIT times what they cost, and at least an emerald over
-- it. Nil for a conversion with no cost, or sources that cost nothing.
function M.cost_floor(seller, conversion)
	local cost = conversion.cost and seller[conversion.cost]
	if not cost or cost <= 0 then return nil end
	local per = cost / conversion.ratio
	return math.max(per * PROFIT, per + 1)
end

-- Notes `count` sources bought for `paid` emeralds into the seller's average cost
-- (`seller[field]`), over the `held` it had before.
function M.note_cost(seller, field, held, count, paid)
	local before = seller[field] or 0
	held = math.max(held or 0, 0)
	seller[field] = (before * held + paid) / (held + count)
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
