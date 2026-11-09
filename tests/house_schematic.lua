-- Run with: lua tests/house_schematic.lua
minetest = {}
local furnish, house = dofile("house_schematic.lua")

-- Each stock house, from its fixture, gets one chest per bed, nearer that bed than any other.
local function load(name)
	local t = dofile("tests/fixtures/buildings/" .. name .. ".lua")
	local data = {}
	for i, id in ipairs(t.ids) do data[i] = {name = t.names[id + 1], param2 = t.param2 and t.param2[i] or 0} end
	return {size = t.size, data = data}
end
local function cells(schematic, pattern)
	local found = {}
	local size = schematic.size
	for i, cell in ipairs(schematic.data) do
		if cell.name:find(pattern) then
			local n = i - 1
			found[#found + 1] = {x = n % size.x, y = math.floor(n / size.x) % size.y, z = math.floor(n / (size.x * size.y))}
		end
	end
	return found
end
local function distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

for _, name in ipairs({"small_house", "medium_house", "large_house"}) do
	local schematic = load(name)
	assert(#cells(schematic, "^mcl_chests:") == 0, name .. " starts with no chest")
	assert(furnish(schematic), name)
	local chests, beds = cells(schematic, "^mcl_chests:chest$"), cells(schematic, "^mcl_beds:.*_bottom$")
	assert(#chests == #beds and #beds > 0, name .. ": a chest per bed")
	for _, bed in ipairs(beds) do
		table.sort(chests, function(a, b) return distance(a, bed) < distance(b, bed) end)
		assert(distance(chests[1], bed) <= 2.5, name .. ": a chest beside each bed")
		assert(#chests == 1 or distance(chests[1], bed) < distance(chests[2], bed), name .. ": its own chest is nearest")
	end
	assert(not furnish(schematic), name .. ": never twice")
end
-- Other buildings, and a changed layout, are left alone.
assert(not furnish(load("tavern")) and not furnish(load("library")))
local changed = load("small_house")
changed.data[3 * 9 * 9 + 2 * 9 + 5 + 1].name = "mcl_core:wood"
assert(not furnish(changed))

-- The generator's loot is taken out of a chest beside a bed; others keep theirs.
local lists = {}
local bed_at = {x = 0, y = 0, z = 0}
minetest.find_node_near = function(pos, radius)
	if math.abs(pos.x - bed_at.x) <= radius and math.abs(pos.y - bed_at.y) <= radius and math.abs(pos.z - bed_at.z) <= radius then return bed_at end
end
minetest.get_meta = function(pos)
	return {get_inventory = function()
		local list = lists[pos.x]
		return {
			get_size = function() return list and 27 or 0 end,
			set_list = function(_, _, items) for k in pairs(list) do list[k] = nil end end,
		}
	end}
end
lists[1], lists[30] = {"mcl_core:diamond 2"}, {"mcl_core:diamond 2"}
assert(house.empty_house_chest({x = 1, y = 0, z = 0}) and next(lists[1]) == nil)
assert(not house.empty_house_chest({x = 30, y = 0, z = 0}) and lists[30][1] == "mcl_core:diamond 2")

print("house_schematic.lua: ok")
