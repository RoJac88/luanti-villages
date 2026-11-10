-- Run with: luajit tests/wants.lua
local logs = {}
local clock = 5000
minetest = {
	get_modpath = function() return "." end,
	log = function(_, text) table.insert(logs, text) end,
	get_gametime = function() return clock end,
}
local wants = dofile("wants.lua")
local ledger = dofile("ledger.lua")

local HOE, AXE, PICK = "mcl_farming:hoe_stone", "mcl_tools:axe_stone", "mcl_tools:pick_stone"

local function villager(extra)
	local v = {_id = "abcdef123", _profession = "unemployed"}
	for k, value in pairs(extra or {}) do v[k] = value end
	return v
end
-- A take() over a plain table of belongings.
local function take_from(held)
	return function(_, item, count)
		local have = held[item] or 0
		local taken = math.min(have, count)
		held[item] = have - taken
		return taken
	end
end
-- Targets with no tool in them: an adult always wants a book (ticket 11e).
local function only_book(targets)
	local n = 0
	for item in pairs(targets) do if item ~= wants.BOOK.item then return false end n = n + 1 end
	return n == 1
end
local function logged(pattern)
	for _, line in ipairs(logs) do if line:find(pattern, 1, true) then return true end end
	return false
end

-- Who wants what: a farmer a hoe; a woodcutter an axe, a quarrier a pickaxe, by their
-- labour; a child nothing, a mason only a book.
do
	local farmer = villager({_profession = "farmer"})
	local targets, worth = wants.targets(farmer)
	assert(targets[HOE] == 1 and not targets[AXE])
	assert(worth[HOE] == 64 * ledger.price("mcl_farming:wheat_item") * 0.5, worth[HOE])
	targets = wants.targets(villager({_villages_labour = {day = 3, activity = "woodcutter"}}))
	assert(targets[AXE] == 1 and not targets[HOE])
	targets = wants.targets(villager({_villages_labour = {day = 3, activity = "quarrier"}}))
	assert(targets[PICK] == 1)
	-- One that took a job after the morning's choice is no longer a woodcutter.
	assert(only_book((wants.targets(villager({_profession = "tool_smith", _jobsite = {x = 0, y = 0, z = 0},
		_villages_labour = {day = 3, activity = "woodcutter"}})))))
	assert(wants.targets(villager({_profession = "nitwit", _villages_labour = {day = 3, activity = "woodcutter"}}))[AXE] == 1)
	assert(next((wants.targets(villager({_profession = "farmer", child = true})))) == nil)
	assert(only_book((wants.targets(villager({_profession = "mason"})))))
	-- Worth over its life: more than its price, so it is worth buying.
	for _, good in ipairs(wants.GOODS) do
		assert(wants.worth(good) > ledger.price(good.item), good.key)
	end
end

-- Using: by hand at rate 1; with one held, it is taken up, works at 1.5, wears, and the
-- next is wanted once it is nearly worn.
do
	logs = {}
	local farmer = villager({_profession = "farmer"})
	local held = {}
	assert(wants.use(farmer, "harvest", take_from(held), 0) == 1)
	assert(farmer._villages_wants == nil)
	held[HOE] = 1
	assert(wants.use(farmer, "harvest", take_from(held), 1) == 1.5)
	assert(held[HOE] == 0 and farmer._villages_wants.hoe.left == 63)
	assert(logged("takes up a " .. HOE))
	assert(not wants.targets(farmer)[HOE], "a fresh hoe: no need")
	-- Another use is not taken from belongings while one is in use.
	held[HOE] = 1
	wants.use(farmer, "harvest", take_from(held), 2)
	assert(held[HOE] == 1 and farmer._villages_wants.hoe.left == 62)
	held[HOE] = 0
	-- Nearly worn: the next is wanted.
	farmer._villages_wants.hoe.left = 8
	assert(wants.targets(farmer)[HOE] == 1)
	-- Worn out: gone, and by hand again.
	farmer._villages_wants.hoe.left = 1
	assert(wants.use(farmer, "harvest", take_from(held), 3) == 1.5)
	assert(farmer._villages_wants == nil and logged("wore out its " .. HOE))
	assert(wants.use(farmer, "harvest", take_from(held), 4) == 1)
	-- Another use, or a use it has no good for, changes nothing.
	assert(wants.use(farmer, "fell", take_from({[AXE] = 1}), 5) == 1)
	assert(wants.status(farmer) == "none")
end

-- The pace is logged every LOG_EVERY uses, by hand and with the good apart.
do
	logs = {}
	local cutter = villager({_villages_labour = {day = 1, activity = "woodcutter"}})
	for i = 1, wants.LOG_EVERY do wants.use(cutter, "fell", nil, i * 3) end
	assert(logged("16 fell in 45 s (3.00 s each while working) by hand"), logs[#logs])
	local held = {[AXE] = 1}
	for i = 1, wants.LOG_EVERY do wants.use(cutter, "fell", take_from(held), 100 + i * 2) end
	assert(logged("16 fell in 30 s (2.00 s each while working) with a " .. AXE), logs[#logs])
	-- A long gap (a walk, a night) counts toward the time, not the pace.
	logs = {}
	local walker = villager({_villages_labour = {day = 1, activity = "woodcutter"}})
	for i = 1, wants.LOG_EVERY do wants.use(walker, "fell", nil, 1000 + i * 3 + (i == 8 and 600 or 0) + (i > 8 and 600 or 0)) end
	assert(logged("(3.00 s each while working) by hand"), logs[#logs])
	assert(wants.status(cutter):find("16 of 32 uses left", 1, true), wants.status(cutter))
end


-- Books (ticket 11e): an adult wants one; one it holds is read at its next work, speeds
-- it by a fifth for BOOK.days, and is then used up and wanted again.
do
	local BOOK = wants.BOOK.item
	local reader = villager({_id = "reader1", _profession = "farmer"})
	local targets, worth = wants.targets(reader)
	assert(targets[BOOK] == 1 and math.abs(worth[BOOK] - wants.book_worth()) < 1e-9 and wants.book_worth() > 0)
	local held = {[BOOK] = 1}
	assert(wants.reading_rate(reader, take_from(held), clock) == wants.BOOK.rate)
	assert(held[BOOK] == 0 and logged("reads a " .. BOOK))
	assert(not wants.targets(reader)[BOOK], "reading one, it wants no other yet")
	-- A harvest by hand goes a fifth faster.
	assert(math.abs(wants.use(reader, "harvest", take_from({}), clock + 1) - wants.BOOK.rate) < 1e-9)
	local length = wants.BOOK.days * wants.DAY_SECONDS
	assert(wants.targets(reader, clock + length * 0.9)[BOOK] == 1, "near the end it wants the next")
	assert(wants.reading_rate(reader, take_from({}), clock + length) == 1)
	assert(reader._villages_wants == nil and logged("finished reading its " .. BOOK))
	-- Nothing to read: no effect.
	assert(wants.reading_rate(villager({_id = "idle"}), take_from({}), clock) == 1)
	assert(wants.reading_rate(villager({_id = "kid", child = true}), take_from({[BOOK] = 1}), clock) == 1)
end

print("wants.lua: ok")
