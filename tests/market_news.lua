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

-- A keeper notes every dish it hears offered (ticket 35); not a need, not a raw food, and
-- no one else.
do
	minetest.get_day_count = function() return 12 end
	local CHICKEN = "mcl_mobitems:cooked_chicken"
	local told = {
		{item = CHICKEN, who = "ann", kind = "has", count = 4, heard = now, hops = 0},
		{item = "mcl_fishing:salmon_cooked", who = "ann", kind = "needs", count = 4, heard = now, hops = 0},
		{item = "mcl_farming:potato_item", who = "ann", kind = "has", count = 4, heard = now, hops = 0},
	}
	local keeper = villager("kip", {}, {_villages_keeper = true})
	for _ = 1, 5 do news.tell(told, keeper, nil, now) end
	local known = keeper._villages_known_dishes
	assert(known and known[CHICKEN] == 12, "heard of chicken on day 12")
	assert(not known["mcl_fishing:salmon_cooked"] and not known["mcl_farming:potato_item"])
	local other = villager("oth", {})
	for _ = 1, 5 do news.tell(told, other, nil, now) end
	assert(other._villages_known_dishes == nil)
	minetest.get_day_count = nil
end

-- Anyone notes a good it hears offered that nothing here makes (ticket 39e); not one the
-- village makes, not a need.
do
	minetest.get_day_count = function() return 20 end
	local MUTTON, RABBIT = "mcl_mobitems:mutton", "mcl_mobitems:rabbit"
	local told = {
		{item = MUTTON, who = "ann", kind = "has", count = 3, heard = now, hops = 0},
		{item = RABBIT, who = "ann", kind = "needs", count = 3, heard = now, hops = 0},
		{item = "mcl_mobitems:beef", who = "ann", kind = "has", count = 3, heard = now, hops = 0},
	}
	local listener = villager("lis", {})
	for _ = 1, 5 do news.tell(told, listener, nil, now) end
	local heard = listener._villages_heard_offered
	assert(heard and heard[MUTTON] == 20, "heard mutton offered on day 20")
	assert(not heard[RABBIT] and not heard["mcl_mobitems:beef"])
	minetest.get_day_count = nil
end

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
	-- Coal is fuel, and a category's members share one factor (ticket 21b).
	local prices = dofile("prices.lua")
	local spare = prices.factor(joe._villages_prices, COAL)
	assert(spare < 1, "joe's spare coal is worth less to it")
	assert(prices.factor(kim._villages_prices, COAL) ~= 1, "kim hears of it in passing")
	assert(joe._villages_prices_day == day and kim._villages_prices_day == day)
	local logged = false
	for _, line in ipairs(logs) do if line:find("prices: villager joe, day 30", 1, true) then logged = true end end
	assert(logged)
	-- Later the same day only the sharing moves it, toward kim's.
	local before = prices.factor(joe._villages_prices, COAL)
	news.exchange({joe, kim})
	local after = prices.factor(joe._villages_prices, COAL)
	assert(after > before and after < 1)
	minetest.get_day_count = nil
end

