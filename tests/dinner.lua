-- Run with: lua tests/dinner.lua
-- A dinner that floats (ticket 21e): the keeper's price from its food cost and dinner
-- factor, the factor's daily move, who dines by value, and the amounts counted in dinners.
local metas, logs = {}, {}
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return 0 end,
	get_day_count = function() return 1 end,
	get_timeofday = function() return 0.4 end,
	get_item_group = function() return 0 end,
	registered_items = {},
	registered_nodes = {},
	settings = {get = function() return nil end, get_bool = function(_, _, default) return default end},
	log = function(_, message) logs[#logs + 1] = message end,
	pos_to_string = function(p) return "(" .. key(p) .. ")" end,
	get_objects_inside_radius = function() return {} end,
	get_meta = function(pos)
		local k = key(pos)
		metas[k] = metas[k] or {}
		return {
			get_string = function(_, field) return metas[k][field] or "" end,
			set_string = function(_, field, value) metas[k][field] = value end,
		}
	end,
}

local ledger = dofile("ledger.lua")
local dinner = dofile("dinner.lua")
local possessions = dofile("possessions.lua")
local comforts = dofile("comforts.lua")
local alms = dofile("alms.lua")
local asks = dofile("asks.lua")

local BREAD, EMERALD = "mcl_farming:bread", "mcl_core:emerald"
local LOAF = ledger.price(BREAD)
local function near(a, b) return math.abs(a - b) < 1e-6 end

-- The pseudo-item's base price is the old fixed dinner, only a seed now.
assert(ledger.price(dinner.ITEM) == ledger.DINNER)

-- The keeper's price: a loaf at its reference price, times its factor, whole emeralds.
local kate = {_id = "kate", _villages_keeper = true}
local jukebox = {x = 0, y = 0, z = 0}
assert(near(dinner.food_cost(kate), LOAF) and dinner.factor(kate) == 1)
assert(dinner.settle(kate, jukebox, 1) == math.floor(LOAF + 0.5))
assert(dinner.posted(jukebox) == dinner.price(kate), "posted at the jukebox")
assert(near(dinner.reference(kate), dinner.price(kate)), "the keeper reckons a dinner its own price")
kate._villages_prices = {["group:food"] = 2}
assert(dinner.price(kate) == math.floor(2 * LOAF + 0.5), "dearer food, a dearer dinner")
kate._villages_prices = nil

