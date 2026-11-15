-- Run with: luajit tests/comforts.lua
-- Comforts (ticket 19): goods a villager with savings buys for its own sake and uses up.
local logs = {}
local clock = 5000
minetest = {
	get_modpath = function() return "." end,
	log = function(_, text) table.insert(logs, text) end,
	get_gametime = function() return clock end,
}
local comforts = dofile("comforts.lua")
local ledger = dofile("ledger.lua")
local wants = dofile("wants.lua")

local DAY = wants.DAY_SECONDS
local function take_from(held)
	return function(_, item, count)
		local have = held[item] or 0
		local taken = math.min(have, count)
		held[item] = have - taken
		return taken
	end
end
local function total(targets)
	local n = 0
	for _, count in pairs(targets) do n = n + count end
	return n
end

-- Tastes: TASTES distinct comforts, always the same for one villager, and not the same
-- for everyone.
do
	local a, b = comforts.tastes("abc123"), comforts.tastes("abc123")
	assert(#a == comforts.TASTES)
	local seen = {}
	for i, taste in ipairs(a) do
		assert(b[i].item == taste.item, "the same each time")
		assert(not seen[taste.item], "distinct")
		seen[taste.item] = true
	end
	local differ = false
	for _, id in ipairs({"f00d", "beef", "cafe", "0123456789", "zz"}) do
		if comforts.tastes(id)[1].item ~= a[1].item then differ = true end
	end
	assert(differ, "villagers differ in taste")
end

-- Slots: none at or below the savings, one per STEP over them, up to MAX_SLOTS.
assert(comforts.slots(0) == 0 and comforts.slots(comforts.SAVINGS) == 0)
assert(comforts.slots(comforts.SAVINGS + comforts.STEP - 1) == 0)
assert(comforts.slots(comforts.SAVINGS + comforts.STEP) == 1)
assert(comforts.slots(comforts.SAVINGS + 3 * comforts.STEP) == 3)
assert(comforts.slots(comforts.SAVINGS + 6 * comforts.STEP) == comforts.BASE_SLOTS)
-- Past BASE_SLOTS each slot needs twice the span of the one before (ticket 23c): at a
-- dinner of 18, 720, 1,008 and 1,584 emeralds for the 7th, 8th and 9th, 9,648 for the 12th.
assert(comforts.SAVINGS == 144 and comforts.STEP == 72)
assert(comforts.slots(719) == 6 and comforts.slots(720) == 7)
assert(comforts.slots(1007) == 7 and comforts.slots(1008) == 8)
assert(comforts.slots(1163) == 8, "farmer 84ebb7's 1,163")
assert(comforts.slots(1584) == 9 and comforts.slots(2736) == 10 and comforts.slots(5040) == 11)
assert(comforts.slots(9647) == 11 and comforts.slots(9648) == 12)
assert(comforts.slots(1e9) == comforts.MAX_SLOTS and comforts.MAX_SLOTS == 12)

-- A poor villager wants none; a rich one a comfort per slot, round its tastes, each worth
-- at most WORTH times its price.
local v = {_id = "farmer-rich"}
local tastes = comforts.tastes(v._id)
do
	local targets = comforts.targets(v, comforts.SAVINGS, clock)
	assert(total(targets) == 0, "nothing below the savings")
	local rich = comforts.SAVINGS + 4 * comforts.STEP
	local worth
	targets, worth = comforts.targets(v, rich, clock)
	assert(total(targets) == 4)
	assert(targets[tastes[1].item] == 2 and targets[tastes[2].item] == 1 and targets[tastes[3].item] == 1,
		"round its tastes")
	for _, taste in ipairs(tastes) do
		assert(math.abs(worth[taste.item] - comforts.WORTH * ledger.price(taste.item) / ledger.lambda(rich)) < 1e-9)
	end
	assert(comforts.targets({_id = "kid", child = true}, rich, clock) and
		total(comforts.targets({_id = "kid", child = true}, rich, clock)) == 0, "no child")
end

-- An alchemist (ticket 20) wants no comforts, however rich.
assert(total(comforts.targets({_id = "alch", _villages_alchemist = true}, comforts.SAVINGS + 4 * comforts.STEP, clock)) == 0)

-- It takes up what it holds into free slots, and wants only for the slots still free.
do
	local rich = comforts.SAVINGS + 2 * comforts.STEP
	local held = {[tastes[1].item] = 3}
	comforts.update(v, rich, take_from(held), clock)
	assert(#v._villages_comforts == 1 and v._villages_comforts[1].item == tastes[1].item)
	assert(held[tastes[1].item] == 2, "one taken up")
	assert(v._villages_comforts[1]["until"] == clock + tastes[1].days * DAY)
	local targets = comforts.targets(v, rich, clock)
	assert(total(targets) == 1 and targets[tastes[2].item] == 1, "the second slot is its second taste")
	-- Nearly used up, it wants the next.
	clock = v._villages_comforts[1]["until"] - 1
	assert(total(comforts.targets(v, rich, clock)) == 2)
	-- Used up: gone, logged, and the slot filled again from what it holds.
	clock = clock + 2
	comforts.update(v, rich, take_from(held), clock)
	assert(#v._villages_comforts == 1 and held[tastes[1].item] == 1)
	local used = false
	for _, line in ipairs(logs) do if line:find("used up its " .. tastes[1].item, 1, true) then used = true end end
	assert(used)
	-- Grown poor, it keeps what it uses until it is used up, takes up no more, wants none.
	comforts.update(v, 0, take_from(held), clock)
	assert(#v._villages_comforts == 1 and held[tastes[1].item] == 1)
	assert(total(comforts.targets(v, 0, clock)) == 0)
	clock = clock + 10 * DAY
	comforts.update(v, 0, take_from(held), clock)
	assert(v._villages_comforts == nil)
end

-- Nine slots go round its tastes: the first is wanted once per round (ticket 23c).
do
	local nine = {_id = "nine"}
	local list = comforts.tastes(nine._id)
	local targets = comforts.targets(nine, 1584, clock)
	assert(total(targets) == 9)
	assert(targets[list[1].item] == math.ceil(9 / #list), tostring(targets[list[1].item]))
end

-- Every comfort has a price, so it is worth something, and lasts some days.
for _, comfort in ipairs(comforts.COMFORTS) do
	assert((ledger.price(comfort.item) or 0) > 0, comfort.item .. " has no price")
	assert(comfort.days > 0)
end

print("comforts.lua: ok")
