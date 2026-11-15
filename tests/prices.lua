-- Run with: lua tests/prices.lua
minetest = {get_modpath = function() return "." end}
local prices = dofile("prices.lua")
local ledger = dofile("ledger.lua")
local function near(a, b) return math.abs(a - b) < 1e-9 end
local APPLE, FISH, WOOL = "mcl_core:apple", "mcl_fishing:salmon_raw", "mcl_wool:white"

-- Demand and supply from news heard and its own view; emeralds are no good.
local heard = {
	{kind = "needs", item = APPLE, count = 4, who = "a"},
	{kind = "needs", item = APPLE, count = 3, who = "b"},
	{kind = "has", item = FISH, count = 8, who = "c"},
	{kind = "has", item = "mcl_core:emerald", count = 9, who = "d"},
}
local view = {needs = {[APPLE] = 1}, surplus = {[FISH] = 8, [WOOL] = 2}}
local balance = prices.balance(heard, view)
-- Apples are food (ticket 15): counted in points, 3 an apple, and shared by every food.
assert(balance[APPLE].demand == 24 and balance[APPLE].supply == 0)
assert(balance["mcl_farming:bread"] == balance[APPLE], "one entry for every food")
assert(balance[FISH].supply == 16 and balance[FISH].demand == 0)
assert(balance["mcl_core:emerald"] == nil)

-- A need counts only as far as its villager can pay at its own value: heard needs carry
-- the needer's emeralds, its own are held to its own (ColonyFood, 2026-11-14: bread at
-- eight times its price on the wants of villagers with an emerald each).
local BREAD = "mcl_farming:bread"
local poor = prices.balance({
	{kind = "needs", item = WOOL, count = 4, price = 10, budget = 20, who = "a"},
	{kind = "needs", item = WOOL, count = 4, price = 10, who = "b"},
	{kind = "needs", item = WOOL, count = 4, price = 10, budget = 0, who = "c"},
}, {needs = {[WOOL] = 3}, value = function() return 10 end}, {budget = 15})
assert(near(poor[WOOL].demand, 2 + 4 + 0 + 1.5), poor[WOOL].demand)
-- A category's shortfall, at the cheapest member per unit: bread, 4 points at 40.
local hungry = prices.balance({}, {
	needs = {[BREAD] = 2, [APPLE] = 4}, group = {[BREAD] = "food", [APPLE] = "food"},
	categories = {food = {target = 10, held = 0, short = 10}},
	value = function(item) return item == BREAD and 40 or 60 end,
}, {budget = 20})
assert(near(hungry[BREAD].demand, 2), "20 emeralds buy 2 points at 10 each, not 10")
-- What it can sell from elsewhere (a farmer's chest) is supply.
local stocked = prices.balance({}, {}, {stock = {[WOOL] = 30}})
assert(stocked[WOOL].supply == 30 and stocked[WOOL].demand == 0)

local FOOD = "group:food"
assert(prices.key(APPLE) == FOOD and prices.key(BREAD) == FOOD and prices.key(FISH) == FISH)
assert(prices.key("mcl_core:cobble") == "group:stone" and prices.key("mcl_core:birchtree") == "group:log")

-- A day's imbalance: wanted and unmet rises, offered and unwanted falls, by at most
-- IMBALANCE_DAY a day, on the keys.
local day1 = prices.drift(nil, balance)
assert(near(day1[FOOD], prices.IMBALANCE_DAY ^ (24 / 28)), day1[FOOD])
assert(day1[APPLE] == nil, "apples are kept under food")
assert(near(day1[FISH], prices.IMBALANCE_DAY ^ (-16 / 20)), day1[FISH])
-- No pull back toward the base price: with no evidence a price stays where it is.
local kept = prices.drift({[FOOD] = 2}, {})
assert(near(kept[FOOD], 2))
-- Counts alone take it no further than COUNT_SPAN either way...
local beliefs
for _ = 1, 400 do beliefs = prices.drift(beliefs, balance) end
assert(near(beliefs[FOOD], prices.COUNT_SPAN) and near(beliefs[FISH], 1 / prices.COUNT_SPAN))
-- ...nor pull back one that trades took further.
beliefs = prices.drift({[FOOD] = 10, [FISH] = 0.1}, balance)
assert(near(beliefs[FOOD], 10) and near(beliefs[FISH], 0.1))
-- The rails: trades within 1 / SPAN and SPAN.
local railed = {}
for _ = 1, 100 do prices.learn(railed, FISH, ledger.price(FISH) * 1000) end
assert(near(prices.factor(railed._villages_prices, FISH), prices.MAX))

-- A trade: LEARN_TRADE of the way, in log space, to the price paid. A category's members
-- move together, so bread learnt is apples learnt.
local trader = {}
prices.learn(trader, BREAD, 4 * ledger.price(BREAD))
assert(near(prices.factor(trader._villages_prices, BREAD), 4 ^ prices.LEARN_TRADE))
assert(near(prices.price(trader._villages_prices, APPLE), ledger.price(APPLE) * 4 ^ prices.LEARN_TRADE))
prices.learn(trader, "mcl_core:emerald", 5)
assert(trader._villages_prices["mcl_core:emerald"] == nil, "an emerald is an emerald")

-- Heard asks and bids: toward their weighted geometric mean, by LEARN_NEWS at most, the
-- nearer (fewer hops) weighing more.
local heard_prices = {
	{kind = "has", item = FISH, ref = 2 * ledger.price(FISH), hops = 0},
	{kind = "needs", item = FISH, ref = 8 * ledger.price(FISH), price = 1000, hops = 1},
}
local after_news = prices.hear(nil, heard_prices)
local target = math.exp((1 * math.log(2) + 0.5 * math.log(8)) / 1.5)
assert(near(after_news[FISH], target ^ prices.LEARN_NEWS), after_news[FISH])
-- One far-off report moves it less.
local faint = prices.hear(nil, {{kind = "has", item = FISH, ref = 4 * ledger.price(FISH), hops = 3}})
-- An entry's price (a need's value) is not learnt from, nor news from before refs were told.
assert(prices.hear(nil, {{kind = "needs", item = FISH, price = 50 * ledger.price(FISH), hops = 0}}) == nil)
assert(near(faint[FISH], 4 ^ (prices.LEARN_NEWS / 4)))

