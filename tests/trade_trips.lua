-- Run with: lua tests/trade_trips.lua
local now, day, time = 1000, 3, 6000 / 24000
local settings, logs, objects, chests = {}, {}, {}, {}
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	subtract = function(a, n) return {x = a.x - n, y = a.y - n, z = a.z - n} end,
	round = function(a) return {x = math.floor(a.x + 0.5), y = math.floor(a.y + 0.5), z = math.floor(a.z + 0.5)} end,
	add = function(a, n) return {x = a.x + n, y = a.y + n, z = a.z + n} end,
}

-- A chest's inventory: a list of {name, count} stacks, with add and remove by item string.
local function inventory(stacks)
	local function split(text)
		local name, count = text:match("^(%S+)%s*(%d*)")
		return name, tonumber(count) or 1
	end
	local inv = {stacks = stacks, size = 4}
	function inv:get_size() return self.size end
	function inv:get_list()
		local list = {}
		for _, s in ipairs(self.stacks) do
			list[#list + 1] = {
				get_name = function() return s.name end, get_count = function() return s.count end,
				is_empty = function() return s.count == 0 end,
			}
		end
		return list
	end
	function inv:add_item(_, text)
		local name, count = split(text)
		for _, s in ipairs(self.stacks) do
			if s.name == name then s.count = s.count + count return {get_count = function() return 0 end} end
		end
		if #self.stacks >= self.size then return {get_count = function() return count end} end
		self.stacks[#self.stacks + 1] = {name = name, count = count}
		return {get_count = function() return 0 end}
	end
	function inv:remove_item(_, text)
		local name, count = split(text)
		for _, s in ipairs(self.stacks) do
			if s.name == name then
				local taken = math.min(s.count, count)
				s.count = s.count - taken
				return {get_count = function() return taken end}
			end
		end
		return {get_count = function() return 0 end}
	end
	return inv
end
local function chest(pos, owner, stacks)
	chests[key(pos)] = {owner = owner, inv = inventory(stacks or {})}
	return pos
end
local function chest_count(pos, item)
	local total = 0
	for _, s in ipairs(chests[key(pos)].inv.stacks) do
		if s.name == item then total = total + s.count end
	end
	return total
end

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	get_day_count = function() return day end,
	get_timeofday = function() return time end,
	is_protected = function() return false end,
	settings = {
		get = function(_, name) return settings[name] end,
		get_bool = function(_, name, default)
			if settings[name] == nil then return default end
			return settings[name]
		end,
	},
	log = function(_, message) logs[#logs + 1] = message end,
	pos_to_string = function(p) return "(" .. key(p) .. ")" end,
	registered_items = {},
	add_particle = function() end,
	sound_play = function() end,
	get_node_or_nil = function(pos)
		if chests[key(pos)] then return {name = "mcl_chests:chest_small"} end
		return {name = "air"}
	end,
	get_meta = function(pos)
		local c = chests[key(pos)] or {inv = inventory({})}
		return {
			get_string = function(_, k) return k == "villages_owner" and (c.owner or "") or "" end,
			get_inventory = function() return c.inv end,
		}
	end,
	find_nodes_in_area = function(minp, maxp, names)
		local found = {}
		local wants_chests = false
		for _, name in ipairs(type(names) == "table" and names or {names}) do
			if tostring(name):find("chest") then wants_chests = true end
		end
		if not wants_chests then return found end
		for k in pairs(chests) do
			local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
			local p = {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
			if p.x >= minp.x and p.x <= maxp.x and p.y >= minp.y and p.y <= maxp.y and p.z >= minp.z and p.z <= maxp.z then
				found[#found + 1] = p
			end
		end
		return found
	end,
	get_objects_inside_radius = function(pos, radius)
		local found = {}
		for _, object in ipairs(objects) do
			if vector.distance(object:get_pos(), pos) <= radius then found[#found + 1] = object end
		end
		return found
	end,
}

local trips = dofile("trade_trips.lua")
local possessions = dofile("possessions.lua")
local market = dofile("builder_market.lua")
local stock = dofile("farm_stock.lua")

local COBBLE, EMERALD = "mcl_core:cobble", "mcl_core:emerald"

local function villager(id, at, fields)
	local pos = vector.new(at)
	local v = {name = "mobs_mc:villager", _id = id, _profession = "nitwit", _villages_food = 20, state = "stand",
		_bed = vector.new(at), walks = {}}
	for k, value in pairs(fields or {}) do v[k] = value end
	v.object = {get_pos = function() return pos end, get_luaentity = function() return v end}
	v.gopath = function(self, target, callbacks)
		self.walks[#self.walks + 1] = vector.new(target)
		self.arrive = function()
			pos = vector.new(target)
			callbacks.arrived(self)
		end
		self.lose = function(reason) callbacks.lost(self, reason) end
		return true
	end
	v.teleport = function(p) pos = vector.new(p) end
	objects[#objects + 1] = v.object
	return v
end
local function count(v, item) return possessions.count(v, item) end
local function has_news(who, item, home, price)
	return {item = item, who = who, kind = "has", count = 40, price = price, home = home, heard = now, hops = 1}
end

-- Terms: at the seller's ask, whole emeralds, at least one, the buyer valuing it at least
-- the ask, within the budget.
do
	local n, pay = trips.terms(100, 40, 0.12, 0.04, 8)
	assert(n == 40 and pay == 2, n .. " " .. pay) -- 40 * 0.04 = 1.6
	n, pay = trips.terms(5, 40, 0.12, 0.04, 8)
	assert(n == 25 and pay == 1, "a sale under one emerald grows to the fewest items that make one")
	n, pay = trips.terms(100, 40, 0.12, 0.04, 1)
	assert(n == 25 and pay == 1, "cut to the budget")
	assert(trips.terms(10, 40, 0.04, 0.05, 8) == nil, "the buyer must value it at the ask")
	assert(trips.terms(10, 40, 0.05, 0.05, 8), "valuing it at the ask is enough")
	assert(trips.terms(10, 0, 0.12, 0.04, 8) == nil and trips.terms(10, 40, 0.12, 0.04, 0) == nil)
end

-- The Builder short of cobble: its wants come from the materials report, it stows what it
-- bought into its pouch, and takes a purse from its chests.
-- Five vanilla emeralds at the economy's scale (ticket 11h).
local bench_chest = chest({x = 0, y = 1, z = 2}, nil, {{name = EMERALD, count = 320}})
local bob = villager("bob-builder", {x = 0, y = 1, z = 0},
	{_profession = "mason", _villages_builder = true, _jobsite = {x = 0, y = 1, z = 1}, _villages_belongings = {}})
local function report(missing)
	return {
		rows = {
			{item = COBBLE, need = 200, in_chests = 0, carried = stock.count(bob, COBBLE), missing = missing},
			{item = "mcl_core:stonebrick", need = 10, in_chests = 0, carried = 0, missing = 10},
		},
		short = true, chests = {bench_chest},
	}
end
market.update(bob, report(200))
assert(bob._villages_builder_wants[COBBLE] == 200 and bob._villages_builder_wants["mcl_core:stonebrick"] == nil,
	"an unpriced material is no want: a player must bring it")
assert(bob._villages_builder_drop.z == 2 and count(bob, EMERALD) == 320 and chest_count(bench_chest, EMERALD) == 0)
assert(logs[#logs]:find("took 320 emerald"))
local view = possessions.assess(bob)
assert(view.needs[COBBLE] == 200 and trips.urgency(view, COBBLE) >= trips.URGENT)
assert(market.status(bob) == "200 cobble")

-- A quarrier 20 east has cobble spare; the Builder has heard so. It plans the trip...
local quinn = villager("quinn-quarrier", {x = 20, y = 1, z = 0}, {_villages_belongings = {[COBBLE] = 64}})
local heard = {has_news("quinn-quarrier", COBBLE, {x = 20, y = 1, z = 0}, 0.03)}
local trip = trips.plan(bob, view, heard, bob._bed)
assert(trip and trip.item == COBBLE and trip.who == "quinn-quarrier" and trip.want == 200 and trip.leg == "seller")
-- ...but not to a seller too far, or asking more than it values the cobble, or itself.
assert(trips.plan(bob, view, {has_news("far", COBBLE, {x = 200, y = 1, z = 0}, 0.03)}, bob._bed) == nil)
assert(trips.plan(bob, view, {has_news("dear", COBBLE, {x = 20, y = 1, z = 0}, 100)}, bob._bed) == nil)
assert(trips.plan(bob, view, {has_news("bob-builder", COBBLE, {x = 20, y = 1, z = 0}, 0.03)}, bob._bed) == nil)
-- At the economy's scale one cobble is worth whole emeralds, so a seller with one is a
-- trip (ticket 11h; at vanilla's prices it came to under one, run 34)...
local few = has_news("few", COBBLE, {x = 20, y = 1, z = 0}, 0.03)
few.count = 1
assert(trips.plan(bob, view, {few}, bob._bed), "one cobble is a sale")
-- ...but a seller it cannot make a sale with is passed over, and logged once a day.
do
	local purse = bob._villages_belongings[EMERALD]
	bob._villages_belongings[EMERALD] = nil
	assert(trips.plan(bob, view, {few}, bob._bed) == nil, "no sale without an emerald")
	assert(logs[#logs]:find("passes over few's mcl_core:cobble: heard 1 spare %(carries unknown now%)"), logs[#logs])
	local n = #logs
	trips.plan(bob, view, {few}, bob._bed)
	assert(#logs == n, "once a day")
	bob._villages_belongings[EMERALD] = purse
end

-- In its work stage, while short, it goes: walks to the quarrier's home and buys in person.
time = 9000 / 24000
bob._villages_market_news = heard
-- Not with an empty purse: it could buy nothing there.
bob._villages_belongings[EMERALD] = nil
trips.step(bob, now - trips.PLAN_SECONDS - 1)
assert(not bob._villages_trade_trip and #bob.walks == 0, "no trip without an emerald")
bob._villages_belongings[EMERALD] = 320
trips.step(bob, now)
assert(bob._villages_trade_trip and #bob.walks == 1 and bob.walks[1].x == 20, "walks to the quarrier")
assert(logs[#logs - 0] and table.concat(logs, "\n"):find("sets off for 200 mcl_core:cobble from quinn%-"))
trips.step(bob, now + 2)
assert(#bob.walks == 1, "waits for the walk")
-- A lost walk is walked again on the next step; if no walk can start, the reason says why.
bob.lose("taken over by another mover")
trips.step(bob, now + 3)
assert(#bob.walks == 2 and bob._villages_trade_trip.tries == 2, "walks again after a lost walk")
bob.arrive()
trips.step(bob, now + 4)
local bought = count(bob, COBBLE)
assert(bought > 0 and count(quinn, COBBLE) == 64 - bought and count(quinn, EMERALD) > 0, "bought in person")
assert(bob._villages_trade_trip == nil, "done")
assert(table.concat(logs, "\n"):find("trade: villager quinn%- sold"))
-- Back at the bench its next check stows the cobble where the bill counts it, and wants less.
market.update(bob, report(200 - stock.count(bob, COBBLE)))
assert(count(bob, COBBLE) == 0 and stock.count(bob, COBBLE) == bought)
assert(bob._villages_builder_wants[COBBLE] == 200 - bought, "wants what is still missing")

-- Nobody home: on to the seller's stash, and it buys from the chest, paying into it.
do
	local away = villager("ada-away", {x = 0, y = 1, z = 30})
	away.teleport({x = 100, y = 1, z = 100})
	local stash = chest({x = 6, y = 1, z = 30}, "ada-away", {{name = COBBLE, count = 50}})
	local before = count(bob, EMERALD)
	bob._villages_market_news = {has_news("ada-away", COBBLE, {x = 0, y = 1, z = 30}, 0.03)}
	bob.walks = {}
	now = now + 100
	trips.step(bob, now)
	assert(#bob.walks == 1 and bob.walks[1].z == 30)
	bob.arrive()
	trips.step(bob, now + 2)
	assert(bob._villages_trade_trip.leg == "stash" and #bob.walks == 2 and bob.walks[2].x == 6, "to the stash")
	bob.arrive()
	trips.step(bob, now + 4)
	local got = count(bob, COBBLE)
	assert(got > 0 and chest_count(stash, COBBLE) == 50 - got)
	assert(chest_count(stash, EMERALD) == before - count(bob, EMERALD) and chest_count(stash, EMERALD) >= 1)
	assert(table.concat(logs, "\n"):find("bought %d+ mcl_core:cobble from ada%-aw's stash"))
	assert(bob._villages_trade_trip == nil)
end

-- At the end of each leg it goes on, though the walk never reported arriving.
do
	local away = villager("cal-callback", {x = 0, y = 1, z = 40})
	away.teleport({x = 100, y = 1, z = 100})
	local stash = chest({x = 6, y = 1, z = 40}, "cal-callback", {{name = COBBLE, count = 50}})
	bob._villages_market_news = {has_news("cal-callback", COBBLE, {x = 0, y = 1, z = 40}, 0.03)}
	bob._villages_belongings[EMERALD] = 2 * 64
	bob.walks = {}
	now = now + 100
	trips.step(bob, now)
	assert(#bob.walks == 1 and bob.walks[1].z == 40)
	bob.teleport({x = 1, y = 1, z = 40})
	trips.step(bob, now + 2)
	assert(bob._villages_trade_trip.leg == "stash" and #bob.walks == 2, "on to the stash")
	bob.teleport({x = 6, y = 1, z = 41})
	trips.step(bob, now + 4)
	assert(bob._villages_trade_trip == nil and chest_count(stash, COBBLE) < 50, "bought from the stash")
end

-- Out, but about: it goes after the seller where it stands, and buys there.
do
	local roy = villager("roy-roaming", {x = -40, y = 1, z = 0}, {_villages_belongings = {[COBBLE] = 64}})
	roy.teleport({x = -40, y = 1, z = 20})
	possessions.add(bob, EMERALD, 3 * 64)
	bob._villages_builder_wants = {[COBBLE] = count(bob, COBBLE) + 120}
	bob._villages_market_news = {has_news("roy-roaming", COBBLE, {x = -40, y = 1, z = 0}, 0.03)}
	bob.walks = {}
	now = now + 100
	trips.step(bob, now)
	assert(#bob.walks == 1 and bob.walks[1].x == -40 and bob.walks[1].z == 0, "to its home first")
	bob.arrive()
	trips.step(bob, now + 2)
	assert(bob._villages_trade_trip.leg == "chase" and bob.walks[2].z == 20, "then where it is")
	-- It moves on before it is caught: the walk is aimed afresh, as another chase.
	roy.teleport({x = -40, y = 1, z = 40})
	trips.step(bob, now + 3)
	assert(#bob.walks == 3 and bob.walks[3].z == 40 and bob._villages_trade_trip.chases == 2, "after it")
	local before = count(bob, COBBLE)
	bob.arrive()
	trips.step(bob, now + 4)
	assert(count(bob, COBBLE) > before and bob._villages_trade_trip == nil, "caught and bought")
	assert(count(roy, COBBLE) < 64)
end

-- An empty stash or none: it gives up and passes that seller over for a while.
do
	local carl = villager("carl", {x = -10, y = 1, z = 0}, {_villages_belongings = {[EMERALD] = 5 * 64}, _villages_food = 0})
	carl.teleport({x = -300, y = 1, z = 0})
	local hungry = villager("hal", {x = 0, y = 1, z = -10}, {_villages_belongings = {[EMERALD] = 5 * 64}, _villages_food = 0})
	hungry._villages_market_news = {has_news("carl", "mcl_farming:bread", {x = -10, y = 1, z = 0}, 0.1)}
	time = 6000 / 24000
	trips.step(hungry, now)
	assert(hungry._villages_trade_trip, "putter: hungry, it goes for bread")
	hungry.arrive()
	trips.step(hungry, now + 2)
	assert(hungry._villages_trade_trip == nil and logs[#logs]:find("gave up on mcl_farming:bread from carl: nobody home"))
	assert(trips.plan(hungry, possessions.assess(hungry), hungry._villages_market_news, hungry._bed) == nil, "skipped")
	now = now + trips.SKIP_SECONDS + 1
	assert(trips.plan(hungry, possessions.assess(hungry), hungry._villages_market_news, hungry._bed), "for a while")
	-- Outside the putter stage a villager that is no Builder does not go.
	time = 9000 / 24000
	hungry._villages_trade_trip = nil
	trips.step(hungry, now + 100)
	assert(hungry._villages_trade_trip == nil)
end

-- An empty stash (ticket 12b): the news of its spare is forgotten and the seller passed
-- over for a game day, not the usual while.
do
	local stash = chest({x = -20, y = 1, z = 2}, "cid", {})
	local cid = villager("cid", {x = -20, y = 1, z = 0}, {_villages_belongings = {[EMERALD] = 64}, _villages_stash = stash})
	cid.teleport({x = -300, y = 1, z = 0})
	local hungry = villager("hil", {x = 0, y = 1, z = -10}, {_villages_belongings = {[EMERALD] = 5 * 64}, _villages_food = 0})
	local heard = has_news("cid", "mcl_farming:bread", {x = -20, y = 1, z = 0}, 0.1)
	hungry._villages_market_news = {heard}
	time = 6000 / 24000
	trips.step(hungry, now)
	assert(hungry._villages_trade_trip, "it goes for bread")
	hungry.arrive()
	trips.step(hungry, now + 2)
	assert(hungry._villages_trade_trip == nil and logs[#logs]:find("nothing to buy in the stash"),
		"nobody home, and the stash beside its home is empty")
	assert(hungry._villages_market_news == nil, "what it heard of cid's bread is forgotten")
	hungry._villages_market_news = {heard}
	assert(trips.plan(hungry, possessions.assess(hungry), {heard}, hungry._bed) == nil, "heard again, still skipped")
	now = now + trips.SKIP_SECONDS + 1
	assert(trips.plan(hungry, possessions.assess(hungry), {heard}, hungry._bed) == nil, "past the usual while")
	now = now + trips.EMPTY_SKIP_SECONDS
	assert(trips.plan(hungry, possessions.assess(hungry), {heard}, hungry._bed), "a day later it tries again")
end

-- Porters: hired at the end of a conversation by a member with a job and an urgent need,
-- with a purse; it buys at the client's value, delivers the goods and the change, and
-- keeps its fee.
do
	local smith_stash = chest({x = 50, y = 1, z = 2}, "sam-smith", {})
	local sam = villager("sam-smith", {x = 50, y = 1, z = 0}, {_profession = "tool_smith",
		_jobsite = {x = 51, y = 1, z = 0}, _villages_stash = smith_stash,
		_villages_belongings = {[EMERALD] = 6 * 64}})
	local coal_seller = villager("cole", {x = 70, y = 1, z = 0},
		{_villages_belongings = {["mcl_core:coal_lump"] = 40}})
	sam._villages_market_news = {has_news("cole", "mcl_core:coal_lump", {x = 70, y = 1, z = 0}, 0.04)}
	local pat = villager("pat-porter", {x = 50, y = 1, z = 1}, {_villages_belongings = {},
		_villages_labour = {day = day, activity = "porter"}})
	local idler = villager("ida", {x = 50, y = 1, z = 1}, {_villages_belongings = {[EMERALD] = 9 * 64}})
	local hires = trips.hire({pat, sam, idler})
	assert(#hires == 1 and hires[1].client == sam and pat._villages_trade_trip.client.id == "sam-smith")
	local purse = pat._villages_trade_trip.client.purse
	assert(purse == 384 and count(sam, EMERALD) == 0 and count(pat, EMERALD) == 384)
	assert(logs[#logs]:find("hired porter pat%-po with 384 emerald"))
	-- A second porter finds nobody left to hire it.
	local pia = villager("pia", {x = 50, y = 1, z = 1}, {_villages_labour = {day = day, activity = "porter"}})
	assert(#trips.hire({pia, sam}) == 0)
	-- Its work stage: to the seller, buy, back to the smith's stash.
	time = 9000 / 24000
	trips.step(pat, now)
	assert(#pat.walks == 1 and pat.walks[1].x == 70)
	pat.arrive()
	trips.step(pat, now + 2)
	local coal = count(pat, "mcl_core:coal_lump")
	assert(coal > 0 and pat._villages_trade_trip.leg == "deliver", "bought, now delivering")
	trips.step(pat, now + 4)
	assert(pat.walks[2].z == 2, "to the stash")
	pat.arrive()
	trips.step(pat, now + 6)
	assert(pat._villages_trade_trip == nil and chest_count(smith_stash, "mcl_core:coal_lump") == coal)
	local spent = count(coal_seller, EMERALD)
	assert(chest_count(smith_stash, EMERALD) == purse - spent - trips.PORTER_FEE, "the change, less the fee")
	assert(count(pat, EMERALD) == trips.PORTER_FEE and count(pat, "mcl_core:coal_lump") == 0)
	assert(logs[#logs]:find("porter pat%-po delivered"))
end

-- A porter whose trip fails brings the whole purse back, and keeps no fee.
do
	local stash = chest({x = -50, y = 1, z = 2}, "lib", {})
	local lib = villager("lib", {x = -50, y = 1, z = 0}, {_profession = "librarian",
		_jobsite = {x = -51, y = 1, z = 0}, _villages_stash = stash, _villages_belongings = {[EMERALD] = 4 * 64}})
	lib._villages_market_news = {has_news("gone", "mcl_core:paper", {x = -70, y = 1, z = 0}, 0.01)}
	local por = villager("por", {x = -50, y = 1, z = 1}, {_villages_labour = {day = day, activity = "porter"}})
	assert(#trips.hire({por, lib}) == 1)
	trips.step(por, now)
	por.arrive()
	trips.step(por, now + 2)
	assert(por._villages_trade_trip.leg == "deliver", "nobody home, nothing to buy: back")
	trips.step(por, now + 4)
	por.arrive()
	trips.step(por, now + 6)
	assert(chest_count(stash, EMERALD) == 4 * 64 and count(por, EMERALD) == 0)
	-- An own trip lasts into the next day's work stage, not called back to the jobsite;
	-- one from the day before that is dropped.
	local own = villager("own", {x = 0, y = 1, z = 0}, {_villages_belongings = {[EMERALD] = 2 * 64}})
	own._villages_trade_trip = {item = COBBLE, who = "x", home = {x = 1, y = 1, z = 40}, want = 1, leg = "seller", day = day - 1}
	assert(trips.activity_override(own, "work") == "putter" and trips.activity_override(own, "putter") == nil)
	trips.step(own, now)
	assert(own._villages_trade_trip and own.walks[1].z == 40, "yesterday's trip goes on in the work stage")
	own._villages_trade_trip.day = day - 2
	trips.step(own, now + 200)
	assert(own._villages_trade_trip == nil and logs[#logs]:find("dropped an unfinished trip"), "then it is dropped")
	assert(trips.activity_override(own, "work") == nil, "back to work")
	own._villages_trade_trip, own._villages_builder = {}, {}
	assert(trips.activity_override(own, "work") == nil, "the Builder has its own")
end

-- A farmer with no hoe plans a trip to a tool smith that has one, though the hoe is worth
-- under URGENT times its price (wants.lua caps it at what it brings): run 46.
do
	local HOE = "mcl_farming:hoe_stone"
	local ledger = dofile("ledger.lua")
	local fern = villager("fern-farmer", {x = 0, y = 1, z = 0},
		{_profession = "farmer", _villages_belongings = {[EMERALD] = 200}})
	local fern_view = possessions.assess(fern)
	assert(fern_view.needs[HOE] == 1)
	assert(fern_view.value(HOE) < trips.URGENT * ledger.price(HOE), "capped below URGENT")
	assert(trips.urgency(fern_view, HOE) >= trips.URGENT)
	local hoe_news = has_news("tess-smith", HOE, {x = 15, y = 1, z = 0}, ledger.price(HOE) * 0.6)
	hoe_news.count = 1
	local hoe_trip = trips.plan(fern, fern_view, {hoe_news}, fern._bed)
	assert(hoe_trip and hoe_trip.item == HOE and hoe_trip.who == "tess-smith", "a trip for the hoe")
end

-- Off with the economy: no hire.
settings.living_villages_economy = false
assert(#trips.hire({}) == 0)

print("trade_trips.lua: ok")
