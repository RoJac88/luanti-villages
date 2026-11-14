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

-- A seller that believes an item worth less than its base price asks that much less:
-- beef heard of in glut at an eighth of its price is not asked for at near twice it.
local ledger = dofile("ledger.lua")
local glut = {_villages_asks = {[BEEF] = 1.8}, _villages_prices = {[BEEF] = 0.125}}
assert(near(asks.ask(glut, BEEF), ledger.price(BEEF) * 1.8 * 0.125))
-- A belief over 1 leaves the ask to its sales.
glut._villages_prices[BEEF] = 4
assert(near(asks.ask(glut, BEEF), ledger.price(BEEF) * 1.8))
-- A peddler still never asks below what it paid.
glut._villages_prices[BEEF] = 0.125
glut._villages_peddle = {item = BEEF, bid = 5}
assert(asks.ask(glut, BEEF) == 5)

print("asks.lua: ok")
