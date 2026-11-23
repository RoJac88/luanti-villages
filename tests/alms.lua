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
-- Progressive (ticket 37b): a tenth from 8 to 24 dinners, a fifth to 64, three tenths past.
local D = ledger.DINNER
assert(alms.donation(24 * D) == math.floor(16 * D * 0.1))
assert(alms.donation(64 * D) == math.floor(16 * D * 0.1 + 40 * D * 0.2))
assert(alms.donation(100 * D) == math.floor(16 * D * 0.1 + 40 * D * 0.2 + 36 * D * 0.3))
assert(alms.donation(32 * D, 0.5) == math.floor(16 * D * 0.5 * 0.1 + 40 * D * 0.5 * 0.2), "bands at its dinner scale")
-- 688 gives 80: 28.8 from the first band and 51.2 from the second.
local RICH = 688

-- The service: a rich farmer donates, the cleric keeps a tenth and funds the rest, a broke
-- villager is topped up to two dinners from it, and those there note the donor.
local priest = villager("cleric1", 0, {_profession = "cleric"})
local rich = villager("farmer1", RICH, {_profession = "farmer"})
local broke = villager("broke1", 3)
local middling = villager("mid1", 100)
alms.hold(priest, {broke, priest, rich, middling}, day, gossip)
local gift = alms.donation(RICH)
assert(gift == 80 and emeralds(rich) == RICH - gift)
assert(emeralds(priest) == 8, "keeps a tenth")
assert(emeralds(broke) == alms.ALMS_TO, "topped up to two dinners")
assert(priest._villages_alms == 72 - (alms.ALMS_TO - 3))
assert(emeralds(middling) == 100, "neither gives nor gets")
assert(logged("alms: villager farmer gave 80") and logged("alms: cleric cleric gave 33 emerald(s) to villager broke1"))
-- 80 is two dinners or more: minor and major. The donor does not gossip about itself.
local subject = gossip.villager_subject("farmer1")
assert(gossip.reputation(middling, subject) == 125 and gossip.reputation(broke, subject) == 125)
assert(gossip.reputation(rich, subject) == 0)
assert(alms.status(rich) == "gave 80 on day 8" and alms.status(broke) == "alms on day 8")
assert(alms.status(priest):find("alms fund 39", 1, true))

-- Each one there swapped market news with the cleric, once this holiday.
assert(rich._villages_church_news == day and broke._villages_church_news == day and not priest._villages_church_news)
local heard_rich = false
for _, entry in ipairs(priest._villages_market_news or {}) do
	if entry.who == "farmer1" then heard_rich = true end
end
assert(heard_rich, "the cleric heard the farmer's news")
assert(alms.church_news(priest, rich, day) == false and alms.church_news(priest, rich, day + 4) == true)
rich._villages_church_news = day

-- Once a holiday: a second look the same day changes nothing.
alms.hold(priest, {broke, priest, rich, middling}, day, gossip)
assert(emeralds(rich) == RICH - gift and emeralds(priest) == 8)
-- The next holiday it gives again.
alms.hold(priest, {priest, rich}, day + 4, gossip)
assert(emeralds(rich) == RICH - gift - alms.donation(RICH - gift))

-- An empty fund gives nothing, and the villager can still get alms later that day.
local poor_priest = villager("cleric2", 0, {_profession = "cleric"})
local waiting = villager("waiting", 0)
assert(alms.give(poor_priest, waiting, day) == 0 and waiting._villages_alms_got == nil)
poor_priest._villages_alms = 5
assert(alms.give(poor_priest, waiting, day) == 5 and poor_priest._villages_alms == nil)

-- One that can pay one dinner but not two is topped up too (ticket 19).
do
	local fund = villager("cleric4", 0, {_profession = "cleric", _villages_alms = 100})
	local short = villager("short", ledger.DINNER + 2)
	assert(alms.give(fund, short, day) == alms.ALMS_TO - ledger.DINNER - 2 and emeralds(short) == alms.ALMS_TO)
	assert(alms.give(fund, villager("enough", alms.ALMS_TO), day) == 0, "two dinners is enough")
end

