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
-- What comforts.targets wants in all, items and categories (a flower) together.
local function total(targets, categories)
	local n = 0
	for _, count in pairs(targets) do n = n + count end
	for _, count in pairs(categories or {}) do n = n + count end
	return n
end
-- How many of a taste it wants: a flower as its category.
local function wanted_of(taste, targets, categories)
	if taste.category then return (categories or {})[taste.category] or 0 end
	return targets[taste.item] or 0
end
-- An item that is the taste: a flower's first member for a flower.
local function item_of(taste)
	if not taste.category then return taste.item end
	local list = {}
	for item in pairs(dofile("goods.lua").CATEGORIES[taste.category]) do list[#list + 1] = item end
	table.sort(list)
	return list[1]
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
local v = {_id = "rich-farmer"}  -- no pot among its tastes: a pot wants flowers too
local tastes = comforts.tastes(v._id)
do
	local targets = comforts.targets(v, comforts.SAVINGS, clock)
	assert(total(targets) == 0, "nothing below the savings")
	local rich = comforts.SAVINGS + 5 * comforts.STEP
	local worth, categories
	targets, worth, categories = comforts.targets(v, rich, clock)
	assert(total(targets, categories) == 5)
	assert(wanted_of(tastes[1], targets, categories) == 2, "round its tastes")
	for i = 2, comforts.TASTES do assert(wanted_of(tastes[i], targets, categories) == 1, "round its tastes") end
	for _, taste in ipairs(tastes) do
		local item = item_of(taste)
		assert(math.abs(worth[item] - comforts.WORTH * ledger.price(item) / ledger.lambda(rich)) < 1e-9)
	end
	assert(comforts.targets({_id = "kid", child = true}, rich, clock) and
		total(comforts.targets({_id = "kid", child = true}, rich, clock)) == 0, "no child")
end

-- An alchemist (ticket 20) wants no comforts, however rich.
assert(total(comforts.targets({_id = "alch", _villages_alchemist = true}, comforts.SAVINGS + 4 * comforts.STEP, clock)) == 0)

-- It takes up what it holds into free slots, and wants only for the slots still free.
do
	local rich = comforts.SAVINGS + 2 * comforts.STEP
	local first = item_of(tastes[1])
	local held = {[first] = 3}
	comforts.update(v, rich, take_from(held), clock)
	assert(#v._villages_comforts == 1 and v._villages_comforts[1].item == first)
	assert(held[first] == 2, "one taken up")
	assert(v._villages_comforts[1]["until"] == clock + tastes[1].days * DAY)
	local targets, _, categories = comforts.targets(v, rich, clock)
	assert(total(targets, categories) == 1 and wanted_of(tastes[2], targets, categories) == 1,
		"the second slot is its second taste")
	-- Nearly used up, it wants the next.
	clock = v._villages_comforts[1]["until"] - 1
	local soon, _, soon_categories = comforts.targets(v, rich, clock)
	assert(total(soon, soon_categories) == 2)
	-- Used up: gone, logged, and the slot filled again from what it holds.
	clock = clock + 2
	comforts.update(v, rich, take_from(held), clock)
	assert(#v._villages_comforts == 1 and held[first] == 1)
	local used = false
	for _, line in ipairs(logs) do if line:find("used up its " .. first, 1, true) then used = true end end
	assert(used)
	-- Grown poor, it keeps what it uses until it is used up, takes up no more, wants none.
	comforts.update(v, 0, take_from(held), clock)
	assert(#v._villages_comforts == 1 and held[first] == 1)
	assert(next((comforts.targets(v, 0, clock))) == nil)
	clock = clock + 10 * DAY
	comforts.update(v, 0, take_from(held), clock)
	assert(v._villages_comforts == nil)
end

-- Nine slots go round its tastes: the first is wanted once per round (ticket 23c).
do
	local nine = {_id = "nine"}
	local list = comforts.tastes(nine._id)
	local targets, _, categories = comforts.targets(nine, 1584, clock)
	assert(total(targets, categories) == 9)
	assert(wanted_of(list[1], targets, categories) == math.ceil(9 / #list))
end

-- Each taste fills its own slots: nine slots and plenty of the first taste held fill only
-- that taste's three, and the other tastes are still wanted (ColonyFood, 2026-11-15: an
-- armorer filled all nine slots with lilies).
do
	local nine = {_id = "rich-farmer"}
	local list = comforts.tastes(nine._id)
	local first = item_of(list[1])
	local held = {[first] = 20}
	comforts.update(nine, 1584, take_from(held), clock)
	assert(#nine._villages_comforts == 3 and held[first] == 17, tostring(#nine._villages_comforts))
	comforts.update(nine, 1584, take_from(held), clock + 1)
	assert(#nine._villages_comforts == 3 and held[first] == 17, "no more the next time")
	local targets, _, categories = comforts.targets(nine, 1584, clock + 1)
	assert(wanted_of(list[1], targets, categories) == 0 and total(targets, categories) == 6)
end

-- Every comfort has a price, so it is worth something, and perishes (ticket 23b): some
-- days, never more than MAX_DAYS.
for _, comfort in ipairs(comforts.COMFORTS) do
	assert((ledger.price(comfort.item) or 0) > 0, comfort.item .. " has no price")
	assert(type(comfort.days) == "number" and comfort.days > 0 and comfort.days <= comforts.MAX_DAYS,
		comfort.item .. " must perish within MAX_DAYS")
end
assert(comforts.MAX_DAYS == 12 and comforts.TASTES == 4)

-- Flowers (ticket 23b): any flower fills a flower slot, a lily of the valley too.
local FLOWER_TASTE
for _, comfort in ipairs(comforts.COMFORTS) do if comfort.category == comforts.FLOWER then FLOWER_TASTE = comfort end end
assert(FLOWER_TASTE and FLOWER_TASTE.days == 2)
local function with_tastes(id, want)
	-- An id whose tastes include `want` (a comfort entry), first among them.
	for i = 1, 5000 do
		local candidate = id .. i
		if comforts.tastes(candidate)[1] == want then return candidate end
	end
	error("no id with that first taste")
end
do
	local f = {_id = with_tastes("flora", FLOWER_TASTE)}
	local rich = comforts.SAVINGS + comforts.STEP
	local targets, worth, categories = comforts.targets(f, rich, clock)
	assert(total(targets) == 0 and categories.flower == 1, "a flower is wanted as the category")
	assert(worth["mcl_flowers:lily_of_the_valley"] > 0 and worth["mcl_flowers:poppy"] > 0)
	local held = {["mcl_flowers:lily_of_the_valley"] = 2}
	comforts.update(f, rich, take_from(held), clock)
	assert(#f._villages_comforts == 1 and f._villages_comforts[1].item == "mcl_flowers:lily_of_the_valley")
	assert(held["mcl_flowers:lily_of_the_valley"] == 1)
	-- An old save's poppy still counts as a flower, its days and all.
	assert(comforts.by_item["mcl_flowers:dandelion"] == FLOWER_TASTE)
	-- Wilted after its days: gone from the villager.
	comforts.update(f, 0, take_from(held), clock + 2 * DAY)
	assert(f._villages_comforts == nil and held["mcl_flowers:lily_of_the_valley"] == 1)
end

-- A flower pot holds a flower: it wants one every FLOWER_DAYS, takes one it holds, and
-- keeps its slot without one. Used up, the pot and its flower are gone.
local POT_TASTE
for _, comfort in ipairs(comforts.COMFORTS) do if comfort.holds then POT_TASTE = comfort end end
assert(POT_TASTE.item == "mcl_flowerpots:flower_pot" and POT_TASTE.days == 8 and comforts.FLOWER_DAYS == 2)
do
	local t = clock
	local p = {_id = with_tastes("potter", POT_TASTE)}
	local rich = comforts.SAVINGS + comforts.STEP
	local held = {[POT_TASTE.item] = 1}
	comforts.update(p, rich, take_from(held), t)
	local pot = p._villages_comforts[1]
	assert(pot.item == POT_TASTE.item and pot.flower == nil, "no flower to put in it")
	local targets, _, categories = comforts.targets(p, rich, t)
	assert(categories.flower == 1 and total(targets) == 0, "its pot wants a flower; the slot is full")
	held["mcl_flowers:poppy"] = 3
	comforts.update(p, rich, take_from(held), t + 1)
	assert(pot.flower == "mcl_flowers:poppy" and held["mcl_flowers:poppy"] == 2)
	assert(pot.flower_until == t + 1 + 2 * DAY)
	targets, _, categories = comforts.targets(p, rich, t + 2)
	assert(not categories.flower, "a fresh flower: no want")
	-- Nearly wilted, it wants the next; wilted, the next goes in.
	targets, _, categories = comforts.targets(p, rich, pot.flower_until - 1)
	assert(categories.flower == 1)
	comforts.update(p, rich, take_from(held), pot.flower_until)
	assert(pot.flower == "mcl_flowers:poppy" and held["mcl_flowers:poppy"] == 1, "a new flower in it")
	local wilted = false
	for _, line in ipairs(logs) do if line:find("poppy wilted", 1, true) then wilted = true end end
	assert(wilted)
	-- No flower left: it wilts and the pot stays, still its slot.
	comforts.update(p, rich, take_from({}), pot.flower_until)
	assert(pot.flower == nil and #p._villages_comforts == 1)
	-- Used up after its 8 days: pot gone, nothing left of it.
	comforts.update(p, rich, take_from({}), t + 8 * DAY)
	assert(p._villages_comforts == nil and (held[POT_TASTE.item] or 0) == 0)
	assert(comforts.status(p) == "none")
end

print("comforts.lua: ok")
