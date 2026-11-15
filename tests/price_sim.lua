-- Run with: lua tests/price_sim.lua
-- Price discovery in a thin market (ticket 21b): a few stub villagers trade day after day
-- through the real ledger, asks, exchange and prices, with the news they would tell each
-- other built from their views. Checks that a price settles between the two sides'
-- values, that a glut gets cheaper until it sells, that a rich buyer's money reaches
-- several sellers, and that nothing runs to a rail in a steady state.
local now, day = 1000, 1
local logs = {}

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
}

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	get_day_count = function() return day end,
	get_timeofday = function() return 0.4 end,
	get_item_group = function() return 0 end,
	registered_nodes = {},
	registered_items = {},
	settings = {get = function() return nil end, get_bool = function(_, _, default) return default end},
	log = function(_, message) logs[#logs + 1] = message end,
	pos_to_string = function(p) return "(" .. p.x .. "," .. p.y .. "," .. p.z .. ")" end,
	get_objects_inside_radius = function() return {} end,
	add_particle = function() end,
	sound_play = function() end,
}

local possessions = dofile("possessions.lua")
local ledger = dofile("ledger.lua")
local exchange = dofile("exchange.lua")
local asks = dofile("asks.lua")
local prices = dofile("prices.lua")

local EMERALD = "mcl_core:emerald"
local FLINT, FEATHER, STRING = "mcl_core:flint", "mcl_mobitems:feather", "mcl_mobitems:string"

local function villager(id, held, fields)
	local pos = {x = 0, y = 1, z = 0}
	local v = {_id = id, _profession = "nitwit", _villages_food = 12, _villages_belongings = held,
		object = {get_pos = function() return pos end}}
	for k, value in pairs(fields or {}) do v[k] = value end
	return v
end

-- What each would tell the others: its spare at its ask, its needs at its bid.
local function news_of(members)
	local heard = {}
	for _, v in ipairs(members) do
		local view = possessions.assess(v)
		for item, count in pairs(view.surplus) do
			local ask = asks.ask(v, item, view)
			local ref = prices.price(v._villages_prices, item)
			if ask then
				heard[#heard + 1] = {kind = "has", item = item, count = count, price = ask, who = v._id, hops = 1,
					ref = ref and ref * asks.factor(v, item)}
			end
		end
		for item, count in pairs(view.needs) do
			local value = view.value(item)
			if value then
				heard[#heard + 1] = {kind = "needs", item = item, count = count, who = v._id, hops = 1,
					price = math.min(value, math.max(possessions.emeralds(v), 1)), budget = possessions.emeralds(v),
					ref = prices.price(v._villages_prices, item),
					group = view.group[item]}
			end
		end
	end
	return heard
end

-- A day: everyone hears everyone, its prices move, each pair trades once, asks move.
local function run_day(members)
	local heard = news_of(members)
	for _, v in ipairs(members) do
		local mine = {}
		for _, entry in ipairs(heard) do if entry.who ~= v._id then mine[#mine + 1] = entry end end
		prices.daily(v, mine, possessions.assess(v), day, {budget = possessions.emeralds(v)})
	end
	local made = exchange.exchange(members)
	for _, v in ipairs(members) do
		asks.daily(v, possessions.assess(v).surplus, day, possessions.money(v))
	end
	day = day + 1
	now = now + 1200
	return made
end

local function unit_of(trade) return trade.pay / trade.count end

-- 1 and 2. A glut held by a broke seller, and a buyer with too little money to pay its
-- base price: the ask falls until a sale happens, at a price between the seller's own
-- value and the buyer's.
do
	day = 1
	local seller = villager("glut", {[FLINT] = 40, [EMERALD] = 5})
	local fletcher = villager("fletch", {[EMERALD] = 30}, {_profession = "fletcher", _max_trade_tier = 1})
	assert(ledger.price(FLINT) > 30, "flint at its base price is beyond the fletcher")
	local first
	for _ = 1, 30 do
		local seller_view, buyer_view = possessions.assess(seller), possessions.assess(fletcher)
		local made = run_day({seller, fletcher})
		for _, trade in ipairs(made) do
			if trade.item == FLINT and not first then
				first = trade
				local unit = unit_of(trade)
				assert(unit <= buyer_view.value(FLINT) + 1, "no more than the buyer's value")
				assert(unit >= seller_view.value(FLINT) - 1, "no less than the seller's own")
			end
		end
		if first then break end
	end
	assert(first, "the glut sold")
	assert(unit_of(first) < ledger.price(FLINT), "below its base price, which nobody here could pay")
	-- Both learnt the price: their reference prices for flint fell.
	assert(prices.factor(seller._villages_prices, FLINT) < 1 and prices.factor(fletcher._villages_prices, FLINT) < 1)
end

-- 3. A rich buyer's money reaches several sellers: each of three broke sellers holds a
-- good the rich fletcher needs.
do
	day = 1
	local rich = villager("rich", {[EMERALD] = 3000}, {_profession = "fletcher", _max_trade_tier = 1})
	local sellers = {
		villager("s-flint", {[FLINT] = 30}),
		villager("s-feather", {[FEATHER] = 30}),
		villager("s-string", {[STRING] = 30}),
	}
	for _ = 1, 10 do
		for _, s in ipairs(sellers) do run_day({rich, s}) end
	end
	for _, s in ipairs(sellers) do
		assert(possessions.emeralds(s) > 0, s._id .. " was paid")
	end
	assert(possessions.emeralds(rich) < 3000)
end

-- 4. A steady state for 60 days: each seller makes 4 a day, the buyer's batch, and the
-- buyer uses up all it bought and gets back what the sellers do not keep (they spend it on
-- its goods). No reference price or ask runs to a rail, the fletcher's planks included,
-- which nobody sells.
do
	day = 1
	local buyer = villager("steady", {[EMERALD] = 600}, {_profession = "fletcher", _max_trade_tier = 1})
	local sellers = {
		villager("m-flint", {[FLINT] = 16, [EMERALD] = 100}),
		villager("m-feather", {[FEATHER] = 16, [EMERALD] = 100}),
	}
	local goods = {FLINT, FEATHER}
	local sold = 0
	for _ = 1, 60 do
		for i, s in ipairs(sellers) do
			possessions.add(s, goods[i], 4)
			sold = sold + #run_day({buyer, s})
			-- What the seller holds past 100 goes back to the buyer, for its own goods.
			local extra = possessions.emeralds(s) - 100
			if extra > 0 then
				possessions.take(s, EMERALD, extra)
				possessions.add(buyer, EMERALD, extra)
			end
		end
		for _, item in ipairs(goods) do possessions.take(buyer, item, possessions.count(buyer, item)) end
	end
	assert(sold >= 60, "trade goes on: " .. sold)
	local rail = math.log(prices.SPAN) * 0.99
	for _, v in ipairs({buyer, sellers[1], sellers[2]}) do
		for key, factor in pairs(v._villages_prices or {}) do
			assert(math.abs(math.log(factor)) < rail, v._id .. " " .. key .. " at a rail: " .. factor)
		end
	end
	for i, s in ipairs(sellers) do
		local factor = asks.factor(s, goods[i])
		assert(factor > asks.MIN * 1.001 and factor < asks.MAX * 0.999, s._id .. " ask at a rail: " .. factor)
	end
end

print("price_sim.lua: ok")
