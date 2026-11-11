-- Run with: lua tests/market_news.lua
local now = 1000
local settings = {}
local logs = {}

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
}

local news = dofile("market_news.lua")

-- Fed villagers, so food is not every one's top need, each with something to spare.
local function villager(id, held, fields)
	local v = {_id = id, _profession = "nitwit", _villages_food = 12, _villages_belongings = held,
		_bed = {x = 0, y = 0, z = 0}}
	for k, value in pairs(fields or {}) do v[k] = value end
	return v
end

local function knows(v, who, kind, item)
	for _, entry in ipairs(news.heard(v, now)) do
		if entry.who == who and entry.kind == kind and (not item or entry.item == item) then return entry end
	end
	return nil
end

-- Its own news: its top needs and surpluses, hops 0, and never emeralds as surplus.
local ann = villager("ann", {["mcl_core:coal_lump"] = 40, ["mcl_core:emerald"] = 9})
local possessions = dofile("possessions.lua")
local own = news.own(ann, possessions.assess(ann), now)
local found_coal = false
for _, entry in ipairs(own) do
	assert(entry.who == "ann" and entry.hops == 0 and entry.heard == now)
	assert(entry.item ~= "mcl_core:emerald")
	if entry.kind == "has" and entry.item == "mcl_core:coal_lump" then found_coal = entry.count == 40 end
end
assert(found_coal, "its spare coal is news")

-- A surplus outside its top few is still told once it has heard someone needs it.
do
	local smith = villager("tess", {["mcl_tools:shovel_stone"] = 6, ["mcl_tools:axe_stone"] = 5,
		["mcl_tools:pick_stone"] = 4, ["mcl_farming:hoe_stone"] = 1})
	local function tells_hoe()
		for _, entry in ipairs(news.own(smith, possessions.assess(smith), now)) do
			if entry.kind == "has" and entry.item == "mcl_farming:hoe_stone" then return true end
		end
		return false
	end
	assert(not tells_hoe(), "a single hoe is outranked")
	smith._villages_market_news = {{item = "mcl_farming:hoe_stone", who = "fern", kind = "needs", count = 1,
		price = 100, heard = now, hops = 1}}
	assert(tells_hoe(), "told once someone needs it")
	smith._villages_market_news = nil
end

