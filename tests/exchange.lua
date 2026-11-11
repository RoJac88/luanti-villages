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

-- A hungry villager with emeralds buys bread a fed one has spare, at the midpoint, in
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

-- Synthetic views pin the rule down.
local function view(needs, surplus, values)
	return {needs = needs, surplus = surplus, value = function(item) return values[item] end}
end
local s = villager("s", {["mcl_core:paper"] = 30})
local b = villager("b", {["mcl_core:emerald"] = 3})
-- The buyer values it above the seller: a sale at the midpoint, 10 x 0.1 = 1 emerald.
local offer = exchange.offer(s, view({}, {["mcl_core:paper"] = 30}, {["mcl_core:paper"] = 0.05}),
	b, view({["mcl_core:paper"] = 10}, {}, {["mcl_core:paper"] = 0.15}))
assert(offer and offer.count == 10 and offer.pay == 1)
-- The buyer values it no higher than the seller: nothing.
assert(not exchange.offer(s, view({}, {["mcl_core:paper"] = 30}, {["mcl_core:paper"] = 0.15}),
	b, view({["mcl_core:paper"] = 10}, {}, {["mcl_core:paper"] = 0.15})))
-- A small need grows to the fewest that make an emerald, if the seller has them spare.
offer = exchange.offer(s, view({}, {["mcl_core:paper"] = 30}, {["mcl_core:paper"] = 0.05}),
	b, view({["mcl_core:paper"] = 1}, {}, {["mcl_core:paper"] = 0.15}))
assert(offer and offer.count == 10 and offer.pay == 1, "10 x 0.1 makes an emerald")
-- But not when paying a whole emerald for it would lose the buyer value.
assert(not exchange.offer(s, view({}, {["mcl_core:paper"] = 3}, {["mcl_core:paper"] = 0.05}),
	b, view({["mcl_core:paper"] = 1}, {}, {["mcl_core:paper"] = 0.15})))
-- Surplus it does not carry (in its stash) is not at hand.
local stash_only = villager("t", {})
assert(not exchange.offer(stash_only, view({}, {["mcl_core:paper"] = 30}, {["mcl_core:paper"] = 0.05}),
	b, view({["mcl_core:paper"] = 10}, {}, {["mcl_core:paper"] = 0.15})))
-- Emeralds are never goods.
assert(not exchange.offer(villager("u", {["mcl_core:emerald"] = 9}), view({}, {["mcl_core:emerald"] = 9}, {["mcl_core:emerald"] = 1}),
	b, view({["mcl_core:emerald"] = 1}, {}, {["mcl_core:emerald"] = 1})))
-- Too few emeralds and nothing the seller needs: nothing.
local poor = villager("p", {})
assert(not exchange.offer(s, view({}, {["mcl_core:paper"] = 30}, {["mcl_core:paper"] = 0.05}),
	poor, view({["mcl_core:paper"] = 10}, {}, {["mcl_core:paper"] = 0.15})))

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
-- whole wools only, valued at the wool's value over four. A stall showing wool sells it.
do
	local shepherd = villager("sh", {["mcl_wool:grey"] = 10}, {_profession = "shepherd"})
	local weaver = villager("we", {["mcl_core:emerald"] = 64})
	local seller_view = view({}, {["mcl_wool:grey"] = 10}, {["mcl_wool:grey"] = 0.4})
	local buyer_view = view({["mcl_mobitems:string"] = 6}, {}, {["mcl_mobitems:string"] = 0.5})
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
