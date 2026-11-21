-- Run with: lua tests/asks.lua
minetest = {get_modpath = function() return "." end}
local asks = dofile("asks.lua")
local function near(a, b) return math.abs(a - b) < 1e-9 end
local BEEF = "mcl_mobitems:beef"

-- A sale raises the ask; the first daily look only starts the clock.
local seller = {_villages_asks = {[BEEF] = 1.5}}
asks.sold(seller, BEEF, 1, 2)
assert(near(asks.factor(seller, BEEF), 1.5 * asks.MARKUP))
assert(asks.daily(seller, {[BEEF] = 28}, 1) and near(asks.factor(seller, BEEF), 1.5 * asks.MARKUP))
assert(not asks.daily(seller, {[BEEF] = 28}, 1), "once a day")

-- Selling a few of a big spare is selling slowly: the ask still falls (ColonyFood,
-- 2026-11-14: 2 beef sold now and then, 26 piling up, the ask near MAX).
asks.sold(seller, BEEF, 2, 2)
local before = asks.factor(seller, BEEF)
asks.daily(seller, {[BEEF] = 26}, 2)
assert(near(asks.factor(seller, BEEF), before * asks.MARKDOWN), "2 of 26 is under a quarter")

-- Selling a quarter or more of it holds the ask.
asks.sold(seller, BEEF, 3, 4)
asks.sold(seller, BEEF, 3, 3)
before = asks.factor(seller, BEEF)
asks.daily(seller, {[BEEF] = 20}, 3)
assert(near(asks.factor(seller, BEEF), before), "7 of 20 holds")

-- Counts start afresh each day: yesterday's sales do not hold today's ask.
asks.daily(seller, {[BEEF] = 20}, 4)
assert(near(asks.factor(seller, BEEF), before * asks.MARKDOWN))

-- Nothing sold at all: falls, down to MIN and no further.
local idle = {}
asks.daily(idle, {[BEEF] = 5}, 1)
for d = 2, 40 do asks.daily(idle, {[BEEF] = 5}, d) end
assert(near(asks.factor(idle, BEEF), asks.MIN))

-- A save from before counts were kept (a bare day) still counts as sold that day.
local old = {_villages_asks_day = 5, _villages_ask_sold = {[BEEF] = 5}, _villages_asks = {[BEEF] = 1.5}}
asks.daily(old, {[BEEF] = 30}, 6)
assert(near(asks.factor(old, BEEF), 1.5), "held, as before")
assert(old._villages_ask_sold[BEEF].count == 0)
asks.sold(old, BEEF, 6)
assert(old._villages_ask_sold[BEEF].count == 1, "one when no count is given")

-- It asks its reference price (prices.lua) times its factor, a belief over 1 too.
local ledger = dofile("ledger.lua")
local prices = dofile("prices.lua")
local glut = {_villages_asks = {[BEEF] = 1.8}, _villages_prices = {[BEEF] = 0.125}}
assert(near(asks.ask(glut, BEEF), ledger.price(BEEF) * 1.8 * 0.125))
glut._villages_prices[BEEF] = 4
assert(near(asks.ask(glut, BEEF), ledger.price(BEEF) * 1.8 * 4))
-- Never below its own value, given its view.
assert(near(asks.ask(glut, BEEF, {value = function() return 1e6 end}), 1e6))
-- A peddler still never asks below what it paid.
glut._villages_prices[BEEF] = 0.125
glut._villages_peddle = {item = BEEF, bid = 5}
assert(asks.ask(glut, BEEF) == 5)

-- A sale at a price: its reference price learns it, and the factor is pulled back toward 1
-- by the same share before the markup, so the rise is not counted twice.
local trader = {_villages_asks = {[BEEF] = 2}}
local base = ledger.price(BEEF)
asks.sold(trader, BEEF, 1, 1, 2 * base)
assert(near(prices.factor(trader._villages_prices, BEEF), 2 ^ prices.LEARN_TRADE))
assert(near(asks.factor(trader, BEEF), 2 ^ (1 - prices.LEARN_TRADE) * asks.MARKUP))
assert(near(asks.ask(trader, BEEF), base * 2 * asks.MARKUP), "the same ask, now mostly in the reference")

-- Short of money, an unsold good's ask falls twice as fast.
local broke, comfy = {}, {}
asks.daily(broke, {[BEEF] = 5}, 1, 10)
asks.daily(comfy, {[BEEF] = 5}, 1, 1000)
asks.daily(broke, {[BEEF] = 5}, 2, 10)
asks.daily(comfy, {[BEEF] = 5}, 2, 1000)
assert(near(asks.factor(broke, BEEF), asks.MARKDOWN ^ 2) and near(asks.factor(comfy, BEEF), asks.MARKDOWN))