-- A broke craftsman gets a stake past two dinners, the price of four crafts of its
-- cheapest recipe, fuel too (ColonyFood, 2026-11-14: a butcher with one emerald could not
-- buy the beef piling up at the leatherworker's). No recipe, no stake; nor for the keeper
-- or a Builder.
do
	local stake = alms.stake({_profession = "butcher"})
	local beef = ledger.price("mcl_mobitems:beef") + ledger.price("mcl_core:coal_lump")
	assert(stake > 0 and stake <= math.min(math.ceil(beef * alms.CRAFT_BATCH), alms.STAKE_CAP), "beef, or cheaper")
	assert(alms.stake({_profession = "nitwit"}) == 0 and alms.stake({_profession = "farmer"}) == 0)
	assert(alms.stake({_profession = "butcher", _villages_keeper = true}) == 0)
	assert(alms.stake({_profession = "mason", _villages_builder = true}) == 0)
	assert(alms.stake({_profession = "weapon_smith"}) == alms.STAKE_CAP, "capped")

	-- Two dinners for everyone first, then the stakes; a small fund runs out on the stake.
	local fund = villager("cleric5", 0, {_profession = "cleric", _villages_alms = alms.ALMS_TO * 2 + 10})
	local butcher = villager("butch", 0, {_profession = "butcher"})
	local idle = villager("idle", 0)
	alms.hold(fund, {butcher, fund, idle}, day, nil)
	assert(emeralds(idle) == alms.ALMS_TO, "food money first")
	assert(emeralds(butcher) == alms.ALMS_TO + 10 and fund._villages_alms == nil, "the stake takes what is left")
	-- With the fund empty, the cleric gives from its own emeralds over its savings.
	local rich_priest = villager("cleric6", alms.SAVINGS + 100, {_profession = "cleric"})
	local smith = villager("smith", 0, {_profession = "tool_smith"})
	alms.hold(rich_priest, {smith}, day, nil)
	local want = alms.ALMS_TO + alms.stake(smith)
	assert(emeralds(smith) == want and emeralds(rich_priest) == alms.SAVINGS + 100 - want)
	-- Once a holiday: nothing more today, even after spending it.
	possessions.take(smith, EMERALD, want)
	alms.hold(rich_priest, {smith}, day, nil)
	assert(emeralds(smith) == 0)
	-- Never below its savings.
	local thrifty = villager("cleric7", alms.SAVINGS, {_profession = "cleric"})
	assert(alms.give(thrifty, villager("x", 0), day) == 0 and emeralds(thrifty) == alms.SAVINGS)
end

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

-- An alchemist (ticket 20) never goes to church: one near the pulpit neither gives nor gets.
do
	local fund = villager("cleric8", 0, {_profession = "cleric", _villages_alms = 500})
	local rich_alchemist = villager("alch1", alms.SAVINGS + 800, {_profession = "cleric", _villages_alchemist = true})
	local poor_alchemist = villager("alch2", 0, {_profession = "cleric", _villages_alchemist = true})
	alms.hold(fund, {fund, rich_alchemist, poor_alchemist}, day + 40, gossip)
	assert(emeralds(rich_alchemist) == alms.SAVINGS + 800 and not rich_alchemist._villages_donated, "gives nothing")
	assert(emeralds(poor_alchemist) == 0 and fund._villages_alms == 500, "gets nothing")
	-- Found near the pulpit (E11), a poor one gets its stake: topped up to ALCHEMIST_STAKE,
	-- from the fund; a rich one nothing.
	alms.hold(fund, {fund}, day + 41, gossip, {rich_alchemist, poor_alchemist})
	local stake = alms.alchemist_stake(poor_alchemist)
	assert(stake == alms.ALCHEMIST_STAKE, stake)
	assert(emeralds(poor_alchemist) == math.min(stake, 500), emeralds(poor_alchemist))
	assert(emeralds(rich_alchemist) == alms.SAVINGS + 800, "a rich one gets none")
	-- Once a service: the same day again gives nothing more.
	local had = emeralds(poor_alchemist)
	alms.hold(fund, {fund}, day + 41, gossip, {poor_alchemist})
	assert(emeralds(poor_alchemist) == had)
	-- The fund's target counts each one's stake.
	assert(alms.fund_target(fund, {fund}, {poor_alchemist}) == alms.FUND_HOLIDAYS * stake)
end

-- With the economy off, nothing is installed.
settings.living_villages_economy = false
local def = {do_custom = function() return true end}
local before = def.do_custom
alms.install(def, gossip)
assert(def.do_custom == before)

-- A fund that spends down (ticket 22a): its target is FUND_HOLIDAYS holidays of everyone's
-- level; under it a donation is no more than it lacks, at it none, over it the excess goes
-- out poorest first toward savings.
do
	local a, b = villager("ta", 0), villager("tb", 0, {_profession = "weapon_smith"})
	assert(alms.level(a) == alms.ALMS_TO and alms.level(b) == alms.ALMS_TO + alms.STAKE_CAP)
	local priest9 = villager("cleric9", 0, {_profession = "cleric"})
	assert(alms.fund_target(priest9, {priest9, a, b}) == alms.FUND_HOLIDAYS * (2 * alms.ALMS_TO + alms.STAKE_CAP))

	-- Room for 10: the donor gives 10, not a tenth of its excess.
	local full = villager("cleric10", 0, {_profession = "cleric"})
	local donor = villager("donor", alms.SAVINGS + 2000)
	local enough = villager("enough2", alms.SAVINGS)
	local target = alms.target(full, {full, donor, enough})
	full._villages_alms = target - 10
	alms.hold(full, {full, donor, enough}, day, nil)
	assert(emeralds(donor) == alms.SAVINGS + 2000 - 10, "gives only what the fund lacks")
	-- At the target: nothing taken, and its money stays its own.
	local at = villager("cleric11", 0, {_profession = "cleric"})
	local donor2 = villager("donor2", alms.SAVINGS + 2000)
	at._villages_alms = alms.target(at, {at, donor2, enough})
	alms.hold(at, {at, donor2, enough}, day, nil)
	assert(emeralds(donor2) == alms.SAVINGS + 2000 and donor2._villages_donated == day)

	-- Over it: alms first, then the excess to the poorest, toward savings, down to the target.
	local hoard = villager("cleric12", 0, {_profession = "cleric"})
	local zero, some, saver = villager("zero", 0), villager("some", 50), villager("saver", alms.SAVINGS)
	local list = {hoard, saver, some, zero}
	local t = alms.target(hoard, list)
	hoard._villages_alms = t + 200
	alms.hold(hoard, list, day, nil)
	-- zero: ALMS_TO, then up to SAVINGS; some: what is left of the 200.
	assert(emeralds(zero) == alms.SAVINGS, emeralds(zero))
	assert(emeralds(saver) == alms.SAVINGS, "at its savings: nothing")
	assert(hoard._villages_alms == t, hoard._villages_alms)
	assert(emeralds(some) == 50 + 200 - alms.SAVINGS, emeralds(some))
	-- Only the fund: its own emeralds stay.
	assert(emeralds(hoard) == 0)
	-- At a cheap dinner too it tops up toward SAVINGS at the old dinner, not 8 dinners at
	-- 1 emerald (ColonyFood, 2026-11-15: a fund of 1,702 gave 15).
	local cheap_priest = villager("cleric13", 0, {_profession = "cleric"})
	local dinner_item = ledger.DINNER_ITEM
	local thin = villager("thin", 0, {_villages_prices = {[dinner_item] = 1 / 18}})
	local cheap_list = {cheap_priest, thin}
	cheap_priest._villages_alms = alms.target(cheap_priest, cheap_list) + 500
	alms.hold(cheap_priest, cheap_list, day, nil)
	assert(emeralds(thin) == alms.SAVINGS, emeralds(thin))
end

-- Rotten flesh (ticket 37b): the target holds a flesh reserve past the alms; the cleric pays
-- for flesh from the fund past its alms part, then its own emeralds past SAVINGS.
do
	local p = villager("cleric20", 0, {_profession = "cleric"})
	local poor = villager("poor20", 0)
	local list = {p, poor}
	assert(alms.flesh_reserve(p) == 12 * ledger.DINNER)
	assert(alms.target(p, list) == alms.fund_target(p, list) + alms.flesh_reserve(p))
	-- Before its first service its fund is all for alms.
	p._villages_alms = 1000
	assert(alms.flesh_budget(p) == 0 and not alms.pay_flesh(p, 1))
	alms.hold(p, list, day + 50, nil)
	local need = alms.fund_target(p, list)
	assert(p._villages_alms_need == need)
	local fund = p._villages_alms
	assert(alms.flesh_budget(p) == fund - need, alms.flesh_budget(p))
	-- Its own past SAVINGS counts too, and is spent after the fund.
	p._villages_belongings[EMERALD] = alms.SAVINGS + 30
	local budget = alms.flesh_budget(p)
	assert(budget == fund - need + 30)
	assert(alms.pay_flesh(p, fund - need + 10))
	assert(p._villages_alms == need and emeralds(p) == alms.SAVINGS + 20, "the fund first, then its own")
	assert(not alms.pay_flesh(p, 21) and alms.pay_flesh(p, 20) and emeralds(p) == alms.SAVINGS)
	assert(alms.flesh_budget(p) == 0, "the alms part and its savings are never spent on flesh")
end

print("alms.lua: ok")
