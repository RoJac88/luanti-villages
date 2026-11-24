-- Run with: lua tests/alchemist_trade.lua
-- The alchemist's trade (ticket 20c): what it makes at its stand and how fast, what it
-- buys and at what most, and what it sells by conversion.
local now, day, time = 1000, 5, 9000 / 24000
local settings = {}
local logs = {}

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
}

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	get_day_count = function() return day end,
	get_timeofday = function() return time end,
	get_item_group = function() return 0 end,
	registered_nodes = {},
	registered_items = {},
	settings = {
		get = function(_, name) return settings[name] end,
		get_bool = function(_, name, default)
			if settings[name] == nil then return default end
			return settings[name]
		end,
	},
	log = function(_, message) logs[#logs + 1] = message end,
	pos_to_string = function(p) return "(" .. p.x .. "," .. p.y .. "," .. p.z .. ")" end,
	get_objects_inside_radius = function() return {} end,
	add_particle = function() end,
	sound_play = function() end,
}

local production = dofile("production.lua")
local possessions = dofile("possessions.lua")
local ledger = dofile("ledger.lua")
local exchange = dofile("exchange.lua")
local asks = dofile("asks.lua")
local goods = dofile("goods.lua")
local alchemist = dofile("alchemist.lua")
local recipes = dofile("recipes.lua")
local news = dofile("market_news.lua")

local NUGGET, INGOT = "mcl_core:iron_nugget", "mcl_core:iron_ingot"
local GOLD_NUGGET = "mcl_core:gold_nugget"
local FLINT, GLASS, PANE = "mcl_core:flint", "mcl_core:glass", "xpanes:pane_natural_flat"
local STONE, COBBLE, LOG = "mcl_core:stone", "mcl_core:cobble", "mcl_core:tree"
local EMERALD = "mcl_core:emerald"
local CHARCOAL = "mcl_core:charcoal_lump"
local function near(a, b) return math.abs(a - b) < 1e-6 end

local function villager(id, held, fields)
	local pos = {x = 0, y = 1, z = 0}
	local v = {_id = id, _profession = "nitwit", _villages_food = 12, _villages_belongings = held or {},
		object = {get_pos = function() return pos end}}
	for k, value in pairs(fields or {}) do v[k] = value end
	return v
end
local function alchemist_with(held)
	return villager("alch", held, {_profession = "cleric", _villages_alchemist = true,
		_jobsite = {x = 1, y = 1, z = 0}})
end
local function count(v, item) return possessions.count(v, item) end

-- recipes.lua's stops match alchemist.lua's keeps.
local by_makes = {}
for _, recipe in ipairs(recipes.alchemist) do by_makes[recipe.makes] = recipe end
assert(by_makes[GLASS].upto == alchemist.GLASS_KEEP + 1 and by_makes[FLINT].upto == alchemist.FLINT_KEEP)
assert(by_makes[NUGGET].upto == alchemist.NUGGET_KEEP, "nuggets stop at 192 (ticket 30)")
assert(alchemist.NUGGET_KEEP >= alchemist.GOLD_RESERVE + 162, "room for a gold ingot")

-- Its working day is 10500 ticks, 525 s at time_speed 72: a nugget a 36th of it (ticket 30:
-- twice the eighteenth it was).
local alch = alchemist_with()
assert(production.recipes(alch) == production.RECIPES.alchemist)
assert(near(production.cost(alch, by_makes[NUGGET]), 525 / 36))
assert(near(production.cost(alch, by_makes[FLINT]), 525 / 12))
assert(near(production.cost(alch, by_makes[GLASS]), 525 / 72))
settings.time_speed = "144"
assert(near(production.cost(alch, by_makes[NUGGET]), 525 / 72), "a faster clock, a shorter day")
settings.time_speed = nil
-- A crafter's own cost is unchanged.
assert(production.cost(alch, recipes.tool_smith[1]) == production.craft_seconds())

