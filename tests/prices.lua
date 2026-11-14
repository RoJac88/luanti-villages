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

-- A day: wanted and unmet rises, offered and unwanted falls, toward the full rate as
-- the counts outgrow DAMP.
local day1 = prices.drift(nil, balance)
assert(near(day1[APPLE], prices.RATE_DAY ^ (24 / 28)), day1[APPLE])
assert(near(day1["mcl_farming:bread"], day1[APPLE]), "bread dears with apples")
assert(near(day1[FISH], prices.RATE_DAY ^ (-16 / 20)), day1[FISH])
assert(day1[WOOL] < 1 and day1[WOOL] > day1[FISH], "two spare move it less than sixteen")
-- Day after day it reaches the bounds and stays there.
local beliefs = day1
for _ = 1, 20 do beliefs = prices.drift(beliefs, balance) end
assert(near(beliefs[APPLE], prices.MAX) and near(beliefs[FISH], prices.MIN))
-- Balanced: no move. Heard of no more: back toward 1, and dropped once there.
local even = prices.drift({[APPLE] = 2}, {[APPLE] = {demand = 5, supply = 5}})
assert(near(even[APPLE], 2))
local forgot = prices.drift({[APPLE] = 2}, {})
assert(near(forgot[APPLE], 2 ^ prices.FORGET))
for _ = 1, 40 do forgot = prices.drift(forgot, {}) end
assert(forgot == nil, "back to base prices")

-- Once a day only.
local villager = {}
assert(prices.daily(villager, heard, view, 7) and villager._villages_prices[APPLE] > 1)
local after = villager._villages_prices[APPLE]
assert(not prices.daily(villager, heard, view, 7) and villager._villages_prices[APPLE] == after)
assert(prices.daily(villager, heard, view, 8) and villager._villages_prices[APPLE] > after)

-- In a conversation, prices move SHARE of the way to the members' geometric mean; one
-- with no belief counts as 1.
local shared = prices.share({{[APPLE] = 4}, nil}, 2)
assert(near(shared[1][APPLE], math.exp(math.log(4) * (1 - prices.SHARE / 2))))
assert(near(shared[2][APPLE], math.exp(math.log(4) * prices.SHARE / 2)))
assert(shared[1][APPLE] > shared[2][APPLE], "still disagreeing")
local none = prices.share({nil, nil}, 2)
assert(none[1] == nil and none[2] == nil)

-- The ledger values an item at base price times the multiplier times urgency.
local input = {id = "x", profession = "farmer", held = {[APPLE] = 0}}
local plain = ledger.assess(input).value(APPLE)
input.prices = {[APPLE] = 3}
assert(near(ledger.assess(input).value(APPLE), plain * 3))
assert(ledger.assess(input).value("mcl_core:emerald") == 1, "an emerald is an emerald")

assert(prices.describe({[APPLE] = 2.3, [FISH] = 0.4, [WOOL] = 1.1}, 2) == "salmon_raw x0.4, apple x2.3", "furthest from 1 first")
assert(prices.describe(nil) == "base prices")
print("prices.lua: ok")
