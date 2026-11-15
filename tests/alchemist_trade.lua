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
assert(by_makes[NUGGET].upto == nil, "nuggets never stop")

-- Its working day is 10500 ticks, 525 s at time_speed 72: a nugget a eighteenth of it.
local alch = alchemist_with()
assert(production.recipes(alch) == production.RECIPES.alchemist)
assert(near(production.cost(alch, by_makes[NUGGET]), 525 / 18))
assert(near(production.cost(alch, by_makes[FLINT]), 525 / 6))
assert(near(production.cost(alch, by_makes[GLASS]), 525 / 36))
settings.time_speed = "144"
assert(near(production.cost(alch, by_makes[NUGGET]), 525 / 36), "a faster clock, a shorter day")
settings.time_speed = nil
-- A crafter's own cost is unchanged.
assert(production.cost(alch, recipes.tool_smith[1]) == production.craft_seconds())

-- With nothing to make it waits at its stand: it never labours.
assert(production.choose(alch) == nil and production.idle_today(alch) == false)

-- A whole day on cobble: 18 nuggets from 72.
local miner = alchemist_with({[COBBLE] = 72})
for _ = 1, 18 do production.work(miner, 525 / 18) end
assert(count(miner, NUGGET) == 18 and count(miner, COBBLE) == 0, count(miner, NUGGET))
assert(logs[#logs]:find("made 1 mcl_core:iron_nugget", 1, true))
-- Stone and cobble both serve, the one held most first.
local mixed = alchemist_with({[COBBLE] = 3, [STONE] = 1})
assert(production.choose(mixed).makes == NUGGET and production.make(mixed, by_makes[NUGGET]))
assert(count(mixed, COBBLE) == 0 and count(mixed, STONE) == 0 and count(mixed, NUGGET) == 1)

-- A whole day on logs: 6 flint from 24, any species.
local cutter = alchemist_with({[LOG] = 12, ["mcl_core:birchtree"] = 12})
for _ = 1, 6 do production.work(cutter, 525 / 6) end
assert(count(cutter, FLINT) == 6 and count(cutter, LOG) + count(cutter, "mcl_core:birchtree") == 0)

-- It makes what pays most (ticket 21d). At their seed prices glass and flint sell for
-- what their stone and logs would, so nuggets, which earn over their cobble, come first.
local busy = alchemist_with({[STONE] = 40, [LOG] = 8})
assert(production.choose(busy).makes == NUGGET)
assert(production.status(busy):find("making iron_nugget", 1, true))
-- Once nuggets glut and their ask falls below their stone, glass and flint tie at no gain
-- and go by rank: glass while it holds 12 or fewer, then flint under 32, then nothing.
busy._villages_asks = {[NUGGET] = 0.25}
assert(production.choose(busy).makes == GLASS)
possessions.add(busy, GLASS, 13)
assert(production.choose(busy).makes == FLINT, "past 12 glass")
possessions.add(busy, FLINT, 32)
assert(production.choose(busy) == nil, "at 32 flint, and nuggets lose")
-- Flint that sells dear beats glass at its seed price.
local keen = alchemist_with({[STONE] = 40, [LOG] = 8})
keen._villages_asks = {[FLINT] = 2}
assert(production.choose(keen).makes == FLINT)

-- What it buys: a day's 72 stone or cobble always, and logs for the flint it is short of,
-- four a flint, at most 32 at once.
local view = possessions.assess(alchemist_with({[EMERALD] = 1000}))
assert(view.categories.stone.target == 72 and view.categories.log.target == 32)
assert(view.needs[COBBLE] == 72 and view.needs[STONE] == 72 and view.needs[LOG] == 32)
view = possessions.assess(alchemist_with({[EMERALD] = 1000, [FLINT] = 30}))
assert(view.categories.log.target == 8)
view = possessions.assess(alchemist_with({[EMERALD] = 1000, [FLINT] = 32}))
assert(view.categories.log == nil and not view.needs[LOG], "no logs at 32 flint")
-- It values an input at no more than its best recipe returns for it (ticket 21d): stone
-- at glass's 3.2 or a nugget's 3.84, cobble at a nugget's 3.84; short, it pays its price.
local caps = ledger.imputed(recipes.alchemist, ledger.price, 5)
assert(near(caps[STONE], ledger.price(NUGGET) / 4) and near(caps[COBBLE], caps[STONE]))
assert(view.value(COBBLE) <= caps[COBBLE] + 1e-9 and view.value(STONE) <= caps[STONE] + 1e-9)
assert(near(view.value(STONE), ledger.price(STONE)), "short, so at its price")
local rich = possessions.assess(alchemist_with({[NUGGET] = 500, [GLASS] = 100}))
assert(rich.surplus[NUGGET] == 500, "every nugget is spare")

-- Its goods have no floor at their cost (ticket 21b): it asks its reference price times
-- its factor like anyone, so a broke alchemist with goods nobody buys gets cheaper.
local seller = alchemist_with({[NUGGET] = 50})
seller._villages_asks = {[INGOT] = 0.5, [NUGGET] = 0.5}
assert(near(asks.ask(seller, INGOT), ledger.price(INGOT) / 2) and near(asks.ask(seller, NUGGET), ledger.price(NUGGET) / 2))

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
	local broke = alchemist_with({[NUGGET] = 19})
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
	fresh._villages_asks = {[INGOT] = asks.MIN}
	local fview = possessions.assess(fresh)
	assert(near(asks.converted(fresh, by_nuggets, fview), asks.ask(fresh, INGOT, fview)))
	assert(asks.ask(fresh, INGOT, fview) < 9 * asks.ask(fresh, NUGGET, fview))
end

-- Gold only past 108 nuggets, and from the excess alone.
local conversions = goods.conversions(alchemist_with())
local gold_nugget, ingot_from_nuggets
for _, conversion in ipairs(conversions) do
	if conversion.to == GOLD_NUGGET then gold_nugget = conversion end
	if conversion.to == INGOT then ingot_from_nuggets = conversion end
end
assert(gold_nugget and gold_nugget.reserve == alchemist.GOLD_RESERVE)
assert(goods.yield(gold_nugget, 120) == 0 and goods.yield(gold_nugget, 126) == 1)
local _, spent = goods.yield(gold_nugget, 126)
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
local hoard = alchemist_with({[NUGGET] = 120})
assert(exchange.offer(hoard, possessions.assess(hoard), buyer, wants_gold(buyer), GOLD_NUGGET) == nil, "under the reserve")
hoard = alchemist_with({[NUGGET] = 130})
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
assert(told["needs " .. COBBLE] or told["needs " .. STONE], "stone")
local logs_told = false
for key, entry in pairs(told) do logs_told = logs_told or (entry.kind == "needs" and entry.group == "log") end
assert(logs_told, "logs")
assert(not told["has " .. GOLD_NUGGET], "no gold under the reserve")

print("alchemist_trade.lua: ok")
