-- Run with: lua tests/market_stall.lua
local now, day = 1000, 10
local logs, objects = {}, {}

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
}

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	get_day_count = function() return day end,
	settings = {get = function() return nil end, get_bool = function(_, _, default) return default end},
	log = function(_, message) logs[#logs + 1] = message end,
	registered_items = {},
	add_particle = function() end,
	sound_play = function() end,
	get_objects_inside_radius = function(center, radius)
		local list = {}
		for _, object in ipairs(objects) do
			if vector.distance(object:get_pos(), center) <= radius then list[#list + 1] = object end
		end
		return list
	end,
}

local stall = dofile("market_stall.lua")
local possessions = dofile("possessions.lua")
local ledger = dofile("ledger.lua")
local EMERALD, BREAD, APPLE, COBBLE = "mcl_core:emerald", "mcl_farming:bread", "mcl_core:apple", "mcl_core:cobble"
local BANNER = stall.BANNER

local function logged(text)
	for _, line in ipairs(logs) do if line:find(text, 1, true) then return true end end
	return false
end
local function villager(id, held, pos, fields)
	local v = {name = "mobs_mc:villager", _id = id, _profession = "nitwit", _villages_food = 12, _villages_belongings = held}
	local object = {pos = pos or {x = 0, y = 0, z = 0}}
	function object:get_pos() return self.pos end
	function object:get_luaentity() return v end
	v.object = object
	for k, value in pairs(fields or {}) do v[k] = value end
	objects[#objects + 1] = object
	return v
end

-- A stall shows the seller's top spare goods it carries, by value.
local seller = villager("seller", {[BREAD] = 40, [APPLE] = 30, [COBBLE] = 10})
local goods = stall.goods(seller)
assert(goods and #goods == stall.STALL_ITEMS, "two goods")
local shown = {[goods[1]] = true, [goods[2]] = true}
assert(shown[BREAD] and shown[APPLE], "the spare goods worth most")
assert(stall.goods(villager("empty", {})) == nil, "nothing spare, nothing shown")
-- Spare goods it heard someone needs come first, whatever their value (ticket 12b).
seller._villages_market_news = {{item = COBBLE, kind = "needs", price = 3, count = 10, who = "mason",
	heard = now, hops = 1}}
goods = stall.goods(seller)
assert(goods[1] == COBBLE and (goods[2] == BREAD or goods[2] == APPLE), "the needed cobble, then by value")
seller._villages_market_news = nil

-- A banner: taken from belongings on opening, lasting BANNER_MARKETS markets.
assert(stall.open(seller, day) == false and seller._villages_stall_day == day, "no banner to fly")
-- Having kept a stall lately with none flying, it wants one, at no more than its price.
local view = possessions.assess(seller)
assert(view.targets[BANNER] == 1)
assert(view.value(BANNER) <= ledger.price(BANNER) + 1e-9)
possessions.add(seller, BANNER, 1)
assert(stall.open(seller, day) == true and possessions.count(seller, BANNER) == 0 and logged("hung a new banner"))
assert(seller._villages_banner_left == stall.BANNER_MARKETS - 1)
assert(not possessions.assess(seller).targets[BANNER], "one flying: no want")
for _ = 1, stall.BANNER_MARKETS - 1 do assert(stall.open(seller, day)) end
assert(seller._villages_banner_left == nil and stall.open(seller, day) == false, "worn out after its markets")
-- Long after its last stall it no longer wants one.
seller._villages_stall_day = day - stall.BANNER_DAYS - 1
assert(not possessions.assess(seller).targets[BANNER])
seller._villages_stall_day = nil

-- Browsers near buy what they need of the stall goods, once a stall day; one far off does not.
local hungry = villager("hungry", {[EMERALD] = 5 * ledger.SCALE}, {x = 2, y = 0, z = 0}, {_villages_food = 0})
local far = villager("far", {[EMERALD] = 5 * ledger.SCALE}, {x = 20, y = 0, z = 0}, {_villages_food = 0})
local made = stall.serve(seller, {BREAD, APPLE}, now, day)
assert(#made == 1 and made[1].buyer == hungry and possessions.count(hungry, BREAD) + possessions.count(hungry, APPLE) > 0)
assert(logged("market: villager hungry bought") and possessions.count(far, BREAD) == 0)
-- Not again so soon, nor again today.
assert(#stall.serve(seller, {BREAD, APPLE}, now + 1, day) == 0)
hungry._villages_food = 0
possessions.take(hungry, BREAD, possessions.count(hungry, BREAD))
possessions.take(hungry, APPLE, possessions.count(hungry, APPLE))
assert(#stall.serve(seller, {BREAD, APPLE}, now + stall.SERVE_SECONDS, day) == 0, "once a stall day")
assert(#stall.serve(seller, {BREAD, APPLE}, now + 2 * stall.SERVE_SECONDS, day + 1) == 1, "and again the next")
-- Another seller is no browser.
local other = villager("other", {[EMERALD] = 5 * ledger.SCALE}, {x = 1, y = 0, z = 1}, {_villages_food = 0, _villages_market_session = {}})
assert(#stall.serve(seller, {BREAD}, now + 3 * stall.SERVE_SECONDS, day + 2) == 1)
assert(possessions.count(other, BREAD) == 0)
-- One at its own stall browses its neighbours' (ticket 12b).
other._villages_market_session = {arrived = true}
assert(#stall.serve(seller, {BREAD}, now + 4 * stall.SERVE_SECONDS, day + 3) >= 1)
assert(possessions.count(other, BREAD) > 0, "a neighbouring seller buys")

-- A peddler buying wants its lot at its bid, and no more; holding it, it takes no less.
local peddler = villager("peddler", {[EMERALD] = 10 * ledger.SCALE}, nil,
	{_villages_peddle = {item = COBBLE, count = 8, bid = 3, sell_at = 6, day = day, buying = true}})
view = possessions.assess(peddler)
assert(view.needs[COBBLE] == 8 and view.value(COBBLE) == 3)
peddler._villages_peddle.buying = nil
possessions.add(peddler, COBBLE, 8)
view = possessions.assess(peddler)
assert(view.surplus[COBBLE] == 8 and view.value(COBBLE) == 3, "spare, at no less than its bid")
peddler._villages_peddle = nil
assert(possessions.assess(peddler).value(COBBLE) < 3, "a nitwit's own value for spare cobble is lower")

print("market_stall.lua: ok")
