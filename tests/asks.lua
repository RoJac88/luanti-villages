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
-- Never below its value with no money in it, for one it wants and holds no spare of (ticket
-- 43b); spare, or one it does not want, has no use value to it.
local function wanting(spare, target)
	return {real = function() return 1e6 end, value = function() return 1e9 end,
		surplus = {[BEEF] = spare}, targets = {[BEEF] = target}}
end
assert(near(asks.ask(glut, BEEF, wanting(nil, 10)), 1e6), "its real value, not the money-scaled one")
assert(near(asks.ask(glut, BEEF, wanting(5, 10)), ledger.price(BEEF) * 1.8 * 4), "spare")
assert(near(asks.ask(glut, BEEF, wanting(nil, 0)), ledger.price(BEEF) * 1.8 * 4), "not wanted")
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

-- The cleric's leather (ticket 37b): never at a loss, from what its flesh cost it: PROFIT
-- over three flesh (ticket 43b: no longer an emerald over too).
do
	local goods = dofile("goods.lua")
	local book = dofile("cost_book.lua")
	local FLESH, LEATHER = "mcl_mobitems:rotten_flesh", "mcl_mobitems:leather"
	local conversion = goods.CONVERSIONS.cleric[1]
	local c = {_id = "cl", _profession = "cleric"}
	local unpaid = asks.reservation(c, LEATHER)
	assert(near(unpaid, 3 * ledger.price(FLESH) * asks.GATHER_SHARE * asks.PROFIT), "flesh never bought: gathered")
	book.note(c, FLESH, 10, 20)
	assert(near(asks.reservation(c, LEATHER), 6 * asks.PROFIT))
	-- A flesh ask fallen to a quarter cannot drag leather below it.
	c._villages_asks = {[FLESH] = asks.MIN}
	assert(asks.converted(c, conversion) >= 6 * asks.PROFIT - 1e-9)
	-- Flesh itself, bought, sells at no less than it cost.
	assert(asks.ask(c, FLESH) >= 2 - 1e-9)
end

-- Ticket 43b: the reservation price. Grown, gathered or raised: GATHER_SHARE of base, fixed,
-- whatever its wealth; a rich leatherworker's spare beef no longer at its money-scaled value.
do
	local view = {value = function() return 50 end, real = function() return 50 end,
		surplus = {[BEEF] = 290}, targets = {}}
	local tanner = {_profession = "leatherworker", _villages_asks = {[BEEF] = 0.25}, _villages_prices = {[BEEF] = 1 / 64}}
	assert(near(asks.reservation(tanner, BEEF, view), ledger.price(BEEF) * asks.GATHER_SHARE))
	assert(near(asks.ask(tanner, BEEF, view), ledger.price(BEEF) * asks.GATHER_SHARE), "the spiral stops at the floor")
	tanner._villages_prices[BEEF] = 1
	assert(near(asks.ask(tanner, BEEF, view), ledger.price(BEEF) * 0.25), "over the floor, by supply")
	-- An item with no base price has none.
	assert(asks.reservation(tanner, "no:price") == nil)
end