-- A finished conversation: each hears the other, one hop away, and nothing about itself.
math.randomseed(1)
local bob = villager("bob", {["mcl_farming:wheat_item"] = 50})
local kept = news.exchange({ann, bob})
assert(kept > 0 and logs[#logs]:find("market news"))
local heard = knows(bob, "ann", "has", "mcl_core:coal_lump")
assert(heard and heard.hops == 1 and heard.heard == now and heard.home.x == 0, "bob heard of ann's coal")
assert(knows(ann, "bob", "has", "mcl_farming:wheat_item"), "ann heard of bob's wheat")
assert(not knows(ann, "ann", "has") and not knows(bob, "bob", "has"), "never news of itself")
assert(#news.heard(bob, now) <= news.NEWS_SHARE)

-- Hearsay travels on, a hop further each time, and keeps when it was first told.
now = now + 10
local cy = villager("cy", {})
for _ = 1, 20 do news.exchange({bob, cy}) end
local relayed = knows(cy, "ann", "has", "mcl_core:coal_lump")
assert(relayed and relayed.hops == 2 and relayed.heard == 1000, "cy heard it from bob")

-- The listener keeps the freshest of the same news.
local dee = villager("dee", {}, {_villages_market_news = {
	{item = "mcl_core:coal_lump", who = "ann", kind = "has", count = 40, heard = 900, hops = 1},
}})
news.exchange({ann, dee})
assert(knows(dee, "ann", "has", "mcl_core:coal_lump").heard == now, "fresher replaces older")
dee._villages_market_news = {{item = "mcl_core:coal_lump", who = "ann", kind = "has", count = 40, heard = now + 5, hops = 3}}
assert(news.tell({{item = "mcl_core:coal_lump", who = "ann", kind = "has", count = 40, heard = now, hops = 0}},
	dee, nil, now) == 0, "older news does not replace fresher")

-- Interest: a listener short of food cares more for an offer of bread; fresh and near
-- news more than old and far.
local hungry = villager("eve", {}, {_villages_food = 0})
local view = possessions.assess(hungry)
local bread = {item = "mcl_farming:bread", who = "x", kind = "has", count = 6, heard = now, hops = 0}
local coal = {item = "mcl_core:coal_lump", who = "x", kind = "has", count = 6, heard = now, hops = 0}
assert(news.interest(view, bread, now) > news.interest(view, coal, now))
local far_bread = {item = "mcl_farming:bread", who = "x", kind = "has", count = 6, heard = now, hops = 3}
assert(news.interest(view, bread, now) > news.interest(view, far_bread, now))
local old_bread = {item = "mcl_farming:bread", who = "x", kind = "has", count = 6, heard = now - news.lifetime() / 2, hops = 0}
assert(news.interest(view, bread, now) > news.interest(view, old_bread, now))
-- One wanting what the listener has spare interests it too.
local wanting = {item = "mcl_core:coal_lump", who = "x", kind = "needs", count = 6, heard = now, hops = 0}
assert(news.interest(possessions.assess(ann), wanting, now) > news.interest(possessions.assess(ann), coal, now))
-- An offer that completes a trade it heard of interests a listener that wants neither:
-- it has heard a smith needs coal, so an offer of coal is news worth passing on.
do
	local known = news.wanted_and_had({{item = "mcl_core:coal_lump", who = "smith", kind = "needs", heard = now, hops = 1}})
	assert(news.interest(view, coal, now, known) > news.interest(view, coal, now))
	local seller_known = news.wanted_and_had({{item = "mcl_core:cobble", who = "q", kind = "has", heard = now, hops = 1}})
	local wants_cobble = {item = "mcl_core:cobble", who = "b", kind = "needs", count = 40, heard = now, hops = 0}
	assert(news.interest(view, wants_cobble, now, seller_known) > news.interest(view, wants_cobble, now))
	assert(news.interest(view, coal, now, seller_known) == news.interest(view, coal, now), "another item: no help")
end

-- Stale news is forgotten when next read.
now = now + news.lifetime() + 1
assert(#news.heard(cy, now) == 0 and cy._villages_market_news == nil)

-- No more than NEWS_ENTRIES, the least interesting going first.
local fay = villager("fay", {})
local many = {}
for i = 1, 40 do
	many[#many + 1] = {item = "mcl_core:item" .. i, who = "v" .. i, kind = "has", count = 1, heard = now, hops = i % 5}
end
for _ = 1, 10 do news.tell(many, fay, nil, now) end
assert(#fay._villages_market_news <= news.NEWS_ENTRIES)
for _, entry in ipairs(fay._villages_market_news) do assert(entry.hops <= 4) end

-- The inspector line.
assert(news.status(villager("gus", {})) == "nothing heard")
assert(news.status(fay):find("^%d+ heard; "))

-- Ticket 13: the first conversation of a day moves each member's prices from what it
-- heard and its own state, once a day, and the members' prices move toward each other's.
do
	local day = 30
	minetest.get_day_count = function() return day end
	local COAL = "mcl_core:coal_lump"
	local joe = villager("joe", {[COAL] = 64})
	local kim = villager("kim", {}, {_profession = "armorer"})
	news.exchange({joe, kim})
	local spare = joe._villages_prices and joe._villages_prices[COAL]
	assert(spare and spare < 1, "joe's spare coal is worth less to it")
	assert(kim._villages_prices and kim._villages_prices[COAL], "kim hears of it in passing")
	assert(joe._villages_prices_day == day and kim._villages_prices_day == day)
	local logged = false
	for _, line in ipairs(logs) do if line:find("prices: villager joe, day 30", 1, true) then logged = true end end
	assert(logged)
	-- Later the same day only the sharing moves it, toward kim's.
	local before = joe._villages_prices[COAL]
	news.exchange({joe, kim})
	assert(joe._villages_prices[COAL] > before and joe._villages_prices[COAL] < 1)
	minetest.get_day_count = nil
end

-- With the economy off nothing passes.
settings.living_villages_economy = false
local hal, ivy = villager("hal", {["mcl_core:coal_lump"] = 40}), villager("ivy", {})
assert(news.exchange({hal, ivy}) == 0 and ivy._villages_market_news == nil)

print("market_news.lua: ok")
