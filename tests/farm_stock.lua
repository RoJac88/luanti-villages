-- Run with: lua tests/farm_stock.lua
local world = dofile("tests/support/farm_world.lua").new()
local stock = dofile("farm_stock.lua")

local farmer = {}
assert(stock.count(farmer, "a") == 0 and stock.total(farmer) == 0)
assert(stock.take(farmer, "a", 1) == 0)
assert(farmer._villages_farm_pouch == nil, "reading makes no field")

stock.add(farmer, "a", 3)
stock.add_itemstring(farmer, "a")
stock.add_itemstring(farmer, "b 5")
assert(stock.count(farmer, "a") == 4 and stock.count(farmer, "b") == 5 and stock.total(farmer) == 9)
assert(stock.take(farmer, "a", 2) == 2 and stock.count(farmer, "a") == 2)
assert(stock.take(farmer, "a", 9) == 2)
assert(farmer._villages_farm_pouch.a == nil, "an emptied item leaves no entry to save")

-- Room for a whole harvest or none started.
assert(stock.has_harvest_room(farmer))
stock.add(farmer, "c", stock.CAPACITY - stock.total(farmer))
assert(not stock.has_harvest_room(farmer))

-- Dropping conserves every item, in legal stacks.
local before = stock.total(farmer)
stock.drop_all(farmer, {x = 0, y = 0, z = 0})
local dropped = 0
for _, drop in ipairs(world.dropped) do
	local count = tonumber(drop.item:match("(%d+)$"))
	assert(count <= 64)
	dropped = dropped + count
end
assert(dropped == before and farmer._villages_farm_pouch == nil)

-- Chests: nearest the composter first, only ordinary ones, only usable ones.
world = dofile("tests/support/farm_world.lua").new()
stock = dofile("farm_stock.lua")
local support = dofile("tests/support/farm_world.lua")
local job = {x = 0, y = 2, z = 0}
local near, far = {x = 3, y = 2, z = 0}, {x = 20, y = 2, z = 0}
support.chest(world, far)
support.chest(world, near)
support.chest(world, {x = 33, y = 2, z = 0})
support.chest(world, {x = 1, y = 11, z = 0})
support.chest(world, {x = 4, y = 2, z = 0}, "mcl_chests:trapped_chest_small")
world.set({x = 5, y = 2, z = 0}, "mcl_chests:chest_small") -- no inventory yet
support.chest(world, {x = 6, y = 2, z = 0})
world.protected["6,2,0"] = true
local chests = stock.find_chests(job)
assert(#chests == 2 and chests[1].x == 3 and chests[2].x == 20)
world.settings["living_villages_farmer_chest_radius"] = "10"
assert(#stock.find_chests(job) == 1)
world.settings["living_villages_farmer_chest_radius"] = "0"
assert(#stock.find_chests(job) == 0)
world.settings["living_villages_farmer_chest_radius"] = nil

-- Into a chest: conserved, and what does not fit stays in the pouch.
local carrier = {_villages_farm_pouch = {x = 10}}
local moved, fitted = stock.put_in_chest(carrier, near, "x", 6)
assert(moved == 6 and fitted and stock.count(carrier, "x") == 4 and stock.chest_count(near, "x") == 6)
for i = 1, 27 do world.meta(near).inv:set_stack("main", i, "full 64") end
moved, fitted = stock.put_in_chest(carrier, near, "x", 4)
assert(moved == 0 and not fitted and stock.count(carrier, "x") == 4)
for i = 1, 27 do world.meta(near).inv:set_stack("main", i, "") end
world.meta(near).inv:set_stack("main", 1, "x 62")
for i = 2, 27 do world.meta(near).inv:set_stack("main", i, "full 64") end
moved, fitted = stock.put_in_chest(carrier, near, "x", 4)
assert(moved == 2 and not fitted and stock.count(carrier, "x") == 2 and stock.chest_count(near, "x") == 64)

-- Out of a chest: what is there, up to what was asked.
assert(stock.take_from_chest(carrier, near, "x", 5) == 5 and stock.count(carrier, "x") == 7)
assert(stock.chest_count(near, "x") == 59)
assert(stock.take_from_chest(carrier, near, "nothing", 5) == 0)

-- A chest gone or newly protected is not written to, and nothing goes missing.
world.protected["3,2,0"] = true
assert(stock.put_in_chest(carrier, near, "x", 1) == 0 and stock.take_from_chest(carrier, near, "x", 1) == 0)
world.protected["3,2,0"] = nil
world.set(near, "air")
assert(stock.put_in_chest(carrier, near, "x", 1) == 0 and stock.count(carrier, "x") == 7)

-- Withdrawing can be turned off.
assert(stock.may_withdraw())
world.settings["living_villages_farmer_chest_withdraw"] = false
assert(not stock.may_withdraw())

print("farm_stock.lua: ok")
