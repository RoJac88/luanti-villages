-- Run with: lua tests/gossip.lua
local now = 1000
local setting = true
local logged = {}
local blocked_sight = false
local creative = {}

vector = {
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
}

local function stack(name, count, max)
	local self = {name = name or "", count = count or 0, max = max or 64}
	function self:is_empty() return self.name == "" or self.count == 0 end
	function self:get_count() return self.count end
	function self:set_count(n) self.count = n end
	function self:get_stack_max() return self.max end
	function self:to_string()
		if self:is_empty() then return "" end
		return self.count == 1 and self.name or (self.name .. " " .. self.count)
	end
	return self
end
ItemStack = function(from)
	if type(from) == "table" then return stack(from.name, from.count, from.max) end
	return stack()
end

local objects = {}
local players_by_name = {}
local inventories, join_callbacks, leave_callbacks, shown = {}, {}, {}, {}
minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	settings = {get = function() return nil end, get_bool = function(_, name)
		assert(name == "living_villages_gossip", "the setting is read by its name")
		return setting
	end},
	log = function(_, message) logged[#logged + 1] = message end,
	line_of_sight = function() return not blocked_sight end,
	get_player_by_name = function(name) return players_by_name[name] end,
	is_creative_enabled = function(name) return creative[name] end,
	get_objects_inside_radius = function(pos, radius)
		local found = {}
		for _, object in ipairs(objects) do
			if vector.distance(pos, object:get_pos()) <= radius then found[#found + 1] = object end
		end
		return found
	end,
	get_inventory = function(where) return inventories[where.name] end,
	detached_inventories = {},
	show_formspec = function(player_name, formname, formspec)
		shown[#shown + 1] = {player = player_name, name = formname, formspec = formspec}
	end,
	register_on_joinplayer = function(fn) join_callbacks[#join_callbacks + 1] = fn end,
	register_on_leaveplayer = function(fn) leave_callbacks[#leave_callbacks + 1] = fn end,
}

local gossip = dofile("gossip.lua")

local function expect(value, expected, what)
	assert(value == expected, what .. ": expected " .. tostring(expected) .. ", got " .. tostring(value))
end

local function clear()
	objects = {}
end

local count = 0
local function villager(x, z, y)
	count = count + 1
	local self = {name = "mobs_mc:villager", _id = "villager" .. count, health = 20, pos = {x = x or 0, y = y or 0, z = z or 0}}
	self.object = {get_pos = function() return self.pos end}
	local object = {
		get_pos = function() return self.pos end,
		get_luaentity = function() return self end,
		is_player = function() return false end,
	}
	objects[#objects + 1] = object
	return self
end

local function player(name, x, z)
	local self = {pos = {x = x or 0, y = 0, z = z or 0}}
	function self.is_player() return true end
	function self.get_player_name() return name end
	function self.get_pos() return self.pos end
	function self.get_luaentity() return nil end
	players_by_name[name] = self
	return self
end

-- Vanilla's half of the villager, the part gossip.lua wraps.
local hit_damage, activated = 5, nil
local def = {
	on_rightclick = function(self, clicker) self.clicked = clicker end,
	on_die = function(self) self.died = true; return "vanilla die" end,
	on_activate = function(self) activated = self end,
	on_punch = function(self) self.health = self.health - hit_damage; return "vanilla punch" end,
}
local golem_def = {
	on_activate = function() end,
	do_custom = function() return "vanilla golem" end,
}
local zombie_def = {
	on_rightclick = function(self) self._curing = 100 end,
	do_custom = function(self)
		if self._curing and self._curing <= 0 then def.on_activate(self.cured) end
	end,
}
local summoned_golem
mobs_mc = {check_iron_golem_summon = function() golem_def.on_activate(summoned_golem) return "summoned" end}
mcl_mobs = {invis = {}}
gossip.install(def, golem_def, zombie_def)

-- Gains add up to the maximum; each type weighs its multiplier.
do
	local v = villager()
	expect(gossip.reputation(v, "alice"), 0, "a stranger")
	gossip.add(v, "alice", "trading")
	expect(gossip.reputation(v, "alice"), 4, "a trade")
	for _ = 1, 20 do gossip.add(v, "alice", "trading") end
	expect(gossip.reputation(v, "alice"), 25, "trading stops at its maximum")
	gossip.add(v, "alice", "major_negative")
	expect(gossip.reputation(v, "alice"), 25 - 125, "a kill weighs five")
	expect(gossip.reputation(v, "bob"), 0, "memory is per player")
	expect(gossip.reputation(villager(), "alice"), 0, "and per villager")
end

-- Decay: in steps of 20 minutes, with catch-up, and entries at nothing go.
do
	local v = villager()
	gossip.add(v, "alice", "minor_negative")
	gossip.add(v, "alice", "major_positive")
	now = now + gossip.DECAY_SECONDS - 1
	expect(v._villages_gossip.alice.minor_negative, 25, "not yet a step")
	gossip.reputation(v, "alice")
	expect(v._villages_gossip.alice.minor_negative, 25, "under a step does not decay")
	now = now + 1
	expect(gossip.reputation(v, "alice"), 100 - 5, "one step takes 20 off minor_negative")
	now = now + 2 * gossip.DECAY_SECONDS
	expect(v._villages_gossip_decayed + gossip.DECAY_SECONDS * 2, now, "steps are counted from the last")
	expect(gossip.reputation(v, "alice"), 100, "time away catches up, and major_positive never fades")
	assert(v._villages_gossip.alice.minor_negative == nil, "an entry at nothing is removed")

	local w = villager()
	gossip.add(w, "alice", "trading")
	now = now + 2 * gossip.DECAY_SECONDS
	expect(gossip.reputation(w, "alice"), 0, "a faded trade")
	assert(w._villages_gossip == nil and w._villages_gossip_decayed == nil, "an empty memory is not kept")
end

-- Sharing: less the cost, keeps the larger, major_positive never, no growth back and forth.
do
	local a, b = villager(), villager()
	for _ = 1, 2 do gossip.add(a, "alice", "minor_negative") end
	gossip.add(a, "alice", "major_positive")
	gossip.add(a, "bob", "trading") -- 4, less than its cost: dies in the telling
	expect(gossip.share(a, b), 1, "only one entry survives its cost")
	expect(b._villages_gossip.alice.minor_negative, 30, "minor_negative less 20")
	assert(b._villages_gossip.alice.major_positive == nil, "major_positive is never shared")
	assert(b._villages_gossip.bob == nil, "a value under its cost is not shared")
	expect(gossip.reputation(a, "alice"), 100 - 50, "the teller loses nothing")

	gossip.exchange({a, b})
	gossip.exchange({a, b})
	expect(a._villages_gossip.alice.minor_negative, 50, "hearing it back does not grow it")
	expect(b._villages_gossip.alice.minor_negative, 30, "nor does retelling")

	local c = villager()
	c._villages_gossip, c._villages_gossip_decayed = {alice = {minor_negative = 45}}, now
	gossip.share(a, c)
	expect(c._villages_gossip.alice.minor_negative, 45, "a listener's own larger value stands")

	-- At most SHARE_ENTRIES at a time.
	local many, listener = villager(), villager()
	for i = 1, gossip.SHARE_ENTRIES + 5 do
		many._villages_gossip = many._villages_gossip or {}
		many._villages_gossip["p" .. i] = {minor_negative = 100}
	end
	many._villages_gossip_decayed = now
	expect(gossip.share(many, listener), gossip.SHARE_ENTRIES, "the limit")
end

-- Everyone in a group hears; with the setting off, nobody does.
do
	local a, b, c = villager(), villager(), villager()
	gossip.add(a, "alice", "major_negative")
	gossip.exchange({a, b, c})
	expect(b._villages_gossip.alice.major_negative, 15, "b heard")
	expect(c._villages_gossip.alice.major_negative, 15, "c heard")

	setting = false
	local d = villager()
	gossip.exchange({a, d})
	gossip.add(d, "alice", "major_negative")
	assert(d._villages_gossip == nil, "off: nothing is passed on or noted")
	expect(a._villages_gossip.alice.major_negative, 25, "off: what is remembered stays")
	setting = true
end

-- Java's price: floor, clamps, the direction of each sign.
do
	expect(gossip.price(10, 0, 0.05, 64), 10, "no opinion")
	expect(gossip.price(10, 19, 0.05, 64), 10, "a discount needs a whole emerald")
	expect(gossip.price(10, 20, 0.05, 64), 9, "a discount")
	expect(gossip.price(10, -1, 0.05, 64), 11, "any dislike costs one, by floor")
	expect(gossip.price(10, 100, 0.2, 64), 1, "never under one")
	expect(gossip.price(60, -500, 0.2, 64), 64, "never over a stack")
end

-- Hits: only when health fell, and only from a player or a player's projectile.
do
	local v = villager()
	local alice = player("alice")
	expect(def.on_punch(v, alice), "vanilla punch", "the result goes through")
	expect(v._villages_gossip.alice.minor_negative, 25, "a hit is noted")

	local refused = villager()
	hit_damage = 0
	def.on_punch(refused, alice)
	hit_damage = 5
	assert(refused._villages_gossip == nil, "a refused hit is not")

	local arrow_of = function(owner)
		return {
			is_player = function() return false end,
			get_luaentity = function() return {_owner = owner} end,
		}
	end
	local shot = villager()
	def.on_punch(shot, arrow_of("alice"))
	expect(shot._villages_gossip.alice.minor_negative, 25, "an arrow answers to its owner")
	local mobbed = villager()
	def.on_punch(mobbed, arrow_of("some-skeleton-uuid"))
	assert(mobbed._villages_gossip == nil, "a mob's arrow answers to nobody")
	local zombied = villager()
	def.on_punch(zombied, {is_player = function() return false end, get_luaentity = function() return {name = "mobs_mc:zombie"} end})
	assert(zombied._villages_gossip == nil, "nor does a mob")
end

-- Kills: every villager in sight within range, not the victim, not for non-players.
do
	clear()
	local alice = player("alice")
	local victim, near, far = villager(0, 0), villager(5, 0), villager(gossip.WITNESS_RADIUS + 1, 0)
	expect(def.on_die(victim, victim.pos, {type = "punch", puncher = alice}), "vanilla die", "the result goes through")
	assert(victim.died, "vanilla still runs")
	expect(near._villages_gossip.alice.major_negative, 25, "a witness")
	assert(far._villages_gossip == nil, "out of range")
	assert(victim._villages_gossip == nil, "the victim tells nobody")

	clear()
	local hidden_victim, hidden = villager(0, 0), villager(5, 0)
	blocked_sight = true
	def.on_die(hidden_victim, hidden_victim.pos, {type = "punch", puncher = alice})
	blocked_sight = false
	assert(hidden._villages_gossip == nil, "behind a wall sees nothing")

	clear()
	local burnt, onlooker = villager(0, 0), villager(5, 0)
	def.on_die(burnt, burnt.pos, {type = "fire"})
	def.on_die(burnt, burnt.pos, nil)
	def.on_die(burnt, burnt.pos, {type = "punch", puncher = {is_player = function() return false end, get_luaentity = function() return {name = "mobs_mc:zombie"} end}})
	assert(onlooker._villages_gossip == nil, "harm with no player behind it adds nothing")
end

-- The trade window. A stand-in for vanilla: set_trade writes the list, then the window
-- is drawn from the list, as villager.lua does.
local function trade_inventory(name)
	local inv = {lists = {wanted = {stack(), stack()}, offered = {stack()}, input = {stack(), stack()}}}
	function inv:get_stack(list, i) return self.lists[list][i] end
	function inv:set_stack(list, i, s) self.lists[list][i] = s end
	function inv:is_empty(list)
		for _, s in ipairs(self.lists[list]) do if not s:is_empty() then return false end end
		return true
	end
	inventories["mobs_mc:trade_" .. name] = inv
	return inv
end

local function draw(name, inv)
	minetest.show_formspec(name, "mobs_mc:trade_" .. name,
		"size[9,8.75]label[3,0;Farmer]item_image[2,1;1,1;" .. inv:get_stack("wanted", 1):to_string() .. "]list[x]")
end

local function set_trade(inv, wanted, offered)
	inv:set_stack("wanted", 1, wanted)
	inv:set_stack("offered", 1, offered)
end

do
	local name = "trader"
	local inv = trade_inventory(name)
	local refreshed, taken_redraw = 0, false
	local trader_player = player(name)
	local callbacks = {
		on_put = function() refreshed = refreshed + 1 end,
		on_take = function(_, listname)
			if listname == "output" then
				-- Vanilla redraws from the list after a tier-up or lock.
				if taken_redraw then draw(name, inv) end
			end
			return "vanilla take"
		end,
	}
	minetest.detached_inventories["mobs_mc:trade_" .. name] = callbacks
	for _, fn in ipairs(join_callbacks) do fn(trader_player) end
	local wrapped = callbacks.on_take
	for _, fn in ipairs(join_callbacks) do fn(trader_player) end
	assert(callbacks.on_take == wrapped, "a rejoin does not wrap it twice")

	local v = villager()
	v._trades = "untouched"
	for _ = 1, 6 do gossip.add(v, name, "trading") end -- 24, a discount of floor(1.2) = 1
	def.on_rightclick(v, trader_player)
	assert(v.clicked == trader_player, "vanilla still answers the click")

	set_trade(inv, stack("mcl_core:emerald", 10), stack("mcl_farming:bread", 6))
	draw(name, inv)
	expect(inv:get_stack("wanted", 1):get_count(), 9, "priced on opening")
	assert(shown[#shown].formspec:find("item_image[2,1;1,1;mcl_core:emerald 9]", 1, true), "and drawn at that price")
	expect(v._trades, "untouched", "_trades stays as it was")
	expect(refreshed, 0, "no refresh with nothing in the input")

	-- Paging: a new trade, with items already in the input: refresh the offer.
	inv:set_stack("input", 1, stack("mcl_core:emerald", 9))
	set_trade(inv, stack("mcl_core:emerald", 5), stack("mcl_farming:bread", 6))
	draw(name, inv)
	expect(inv:get_stack("wanted", 1):get_count(), 4, "priced on paging")
	expect(refreshed, 1, "the offer is judged again at the new price")

	-- Non-stacking goods use the higher multiplier: floor(0.2 * 24) = 4.
	set_trade(inv, stack("mcl_core:emerald", 10), stack("mcl_tools:pick_iron", 1, 1))
	draw(name, inv)
	expect(inv:get_stack("wanted", 1):get_count(), 6, "the higher multiplier")

	-- A redraw inside on_take must not price the priced list again.
	taken_redraw = true
	local before = inv:get_stack("wanted", 1):get_count()
	local rep = gossip.reputation(v, name)
	expect(callbacks.on_take(inv, "output", 1, stack(), trader_player), "vanilla take", "the result goes through")
	expect(inv:get_stack("wanted", 1):get_count(), before, "not priced twice")
	expect(gossip.reputation(v, name), math.min(rep + 4, 25), "the trade is noted")
	callbacks.on_take(inv, "input", 1, stack(), trader_player)
	expect(gossip.reputation(v, name), math.min(rep + 4, 25), "taking back the input is no trade")

	-- A changed formspec: no price in the list that the drawing does not show.
	local warnings = #logged
	set_trade(inv, stack("mcl_core:emerald", 10), stack("mcl_farming:bread", 6))
	minetest.show_formspec(name, "mobs_mc:trade_" .. name, "a redesigned window")
	expect(inv:get_stack("wanted", 1):get_count(), 10, "the base price stands")
	assert(#logged > warnings and logged[#logged]:find("trade window has changed", 1, true), "and it says so")

	-- Another player's price is their own, and other forms are left alone.
	local other = "other"
	local other_inv = trade_inventory(other)
	def.on_rightclick(v, player(other))
	set_trade(other_inv, stack("mcl_core:emerald", 10), stack("mcl_farming:bread", 6))
	draw(other, other_inv)
	expect(other_inv:get_stack("wanted", 1):get_count(), 10, "a stranger pays the base price")
	minetest.show_formspec(name, "something_else", "item_image[2,1;1,1;mcl_core:emerald 10]")
	assert(shown[#shown].formspec:find("emerald 10", 1, true), "another form is untouched")

	-- Disliked: the price rises.
	local hated = villager()
	for _ = 1, 4 do gossip.add(hated, name, "major_negative") end
	def.on_rightclick(hated, trader_player)
	set_trade(inv, stack("mcl_core:emerald", 10), stack("mcl_farming:bread", 6))
	draw(name, inv)
	expect(inv:get_stack("wanted", 1):get_count(), 10 + 25, "dislike costs more")

	-- Setting off: vanilla's price.
	setting = false
	set_trade(inv, stack("mcl_core:emerald", 10), stack("mcl_farming:bread", 6))
	draw(name, inv)
	expect(inv:get_stack("wanted", 1):get_count(), 10, "off: the base price")
	setting = true

	for _, fn in ipairs(leave_callbacks) do fn(trader_player) end
	set_trade(inv, stack("mcl_core:emerald", 10), stack("mcl_farming:bread", 6))
	draw(name, inv)
	expect(inv:get_stack("wanted", 1):get_count(), 10, "gone: the session is forgotten")
end

-- Golems: at the threshold, from villagers in the box, not if a player built it.
local function golem(x, z)
	local self = {name = "mobs_mc:iron_golem", view_range = 16, pos = {x = x or 0, y = 0, z = z or 0}, _villages_gossip_scan = 0}
	self.object = {get_pos = function() return self.pos end}
	function self:do_attack(target) self.attack = target end
	return self
end

do
	clear()
	local bad = player("bad", 2, 0)
	objects[#objects + 1] = bad
	local v = villager(3, 0)
	gossip.add(v, "bad", "major_negative")
	gossip.add(v, "bad", "major_negative")
	gossip.add(v, "bad", "major_negative") -- 75 x -5 = -375
	gossip.add(v, "bad", "major_positive")

	local g = golem()
	expect(golem_def.do_custom(g, 1), "vanilla golem", "the result goes through")
	assert(g.attack == bad and g._aggro, "a hated player is attacked")

	local again = golem()
	again._villages_gossip_scan = 3
	golem_def.do_custom(again, 1)
	assert(not again.attack, "between scans it does nothing")

	local busy = golem()
	busy.state = "attack"
	golem_def.do_custom(busy, 1)
	assert(not busy.attack, "one already fighting keeps its fight")

	v._villages_gossip.bad = {major_negative = 20}
	local threshold = golem()
	golem_def.do_custom(threshold, 1)
	assert(threshold.attack == bad, "-100 is enough")

	v._villages_gossip.bad = {major_negative = 19}
	local spared = golem()
	golem_def.do_custom(spared, 1)
	assert(not spared.attack, "-95 is not")

	v._villages_gossip.bad = {major_negative = 100}
	creative.bad = true
	local peaceful = golem()
	golem_def.do_custom(peaceful, 1)
	assert(not peaceful.attack, "creative players are left alone")
	creative.bad = nil
	mcl_mobs.invis.bad = true
	local blind = golem()
	golem_def.do_custom(blind, 1)
	assert(not blind.attack, "nor is an invisible player seen")
	mcl_mobs.invis.bad = nil

	setting = false
	local off = golem()
	golem_def.do_custom(off, 1)
	assert(not off.attack, "off: no attack")
	setting = true

	-- A villager outside the golem's box does not count, though in scan range.
	v.pos = {x = 11, y = 0, z = 0}
	local out_of_box = golem()
	golem_def.do_custom(out_of_box, 1)
	assert(not out_of_box.attack, "the box limits who is asked")
	v.pos = {x = 3, y = 0, z = 0}

	-- A golem built from a pumpkin is flagged and never turns; one activated otherwise is not.
	summoned_golem = golem()
	expect(mobs_mc.check_iron_golem_summon(), "summoned", "the result goes through")
	assert(summoned_golem._villages_player_built, "a built golem is flagged")
	golem_def.do_custom(summoned_golem, 1)
	assert(not summoned_golem.attack, "and spares even a hated player")
	local village_golem = golem()
	golem_def.on_activate(village_golem)
	assert(not village_golem._villages_player_built, "a village golem is not")
end

-- The cure: whoever fed the apple is credited on the new villager, and nobody else.
do
	clear()
	local healer = player("healer")
	local z = {name = "mobs_mc:villager_zombie"}
	zombie_def.on_rightclick(z, healer)
	expect(z._villages_curer, "healer", "the curer is noted")
	z._curing = 0
	z.cured = villager()
	zombie_def.do_custom(z, 1)
	expect(z.cured._villages_gossip.healer.major_positive, 20, "major_positive")
	expect(z.cured._villages_gossip.healer.minor_positive, 25, "minor_positive")
	expect(gossip.reputation(z.cured, "healer"), 125, "worth 125")

	-- A second click while curing does not change who gets the credit.
	local z2 = {name = "mobs_mc:villager_zombie", _curing = 50, _villages_curer = "healer"}
	zombie_def.on_rightclick(z2, player("latecomer"))
	expect(z2._villages_curer, "healer", "the first curer stands")

	local plain = villager()
	def.on_activate(plain)
	assert(plain._villages_gossip == nil, "a villager activated otherwise gets nothing")
end

-- status, for the Lookup Tool; and what is saved is plain data.
do
	local v = villager()
	expect(gossip.status(v), "knows of nobody", "an empty memory")
	gossip.add(v, "alice", "trading")
	gossip.add(v, "alice", "minor_negative")
	gossip.add(v, "bob", "major_positive")
	expect(gossip.status(v), "alice -21 (trading 4, minor_negative 25); bob 100 (major_positive 20)", "the line")
	for subject, entries in pairs(v._villages_gossip) do
		assert(type(subject) == "string")
		for kind, value in pairs(entries) do assert(type(kind) == "string" and type(value) == "number") end
	end
	assert(type(v._villages_gossip_decayed) == "number", "the decay clock is saved too")
end

print("gossip tests passed")