-- With nothing to make it waits at its stand: it never labours.
assert(production.choose(alch) == nil and production.idle_today(alch) == false)

-- A whole day on cobble: 36 nuggets from 36 (E12c: one each), burning half a lump each (ticket 28c).
local miner = alchemist_with({[COBBLE] = 36, [CHARCOAL] = 18})
for _ = 1, 36 do production.work(miner, 525 / 36) end
assert(count(miner, NUGGET) == 36 and count(miner, COBBLE) == 0, count(miner, NUGGET))
assert(count(miner, CHARCOAL) == 0, "eighteen lumps burned")
-- Without fuel it makes nothing.
assert(production.choose(alchemist_with({[COBBLE] = 8})) == nil, "no fuel")
assert(logs[#logs]:find("made 1 mcl_core:iron_nugget", 1, true))
-- Stone and cobble both serve, the one held most first.
local mixed = alchemist_with({[COBBLE] = 3, [STONE] = 1, [CHARCOAL] = 1})
assert(production.choose(mixed).makes == NUGGET and production.make(mixed, by_makes[NUGGET]))
assert(count(mixed, COBBLE) == 2 and count(mixed, STONE) == 1 and count(mixed, NUGGET) == 1)

-- A whole day on logs: 6 flint from 24, any species, charcoal its fuel (ticket 28c).
local cutter = alchemist_with({[LOG] = 12, ["mcl_core:birchtree"] = 12, [CHARCOAL] = 3})
for _ = 1, 6 do production.work(cutter, 525 / 6) end
assert(count(cutter, FLINT) == 6 and count(cutter, LOG) + count(cutter, "mcl_core:birchtree") == 0)
assert(count(cutter, CHARCOAL) == 0)
-- With no charcoal or coal it burns logs: 4 for a flint and 4 smelts' worth (3 logs).
local no_coal = alchemist_with({[LOG] = 7})
assert(production.choose(no_coal).makes == FLINT and production.make(no_coal, by_makes[FLINT]))
assert(count(no_coal, FLINT) == 1 and count(no_coal, LOG) == 0, count(no_coal, LOG))

-- It makes what pays most (ticket 21d). At their seed prices glass and flint sell for
-- what their stone and logs would, so nuggets, which earn over their cobble, come first.
local busy = alchemist_with({[STONE] = 40, [LOG] = 8, [CHARCOAL] = 10})
assert(production.choose(busy).makes == NUGGET)
assert(production.status(busy):find("making iron_nugget", 1, true))
-- Once nuggets glut and their ask falls below their stone, glass and flint tie at no gain
-- and go by rank: glass while it holds 12 or fewer, then flint under 32, then nothing.
busy._villages_asks = {[NUGGET] = 0.25}
assert(production.choose(busy).makes == GLASS)
possessions.add(busy, GLASS, 13)
assert(production.choose(busy).makes == FLINT, "past 12 glass")
possessions.add(busy, FLINT, 32)
-- At 32 flint it still makes nuggets, at a loss: it works its stand and spends its budget
-- on stone (ticket 28).
assert(production.choose(busy).makes == NUGGET, "at 32 flint, nuggets at a loss")
-- Flint that sells dear beats glass at its seed price.
local keen = alchemist_with({[STONE] = 40, [LOG] = 8, [CHARCOAL] = 10})
keen._villages_asks = {[FLINT] = 2}
assert(production.choose(keen).makes == FLINT)

-- What it buys: a day's 36 stone or cobble and 16 lumps' worth of fuel always, and logs for
-- the flint it is short of, four a flint, at most 48 at once (ticket 30's pace), once it
-- holds IRON_FIRST of iron (E12d): before that, logs only as fuel.
local INGOT_ITEM = "mcl_core:iron_ingot"
local view = possessions.assess(alchemist_with({[EMERALD] = 1000}))
assert(view.categories.stone.target == alchemist.STONE_WANT and view.categories.log == nil, "iron first")
assert(view.needs[LOG] == math.ceil(alchemist.FUEL_WANT * 80 / 15), "logs only as fuel")
assert(alchemist.iron_held({[NUGGET] = 9, [INGOT_ITEM] = 3}) == 36, "an ingot is nine")
view = possessions.assess(alchemist_with({[EMERALD] = 1000, [NUGGET] = alchemist.IRON_FIRST - 9, [INGOT_ITEM] = 1}))
assert(view.categories.log.target == 48, "four ingots' worth, one an ingot")
view = possessions.assess(alchemist_with({[EMERALD] = 1000, [NUGGET] = alchemist.IRON_FIRST}))
assert(view.categories.stone.target == alchemist.STONE_WANT and view.categories.log.target == 48)
assert(view.categories.fuel.target == alchemist.FUEL_WANT * 80)
assert(view.needs[COBBLE] == alchemist.STONE_WANT and view.needs[STONE] == alchemist.STONE_WANT and view.needs[LOG] == 48)
view = possessions.assess(alchemist_with({[EMERALD] = 1000, [FLINT] = 30, [NUGGET] = alchemist.IRON_FIRST}))
assert(view.categories.log.target == 8)
view = possessions.assess(alchemist_with({[EMERALD] = 1000, [FLINT] = 32, [NUGGET] = alchemist.IRON_FIRST}))
assert(view.categories.log == nil, "no logs for flint at 32 flint")
assert(view.needs[LOG] == math.ceil(alchemist.FUEL_WANT * 80 / 15), "logs only as fuel")
-- It values an input at no more than its best recipe returns for it (ticket 21d), less the
-- fuel (ticket 28c): stone and cobble at a nugget's over its half lump; short, it pays its price.
local caps = ledger.imputed(recipes.alchemist, ledger.price, 5)
assert(near(caps[STONE], ledger.price(NUGGET) - ledger.price("mcl_core:coal_lump") / 2), "one stone a nugget (E12c)")
assert(near(caps[COBBLE], caps[STONE]))
assert(view.value(COBBLE) <= caps[COBBLE] + 1e-9 and view.value(STONE) <= caps[STONE] + 1e-9)
assert(near(view.value(STONE), ledger.price(STONE)), "short, so at its price")
local rich = possessions.assess(alchemist_with({[NUGGET] = 500, [GLASS] = 100}))
assert(rich.surplus[NUGGET] == 500, "every nugget is spare")

-- Its goods are asked at no less than their cost and its margin (ticket 30): stock from
-- before its book at its reference price then, kept, so a dearer reference later does not
-- raise it; an ingot at nine nuggets'.
local seller = alchemist_with({[NUGGET] = 50})
seller._villages_asks = {[INGOT] = 0.5, [NUGGET] = 0.5}
assert(near(asks.ask(seller, NUGGET), ledger.price(NUGGET) * alchemist.MARGIN))
assert(near(seller._villages_made_cost[NUGGET], ledger.price(NUGGET)), "entered once")
assert(near(asks.ask(seller, INGOT), 9 * ledger.price(NUGGET) * alchemist.MARGIN))
seller._villages_prices = {[NUGGET] = 2} -- a factor on its base price (prices.lua)
assert(near(asks.ask(seller, NUGGET), ledger.price(NUGGET) * alchemist.MARGIN), "its cost stays where it was entered")
-- Not its own value: rich, it asks no more for that.
local wealthy = alchemist_with({[NUGGET] = 50, [EMERALD] = 5000})
wealthy._villages_made_cost = {[NUGGET] = 0.5}
wealthy._villages_asks = {[NUGGET] = asks.MIN}
local wealthy_ask = asks.ask(wealthy, NUGGET, possessions.assess(wealthy))
assert(near(wealthy_ask, math.max(0.5 * alchemist.MARGIN, ledger.price(NUGGET) * asks.MIN)), wealthy_ask)

-- It sells an armorer ingots from nine nuggets each, at no less than their cost.
local armorer = villager("armo", {[EMERALD] = 2000}, {_profession = "armorer", _max_trade_tier = 1})
local smith = alchemist_with({[NUGGET] = 50})
local trade = exchange.offer(smith, possessions.assess(smith), armorer, possessions.assess(armorer))
assert(trade and trade.item == INGOT and trade.from == NUGGET and trade.from_count == trade.count * 9, trade and trade.item)
assert(trade.pay >= trade.count * ledger.price(INGOT) - 1)
assert(exchange.settle(trade))
assert(count(smith, NUGGET) == 50 - 9 * trade.count and count(armorer, INGOT) == trade.count)
assert(count(smith, EMERALD) == trade.pay)

-- An ingot is never dearer than nine nuggets (ticket 15; ColonyFood, 2026-11-15): its nugget
-- ask fell while it held them unsold, its ingot ask stayed at the seed (115), and an armorer
-- with 46 emeralds could buy none. Now it pays nine nuggets' ask, and the sale counts as
-- sold nuggets too, so their ask stops falling.
do
	-- Nuggets made cheap (ticket 30: no ask under their cost).
	local broke = alchemist_with({[NUGGET] = 19})
	broke._villages_made_cost = {[NUGGET] = 0.5}
	broke._villages_asks = {[NUGGET] = asks.MIN}
	local bview = possessions.assess(broke)
	local per_nugget = asks.ask(broke, NUGGET, bview)
	assert(near(asks.ask(broke, INGOT, bview), ledger.price(INGOT)), "the ingot's own ask is the seed")
	local by_nuggets = {from = NUGGET, to = INGOT, ratio = 1 / 9}
	assert(near(asks.converted(broke, by_nuggets, bview), 9 * per_nugget))
	local poor_armorer = villager("armo2", {[EMERALD] = 46}, {_profession = "armorer", _max_trade_tier = 1})
	local sale = exchange.offer(broke, bview, poor_armorer, possessions.assess(poor_armorer))
	assert(sale and sale.item == INGOT and sale.from == NUGGET, sale and sale.item)
	assert(sale.pay == math.max(math.floor(sale.count * 9 * per_nugget + 0.5), 1), sale.pay)
	assert(sale.pay <= 46)
	assert(exchange.settle(sale))
	assert(broke._villages_ask_sold[NUGGET] and broke._villages_ask_sold[NUGGET].count == 9 * sale.count)
	assert(asks.factor(broke, NUGGET) > asks.MIN, "the nugget ask rose on the sale")
	-- An own ask under the nuggets' stands.
	local fresh = alchemist_with({[NUGGET] = 19})
	fresh._villages_made_cost = {[NUGGET] = 0.5}
	fresh._villages_asks = {[INGOT] = asks.MIN}
	local fview = possessions.assess(fresh)
	assert(near(asks.converted(fresh, by_nuggets, fview), asks.ask(fresh, INGOT, fview)))
	assert(asks.ask(fresh, INGOT, fview) < 9 * asks.ask(fresh, NUGGET, fview))
end

-- Gold only past GOLD_RESERVE nuggets, and from the excess alone.
local conversions = goods.conversions(alchemist_with())
local gold_nugget, ingot_from_nuggets
for _, conversion in ipairs(conversions) do
	if conversion.to == GOLD_NUGGET then gold_nugget = conversion end
	if conversion.to == INGOT then ingot_from_nuggets = conversion end
end
assert(gold_nugget and gold_nugget.reserve == alchemist.GOLD_RESERVE)
local R = alchemist.GOLD_RESERVE
assert(R == 24, "a few lanterns' nuggets kept back (ticket 30: was 108)")
assert(goods.yield(gold_nugget, R + 17) == 0 and goods.yield(gold_nugget, R + 18) == 1)
local _, spent = goods.yield(gold_nugget, R + 18)
assert(spent == 18)
assert( goods.yield(ingot_from_nuggets, 27) == 3, "exactly three, not 2.999")
local buyer = villager("goldbug", {[EMERALD] = 5000})
local function wants_gold(v)
	local view_of = possessions.assess(v)
	view_of.needs[GOLD_NUGGET] = 1
	local value = view_of.value
	view_of.value = function(item) if item == GOLD_NUGGET then return 400 end return value(item) end
	return view_of
end
local hoard = alchemist_with({[NUGGET] = R + 12})
assert(exchange.offer(hoard, possessions.assess(hoard), buyer, wants_gold(buyer), GOLD_NUGGET) == nil, "under the reserve")
hoard = alchemist_with({[NUGGET] = R + 22})
trade = exchange.offer(hoard, possessions.assess(hoard), buyer, wants_gold(buyer), GOLD_NUGGET)
assert(trade and trade.item == GOLD_NUGGET and trade.count == 1 and trade.from_count == 18)
-- A pane from each glass.
local glazier = alchemist_with({[GLASS] = 5})
local builder = villager("bld", {[EMERALD] = 500})
local builder_view = possessions.assess(builder)
builder_view.needs[PANE] = 3
trade = exchange.offer(glazier, possessions.assess(glazier), builder, builder_view)
assert(trade and trade.item == PANE and trade.from == GLASS and trade.from_count == trade.count)

-- It buys no cobble above what a nugget returns for it (ticket 21d): a quarrier asking
-- more is passed over.
local buyer_alch = alchemist_with({[EMERALD] = 1000})
local quarrier = villager("quar", {[COBBLE] = 40})
quarrier._villages_asks = {[COBBLE] = 1.6}
assert(asks.ask(quarrier, COBBLE) > caps[COBBLE])
assert(exchange.offer(quarrier, possessions.assess(quarrier), buyer_alch, possessions.assess(buyer_alch)) == nil)
quarrier._villages_asks = {[COBBLE] = 0.9}
trade = exchange.offer(quarrier, possessions.assess(quarrier), buyer_alch, possessions.assess(buyer_alch))
assert(trade and trade.item == COBBLE and trade.pay <= trade.count * caps[COBBLE] + 1)

-- Its news tells the stone and logs it needs, and its ingots where someone asks for them.
local teller = alchemist_with({[EMERALD] = 1000, [NUGGET] = 40})
teller._villages_market_news = {{kind = "needs", item = INGOT, count = 2, who = "armo", price = 200, heard = now,
	hops = 1}}
local told = {}
for _, entry in ipairs(news.own(teller, possessions.assess(teller), now)) do told[entry.kind .. " " .. entry.item] = entry end
assert(told["has " .. INGOT] and told["has " .. INGOT].count == 4, "four ingots from 40 nuggets")
-- Told with its sources, so a trip buys the nuggets for it (ticket 29).
assert(told["has " .. INGOT].from == NUGGET and told["has " .. INGOT].takes == 9 and near(told["has " .. INGOT].ratio, 1 / 9))
assert(told["needs " .. COBBLE] or told["needs " .. STONE], "stone")
local logs_told = false
for key, entry in pairs(told) do logs_told = logs_told or (entry.kind == "needs" and entry.group == "log") end
assert(logs_told, "logs")
assert(not told["has " .. GOLD_NUGGET], "no gold under the reserve")

-- What it pays for stone and wood (ticket 28a): no less than its budget's share, and no
-- more than that or what its goods pay (ticket 30).
do
	local unit_stone, unit_log = ledger.price(STONE), ledger.price(LOG)
	local unit_fuel = ledger.price("mcl_core:coal_lump") / 80
	local wanted = {stone = 72, log = 32, fuel = 640}
	local total = 72 * unit_stone + 32 * unit_log + 640 * unit_fuel
	-- What it holds over 8 dinners, over 30 days, shared by base price over the day's wants.
	local reserve = alchemist.RESERVE_DINNERS * ledger.DINNER
	local floors = alchemist.floors(wanted, reserve + 3000, 1)
	local budget = 3000 / alchemist.SPEND_DAYS
	assert(near(floors[STONE], budget * unit_stone / total) and near(floors[COBBLE], floors[STONE]), floors[STONE])
	assert(near(floors[LOG], budget * unit_log / total) and near(floors["mcl_core:birchtree"], floors[LOG]))
	assert(near(floors["mcl_core:charcoal_lump"], budget * unit_fuel * 80 / total))
	local spent = 72 * floors[STONE] + 32 * floors[LOG] + 8 * floors["mcl_core:charcoal_lump"]
	assert(near(spent, budget), "the day's wants at its floors cost its budget: " .. spent)
	assert(near(alchemist.floors(wanted, reserve / 20 + 3000, 1 / 20)[STONE], floors[STONE]))
	assert(next(alchemist.floors(wanted, reserve, 1)) == nil, "nothing over its reserve")

	-- Its book (ticket 30): the average it paid a unit, over what it holds.
	local book = alchemist_with({})
	assert(near(alchemist.unit_cost(book, "stone"), ledger.price(STONE)), "before any purchase, its reference")
	alchemist.bought(book, {[COBBLE] = 10}, COBBLE, 10, 2)
	assert(near(alchemist.unit_cost(book, "stone"), 0.2))
	alchemist.bought(book, {[COBBLE] = 10, [STONE] = 10}, STONE, 10, 4)
	assert(near(alchemist.unit_cost(book, "stone"), 0.3), alchemist.unit_cost(book, "stone"))
	alchemist.bought(book, {[CHARCOAL] = 4}, CHARCOAL, 4, 4)
	assert(near(alchemist.unit_cost(book, "fuel"), 1 / 80), "a lump at 1, by the burn second")
	-- A nugget at a stone and half a lump (E12c): 0.8; its stock at the average it was made at.
	assert(near(alchemist.cost(book, by_makes[NUGGET]), 0.8))
	alchemist.made(book, NUGGET, 1, 0)
	assert(near(alchemist.stock_cost(book, NUGGET), 0.8))
	book._villages_input_cost.stone = 0.55
	alchemist.made(book, NUGGET, 1, 1)
	assert(near(alchemist.stock_cost(book, NUGGET), (0.8 + 1.05) / 2))
	assert(near(alchemist.stock_cost(book, INGOT), 9 * (0.8 + 1.05) / 2), "an ingot at nine nuggets'")
	-- Not another's: a plain villager keeps no book.
	local plain_buyer = villager("plainbuy", {})
	alchemist.bought(plain_buyer, {[COBBLE] = 10}, COBBLE, 10, 2)
	assert(plain_buyer._villages_input_cost == nil)
	-- A trade's pay goes in its book.
	local cobbler = villager("cob", {[COBBLE] = 20})
	local shopper = alchemist_with({[EMERALD] = 100})
	local deal = {seller = cobbler, buyer = shopper, item = COBBLE, count = 10, pay = 3}
	assert(exchange.settle(deal) and near(alchemist.unit_cost(shopper, "stone"), 0.3))

	-- Its caps: an input at no more than the goods it would still make pay. With only
	-- nuggets left to make (glass and flint at their stops) and a nugget last sold at 1.2,
	-- every unit cost is scaled by 1.2 over a nugget's cost: it breaks even at its caps.
	local maker = alchemist_with({[GLASS] = 13, [FLINT] = 32})
	maker._villages_sold_at = {[NUGGET] = 1.2}
	local caps = alchemist.caps(maker, possessions.held(maker))
	local scale = 1.2 / alchemist.cost(maker, by_makes[NUGGET])
	assert(near(caps[COBBLE], alchemist.unit_cost(maker, "stone") * scale) and near(caps[STONE], caps[COBBLE]))
	assert(near(caps[CHARCOAL], alchemist.unit_cost(maker, "fuel") * 80 * scale))
	assert(near(caps[COBBLE] + caps[CHARCOAL] / 2, 1.2), "at its caps a nugget costs what it sells for")
	assert(near(caps[LOG], alchemist.unit_cost(maker, "fuel") * goods.units("fuel", LOG) * scale),
		"logs only as fuel, flint at its stop")
	-- A stick at a lump's burn second: 5 of 80, so a dear stick is passed over.
	assert(near(caps["mcl_core:stick"], caps[CHARCOAL] * goods.units("fuel", "mcl_core:stick") / 80))
	-- Rich, it bids no more than its caps: a glut of nuggets and 3,000 emeralds.
	local hoarder = alchemist_with({[EMERALD] = 3000, [NUGGET] = 192, [GLASS] = 13, [FLINT] = 32})
	hoarder._villages_sold_at = {[NUGGET] = 1.2}
	local hview = possessions.assess(hoarder)
	local hcaps = alchemist.caps(hoarder, possessions.held(hoarder))
	assert(hcaps[COBBLE] == 0 and hcaps[LOG] == 0 and hcaps[CHARCOAL] == 0, "at its stops it makes nothing")
	local hfloor = alchemist.floors(alchemist.targets(possessions.held(hoarder)), 3000, 1)[COBBLE]
	assert(near(hview.value(COBBLE), hfloor), "so bids its budget's floor, a day's stock, not its wealth's")
	local broke_view = possessions.assess(alchemist_with({[NUGGET] = 192, [GLASS] = 13, [FLINT] = 32}))
	assert(broke_view.value(COBBLE) == 0, "with no budget, nothing")
	hoarder = alchemist_with({[EMERALD] = 3000, [NUGGET] = 100, [GLASS] = 13, [FLINT] = 32})
	hoarder._villages_sold_at = {[NUGGET] = 1.2}
	hview = possessions.assess(hoarder)
	hcaps = alchemist.caps(hoarder, possessions.held(hoarder))
	assert(hview.needs[COBBLE] == alchemist.STONE_WANT)
	local budget_floor = alchemist.floors(alchemist.targets(possessions.held(hoarder)), 3000, 1)[COBBLE]
	assert(near(hview.value(COBBLE), math.max(budget_floor, hcaps[COBBLE])), hview.value(COBBLE))
	-- A sale of its goods is kept for its bids.
	local seller = alchemist_with({[FLINT] = 10})
	asks.sold(seller, FLINT, day, 2, 8)
	assert(seller._villages_sold_at[FLINT] == 8)
	local plain = villager("plain", {})
	asks.sold(plain, FLINT, day, 1, 8)
	assert(plain._villages_sold_at == nil, "only an alchemist's")
	-- A seller asks at least half the bid it heard for a material, a category's too:
	-- cobble at the alchemist's per-unit bid for stone.
	local quarrier = villager("quarry", {[COBBLE] = 200})
	quarrier._villages_asks = {[COBBLE] = asks.MIN}
	quarrier._villages_market_news = {{item = STONE, who = "alch", kind = "needs", count = 72, price = 0.8,
		group = "stone", budget = 3000, heard = now, hops = 0}}
	assert(asks.bid_priced(COBBLE) and asks.bid_priced(LOG) and asks.bid_priced("mcl_core:charcoal_lump"))
	assert(near(asks.best_bid(quarrier, COBBLE), 0.8))
	assert(asks.ask(quarrier, COBBLE) >= asks.BID_SHARE * 0.8 - 1e-9, asks.ask(quarrier, COBBLE))
	assert(not asks.bid_priced("mcl_farming:bread"), "food has its own pricing")
end

print("alchemist_trade.lua: ok")
