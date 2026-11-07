-- Run with: lua tests/farm_schematic.lua
minetest = {}
local furnish, farm = dofile("farm_schematic.lua")

-- The stock farm's layout, as much of it as the furnisher looks at.
local size = {x = 9, y = 8, z = 7}
local data
local function reset()
	data = {}
	for i = 1, size.x * size.y * size.z do data[i] = {name = "air"} end
end
local function cell(x, y, z) return data[z * size.y * size.x + y * size.x + x + 1] end
reset()
for x = 1, 7 do cell(x, 1, 0).name = "mcl_core:tree" end
cell(4, 2, 0).name = "mcl_composters:composter"
local schematic = {size = size, data = data}

-- A chest on the log ring beside the composter, facing out of the field.
assert(furnish(schematic))
local chest = cell(5, 2, 0)
assert(chest.name == "mcl_chests:chest" and chest.prob == 255 and chest.param2 == 0)
assert(cell(4, 2, 0).name == "mcl_composters:composter", "composter stays")
assert(cell(3, 2, 0).name == "air", "the composter's other side stays open")
assert(not furnish(schematic), "never twice: the cell is taken")

-- A changed layout is left alone.
assert(not furnish({size = {x = 10, y = 8, z = 7}, data = data}))
reset()
cell(5, 1, 0).name = "mcl_core:tree"
assert(not furnish({size = size, data = data}), "no composter where the stock farm has it")
reset()
cell(4, 2, 0).name = "mcl_composters:composter"
assert(not furnish({size = size, data = data}), "nothing under the chest's cell")

-- The generator's loot in a chest beside a composter becomes seeds; any other chest keeps it.
local lists, composters = {}, {}
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
minetest.find_node_near = function(pos)
	for _, c in ipairs(composters) do
		if math.abs(c.x - pos.x) <= 1 and math.abs(c.y - pos.y) <= 1 and math.abs(c.z - pos.z) <= 1 then return c end
	end
end
minetest.get_meta = function(pos)
	return {get_inventory = function()
		local list = lists[key(pos)]
		return {
			get_size = function() return list and 27 or 0 end,
			set_list = function(_, _, items) for k in pairs(list) do list[k] = nil end; for _, i in ipairs(items) do list[#list + 1] = i end end,
			add_item = function(_, _, item) list[#list + 1] = item end,
		}
	end}
end
minetest.log = function() end
minetest.pos_to_string = function(p) return key(p) end
local farm_chest, house_chest = {x = 5, y = 2, z = 0}, {x = 30, y = 2, z = 0}
composters[1] = {x = 4, y = 2, z = 0}
lists[key(farm_chest)] = {"mcl_core:diamond 2", "mcl_farming:bread 3"}
lists[key(house_chest)] = {"mcl_core:diamond 2"}
assert(farm.seed_farm_chest(farm_chest))
assert(#lists[key(farm_chest)] == #farm.STARTING_SEEDS and lists[key(farm_chest)][1] == "mcl_farming:wheat_seeds 12")
assert(not farm.seed_farm_chest(house_chest) and lists[key(house_chest)][1] == "mcl_core:diamond 2")

-- Installed: the stock farm is furnished and the generator's fill wrapped.
reset()
for x = 1, 7 do cell(x, 1, 0).name = "mcl_core:tree" end
cell(4, 2, 0).name = "mcl_composters:composter"
local stock = {size = size, data = data}
minetest.serialize_schematic = function() return "fixture" end
minetest.log = function() end
loadstring = function() return function() return stock end end
local filled = 0
settlements = {
	schematic_table = {{name = "farm", mts = "farm.mts"}},
	fill_chest = function() filled = filled + 1 end,
}
dofile("farm_schematic.lua")
assert(settlements.schematic_table[1].mts == stock and cell(5, 2, 0).name == "mcl_chests:chest")
lists[key(farm_chest)] = {"mcl_core:diamond 2"}
settlements.fill_chest(farm_chest)
assert(filled == 1 and lists[key(farm_chest)][1] == "mcl_farming:wheat_seeds 12")
print("farm_schematic.lua: ok")
