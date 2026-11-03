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

print("farm_stock.lua: ok")