-- Made goods: PROFIT times inputs at what they cost (bought) or GATHER_SHARE of base (its own),
-- and fuel at the reference price for coal, never under GATHER_SHARE of coal's base. The
-- butcher sold cooked beef from its own herd at 0.25 while raw beef was asked at 0.34.
do
	local book = dofile("cost_book.lua")
	local BEEF_COOKED = "mcl_mobitems:cooked_beef"
	local COAL = "mcl_core:coal_lump"
	local butch = {_profession = "butcher", _villages_asks = {[BEEF_COOKED] = 0.25},
		_villages_prices = {[BEEF_COOKED] = 1 / 64, [COAL] = 1 / 64}}
	local coal = ledger.price(COAL) * asks.GATHER_SHARE
	assert(near(asks.fuel_cost(butch), coal), "coal's reference fell under the floor")
	local own = asks.PROFIT * (ledger.price(BEEF) * asks.GATHER_SHARE + coal / 8)
	assert(near(asks.reservation(butch, BEEF_COOKED), own), "from its own herd")
	assert(asks.reservation(butch, BEEF_COOKED) > ledger.price(BEEF) * asks.GATHER_SHARE, "over raw beef's")
	book.note(butch, BEEF, 10, 20)
	local bought = asks.PROFIT * (2 + coal / 8)
	assert(near(asks.reservation(butch, BEEF_COOKED), bought), "from beef it paid 2 for")
	assert(near(asks.ask(butch, BEEF_COOKED), bought))
	assert(near(asks.reservation(butch, BEEF), 2), "raw beef it bought: what it paid, no profit")
	-- A keeper's dish, bought to sell on: what it paid.
	local kip = {_villages_keeper = true}
	book.note(kip, BEEF_COOKED, 2, 3)
	assert(near(asks.reservation(kip, BEEF_COOKED), 1.5))
	-- A conversion of its own: the woodcutter's planks from its own logs, four to one.
	local wood = {_profession = "woodcutter"}
	local planks = dofile("goods.lua").SPECIES["mcl_core:tree"]
	assert(near(asks.reservation(wood, planks), asks.PROFIT * ledger.price("mcl_core:tree") * asks.GATHER_SHARE / 4))
end

-- Ticket 43c: the markdown stops at the replacement cost, a factor under it is lifted there,
-- and a sale under it teaches the floor, not the price paid.
do
	-- (Paper: a log's reference is kept under its category, group:log.)
	local LOG = "mcl_core:paper"
	local floor = ledger.price(LOG) * asks.GATHER_SHARE
	local cutter = {_villages_prices = {[LOG] = 1 / 64}, _villages_asks = {[LOG] = asks.MIN}}
	asks.daily(cutter, {[LOG] = 40}, 1)
	asks.daily(cutter, {[LOG] = 40}, 2)
	assert(near(asks.factor(cutter, LOG), floor / (ledger.price(LOG) / 64)), "lifted to the floor")
	assert(near(asks.ask(cutter, LOG), floor))
	for d = 3, 30 do asks.daily(cutter, {[LOG] = 40}, d) end
	assert(near(asks.ask(cutter, LOG), floor), "unsold for weeks, still the floor")
	-- Over the floor it falls as before.
	local high = {_villages_prices = {[LOG] = 1}}
	asks.daily(high, {[LOG] = 40}, 1)
	asks.daily(high, {[LOG] = 40}, 2)
	assert(near(asks.factor(high, LOG), asks.MARKDOWN))
	-- A sale under the floor: the reference learns the floor.
	local seller = {_villages_prices = {[LOG] = 0.01}}
	asks.sold(seller, LOG, 1, 3, floor / 3)
	local learnt = prices.price(seller._villages_prices, LOG)
	assert(learnt > ledger.price(LOG) * 0.01 and learnt <= floor + 1e-9, learnt)
	local same = {_villages_prices = {[LOG] = 0.01}}
	asks.sold(same, LOG, 1, 1, floor)
	assert(near(prices.price(same._villages_prices, LOG), learnt), "as if sold at the floor")
end

-- Ticket 43d: its asks over their floors, largest spare first.
do
	local PAPER = "mcl_core:paper"
	local view = {surplus = {[BEEF] = 30, [PAPER] = 5}, targets = {}, real = function() return 0 end}
	local seller = {_villages_prices = {[BEEF] = 1 / 64}}
	local line = asks.describe(seller, view)
	assert(line:find("^30 beef ") and line:find("at floor, gathered") and line:find("5 paper "), line)
	assert(line:find("floor %d"), "paper over its floor: " .. line)
	assert(asks.describe(seller, {surplus = {}}) == "none spare")
end

print("asks.lua: ok")