-- A comfort is asked at no less than BID_SHARE of the best bid heard, a bid capped at its
-- bidder's emeralds (ticket 23d: barrels sold for 28 to buyers who valued them at 374).
local BARREL = "mcl_barrels:barrel_closed"
local maker = {_id = "maker", _villages_market_news = {
	{kind = "needs", item = BARREL, who = "rich", price = 374, budget = 1000, heard = 0, hops = 1},
	{kind = "needs", item = BARREL, who = "poor", price = 900, budget = 100, heard = 0, hops = 1},
	{kind = "needs", item = BEEF, who = "rich", price = 900, budget = 1000, heard = 0, hops = 1},
}}
assert(near(asks.best_bid(maker, BARREL, 0), 374), "the poor bidder's 900 counts as its 100")
assert(near(asks.ask(maker, BARREL), 374 * asks.BID_SHARE))
assert(near(asks.ask(maker, BEEF), ledger.price(BEEF)), "beef is no comfort: no floor")
-- The bid ages out with its news, and the ask falls back to the reference price.
assert(asks.best_bid(maker, BARREL, 1e6) == 0)
assert(near(asks.ask({_id = "maker"}, BARREL), ledger.price(BARREL)))
-- Flowers are told as their category: no floor.
local florist = {_id = "f", _villages_market_news = {
	{kind = "needs", item = "mcl_flowers:poppy", group = "flower", who = "rich", price = 90, heard = 0, hops = 1}}}
assert(asks.best_bid(florist, "mcl_flowers:poppy", 0) == 0)

-- The cleric's leather (ticket 37b): never at a loss or break even, from what its flesh cost
-- it on average: PROFIT over three flesh, and at least an emerald over.
do
	local goods = dofile("goods.lua")
	local LEATHER = "mcl_mobitems:leather"
	local conversion = goods.CONVERSIONS.cleric[1]
	local c = {_id = "cl", _profession = "cleric"}
	local book = dofile("cost_book.lua")
	local FLESH = "mcl_mobitems:rotten_flesh"
	assert(asks.cost_floor(c, conversion) == nil, "nothing paid, no floor")
	book.note(c, FLESH, 10, 20)
	assert(book.cost(c, FLESH) == 2, "its cost book's price for flesh (ticket 43a)")
	assert(asks.cost_floor(c, conversion) == 6 * asks.PROFIT)
	c._villages_input_cost[FLESH] = 0.2
	assert(asks.cost_floor(c, conversion) == 0.6 + 1, "at least an emerald over")
	c._villages_input_cost[FLESH] = 2
	-- A flesh ask fallen to a quarter cannot drag leather below the floor.
	c._villages_asks = {["mcl_mobitems:rotten_flesh"] = asks.MIN}
	assert(asks.converted(c, conversion) >= 6 * asks.PROFIT)
	assert(asks.converted(c, conversion) >= asks.cost_floor(c, conversion))
	-- Without the cost field (the alchemist's), as before.
	local plain = {ratio = 1 / 3, from = "mcl_mobitems:rotten_flesh", to = LEATHER, takes = 3}
	assert(asks.converted(c, plain) < 6)
end

-- Ticket 40a: food its trade makes is stock in trade, asked with no floor at its own value.
-- A rich leatherworker valued its spare beef at 4.62 and asked that, eleven times its 0.42.
do
	local view = {value = function() return 50 end}
	local tanner = {_profession = "leatherworker", _villages_asks = {[BEEF] = 0.5}}
	assert(asks.stock_in_trade(tanner, BEEF) and not asks.stock_in_trade(tanner, "mcl_mobitems:leather"))
	local ledger = dofile("ledger.lua")
	assert(near(asks.ask(tanner, BEEF, view), ledger.price(BEEF) * 0.5), "its beef by supply")
	assert(asks.ask(tanner, "mcl_mobitems:leather", view) == 50, "its leather, no food, at its value")
	-- Food it does not make keeps the floor: the fisherman's beef.
	local fisher = {_profession = "fisherman", _villages_asks = {[BEEF] = 0.5}}
	assert(not asks.stock_in_trade(fisher, BEEF) and asks.ask(fisher, BEEF, view) == 50)
	assert(asks.stock_in_trade({_profession = "butcher"}, "mcl_mobitems:cooked_beef"))
end

-- Ticket 42: a cook's dish is asked at no less than PROFIT times what its raw inputs cost
-- it. The butcher sold 3 cooked salmon for an emerald, from fish it paid 0.25 each for.
do
	local ledger = dofile("ledger.lua")
	local BEEF_COOKED = "mcl_mobitems:cooked_beef"
	local butch = {_profession = "butcher", _villages_asks = {[BEEF_COOKED] = 0.25}, _villages_prices = {}}
	assert(asks.dish_floor(butch, BEEF_COOKED) == nil, "no cost known")
	local book = dofile("cost_book.lua")
	book.note(butch, "mcl_core:cobble", 4, 4)
	assert(butch._villages_input_cost == nil, "not an input of its dishes")
	book.note(butch, BEEF, 10, 20)
	assert(near(butch._villages_input_cost[BEEF], 2))
	book.note(butch, BEEF, 8, 0)
	assert(near(butch._villages_input_cost[BEEF], (2 * 8 + 0) / 16), "an average over about 8")
	butch._villages_input_cost[BEEF] = 2
	local coal = ledger.price("mcl_core:coal_lump")
	local floor = asks.PROFIT * (2 + coal / 8)
	assert(near(asks.dish_floor(butch, BEEF_COOKED), floor))
	assert(near(asks.ask(butch, BEEF_COOKED), math.max(ledger.price(BEEF_COOKED) * 0.25, floor)))
	assert(asks.ask(butch, BEEF_COOKED) >= floor)
	-- Never the keeper's, which cooks only as a last resort.
	local kip = {_profession = "butcher", _villages_keeper = true, _villages_input_cost = {[BEEF] = 2}}
	assert(asks.dish_floor(kip, BEEF_COOKED) == nil)
end

print("asks.lua: ok")
