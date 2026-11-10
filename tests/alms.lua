-- Run with: lua tests/alms.lua
local now, day = 1000, 8
local settings = {}
local logs = {}

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	round = function(a) return {x = math.floor(a.x + 0.5), y = math.floor(a.y + 0.5), z = math.floor(a.z + 0.5)} end,
}

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	get_day_count = function() return day end,
	get_timeofday = function() return 0.5 end,
	get_node_or_nil = function() return nil end,
	get_meta = function() return {get_string = function() return "" end} end,
	settings = {
		get = function(_, name) return settings[name] end,
		get_bool = function(_, name, default)
			if settings[name] == nil then return default end
			return settings[name]
		end,
	},
	log = function(_, message) table.insert(logs, message) end,
	registered_items = {},
	registered_nodes = {},
	add_particle = function() end,
	sound_play = function() end,
	pos_to_string = function(p) return p.x .. "," .. p.y .. "," .. p.z end,
}

local alms = dofile("alms.lua")
local gossip = dofile("gossip.lua")
local exchange = dofile("exchange.lua")
local possessions = dofile("possessions.lua")
local ledger = dofile("ledger.lua")
local EMERALD = "mcl_core:emerald"

local function villager(id, emeralds, fields)
	local v = {_id = id, _profession = "nitwit", _villages_food = 12,
		_villages_belongings = {[EMERALD] = emeralds > 0 and emeralds or nil},
		object = {get_pos = function() return {x = 0, y = 0, z = 0} end}}
	for k, value in pairs(fields or {}) do v[k] = value end
	return v
end
local function emeralds(v) return possessions.emeralds(v) end
local function logged(text)
	for _, line in ipairs(logs) do if line:find(text, 1, true) then return true end end
	return false
end

-- A tenth of what is over the savings, at least 1; nothing at or under them.
assert(alms.SAVINGS == 8 * ledger.DINNER)
assert(alms.donation(alms.SAVINGS) == 0)
assert(alms.donation(alms.SAVINGS + 1) == 1)
assert(alms.donation(alms.SAVINGS + 150) == 15)

-- The service: a rich farmer donates, the cleric keeps half and funds the rest, a broke
-- villager is topped up to two dinners from it, and those there note the donor.
local priest = villager("cleric1", 0, {_profession = "cleric"})
local rich = villager("farmer1", alms.SAVINGS + 800, {_profession = "farmer"})
local broke = villager("broke1", 3)
local middling = villager("mid1", 100)
alms.hold(priest, {broke, priest, rich, middling}, day, gossip)
local gift = alms.donation(alms.SAVINGS + 800)
assert(gift == 80 and emeralds(rich) == alms.SAVINGS + 800 - gift)
assert(emeralds(priest) == 40, "keeps half")
assert(emeralds(broke) == alms.ALMS_TO, "topped up to two dinners")
assert(priest._villages_alms == 40 - (alms.ALMS_TO - 3))
assert(emeralds(middling) == 100, "neither gives nor gets")
assert(logged("alms: villager farmer gave 80") and logged("alms: cleric cleric gave 33 emerald(s) to villager broke1"))
-- 80 is two dinners or more: minor and major. The donor does not gossip about itself.
local subject = gossip.villager_subject("farmer1")
assert(gossip.reputation(middling, subject) == 125 and gossip.reputation(broke, subject) == 125)
assert(gossip.reputation(rich, subject) == 0)
assert(alms.status(rich) == "gave 80 on day 8" and alms.status(broke) == "alms on day 8")
assert(alms.status(priest):find("alms fund 7", 1, true))

-- Once a holiday: a second look the same day changes nothing.
alms.hold(priest, {broke, priest, rich, middling}, day, gossip)
assert(emeralds(rich) == alms.SAVINGS + 800 - gift and emeralds(priest) == 40)
-- The next holiday it gives again.
alms.hold(priest, {priest, rich}, day + 4, gossip)
assert(emeralds(rich) == alms.SAVINGS + 800 - gift - alms.donation(alms.SAVINGS + 800 - gift))

-- An empty fund gives nothing, and the villager can still get alms later that day.
local poor_priest = villager("cleric2", 0, {_profession = "cleric"})
local waiting = villager("waiting", 0)
assert(alms.give(poor_priest, waiting, day) == 0 and waiting._villages_alms_got == nil)
poor_priest._villages_alms = 5
assert(alms.give(poor_priest, waiting, day) == 5 and poor_priest._villages_alms == nil)

-- A small gift is minor gossip.
local modest = villager("modest", alms.SAVINGS + 20)
local seen_by = villager("seen", 50)
alms.hold(villager("cleric3", 0, {_profession = "cleric"}), {modest, seen_by}, day, gossip)
assert(gossip.reputation(seen_by, gossip.villager_subject("modest")) == 25)

-- Standing in trade: a seller that thinks well of the buyer charges less, never below
-- its own value; a buyer that thinks well of the seller pays more.
local seller, buyer = villager("s", 0), villager("b", 0)
assert(exchange.unit_price(seller, buyer, 10, 20) == 15)
gossip.add(seller, gossip.villager_subject("b"), "major_positive")
assert(math.abs(exchange.unit_price(seller, buyer, 10, 20) - 15 * 0.9) < 1e-9)
assert(exchange.unit_price(seller, buyer, 14.5, 15) == 14.5, "not below the seller's value")
gossip.add(buyer, gossip.villager_subject("s"), "major_positive")
assert(exchange.unit_price(seller, buyer, 10, 20) == 15, "both ways cancel")

-- Villager subjects pass in their own share: a memory full of player gossip still
-- passes a donor on.
local talker, listener = villager("talker", 0), villager("listener", 0)
for i = 1, gossip.SHARE_ENTRIES + 5 do gossip.add(talker, "player" .. i, "major_negative") end
gossip.add(talker, gossip.villager_subject("farmer1"), "minor_positive")
gossip.share(talker, listener)
assert(gossip.reputation(listener, gossip.villager_subject("farmer1")) > 0, "the donor is passed on")

-- With the economy off, nothing is installed.
settings.living_villages_economy = false
local def = {do_custom = function() return true end}
local before = def.do_custom
alms.install(def, gossip)
assert(def.do_custom == before)

print("alms.lua: ok")