-- With the economy off nothing passes.
-- Categories (ticket 15): a food need is told once, under the cheapest food per point,
-- and asks every food at its points' worth. A shepherd asked for string offers it.
do
	local APPLE, BREAD, STRING = "mcl_core:apple", "mcl_farming:bread", "mcl_mobitems:string"
	local values = {[APPLE] = 8, [BREAD] = 5, ["mcl_wool:grey"] = 2}
	local view = {
		needs = {[APPLE] = 3, [BREAD] = 2}, surplus = {["mcl_wool:grey"] = 5},
		group = {[APPLE] = "food", [BREAD] = "food"},
		value = function(item) return values[item] end,
	}
	-- With emeralds to cover its bid: a need is told at its value capped at its emeralds.
	local shepherd = villager("shep", {["mcl_core:emerald"] = 100}, {_profession = "shepherd"})
	local entries = news.own(shepherd, view, now)
	local food_needs, need = 0, nil
	for _, entry in ipairs(entries) do
		if entry.kind == "needs" then
			food_needs, need = food_needs + 1, entry
			assert(entry.group == "food" and entry.item == BREAD, entry.item)
		end
		assert(entry.item ~= STRING, "no string unasked")
	end
	assert(food_needs == 1)
	local asking = news.asking({need})
	local per = 5 / dofile("food.lua").POINTS[BREAD]
	assert(math.abs(asking[APPLE] - per * dofile("food.lua").POINTS[APPLE]) < 1e-9)
	-- Someone asked for string: it offers 4 a wool, at its ask for string (asks.lua), but
	-- never dearer than a quarter of its ask for the wool (asks.converted).
	shepherd._villages_market_news = {{item = STRING, who = "weaver", kind = "needs", count = 8, price = 1,
		heard = now, hops = 1}}
	local offered
	for _, entry in ipairs(news.own(shepherd, view, now)) do
		if entry.kind == "has" and entry.item == STRING then offered = entry end
	end
	assert(offered and offered.count == 20)
	local asks_mod = dofile("asks.lua")
	local via_wool = asks_mod.ask(shepherd, "mcl_wool:grey", view) / 4
	assert(via_wool < asks_mod.ask(shepherd, STRING, view), "the wool's quarter is the lower here")
	assert(math.abs(offered.price - via_wool) < 1e-9, offered.price)
	shepherd._villages_market_news = nil
end

-- A fisherman tells of its spare catch, though it values the cod at next to nothing and
-- the iron armour it was born with at far more (ColonyFood, 2026-11-13: the butcher never
-- heard of 16 cod).
do
	local fisher = villager("fisher", {["mcl_fishing:fish_raw"] = 16, ["mcl_armor:leggings_iron"] = 1,
		["mcl_armor:chestplate_iron"] = 1, ["mcl_armor:helmet_iron"] = 1, ["mcl_armor:boots_iron"] = 1},
		{_profession = "fisherman"})
	local told
	for _, entry in ipairs(news.own(fisher, possessions.assess(fisher), now)) do
		if entry.kind == "has" and entry.item == "mcl_fishing:fish_raw" then told = entry end
	end
	assert(told and told.count == 16, "its catch is news")
	assert(math.abs(told.price - dofile("asks.lua").ask(fisher, "mcl_fishing:fish_raw")) < 1e-9)
	-- A nitwit holding the same tells only its top three.
	local nitwit = villager("nit", {["mcl_fishing:fish_raw"] = 16, ["mcl_armor:leggings_iron"] = 1,
		["mcl_armor:chestplate_iron"] = 1, ["mcl_armor:helmet_iron"] = 1, ["mcl_armor:boots_iron"] = 1})
	local has = 0
	for _, entry in ipairs(news.own(nitwit, possessions.assess(nitwit), now)) do
		if entry.kind == "has" then has = has + 1 end
	end
	assert(has <= news.OWN_ITEMS, has)
end

