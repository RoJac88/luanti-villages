-- Run with: lua tests/trade_trips.lua
local now, day, time = 1000, 3, 6000 / 24000
local settings, logs, objects, chests, nodes = {}, {}, {}, {}, {}
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
	-- Ground at y 0 and below; farmland (15/16 high, mcl_farming) where a test puts it.
	registered_nodes = {
		air = {walkable = false},
		["mcl_core:stone"] = {walkable = true},
		["mcl_farming:soil"] = {walkable = true, drawtype = "nodebox",
			node_box = {type = "fixed", fixed = {{-0.5, -0.5, -0.5, 0.5, 0.4375, 0.5}}}},
		["mcl_chests:chest_small"] = {walkable = true},
	},
	get_item_group = function() return 0 end,
	add_particle = function() end,
	sound_play = function() end,
	get_node_or_nil = function(pos)
		if chests[key(pos)] then return {name = "mcl_chests:chest_small"} end
		if nodes[key(pos)] then return {name = nodes[key(pos)]} end
		return {name = pos.y <= 0 and "mcl_core:stone" or "air"}
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
local ledger = dofile("ledger.lua")
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
		if self.refuse and self.refuse(target) then return false end
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
-- Prices in the news are given at vanilla's scale and told at the economy's (ticket 11h).
local function has_news(who, item, home, price)
	return {item = item, who = who, kind = "has", count = 40, price = price and price * 64, home = home, heard = now, hops = 1}
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
-- ...or to one whose goods are for the keeper alone (tavern_duty.lua, ticket 48a), unless it
-- is the keeper; nor buys them from that one's stash.
local only = has_news("quinn-quarrier", COBBLE, {x = 20, y = 1, z = 0}, 0.03)
only.keeper_only = true
assert(trips.plan(bob, view, {only}, bob._bed) == nil)
bob._villages_keeper = true
local keeper_trip = trips.plan(bob, view, {only}, bob._bed)
assert(keeper_trip and keeper_trip.keeper_only)
bob._villages_keeper = nil
assert(trips.buy_from_stash(bob, keeper_trip, {x = 20, y = 1, z = 0}) == 0)
-- At the economy's scale one cobble is worth whole emeralds, so a seller with one is a
-- trip (ticket 11h; at vanilla's prices it came to under one, run 34)...
local few = has_news("few", COBBLE, {x = 20, y = 1, z = 0}, 0.03)
few.count = 1
assert(trips.plan(bob, view, {few}, bob._bed), "one cobble is a sale")
-- Weighed by what it could bring back (ticket 50): a farther seller with forty goes before a
-- nearer one with one.
do
	local many = has_news("many", COBBLE, {x = 30, y = 1, z = 0}, 0.03)
	local pick = trips.plan(bob, view, {few, many}, bob._bed)
	assert(pick and pick.who == "many", pick and pick.who)
end
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

-- A seller in its field stands on farmland, 15/16 high: it is walked to at the cell it
-- stands in, not into the soil its rounded position is in (ColonyFood, 2026-11-14: every
-- chase after a farmer failed "no way there").
do
	local fay = villager("fay-farmer", {x = 50, y = 1, z = 0}, {_villages_belongings = {[COBBLE] = 64}})
	nodes[key({x = 50, y = 1, z = 20})] = "mcl_farming:soil"
	fay.teleport({x = 50, y = 1.4475, z = 20})
	possessions.add(bob, EMERALD, 3 * 64)
	bob._villages_builder_wants = {[COBBLE] = count(bob, COBBLE) + 1000}
	bob._villages_market_news = {has_news("fay-farmer", COBBLE, {x = 50, y = 1, z = 0}, 0.03)}
	bob.walks = {}
	now = now + 100
	trips.step(bob, now)
	bob.arrive()
	trips.step(bob, now + 2)
	local aim = bob.walks[2]
	assert(bob._villages_trade_trip.leg == "chase" and aim.x == 50 and aim.z == 20, "after it in its field")
	assert(aim.y == 2, "at the cell above the soil, not the soil: y " .. aim.y)
	bob.arrive()
	trips.step(bob, now + 4)
	assert(bob._villages_trade_trip == nil and count(fay, COBBLE) < 64, "caught and bought")
end

-- A walk that cannot start is not the end of the trip: from the seller's home it goes
-- after the seller, and from there to its stash. Only a stash it cannot reach ends it.
do
	local function plan_to(who, home)
		bob._villages_builder_wants = {[COBBLE] = count(bob, COBBLE) + 1000}
		bob._villages_market_news = {has_news(who, COBBLE, home, 0.03)}
		possessions.add(bob, EMERALD, 3 * 64)
		bob.walks = {}
		now = now + 100
	end
	-- Its home walled in: it goes after the seller where it is, and buys there.
	local hal = villager("hal-walled", {x = 30, y = 1, z = -30}, {_villages_belongings = {[COBBLE] = 64}})
	hal.teleport({x = 30, y = 1, z = -15})
	plan_to("hal-walled", {x = 30, y = 1, z = -30})
	bob.refuse = function(target) return target.z == -30 end
	trips.step(bob, now)
	assert(bob._villages_trade_trip.leg == "chase" and bob.walks[2].z == -15, "no way home: after the seller")
	assert(table.concat(logs, "\n"):find("cannot reach hal%-wa's home %(no way there%)"))
	bob.arrive()
	trips.step(bob, now + 2)
	assert(bob._villages_trade_trip == nil and count(hal, COBBLE) < 64, "caught and bought")
	-- Neither the seller's home nor the seller reachable: on to its stash.
	local ivy = villager("ivy-island", {x = -30, y = 1, z = -30})
	ivy.teleport({x = -30, y = 1, z = -15})
	local stash = chest({x = -26, y = 1, z = -28}, "ivy-island", {{name = COBBLE, count = 50}})
	plan_to("ivy-island", {x = -30, y = 1, z = -30})
	bob.refuse = function(target) return target.x == -30 end
	trips.step(bob, now)
	assert(bob._villages_trade_trip.leg == "stash" and bob.walks[3].x == -26, "on to the stash")
	bob.arrive()
	trips.step(bob, now + 2)
	assert(bob._villages_trade_trip == nil and chest_count(stash, COBBLE) < 50, "bought from the stash")
	-- Not even the stash: the trip is over, and that seller passed over for a while.
	local jo = villager("jo-nowhere", {x = 0, y = 1, z = -50})
	jo.teleport({x = 400, y = 1, z = 0})
	chest({x = 4, y = 1, z = -48}, "jo-nowhere", {{name = COBBLE, count = 50}})
	plan_to("jo-nowhere", {x = 0, y = 1, z = -50})
	bob.refuse = function(target) return target.z <= -48 end
	trips.step(bob, now)
	assert(bob._villages_trade_trip == nil and logs[#logs]:find("gave up on mcl_core:cobble from jo%-now"), logs[#logs])
	bob.refuse = nil
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
	-- The alchemist plans one in its work stage too (ticket 24): it has no putter time.
	local alch = villager("alc", {x = 0, y = 1, z = -12}, {_profession = "cleric", _villages_alchemist = true,
		_villages_belongings = {[EMERALD] = 5 * 64}})
	alch._villages_market_news = {has_news("quinn", COBBLE, {x = -10, y = 1, z = 4}, 0.01)}
	trips.step(alch, now + 100)
	assert(alch._villages_trade_trip and alch._villages_trade_trip.item == COBBLE, "the alchemist goes for cobble")
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
	sam._villages_market_news = {has_news("cole", "mcl_core:coal_lump", {x = 70, y = 1, z = 0}, dofile("ledger.lua").price("mcl_core:coal_lump") / 64)}
	local pat = villager("pat-porter", {x = 50, y = 1, z = 1}, {_villages_belongings = {},
		_villages_labour = {day = day, activity = "porter"}})
	local idler = villager("ida", {x = 50, y = 1, z = 1}, {_villages_belongings = {[EMERALD] = 9 * 64}})
	local hires = trips.hire({pat, sam, idler})
	assert(#hires == 1 and hires[1].client == sam and pat._villages_trade_trip.client.id == "sam-smith")
	-- The purse is the lot at the client's value, or the price heard with some slack if
	-- that is less, and the fee: not all it has (ColonyFood, 2026-11-14: 512 sent for
	-- one poppy).
	local trip = pat._villages_trade_trip
	local purse = trip.client.purse
	assert(purse == trips.purse_for(trip, trip.client.value), purse)
	assert(purse <= math.ceil(trip.want * trip.client.value) + trips.PORTER_FEE)
	assert(purse < 384 and count(sam, EMERALD) == 384 - purse and count(pat, EMERALD) == purse)
	assert(logs[#logs]:find("hired porter pat%-po with " .. purse .. " emerald"))
	assert(trips.purse_for({want = 1000}, 10) == trips.PURSE, "at most PURSE")
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
	assert(chest_count(stash, EMERALD) + count(lib, EMERALD) == 4 * 64 and count(por, EMERALD) == 0)
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

-- A porter at a full chest hands what does not fit to the client in person, if it is
-- about (ColonyFood, 2026-11-19: a commissioned armor stand and its price both kept).
do
	local STAND = "mcl_armor_stand:armor_stand"
	local stuffed = {{name = "a", count = 1}, {name = "b", count = 1}, {name = "c", count = 1}, {name = "d", count = 1}}
	local full = chest({x = -90, y = 1, z = 2}, "fuller", stuffed)
	local fuller = villager("fuller", {x = -90, y = 1, z = 0}, {_villages_belongings = {}})
	local po = villager("po-full", {x = -90, y = 1, z = 1}, {_villages_belongings = {[EMERALD] = 12, [STAND] = 1}})
	trips.deliver(po, {item = STAND, bought = 1, spent = 0, commission = true,
		client = {id = "fuller", deliver = full, purse = 0, fee = 0}})
	assert(count(fuller, STAND) == 1 and count(po, STAND) == 0 and chest_count(full, STAND) == 0)
	assert(logs[#logs - 1]:find("handed 1 " .. STAND .. " and 0 emerald%(s%) to fuller in person"), logs[#logs - 1])
	-- The change too.
	trips.deliver(po, {item = STAND, bought = 0, spent = 2, client = {id = "fuller", deliver = full, purse = 10, fee = 0}})
	assert(count(fuller, EMERALD) == 8 and count(po, EMERALD) == 4)
	-- With the client away it keeps them, and says so.
	local full2 = chest({x = -190, y = 1, z = 2}, "away", {{name = "a", count = 1}, {name = "b", count = 1},
		{name = "c", count = 1}, {name = "d", count = 1}})
	possessions.add(po, STAND, 1)
	trips.deliver(po, {item = STAND, bought = 1, spent = 0, commission = true,
		client = {id = "away", deliver = full2, purse = 0, fee = 0}})
	assert(count(po, STAND) == 1 and logs[#logs - 1]:find("could not leave 1 " .. STAND), logs[#logs - 1])
end

-- Commissions (ticket 26b): a client with an urgent need for a labour good and nobody
-- selling it pays a porter up front to make it and bring it. The porter's plan is the
-- recipe, its inputs needs; it holds the output back; the price is not its money to spend
-- until it delivers. Made, it leaves the goods in the client's chest and keeps the price;
-- run out of time, it brings the price back.
do
	local comforts = dofile("comforts.lua")
	local commission = dofile("commission.lua")
	local production = dofile("production.lua")
	local recipes = dofile("recipes.lua")
	local LANTERN, NUGGET, TORCH = "mcl_lanterns:lantern_floor", "mcl_core:iron_nugget", "mcl_torches:torch"
	local fond
	for i = 1, 5000 do
		if comforts.tastes("farm-" .. i)[1].item == LANTERN then fond = "farm-" .. i break end
	end
	assert(fond, "an id whose first taste is a lantern")
	local stash = chest({x = 90, y = 1, z = 2}, fond, {})
	local client = villager(fond, {x = 90, y = 1, z = 0}, {_profession = "farmer", _jobsite = {x = 91, y = 1, z = 0},
		_villages_stash = stash, _villages_belongings = {[EMERALD] = 600}})
	local view = possessions.assess(client)
	assert((view.needs[LANTERN] or 0) > 0 and trips.urgency(view, LANTERN) >= trips.URGENT, "it wants a lantern")
	local hand = villager("hand", {x = 90, y = 1, z = 12}, {_villages_belongings = {[EMERALD] = 2},
		_villages_labour = {day = day, activity = "porter"}})
	time = 6000 / 24000
	local hires = trips.hire({hand, client})
	assert(#hires == 1 and hires[1].commission, "no seller: a commission")
	local c = hand._villages_commission
	local recipe = recipes.labour[c.index]
	assert(c.item == LANTERN and recipe.makes == LANTERN and c.client == fond and c.count == 1)
	local cost = commission.cost(recipe, possessions.prices_of(client))
	assert(c.price == math.min(math.ceil(cost * commission.PRICE_SLACK) + trips.PORTER_FEE, trips.PURSE), c.price)
	assert(count(client, EMERALD) == 600 - c.price and count(hand, EMERALD) == 2 + c.price)
	assert(logs[#logs]:find("commissioned porter hand with " .. c.price))
	-- Its plan is the recipe; nuggets and a torch are needs, worth at least a share of what
	-- the lantern is paid; the price is not its own to spend.
	assert(possessions.labour_plan(hand).makes == LANTERN)
	local hand_view = possessions.assess(hand)
	assert(hand_view.needs[NUGGET] == 8 and (hand_view.needs[TORCH] or 0) >= 1, "the inputs are needs")
	assert(hand_view.value(NUGGET) > 0)
	assert(possessions.money(hand) == 2, possessions.money(hand))
	-- Nor a second for the same good while the first is out, from this porter or another.
	client._villages_porter_day = nil
	local other = villager("other", {x = 90, y = 1, z = 1}, {_villages_labour = {day = day, activity = "porter"}})
	assert(#trips.hire({other, client}) == 0, "one lantern commissioned is enough")
	-- With the inputs in hand it makes the lantern, and holds it back.
	possessions.add(hand, NUGGET, 8)
	possessions.add(hand, TORCH, 1)
	local chosen = production.choose(hand, nil, nil, nil, recipes.labour)
	assert(chosen and chosen.makes == LANTERN, "it makes the commissioned lantern")
	assert(production.make(hand, chosen, true))
	assert(count(hand, LANTERN) == 1 and (possessions.assess(hand).surplus[LANTERN] or 0) == 0, "held back")
	-- Its work stage: counted as one of the commission's work days, and off to the
	-- client's chest with the lantern.
	time = 9000 / 24000
	trips.step(hand, now)
	assert(c.worked == 1 and c.worked_day == day, "a work stage counts toward its time")
	assert(hand._villages_commission == nil and hand._villages_trade_trip.commission, "made: delivering")
	assert(hand.walks[#hand.walks].z == 2, "to the client's chest")
	hand.arrive()
	trips.step(hand, now + 2)
	assert(hand._villages_trade_trip == nil and chest_count(stash, LANTERN) == 1 and count(hand, LANTERN) == 0)
	assert(count(hand, EMERALD) == 2 + c.price and chest_count(stash, EMERALD) == 0, "the price is its pay")
	assert(logs[#logs]:find("commission: porter hand delivered 1 mcl_lanterns:lantern_floor"))
	-- One that runs out of time brings the price back, and keeps what it bought.
	local stash2 = chest({x = 120, y = 1, z = 2}, fond .. "b", {})
	local lazy = villager("lazy", {x = 120, y = 1, z = 12}, {_villages_belongings = {[EMERALD] = 1, [NUGGET] = 3}})
	lazy._villages_commission = {index = c.index, item = LANTERN, count = 1, client = fond .. "b",
		deliver = vector.new(stash2), price = 150, day = day - commission.MAX_DAYS}
	assert(commission.expired(lazy._villages_commission, day))
	-- Its time is its work stages: a holiday, or a day it was not loaded, is not counted.
	local timed = {day = day}
	assert(not commission.expired(timed, day + 3), "no work stage yet")
	commission.worked(timed, day + 1)
	commission.worked(timed, day + 1)
	assert(timed.worked == 1 and not commission.expired(timed, day + 3), "one work stage, counted once")
	commission.worked(timed, day + 3)
	assert(not commission.expired(timed, day + 3), "during its last work stage")
	assert(commission.expired(timed, day + 4), "after its last work stage")
	assert(commission.expired({day = day}, day + commission.MAX_DAYS), "at most MAX_DAYS days")
	possessions.add(lazy, EMERALD, 150)
	assert(possessions.money(lazy) == 1)
	trips.step(lazy, now + 10)
	assert(lazy._villages_commission == nil and lazy._villages_trade_trip.client.purse == 150, "the price goes back")
	lazy.arrive()
	trips.step(lazy, now + 12)
	assert(chest_count(stash2, EMERALD) == 150 and count(lazy, EMERALD) == 1 and count(lazy, NUGGET) == 3)
	-- No commission it cannot pay for.
	local poor = villager(fond .. "c", {x = 150, y = 1, z = 0}, {_profession = "farmer", _jobsite = {x = 151, y = 1, z = 0},
		_villages_stash = chest({x = 150, y = 1, z = 2}, fond .. "c", {}), _villages_belongings = {[EMERALD] = trips.PORTER_FEE + 1}})
	local idle = villager("idle", {x = 150, y = 1, z = 1}, {_villages_labour = {day = day, activity = "porter"}})
	assert(#trips.hire({idle, poor}) == 0, "the price is over what it holds")
	time = 6000 / 24000
end

-- A crafter's commission (E12): a client with an urgent want of a good of a jobsite
-- crafter's trade, that the crafter holds none of and nobody is heard to offer, pays it up
-- front, up to all it holds. The crafter bids for the inputs with that money and delivers.
do
	local commission = dofile("commission.lua")
	local production = dofile("production.lua")
	local recipes = dofile("recipes.lua")
	local AXE, INGOT, STICK = "mcl_tools:axe_iron", "mcl_core:iron_ingot", "mcl_core:stick"
	local stash = chest({x = 200, y = 1, z = 2}, "cutter", {})
	local client = villager("cutter", {x = 200, y = 1, z = 0}, {_profession = "leatherworker",
		_jobsite = {x = 201, y = 1, z = 0}, _villages_stash = stash, _villages_belongings = {[EMERALD] = 2000}})
	local view = possessions.assess(client)
	assert((view.needs[AXE] or 0) > 0 and trips.urgency(view, AXE) >= trips.URGENT, "it wants an iron axe")
	local smith = villager("smith", {x = 200, y = 1, z = 12}, {_profession = "weapon_smith",
		_jobsite = {x = 201, y = 1, z = 12}, _villages_belongings = {[EMERALD] = 40}})
	-- Not while it holds one: it sells that one.
	possessions.add(smith, AXE, 1)
	assert(#trips.hire({smith, client}) == 0, "it holds one")
	possessions.take(smith, AXE, 1)
	-- Not while the client has heard one offered.
	client._villages_market_news = {{item = AXE, who = "seller", kind = "has", count = 1, price = 600,
		home = {x = 0, y = 1, z = 0}, heard = now, hops = 0}}
	assert(#trips.hire({smith, client}) == 0, "a seller is heard of")
	client._villages_market_news = nil
	local hires = trips.hire({smith, client})
	assert(#hires == 1 and hires[1].crafter == smith, "a crafter's commission")
	local c = smith._villages_commission
	assert(c.trade == "weapon_smith" and c.item == AXE and c.count == 1 and c.client == "cutter")
	local recipe = commission.recipe(c)
	assert(recipes.weapon_smith[c.index].makes == AXE and recipe.makes == AXE)
	assert(commission.of(smith) == c and commission.labour_of(smith) == nil)
	local cost = commission.cost(recipe, possessions.prices_of(client))
	assert(c.price == math.ceil(cost * commission.PRICE_SLACK) + trips.PORTER_FEE, c.price)
	assert(count(client, EMERALD) == 2000 - c.price and count(smith, EMERALD) == 40 + c.price)
	assert(logs[#logs]:find("commissioned crafter smith %(weapon_smith%) with " .. c.price))
	-- Its ingots are worth at least what the client paid for them, its axe held back at the
	-- price; no labour plan comes of it; the price is not its money.
	assert(possessions.labour_plan(smith) == nil)
	local smith_view = possessions.assess(smith)
	assert((smith_view.needs[INGOT] or 0) >= 3, "ingots are needs")
	local client_ingot = possessions.prices_of(client)(INGOT)
	assert(smith_view.value(INGOT) >= client_ingot - 1e-6, smith_view.value(INGOT) .. " " .. client_ingot)
	assert(possessions.money(smith) == 40, possessions.money(smith))
	-- Nor a second axe for the client while the first is out.
	client._villages_porter_day = nil
	local other = villager("smith2", {x = 200, y = 1, z = 13}, {_profession = "weapon_smith",
		_jobsite = {x = 201, y = 1, z = 13}})
	assert(#trips.hire({other, client}) == 0, "one axe commissioned is enough")
	assert(commission.crafter(smith) == nil, "one commission at a time")
	-- With the inputs it makes the axe, holds it back and takes it to the client's chest.
	possessions.add(smith, INGOT, 3)
	possessions.add(smith, STICK, 2)
	possessions.add(smith, "mcl_core:coal_lump", 2)
	local chosen = production.choose(smith)
	assert(chosen and chosen.makes == AXE, "it makes the commissioned axe")
	assert(production.make(smith, chosen))
	assert((possessions.assess(smith).surplus[AXE] or 0) == 0, "held back")
	time = 9000 / 24000
	trips.step(smith, now)
	assert(smith._villages_commission == nil and smith._villages_trade_trip.commission, "made: delivering")
	smith.arrive()
	trips.step(smith, now + 2)
	assert(chest_count(stash, AXE) == 1 and count(smith, AXE) == 0, "delivered")
	assert(logs[#logs]:find("commission: crafter smith delivered 1 mcl_tools:axe_iron"), logs[#logs])
	-- Only finished goods: no food, nothing a recipe takes in.
	local finished = commission.finished()
	assert(finished[AXE] and finished["mcl_cauldrons:cauldron"] and finished["mcl_books:bookshelf"])
	assert(not finished["mcl_fishing:salmon_cooked"] and not finished["mcl_mobitems:cooked_beef"], "no food")
	assert(not finished["mcl_core:wood"] and not finished[STICK] and not finished[INGOT], "no inputs")
	local cook = villager("cook", {x = 200, y = 1, z = 14}, {_profession = "butcher", _jobsite = {x = 201, y = 1, z = 14}})
	local _, _, cook_goods = commission.crafter(cook)
	for item in pairs(cook_goods or {}) do assert(not dofile("food.lua").POINTS[item], item) end
	-- A crafter's lasts longer: TRADE_WORK_DAYS work stages, at most TRADE_MAX_DAYS days.
	local timed = {day = day, trade = "weapon_smith"}
	for d = day, day + commission.TRADE_WORK_DAYS - 1 do commission.worked(timed, d) end
	assert(not commission.expired(timed, day + commission.TRADE_WORK_DAYS - 1), "during its last work stage")
	assert(commission.expired(timed, day + commission.TRADE_WORK_DAYS), "after it")
	assert(not commission.expired({day = day, trade = "weapon_smith"}, day + commission.MAX_DAYS), "past a porter's days")
	assert(commission.expired({day = day, trade = "weapon_smith"}, day + commission.TRADE_MAX_DAYS))
	-- A client with no job may commission too (E12c), with a chest to deliver to: a nitwit
	-- woodcutting today wants an iron axe.
	local idler_stash = chest({x = 260, y = 1, z = 2}, "idler", {})
	local idler = villager("idler", {x = 260, y = 1, z = 0}, {_profession = "nitwit",
		_villages_labour = {day = day, activity = "woodcutter"},
		_villages_stash = idler_stash, _villages_belongings = {[EMERALD] = 2000}})
	local idle_view = possessions.assess(idler)
	assert((idle_view.needs[AXE] or 0) > 0 and trips.urgency(idle_view, AXE) >= trips.URGENT, "it wants an axe")
	local smith4 = villager("smith4", {x = 260, y = 1, z = 1}, {_profession = "weapon_smith", _jobsite = {x = 261, y = 1, z = 1}})
	local idle_hires = trips.hire({smith4, idler})
	assert(#idle_hires == 1 and smith4._villages_commission.client == "idler", "a nitwit commissions")
	-- No commission the client cannot pay.
	local poor = villager("poor", {x = 230, y = 1, z = 0}, {_profession = "leatherworker", _jobsite = {x = 231, y = 1, z = 0},
		_villages_stash = chest({x = 230, y = 1, z = 2}, "poor", {}), _villages_belongings = {[EMERALD] = 100}})
	local smith3 = villager("smith3", {x = 230, y = 1, z = 1}, {_profession = "weapon_smith", _jobsite = {x = 231, y = 1, z = 1}})
	assert(#trips.hire({smith3, poor}) == 0, "the price is over what it holds")
	time = 6000 / 24000
end

-- A farmer with no hoe plans a trip to a tool smith that has one, whatever the hoe is worth
-- next to URGENT times its price (wants.lua caps it at what it brings; run 46, when that
-- was under, before wheat yielded two a harvest).
do
	local HOE = "mcl_farming:hoe_stone"
	local ledger = dofile("ledger.lua")
	local fern = villager("fern-farmer", {x = 0, y = 1, z = 0},
		{_profession = "farmer", _villages_belongings = {[EMERALD] = 200}})
	local fern_view = possessions.assess(fern)
	assert(fern_view.needs[HOE] == 1)
	assert(trips.urgency(fern_view, HOE) >= trips.URGENT)
	local hoe_news = has_news("tess-smith", HOE, {x = 15, y = 1, z = 0}, ledger.price(HOE) * 0.6 / 64)
	hoe_news.count = 1
	local hoe_trip = trips.plan(fern, fern_view, {hoe_news}, fern._bed)
	assert(hoe_trip and hoe_trip.item == HOE and hoe_trip.who == "tess-smith", "a trip for the hoe")
end

-- Planks any wood will do for, it buys as logs of any species, a quarter of them, and splits
-- what it gets into planks; a porter delivering logs to it hands over the planks.
do
	local OAK_PLANKS, BIRCH_LOG, BIRCH_PLANKS = "mcl_core:wood", "mcl_core:birchtree", "mcl_core:birchwood"
	local bo = villager("bo-builder", {x = 0, y = 1, z = 0},
		{_profession = "mason", _villages_builder = true, _jobsite = {x = 0, y = 1, z = 1},
			_villages_belongings = {[EMERALD] = 320}})
	local function planks_report(exact)
		return {
			rows = {{item = OAK_PLANKS, need = 10, in_chests = 0, carried = stock.count(bo, OAK_PLANKS)
				+ stock.count(bo, BIRCH_PLANKS), missing = 10, swaps = not exact or nil}},
			short = true, chests = {bench_chest},
		}
	end
	market.update(bo, planks_report())
	assert(bo._villages_builder_logs == 3 and bo._villages_builder_wants == nil, "three logs, no planks")
	assert(market.status(bo) == "3 logs (any)", market.status(bo))
	local view = possessions.assess(bo)
	assert(view.needs[BIRCH_LOG] == 3 and view.needs["mcl_core:tree"] == 3 and view.group[BIRCH_LOG] == "log")
	-- A birch log bought becomes four birch planks, which stand in for oak.
	bo._villages_belongings[BIRCH_LOG] = 2
	market.update(bo, planks_report())
	assert(count(bo, BIRCH_LOG) == 0 and stock.count(bo, BIRCH_PLANKS) == 8)
	assert(bo._villages_builder_logs == 1, "two planks still missing: one log")
	assert(table.concat(logs, "\n"):find("split 2 mcl_core:birchtree into 8 mcl_core:birchwood"))
	-- A player's order wants its very planks.
	market.update(bo, planks_report(true))
	assert(bo._villages_builder_logs == nil and bo._villages_builder_wants[OAK_PLANKS] == 10)

	-- The porter's delivery.
	local drop = chest({x = 0, y = 1, z = 4})
	local po = villager("po-porter", {x = 0, y = 1, z = 3}, {_villages_belongings = {[BIRCH_LOG] = 3, [EMERALD] = 10}})
	trips.deliver(po, {item = BIRCH_LOG, bought = 3, spent = 0,
		client = {id = "bo-builder", deliver = drop, purse = 10, fee = 2, split = true}})
	assert(chest_count(drop, BIRCH_PLANKS) == 12 and chest_count(drop, BIRCH_LOG) == 0 and count(po, BIRCH_LOG) == 0)
end

-- Red beds (19i): nobody makes beds, so it makes the red beds it is short of, three wool of
-- any colour, three planks and a red dye each. It wants the wool as any colour, the planks
-- as logs and the dye, and makes them from what it holds past the building's own needs.
do
	local BED, DYE, GREY, OAK_PLANKS = market.RED_BED, market.RED_DYE, "mcl_wool:grey", "mcl_core:wood"
	local bed_chest = chest({x = 0, y = 1, z = 6})
	local bb = villager("bb-builder", {x = 0, y = 1, z = 5},
		{_profession = "mason", _villages_builder = true, _jobsite = {x = 0, y = 1, z = 5},
			_villages_belongings = {[EMERALD] = 600}})
	-- Two beds, any colour (a stock building), and four oak planks for the building itself.
	local function beds_report()
		return {
			rows = {
				{item = BED, need = 2, in_chests = 0, carried = 0, missing = 2, swaps = true},
				{item = OAK_PLANKS, need = 4, in_chests = chest_count(bed_chest, OAK_PLANKS), carried = 0,
					missing = 4, swaps = true},
			},
			short = true, chests = {bed_chest},
		}
	end
	market.update(bb, beds_report())
	assert(bb._villages_builder_wool == 6 and bb._villages_builder_wants[DYE] == 2
		and bb._villages_builder_wants[BED] == nil, "wool, dye, not the bed")
	assert(bb._villages_builder_logs == 3, "ten planks: four for the building, six for the beds")
	assert(market.status(bb) == "2 red, 3 logs (any), 6 wool (any)", market.status(bb))
	local view = possessions.assess(bb)
	assert(view.needs[GREY] == 6 and view.group[GREY] == "wool" and view.needs["mcl_wool:white"] == 6)
	assert(view.needs[DYE] == 2)
	-- Bought: grey wool and a dye in hand, a porter's planks in its chest. One bed made; the
	-- building's four planks are left alone.
	bb._villages_belongings[GREY] = 4
	bb._villages_belongings[DYE] = 1
	chests[key(bed_chest)].inv.stacks[1] = {name = OAK_PLANKS, count = 8}
	market.update(bb, beds_report())
	assert(stock.count(bb, BED) == 1 and table.concat(logs, "\n"):find("builder bb%-bui made 1 red bed"))
	assert(stock.count(bb, GREY) == 1 and stock.count(bb, DYE) == 0)
	assert(chest_count(bed_chest, OAK_PLANKS) + stock.count(bb, OAK_PLANKS) == 5, "three planks used")
	assert(bb._villages_builder_wool == 2 and bb._villages_builder_wants[DYE] == 1, "the second bed's")
	assert(bb._villages_builder_logs == 1, "one plank to spare: the second bed's other two, as a log")
	-- A player's order of a blue bed wants that very bed.
	local blue = "mcl_beds:bed_blue_bottom"
	market.update(bb, {rows = {{item = blue, need = 1, in_chests = 0, carried = 0, missing = 1}},
		short = true, chests = {bed_chest}})
	assert(bb._villages_builder_wants[blue] == 1 and bb._villages_builder_wool == nil)
end

-- Ingots from the alchemist's nuggets (ticket 29): a trip for a product it makes on sale
-- carries its sources from the news, and buys them in its stash and to its face.
do
	local NUGGET, INGOT = "mcl_core:iron_nugget", "mcl_core:iron_ingot"
	local stash = chest({x = 40, y = 1, z = 40}, "alch-away", {{name = NUGGET, count = 30}})
	local armo = villager("armo", {x = 40, y = 1, z = 30}, {_villages_belongings = {[EMERALD] = 100}})
	local trip = {item = INGOT, who = "alch-away", want = 5, price = 16, from = NUGGET, ratio = 1 / 9, takes = 9,
		client = {purse = 100, value = 50}}
	-- 30 nuggets make three ingots, whole batches: 27 go, 3 stay.
	assert(trips.buy_from_stash(armo, trip, stash) == 3, "three ingots from 30 nuggets")
	assert(count(armo, INGOT) == 3 and chest_count(stash, NUGGET) == 3 and chest_count(stash, EMERALD) == 48)
	local bought, why = trips.buy_from_stash(armo, trip, stash)
	assert(bought == 0 and why:find("stash holds 0 from " .. NUGGET, 1, true), why)
	-- Without the sources told, nuggets are no ingots.
	local plain = chest({x = 44, y = 1, z = 40}, "alch-away", {{name = NUGGET, count = 30}})
	assert(trips.buy_from_stash(armo, {item = INGOT, who = "alch-away", want = 5, price = 16,
		client = {purse = 100, value = 50}}, plain) == 0)
	-- A plan carries the sources from what it heard.
	local planned = trips.plan(villager("buyer", {x = 40, y = 1, z = 20}, {_villages_belongings = {[EMERALD] = 100}}),
		{needs = {[INGOT] = 3}, value = function() return 50 end, urgency = function() return 4 end},
		{{item = INGOT, who = "alch-away", kind = "has", count = 3, price = 16, home = {x = 40, y = 1, z = 41},
			heard = now, hops = 1, from = NUGGET, ratio = 1 / 9, takes = 9}}, {x = 40, y = 1, z = 20})
	assert(planned and planned.from == NUGGET and planned.ratio == 1 / 9 and planned.takes == 9)
	-- The seller, loaded though away from its stash, counts the sale as its own (ticket 30):
	-- an alchemist keeps the price per nugget for its bids, and its asks learn the sale.
	local owner = villager("alch-owner", {x = 80, y = 1, z = 80}, {_profession = "cleric", _villages_alchemist = true,
		_villages_belongings = {}})
	local owned = chest({x = 81, y = 1, z = 81}, "alch-owner", {{name = NUGGET, count = 18}})
	local buyer2 = villager("buyer2", {x = 80, y = 1, z = 70}, {_villages_belongings = {[EMERALD] = 100}})
	local stash_trip = {item = INGOT, who = "alch-owner", home = {x = 80, y = 1, z = 80}, want = 2, price = 18,
		from = NUGGET, ratio = 1 / 9, takes = 9, client = {purse = 100, value = 50}}
	assert(trips.buy_from_stash(buyer2, stash_trip, owned) == 2)
	assert(owner._villages_sold_at[INGOT] == 18 and owner._villages_sold_at[NUGGET] == 2, "per ingot, per nugget")
	assert(owner._villages_ask_sold[NUGGET].count == 18 and owner._villages_ask_sold[INGOT].count == 2)
	-- To its face: an alchemist holding only nuggets, made at 2 each and asked at a quarter
	-- of their price, asks nine nuggets' ask for an ingot, not an ingot's base price.
	local alch = villager("alch-here", {x = 60, y = 1, z = 60}, {_profession = "cleric", _villages_alchemist = true,
		_villages_belongings = {[NUGGET] = 90}, _villages_asks = {[NUGGET] = 0.25},
		_villages_made_cost = {[NUGGET] = 2}})
	local porter = villager("porter", {x = 60, y = 1, z = 61}, {_villages_belongings = {[EMERALD] = 200}})
	local face = {item = INGOT, who = "alch-here", want = 2, price = 16, client = {purse = 200, value = 100}}
	local got, reason = trips.buy_in_person(porter, face, alch)
	assert(got == 2 and count(porter, INGOT) == 2 and count(alch, NUGGET) == 72, tostring(got) .. " " .. tostring(reason))
	assert(face.spent < 2 * ledger.price(INGOT), "at nuggets' price: " .. face.spent)
end

-- Off with the economy: no hire.
settings.living_villages_economy = false
assert(#trips.hire({}) == 0)

print("trade_trips.lua: ok")