-- Hungry broke guests turned away with dishes left: down MARKDOWN the next day, once
-- however many.
dinner.turned(kate, "bo", 1)
dinner.turned(kate, "cy", 1)
dinner.turned(kate, "bo", 1)
assert(dinner.factor(kate) == 1, "not before the day is out")
dinner.settle(kate, jukebox, 2)
assert(near(dinner.factor(kate), dinner.MARKDOWN))
assert(logs[#logs]:find("keeper kate moved its dinner factor to 0.90 (guests turned away)", 1, true), logs[#logs])
assert(dinner.posted(jukebox) == math.floor(LOAF * dinner.MARKDOWN + 0.5))
-- The pantry ran out: up MARKUP, even with guests turned away earlier.
dinner.turned(kate, "bo", 2)
dinner.ran_out(kate, 2)
dinner.settle(kate, jukebox, 3)
assert(near(dinner.factor(kate), dinner.MARKDOWN * dinner.MARKUP))
-- A quiet day leaves it be.
dinner.settle(kate, jukebox, 4)
assert(near(dinner.factor(kate), dinner.MARKDOWN * dinner.MARKUP))
-- Within the asks' rails, and never under one emerald.
for d = 5, 60 do dinner.turned(kate, "bo", d - 1) dinner.settle(kate, jukebox, d) end
assert(near(dinner.factor(kate), asks.MIN) and dinner.price(kate) >= 1)
for d = 61, 120 do dinner.ran_out(kate, d - 1) dinner.settle(kate, jukebox, d) end
assert(near(dinner.factor(kate), asks.MAX))
-- No keeper at hand: the last posted price, or none.
assert(dinner.posted(jukebox) == dinner.price(kate))
assert(dinner.posted({x = 9, y = 9, z = 9}) == nil)
-- With no keeper, turning away and running out are nobody's.
dinner.turned(nil, "bo", 1)
dinner.ran_out(nil, 1)

-- Who dines: a loaf's value to it, asked once a day and price, learning the price.
local function villager(id, held, fields)
	local pos = {x = 0, y = 1, z = 0}
	local v = {_id = id, _profession = "nitwit", _villages_belongings = held,
		object = {get_pos = function() return pos end}}
	for k, value in pairs(fields or {}) do v[k] = value end
	return v
end
local hungry = villager("hal", {[EMERALD] = 72}, {_villages_food = 0})
local value = possessions.assess(hungry).value(BREAD)
assert(dinner.wants(hungry, math.floor(value), 1, possessions.assess), "worth it")
assert(dinner.reference(hungry) > ledger.DINNER, "it saw the price, dearer than 18")
assert(not dinner.wants(hungry, math.ceil(value) + 1, 1, possessions.assess), "dear: it buys bread instead")
-- The same day and price: no second look.
local calls = 0
local function counting(v) calls = calls + 1 return possessions.assess(v) end
dinner.wants(hungry, math.ceil(value) + 1, 1, counting)
assert(calls == 0)
-- One with food of its own values a dinner less, and passes it up.
local stocked = villager("sam", {[EMERALD] = 72, [BREAD] = 20}, {_villages_food = 0})
assert(possessions.assess(stocked).value(BREAD) < value)
-- Variety (ticket 34): tired of the only dish on offer, a dinner is worth less to it; with
-- a dish it has not had, a loaf's full worth, however tired of bread it is.
do
	local BAKED, FISH = "mcl_farming:potato_item_baked", "mcl_fishing:fish_cooked"
	local function guest(id) return villager(id, {[EMERALD] = 72}, {_villages_food = 0,
		_villages_meals = {[1] = {[BAKED] = 6, [BREAD] = 6}}}) end
	local fresh = villager("fr", {[EMERALD] = 72}, {_villages_food = 0})
	local worth = possessions.assess(fresh).value(BREAD)
	-- Starving tires of nothing: the hungry are fed first.
	assert(dinner.wants(guest("g0"), math.floor(worth), 1, possessions.assess, {BAKED}))
	local function peckish(id) local g = guest(id); g._villages_food = 2; return g end
	local base = possessions.assess(villager("fr2", {[EMERALD] = 72}, {_villages_food = 2})).value(BREAD)
	assert(not dinner.wants(peckish("g1"), math.floor(base), 1, possessions.assess, {BAKED}), "tired of the dish")
	assert(dinner.wants(peckish("g2"), math.floor(base), 1, possessions.assess, {BAKED, FISH}), "a new dish")
end
-- Paying teaches it more than seeing: LEARN_TRADE.
local payer = villager("pay", {})
dinner.paid(payer, 9)
local seen = villager("see", {})
dinner.wants(seen, 9, 1, function() return {value = function() return 0 end} end)
assert(dinner.reference(payer) < dinner.reference(seen) and dinner.reference(seen) < ledger.DINNER)

-- Food first (ticket 22b): with food at x0.09 and 2 emeralds, a starving villager dines
-- at 1; a fed one with the same purse and prices does not. Its other goods keep their λ.
local cheap_food = {["group:food"] = 0.09}
local starving = villager("st", {[EMERALD] = 2}, {_villages_food = 0, _villages_prices = cheap_food})
local fed = villager("fd", {[EMERALD] = 2}, {_villages_food = 10, _villages_prices = cheap_food})
assert(dinner.wants(starving, 1, 1, possessions.assess), "spends its last emeralds on food")
assert(not dinner.wants(fed, 1, 1, possessions.assess))
local view = possessions.assess(starving)
local fv = possessions.assess(fed)
assert(view.lambda > 1 and near(view.value("mcl_books:book") * view.lambda, fv.value("mcl_books:book") * fv.lambda), "a book keeps its λ")

-- At the 1-emerald floor guests turned away leave the factor be (ticket 22b).
local floor_keeper = {_id = "flo", _villages_keeper = true, _villages_prices = {["group:food"] = 0.05}}
dinner.settle(floor_keeper, nil, 1)
assert(dinner.price(floor_keeper) == 1)
dinner.turned(floor_keeper, "bo", 1)
dinner.settle(floor_keeper, nil, 2)
assert(dinner.factor(floor_keeper) == 1, "held at the floor")
-- Above it, the markdown as before.
floor_keeper._villages_prices = nil
dinner.turned(floor_keeper, "bo", 2)
dinner.settle(floor_keeper, nil, 3)
assert(near(dinner.factor(floor_keeper), dinner.MARKDOWN))

-- Demand (ticket 22c): meals served and guests it ran out on, each guest once, become
-- the next day's demand; a day with none, 0.
local busy = {_id = "busy", _villages_keeper = true}
dinner.settle(busy, nil, 10)
assert(dinner.demand(busy) == 0)
for _ = 1, 20 do dinner.served(busy, 10) end
for i = 1, 5 do dinner.ran_out(busy, 10, "g" .. i) end
dinner.ran_out(busy, 10, "g1")
dinner.ran_out(busy, 10)
assert(dinner.demand(busy) == 0, "not before the day is out")
dinner.settle(busy, nil, 11)
assert(dinner.demand(busy) == 25)
dinner.settle(busy, nil, 12)
assert(dinner.demand(busy) == 0)
dinner.served(nil, 12)

-- Amounts counted in dinners follow its reference price for one.
local cheap = villager("cheap", {[EMERALD] = 40}, {_villages_prices = {[dinner.ITEM] = 0.5}})
assert(near(dinner.scale(cheap), 0.5) and near(possessions.in_dinners(cheap, 40), 80))
-- The cushion: 40 emeralds when dinner is 9 is the money factor of 80 at 18.
local plain = villager("plain", {[EMERALD] = 80})
assert(near(possessions.assess(cheap).lambda, possessions.assess(plain).lambda))
assert(near(ledger.assess({money = 40, dinner = 9}).lambda, ledger.lambda(80)))
-- Savings: comforts and gifts start at half the emeralds.
assert(comforts.slots(possessions.in_dinners(cheap, comforts.SAVINGS / 2 + comforts.STEP / 2)) == 1)
assert(alms.donation(alms.SAVINGS, 0.5) > 0 and alms.donation(alms.SAVINGS, 1) == 0)

print("dinner.lua: ok")