-- Once a day: the imbalance, the heard prices and the buys it passed up.
local villager = {}
assert(prices.daily(villager, heard, view, 7) and prices.factor(villager._villages_prices, APPLE) > 1)
local after = prices.factor(villager._villages_prices, APPLE)
assert(not prices.daily(villager, heard, view, 7) and prices.factor(villager._villages_prices, APPLE) == after)
assert(prices.daily(villager, heard, view, 8) and prices.factor(villager._villages_prices, APPLE) > after)
-- A buy passed up pulls it LEARN_MISS of the way up to the dearest ask, at the day's move.
local looker = {}
prices.missed(looker, FISH, 3 * ledger.price(FISH))
prices.missed(looker, FISH, 9 * ledger.price(FISH))
prices.missed(looker, FISH, 5 * ledger.price(FISH))
prices.daily(looker, {}, {}, 1)
assert(near(prices.factor(looker._villages_prices, FISH), 9 ^ prices.LEARN_MISS))
assert(looker._villages_prices_missed == nil, "used up")

-- Saves from before 21b: a category's members are folded into its key, at their mean.
local old = prices.migrate({[APPLE] = 4, [BREAD] = 1, [FISH] = 0.5})
assert(near(old[FOOD], 2) and old[APPLE] == nil and near(old[FISH], 0.5))
assert(near(prices.factor({[APPLE] = 3}, APPLE), 3), "read as they are until the day's move")

-- At most KEEP keys, those furthest from 1.
local many = {}
for i = 1, prices.KEEP + 10 do many["test:item" .. i] = 1 + i / 100 end
local trimmed = prices.drift(many, {})
local n = 0
for _ in pairs(trimmed) do n = n + 1 end
assert(n == prices.KEEP and trimmed["test:item" .. (prices.KEEP + 10)] and not trimmed["test:item1"])

-- In a conversation, prices move SHARE of the way to the members' geometric mean; one
-- with no belief counts as 1.
local shared = prices.share({{[FOOD] = 4}, nil}, 2)
assert(near(shared[1][FOOD], math.exp(math.log(4) * (1 - prices.SHARE / 2))))
assert(near(shared[2][FOOD], math.exp(math.log(4) * prices.SHARE / 2)))
assert(shared[1][FOOD] > shared[2][FOOD], "still disagreeing")
local none = prices.share({nil, nil}, 2)
assert(none[1] == nil and none[2] == nil)

-- The ledger values an item at its reference price times urgency: a category's factor
-- for its members, an item's own otherwise.
local input = {id = "x", profession = "farmer", held = {[APPLE] = 0}}
local plain = ledger.assess(input).value(APPLE)
input.prices = {[FOOD] = 3}
assert(near(ledger.assess(input).value(APPLE), plain * 3))
input.prices = {[APPLE] = 3}
assert(near(ledger.assess(input).value(APPLE), plain * 3), "an old save's item factor")
assert(ledger.assess(input).value("mcl_core:emerald") == 1, "an emerald is an emerald")

assert(prices.describe({[APPLE] = 2.3, [FISH] = 0.4, [FOOD] = 1.1}, 2) == "salmon_raw x0.4, apple x2.3", "furthest from 1 first")
assert(prices.describe(nil) == "base prices")
print("prices.lua: ok")
