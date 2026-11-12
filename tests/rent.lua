-- Run with: lua tests/rent.lua
local now, day, time = 1000, 3, 6000 / 24000
local settings, logs, objects = {time_speed = "72"}, {}, {}
local nodes, metas = {}, {}
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	round = function(a) return {x = math.floor(a.x + 0.5), y = math.floor(a.y + 0.5), z = math.floor(a.z + 0.5)} end,
}

-- A chest inventory of {name, count} stacks.
local function inventory(size)
	local inv = {stacks = {}, size = size or 4}
	local function split(text)
		local name, count = text:match("^(%S+)%s*(%d*)")
		return name, tonumber(count) or 1
	end
	function inv:get_list()
		local list = {}
		for _, s in ipairs(self.stacks) do
			list[#list + 1] = {get_name = function() return s.name end, get_count = function() return s.count end}
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
	function inv:get_size() return self.size end
	return inv
end
local function meta_of(pos)
	local k = key(pos)
	metas[k] = metas[k] or {strings = {}, inv = inventory()}
	return metas[k]
end
local function place(pos, name) nodes[key(pos)] = name return pos end
local function count_in(pos, item)
	local total = 0
	for _, s in ipairs(meta_of(pos).inv.stacks) do
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
	get_node_or_nil = function(pos) return {name = nodes[key(pos)] or "air"} end,
	get_node = function(pos) return {name = nodes[key(pos)] or "air"} end,
	get_meta = function(pos)
		local m = meta_of(pos)
		return {
			get_string = function(_, k) return m.strings[k] or "" end,
			set_string = function(_, k, v) m.strings[k] = v end,
			get_inventory = function() return m.inv end,
		}
	end,
	find_nodes_in_area = function(minp, maxp, names)
		local wanted = {}
		for _, n in ipairs(type(names) == "table" and names or {names}) do wanted[n] = true end
		local found = {}
		for k, name in pairs(nodes) do
			local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
			local p = {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
			local is_bed = name:find("^mcl_beds:") ~= nil
			if (wanted[name] or (is_bed and wanted["group:bed"]))
				and p.x >= minp.x and p.x <= maxp.x and p.y >= minp.y and p.y <= maxp.y and p.z >= minp.z and p.z <= maxp.z then
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

local rent = dofile("rent.lua")
local possessions = dofile("possessions.lua")
local clock = dofile("economy_clock.lua")
local EMERALD = "mcl_core:emerald"
-- Emeralds per vanilla emerald (ticket 11h): rent and dinners are 64.
local S = 64
local DAY = 86400 / 72 -- seconds of game time in a day at time_speed 72
local PERIOD = rent.RENT_DAYS * DAY

local function villager(id, at, fields)
	local pos = vector.new(at)
	local v = {name = "mobs_mc:villager", _id = id, _profession = "farmer", _bed = vector.new(at), walks = {},
		_villages_econ_clock = 0, state = "stand"}
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
local function emeralds(v) return possessions.emeralds(v) end
local function work(v, seconds) v._villages_econ_clock = clock.read(v) + seconds end

-- A Builder's bench, claimed, with a chest beside it; the Builder noted it.
local bench = place({x = 0, y = 1, z = 0}, "living_villages:builder_block")
local bench_chest = place({x = 2, y = 1, z = 0}, "mcl_chests:chest_small")
local bob = villager("bob-builder", {x = 0, y = 1, z = 3}, {_profession = "mason", _villages_builder = true,
	_jobsite = vector.new(bench), _villages_belongings = {[EMERALD] = S}})
minetest.get_meta(bench):set_string("villager", bob._id)
assert(rent.landlord(bob) == nil, "the Builder pays no rent")

-- No bench noted yet: a farmer owes nothing, and its time is not billed later.
local fay = villager("fay-farmer", {x = 20, y = 1, z = 0}, {_villages_belongings = {[EMERALD] = 4 * S}})
work(fay, PERIOD * 3)
assert(rent.accrue(fay) == 0 and rent.status(fay) == "none")
rent.note_bench(bob._jobsite)
assert(rent.landlord(fay).x == 0, "a farmer owes the nearest claimed bench")
assert(rent.accrue(fay) == 0, "owing starts when the landlord is known")

-- RENT every RENT_DAYS days of economic clock.
work(fay, PERIOD - 1)
assert(rent.accrue(fay) == 0)
work(fay, 1)
assert(rent.accrue(fay) == rent.RENT)
work(fay, PERIOD * 5)
assert(rent.accrue(fay) == rent.RENT_CAP, "arrears stop at the cap")
assert(logs[#logs]:find("fay%-fa owed 384 rent to the bench at %(0,1,0%); 192 forgiven"), logs[#logs])

-- Not a food producer, not in a Builder's house: no rent. A child, the keeper: none.
local liv = villager("liv-librarian", {x = 10, y = 1, z = 0}, {_profession = "librarian"})
assert(rent.landlord(liv) == nil)
assert(rent.landlord(villager("kid", {x = 11, y = 1, z = 0}, {child = true})) == nil)
local kim = villager("kim-keeper", {x = 40, y = 1, z = 0}, {_villages_keeper = true})
assert(rent.landlord(kim) == nil)
-- The keeper's household (a bed in its house) eats free and pays no rent either.
rent.note_keeper(kim)
local fred = villager("fred-fisher", {x = 42, y = 1, z = 2}, {_profession = "fisherman"})
assert(rent.landlord(fred) == nil, "of the keeper's household")
local finn = villager("finn-fisher", {x = 60, y = 1, z = 0}, {_profession = "fisherman"})
assert(rent.landlord(finn) ~= nil)
-- Too far from any bench.
assert(rent.landlord(villager("far", {x = 300, y = 1, z = 0})) == nil)

-- A house the Builder built: its beds owe the bench, whoever sleeps there.
place({x = 10, y = 1, z = 0}, "mcl_beds:bed_red_bottom")
place({x = 10, y = 1, z = 1}, "mcl_beds:bed_red_top")
place({x = 90, y = 1, z = 0}, "mcl_beds:bed_red_bottom") -- outside the footprint
assert(rent.mark_beds(bench, {x = 8, y = 0, z = -2}, {x = 14, y = 5, z = 4}) == 2)
assert(rent.landlord(liv).x == 0, "a librarian in the Builder's house owes it")
-- A bench no longer claimed is no landlord.
minetest.get_meta(bench):set_string("villager", "")
assert(rent.landlord(liv) == nil and rent.landlord(fay) == nil)
-- Claimed again, it is a landlord once its Builder notes it, as it does every step.
minetest.get_meta(bench):set_string("villager", bob._id)
assert(rent.landlord(fay) == nil)
rent.note_bench(bob._jobsite)

-- Paid at the end of a conversation with the Builder, from emeralds above a dinner.
assert(rent.payable(fay) == 3 * S)
assert(rent.settle({fay, bob}) == 3 * S)
assert(emeralds(fay) == S and emeralds(bob) == 4 * S and fay._villages_rent.owed == 0)
assert(logs[#logs]:find("fay%-fa paid 192 emerald%(s%) rent to builder bob%-bu in person, owes 0"), logs[#logs])
assert(rent.status(fay):find("owes 0 to the bench at %(0,1,0%), paid 192 on day 3 %(in person%)"), rent.status(fay))
-- Keeps a dinner's price (18) back: with that much and no more it owes, but pays nothing.
work(fay, PERIOD)
fay._villages_belongings[EMERALD] = rent.DINNER
assert(rent.DINNER == 18 and rent.accrue(fay) == S and rent.payable(fay) == 0 and rent.settle({fay, bob}) == 0)
fay._villages_belongings[EMERALD] = S
assert(rent.payable(fay) == S - 18, "above it, pays what it can")
-- Not to just anyone: a conversation without its Builder settles nothing.
fay._villages_belongings[EMERALD] = 5 * S
assert(rent.settle({fay, liv}) == 0 and fay._villages_rent.owed == S)

-- A farm's chest nearer the bench is not where rent goes: its emeralds are the farmer's.
local farm_chest = place({x = 1, y = 1, z = 1}, "mcl_chests:chest_small")
place({x = 1, y = 1, z = 2}, "mcl_composters:composter")
-- Owing what it can pay, it pays by errand in its putter stage: walks to the bench's chest.
work(fay, PERIOD * 2)
assert(rent.accrue(fay) == rent.RENT_CAP)
time = 6000 / 24000
rent.step(fay, now)
assert(fay._villages_rent_errand and #fay.walks == 1 and fay.walks[1].x == 2, "walks to the bench chest")
assert(logs[#logs]:find("sets off to pay 192 emerald%(s%) rent at %(2,1,0%)"), logs[#logs])
rent.step(fay, now + 5)
assert(#fay.walks == 1, "waits for the walk")
-- A walk another mover took over is walked again at once, not waited out.
fay.lose("taken over by another mover")
rent.step(fay, now + 6)
assert(#fay.walks == 2 and fay._villages_rent_errand.tries == 2, "walks again after a lost walk")
fay.arrive()
rent.step(fay, now + 10)
assert(not fay._villages_rent_errand and count_in(bench_chest, EMERALD) == 3 * S and emeralds(fay) == 2 * S)
assert(fay._villages_rent.owed == 0 and fay._villages_rent.paid.how == "by errand")
assert(logs[#logs]:find("paid 192 emerald%(s%) rent into the chest at %(2,1,0%), owes 0"), logs[#logs])

-- Not in the work stage, and not when a walk fails: then it waits for the next day.
work(fay, PERIOD * 3)
fay._villages_belongings[EMERALD] = 5 * S
time = 9000 / 24000
rent.step(fay, now + 20)
assert(not fay._villages_rent_errand, "only in the putter stage")
time = 6000 / 24000
fay.teleport(fay._bed)
fay.gopath = function() return false end
rent.step(fay, now + 30)
assert(not fay._villages_rent_errand and fay._villages_rent.errand_day == day)
assert(logs[#logs]:find("gave up paying rent at %(2,1,0%): no way there"), logs[#logs])
rent.step(fay, now + 40)
assert(not fay._villages_rent_errand, "tried today already")

-- One period's rent owed is enough for the errand, once it has a dinner's worth besides.
local fern = villager("fern-farmer", {x = 30, y = 1, z = 0}, {_villages_belongings = {[EMERALD] = 2 * S}})
rent.accrue(fern)
work(fern, PERIOD)
rent.step(fern, now + 50)
assert(fern._villages_rent.owed == S and fern._villages_rent_errand and #fern.walks == 1, "goes to pay a period's rent")
-- By the chest it pays, though its walk never reported arriving.
fern.teleport({x = 3, y = 1, z = 1})
rent.step(fern, now + 55)
assert(fern._villages_rent.owed == 0 and not fern._villages_rent_errand and emeralds(fern) == S, "pays at the chest")

-- Off with the economy: nothing settles.
settings.living_villages_economy = false
assert(rent.settle({fay, bob}) == 0)
settings.living_villages_economy = nil

print("rent: ok")