-- A butcher tells of the beef it cooks, though vanilla trade wants nobody here makes
-- outrank it (ColonyFood, 2026-11-14: it never told of beef, never heard of the
-- leatherworker's 29, and laboured instead).
do
	local butcher = villager("butch", {["mcl_core:emerald"] = 40}, {_profession = "butcher"})
	local view = possessions.assess(butcher)
	assert(view.needs["mcl_mobitems:beef"], "beef is a need")
	local told, needs = false, 0
	for _, entry in ipairs(news.own(butcher, view, now)) do
		if entry.kind == "needs" then
			needs = needs + 1
			if entry.item == "mcl_mobitems:beef" then told = true end
		end
	end
	assert(told, "its recipe's beef is news")
	-- Its fuel too, under whichever member of fuel is cheapest per burn second; kelp blocks,
	-- vanilla's butcher's want, are fuel, so charcoal fills them (ColonyFood, 2026-11-14).
	local goods = dofile("goods.lua")
	assert(view.group["mcl_core:charcoal_lump"] == "fuel", "a fuel need")
	assert(not view.needs["mcl_ocean:dried_kelp_block"] or view.group["mcl_ocean:dried_kelp_block"] == "fuel",
		"kelp blocks are wanted as fuel, not as themselves")
	local fuel_told = false
	for _, entry in ipairs(news.own(butcher, view, now)) do
		if entry.kind == "needs" and entry.group == "fuel" then fuel_told = true end
	end
	assert(fuel_told, "its fuel is news")
	assert(goods.fills({item = "mcl_ocean:dried_kelp_block", group = "fuel"}, "mcl_core:charcoal_lump"))
	assert(needs <= 2 * news.OWN_ITEMS + 1, needs)
	assert(news.recipe_inputs({_profession = "butcher", _villages_keeper = true})["mcl_mobitems:beef"] == nil,
		"the keeper makes nothing of the butcher's")
end

-- The alchemist overhears (ticket 24): every loaded villager's own news, a hop away,
-- however many, past NEWS_ENTRIES; never its own, nor a child's.
do
	local crowd = {}
	for i = 1, 12 do
		crowd[i] = villager("v" .. i, {["mcl_core:cobble"] = 40 + i, ["mcl_core:tree"] = 20 + i})
	end
	crowd[#crowd + 1] = villager("kid", {["mcl_core:cobble"] = 50}, {child = true})
	local alch = villager("alch", {["mcl_core:emerald"] = 500},
		{_profession = "cleric", _villages_alchemist = true, _jobsite = {x = 0, y = 0, z = 0}})
	crowd[#crowd + 1] = alch
	minetest.get_day_count = function() return 7 end
	local kept = news.overhear(alch, crowd, now)
	local list = news.heard(alch, now)
	assert(kept == #list and #list > news.NEWS_ENTRIES and #list <= news.OVERHEAR_ENTRIES, #list)
	local cobble = knows(alch, "v12", "has", "mcl_core:cobble")
	assert(cobble and cobble.hops == 1 and cobble.count == 52, "it heard v12's cobble at first hand")
	assert(not knows(alch, "kid", "has") and not knows(alch, "alch", "has"), "no child, never itself")
	assert(alch._villages_prices_day ~= nil, "its prices make the day's move")
	local again, told_again = news.overhear(alch, crowd, now)
	assert(again == 0 and told_again == 0, "the same news again is nothing new")
	minetest.get_day_count = nil
end

-- They overhear the alchemist too (ticket 26a): it opens no stall and goes nowhere news is
-- told, so nobody heard of its nuggets (ColonyFood, day 694). Not a child; kept within
-- NEWS_ENTRIES.
do
	minetest.get_day_count = function() return 7 end
	local crowd = {}
	for i = 1, 4 do
		crowd[i] = villager("w" .. i, {["mcl_core:cobble"] = 40 + i})
	end
	local kid = villager("kid2", {}, {child = true})
	crowd[#crowd + 1] = kid
	local alch = villager("alch2", {["mcl_core:emerald"] = 5, ["mcl_core:iron_nugget"] = 63},
		{_profession = "cleric", _villages_alchemist = true, _jobsite = {x = 0, y = 0, z = 0}})
	crowd[#crowd + 1] = alch
	local own = news.own(alch, possessions.assess(alch), now)
	local spare = false
	for _, entry in ipairs(own) do
		if entry.kind == "has" and entry.item == "mcl_core:iron_nugget" then spare = true end
	end
	assert(spare, "its nuggets are its own news")
	local _, told = news.overhear(alch, crowd, now)
	assert(told > 0 and told % 4 == 0, told)
	for i = 1, 4 do
		local nugget = knows(crowd[i], "alch2", "has", "mcl_core:iron_nugget")
		assert(nugget and nugget.hops == 1, "w" .. i .. " heard of its nuggets at first hand")
		assert(#crowd[i]._villages_market_news <= news.NEWS_ENTRIES)
	end
	assert(kid._villages_market_news == nil, "a child hears nothing")
	minetest.get_day_count = nil
end

settings.living_villages_economy = false
local hal, ivy = villager("hal", {["mcl_core:coal_lump"] = 40}), villager("ivy", {})
assert(news.exchange({hal, ivy}) == 0 and ivy._villages_market_news == nil)

print("market_news.lua: ok")
