-- Run with: lua tests/exchange.lua
local now = 1000
local settings = {}
local logs, handovers = {}, {}

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
}

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	settings = {
		get = function(_, name) return settings[name] end,
		get_bool = function(_, name, default)
			if settings[name] == nil then return default end
			return settings[name]
		end,
	},
	log = function(_, message) table.insert(logs, message) end,
	registered_items = {},
	add_particle = function() end,
	-- food.show_handover's bite: one per item handed across.
	sound_play = function() handovers[#handovers + 1] = true end,
}

local exchange = dofile("exchange.lua")
local possessions = dofile("possessions.lua")

local function villager(id, held, fields)
	local v = {_id = id, _profession = "nitwit", _villages_food = 12, _villages_belongings = held,
		object = {get_pos = function() return {x = 0, y = 0, z = 0} end}}
	for k, value in pairs(fields or {}) do v[k] = value end
	return v
end
local function count(v, item) return possessions.count(v, item) end

-- A hungry villager with emeralds buys bread a fed one has spare, at the baker's ask, in
-- whole emeralds; the goods pass belongings to belongings.
local baker = villager("baker", {["mcl_farming:bread"] = 20})
-- Five vanilla emeralds, at the economy's scale (ticket 11h).
local diner = villager("diner", {["mcl_core:emerald"] = 5 * 64}, {_villages_food = 0})
local made = exchange.exchange({baker, diner})
assert(#made == 1, "one trade")
local trade = made[1]
assert(trade.seller == baker and trade.buyer == diner and trade.item == "mcl_farming:bread" and trade.pay >= 1)
assert(count(diner, "mcl_farming:bread") == trade.count and count(baker, "mcl_farming:bread") == 20 - trade.count)
assert(count(baker, "mcl_core:emerald") == trade.pay and count(diner, "mcl_core:emerald") == 5 * 64 - trade.pay)
assert(logs[#logs]:find("trade: villager baker sold") and #handovers == 2)
-- It needs less bread now, and the baker still has spare.
local after = possessions.assess(diner)
assert((after.needs["mcl_farming:bread"] or 0) < 3 and possessions.assess(baker).surplus["mcl_farming:bread"])

-- One trade per pair per conversation, however much is left to trade.
local made_again = exchange.exchange({baker, diner})
assert(#made_again <= 1)

-- No emeralds on either side: a swap of goods each needs and the other has spare. The
-- smith needs a batch of coal more than the hungry collier needs bread, so the
-- likeliest trade is the coal, paid for in bread.
local smith = villager("smith", {["mcl_farming:bread"] = 20}, {_profession = "armorer", _max_trade_tier = 1})
local collier = villager("collier", {["mcl_core:coal_lump"] = 40}, {_villages_food = 0})
made = exchange.exchange({smith, collier})
assert(#made == 1 and not made[1].pay)
assert(made[1].seller == collier and made[1].item == "mcl_core:coal_lump" and made[1].goods == "mcl_farming:bread")
assert(count(smith, "mcl_core:coal_lump") == made[1].count and count(collier, "mcl_farming:bread") == made[1].goods_count)
assert(made[1].goods_count >= 1 and logs[#logs]:find("for %d+ mcl_farming:bread"))

-- Synthetic views pin the rule down: the seller asks paper's base price (asks.lua), and a
-- buyer valuing paper at least that pays it, whatever the seller's own value.
local function view(needs, surplus, values)
	return {needs = needs, surplus = surplus, value = function(item) return values[item] end}
end
local ledger = dofile("ledger.lua")
local asks = dofile("asks.lua")
local PAPER = ledger.price("mcl_core:paper")
local s = villager("s", {["mcl_core:paper"] = 30})
local b = villager("b", {["mcl_core:emerald"] = 30})
local function seller_view(value) return view({}, {["mcl_core:paper"] = 30}, {["mcl_core:paper"] = value}) end
local offer = exchange.offer(s, seller_view(0.05), b, view({["mcl_core:paper"] = 10}, {}, {["mcl_core:paper"] = PAPER + 1}))
assert(offer and offer.count == 10 and offer.pay == math.floor(10 * PAPER + 0.5), offer and offer.pay)
-- The seller's own value does not move the price.
local dear = exchange.offer(s, seller_view(PAPER * 5), b, view({["mcl_core:paper"] = 10}, {}, {["mcl_core:paper"] = PAPER + 1}))
assert(dear and dear.pay == offer.pay)
-- A buyer valuing it under the ask: nothing.
assert(not exchange.offer(s, seller_view(0.05), b, view({["mcl_core:paper"] = 10}, {}, {["mcl_core:paper"] = PAPER - 0.1})))
-- One short of emeralds buys as many as it can pay for.
local short = villager("short", {["mcl_core:emerald"] = 8})
offer = exchange.offer(s, seller_view(0.05), short, view({["mcl_core:paper"] = 10}, {}, {["mcl_core:paper"] = PAPER + 1}))
assert(offer and offer.count == math.floor(8 / PAPER), offer and offer.count)
-- But not when the whole emeralds paid would cost the buyer more than it values the goods.
assert(not exchange.offer(s, seller_view(0.05), b, view({["mcl_core:paper"] = 1}, {}, {["mcl_core:paper"] = PAPER + 0.01})))
-- A higher ask, after sales, is what the buyer pays.
asks.sold(s, "mcl_core:paper", 1)
offer = exchange.offer(s, seller_view(0.05), b, view({["mcl_core:paper"] = 10}, {}, {["mcl_core:paper"] = PAPER * 2}))
assert(offer.pay == math.floor(10 * PAPER * asks.MARKUP + 0.5))
s._villages_asks, s._villages_ask_sold = nil, nil
-- Surplus it does not carry (in its stash) is not at hand.
local stash_only = villager("t", {})
assert(not exchange.offer(stash_only, seller_view(0.05), b, view({["mcl_core:paper"] = 10}, {}, {["mcl_core:paper"] = PAPER + 1})))
-- Emeralds are never goods.
assert(not exchange.offer(villager("u", {["mcl_core:emerald"] = 9}), view({}, {["mcl_core:emerald"] = 9}, {["mcl_core:emerald"] = 1}),
	b, view({["mcl_core:emerald"] = 1}, {}, {["mcl_core:emerald"] = 1})))
-- Too few emeralds and nothing the seller needs: nothing.
local poor = villager("p", {})
assert(not exchange.offer(s, seller_view(0.05), poor, view({["mcl_core:paper"] = 10}, {}, {["mcl_core:paper"] = PAPER + 1})))
-- An item with no base price settles at the midpoint, the buyer valuing it above the seller.
local odd = villager("odd", {["no:price"] = 4})
offer = exchange.offer(odd, view({}, {["no:price"] = 4}, {["no:price"] = 2}), b, view({["no:price"] = 2}, {}, {["no:price"] = 6}))
assert(offer and offer.pay == 8, offer and offer.pay)
assert(not exchange.offer(odd, view({}, {["no:price"] = 4}, {["no:price"] = 6}), b, view({["no:price"] = 2}, {}, {["no:price"] = 6})))
-- A sale raises the seller's ask.
assert(exchange.settle(offer) and asks.factor(odd, "no:price") == asks.MARKUP)

-- settle checks the goods are still there.
local gone = {seller = villager("v", {}), buyer = b, item = "mcl_core:paper", count = 1, pay = 1}
assert(not exchange.settle(gone))

-- With the economy off nothing is traded.
settings.living_villages_economy = false
local baker2 = villager("baker2", {["mcl_farming:bread"] = 20})
local diner2 = villager("diner2", {["mcl_core:emerald"] = 5}, {_villages_food = 0})
assert(#exchange.exchange({baker2, diner2}) == 0 and count(baker2, "mcl_farming:bread") == 20)

-- A buyer short of emeralds for the whole lot buys what its emeralds pay for: a Builder
-- with one vanilla emerald (64), short of 34 cobble, from a quarrier with 64.
do
	local quarrier = villager("qa", {["mcl_core:cobble"] = 64})
	local builder = villager("bu", {["mcl_core:emerald"] = 64},
		{_villages_builder = true, _profession = "mason", _villages_builder_wants = {["mcl_core:cobble"] = 34}})
	local offer = exchange.offer(quarrier, possessions.assess(quarrier), builder, possessions.assess(builder))
	assert(offer and offer.item == "mcl_core:cobble" and offer.pay <= 64 and offer.pay > 48, "its emeralds' worth")
	assert(offer.count > 1 and offer.count < 34, offer.count)
	assert(exchange.settle(offer) and count(builder, "mcl_core:cobble") == offer.count
		and count(builder, "mcl_core:emerald") == 64 - offer.pay)
end

-- At the economy's scale a few cheap goods make a sale (runs 34 to 36 found 4 coal and a
-- spare loaf worth under one emerald at vanilla's prices, ticket 11h).
do
	local burner = villager("co", {["mcl_core:coal_lump"] = 20})
	local smith = villager("sm", {["mcl_core:emerald"] = 64}, {_profession = "armorer", _max_trade_tier = 1,
		_villages_belongings = {["mcl_core:emerald"] = 64, ["mcl_core:coal_lump"] = 11}})
	local offer = exchange.offer(burner, possessions.assess(burner), smith, possessions.assess(smith), "mcl_core:coal_lump")
	assert(offer and offer.pay and offer.count <= 4, offer and offer.count)
end

-- Conversions (ticket 15): a shepherd sells string from its spare wool, four to a wool,
-- whole wools only, at string's ask. A stall showing wool sells it.
do
	local shepherd = villager("sh", {["mcl_wool:grey"] = 10}, {_profession = "shepherd"})
	local weaver = villager("we", {["mcl_core:emerald"] = 64})
	local seller_view = view({}, {["mcl_wool:grey"] = 10}, {["mcl_wool:grey"] = 0.4})
	local buyer_view = view({["mcl_mobitems:string"] = 6}, {}, {["mcl_mobitems:string"] = ledger.price("mcl_mobitems:string") * 1.5})
	local offer = exchange.offer(shepherd, seller_view, weaver, buyer_view)
	assert(offer and offer.item == "mcl_mobitems:string" and offer.from == "mcl_wool:grey")
	assert(offer.from_count == 2 and offer.count == 8 and offer.pay, offer.count)
	assert(exchange.offer(shepherd, seller_view, weaver, buyer_view, "mcl_wool:grey"), "stall of wool")
	assert(exchange.offer(shepherd, seller_view, weaver, buyer_view, "mcl_mobitems:string"), "trip for string")
	assert(not exchange.offer(shepherd, seller_view, weaver, buyer_view, "mcl_core:dirt"))
	assert(exchange.settle(offer))
	assert(count(shepherd, "mcl_wool:grey") == 8 and count(weaver, "mcl_mobitems:string") == 8)
	assert(count(shepherd, "mcl_mobitems:string") == 0 and logs[#logs]:find("from 2 mcl_wool:grey"))
	-- A nitwit converts nothing.
	local nitwit = villager("nw", {["mcl_wool:grey"] = 10})
	assert(not exchange.offer(nitwit, seller_view, weaver, buyer_view))
end

print("exchange.lua: ok")
