-- Run with: lua tests/builder_house.lua
-- The Builder's house as a schematic, its place in the generator's list, and the setup of
-- its chests. Routes through it are in tests/stock_buildings.lua.
local stock_world = dofile("tests/support/stock_world.lua")
local defs = stock_world.defs
stock_world.install(stock_world.new())

local house = dofile("builder_house.lua")

local function cells_named(schematic, name)
	local found = {}
	for i, cell in ipairs(schematic.data) do
		if cell.name == name then
			local size = schematic.size
			found[#found + 1] = {
				x = (i - 1) % size.x,
				y = math.floor((i - 1) / size.x) % size.y,
				z = math.floor((i - 1) / (size.x * size.y)),
				param2 = cell.param2,
			}
		end
	end
	return found
end

-- Its shape, and what it is for.
do
	local schematic = house.schematic()
	local size = schematic.size
	assert(#schematic.data == size.x * size.y * size.z, "every layer is the same size")
	assert(#cells_named(schematic, "living_villages:builder_block") == 1)

	local beds = cells_named(schematic, "mcl_beds:bed_red_bottom")
	assert(#beds == 1, "one bed, for one villager")
	local tops = cells_named(schematic, "mcl_beds:bed_red_top")
	assert(#tops == 1 and tops[1].x == beds[1].x and tops[1].z == beds[1].z + 1, "its top lies where param2 0 says")

	-- A double chest: two along the axis its param2 joins them on, the same way round.
	local chests = cells_named(schematic, "mcl_chests:chest_small")
	assert(#chests == 2 and chests[1].param2 == chests[2].param2 and chests[1].param2 == 1)
	assert(chests[1].x == chests[2].x and math.abs(chests[1].z - chests[2].z) == 1 and chests[1].y == chests[2].y)
	assert(#cells_named(schematic, "mcl_chests:chest") == 0, "place_schematics would fill that with loot")

	-- A door the villager can use, with a step up to it, as in the stock small house.
	local door = cells_named(schematic, "mcl_doors:wooden_door_b_1")
	local top = cells_named(schematic, "mcl_doors:wooden_door_t_1")
	local stair = cells_named(schematic, "mcl_stairs:stair_cobble")
	assert(#door == 1 and #top == 1 and #stair == 1)
	assert(top[1].x == door[1].x and top[1].y == door[1].y + 1 and top[1].z == door[1].z)
	assert(stair[1].x == door[1].x and stair[1].y == door[1].y - 1 and stair[1].z == door[1].z - 1)

	-- The ground layer is ground, as the other buildings' is.
	for i, cell in ipairs(schematic.data) do
		if math.floor((i - 1) / size.x) % size.y == 0 then assert(cell.name == "mcl_core:dirt") end
	end

	-- No other jobsite to draw a villager off, and nothing the node list lacks.
	local materials = dofile("builder_materials.lua")
	for _, cell in ipairs(schematic.data) do
		if cell.name ~= "living_villages:builder_block" then
			assert(not materials.excluded(cell.name), cell.name .. " is a jobsite")
		end
	end
end

-- Goes in the generator's list last, once, taking the stock houses' pseudobiome rule.
do
	local settlements = {schematic_table = {
		{name = "belltower"}, {name = "small_house", rplc = "the rule"}, {name = "tavern", rplc = false},
	}}
	local entry = assert(house.install(settlements))
	assert(#settlements.schematic_table == 4 and settlements.schematic_table[4] == entry)
	assert(settlements.schematic_table[1].name == "belltower", "site_planner.lua wants it first")
	assert(entry.name == "builder_house" and entry.rplc == "the rule" and entry.max_num == 0)
	local size = entry.mts.size
	assert(entry.hwidth == size.x and entry.hdepth == size.z and entry.hheight == size.y)
	assert(house.install(settlements) == entry and #settlements.schematic_table == 4, "a second install adds nothing")
	assert(house.install(nil) == nil and house.install({}) == nil)

	-- Off, new villages have none.
	local off = {settings = {get_bool = function() return false end}}
	local other = {schematic_table = {{name = "belltower"}}}
	assert(house.install(other, off) == nil and #other.schematic_table == 1)
end

-- The chests of a generated house: nothing a schematic places has an inventory, so
-- setup_house has to make the same calls a player's two placements do.
do
	-- A stand-in for what mcl_chests does (api.lua): chest_small's on_construct creates the
	-- inventory and merges with a neighbouring chest_small, swapping the two.
	local nodes, inventories, log = {}, {}, {}
	local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
	local function neighbour(pos, side)
		-- mcl_util.get_double_container_neighbor_pos for param2 1.
		return {x = pos.x, y = pos.y, z = pos.z + (side == "right" and 1 or -1)}
	end
	local engine = {log = function() end, pos_to_string = key}
	local bench_meta = {}
	function engine.find_nodes_in_area(_, _, names)
		local found = {}
		for id, node in pairs(nodes) do
			if node.name == names[1] then found[#found + 1] = node.pos end
		end
		table.sort(found, function(a, b) return key(a) < key(b) end)
		return found
	end
	function engine.get_node(pos) return nodes[key(pos)] or {name = "air", param2 = 0} end
	function engine.remove_node(pos)
		nodes[key(pos)] = nil
		inventories[key(pos)] = nil
	end
	function engine.set_node(pos, node)
		assert(node.name == "mcl_chests:chest_small")
		nodes[key(pos)] = {name = node.name, param2 = node.param2, pos = pos}
		inventories[key(pos)] = 27
		log[#log + 1] = key(pos)
		for _, side in ipairs({"right", "left"}) do
			local other = neighbour(pos, side)
			local there = nodes[key(other)]
			if there and there.name == "mcl_chests:chest_small" then
				nodes[key(pos)].name = "mcl_chests:chest_" .. side
				there.name = "mcl_chests:chest_" .. (side == "right" and "left" or "right")
				break
			end
		end
	end
	function engine.get_meta(pos)
		local id = key(pos)
		if id == "0,0,0" then
			return {
				get_int = function(_, field) return bench_meta[field] or 0 end,
				set_int = function(_, field, value) bench_meta[field] = value end,
			}
		end
		return {get_inventory = function()
			return {get_size = function() return inventories[id] or 0 end}
		end}
	end

	local registered, abm, craft
	minetest.registered_nodes = {
		["mcl_crafting_table:crafting_table"] = {
			name = "mcl_crafting_table:crafting_table", tiles = {"top.png", "side.png"},
			on_rightclick = function() error("the bench is not a crafting table") end,
		},
	}
	minetest.register_abm = function(definition) abm = definition end
	minetest.register_node = function(name, definition) registered = {name = name, def = definition} end
	minetest.register_craft = function(definition) craft = definition end
	table.copy = table.copy or function(source)
		local copy = {}
		for field, value in pairs(source) do copy[field] = value end
		return copy
	end
	local block = dofile("builder_block.lua")

	-- The bench looks like what it is copied from, tinted, and does nothing when clicked.
	assert(registered.name == "living_villages:builder_block" and registered.def.name == nil)
	assert(registered.def.on_rightclick == nil and registered.def.drop == registered.name)
	assert(registered.def.tiles[2]:find("^side%.png%^%[multiply:"))
	assert(minetest.registered_nodes["mcl_crafting_table:crafting_table"].tiles[1] == "top.png", "the stock node is untouched")
	assert(craft.output == registered.name and #craft.recipe == 2)
	assert(abm.nodenames[1] == registered.name)

	local bench = {x = 0, y = 0, z = 0}
	local a, b = {x = 2, y = 0, z = 3}, {x = 2, y = 0, z = 4}
	nodes[key(a)] = {name = "mcl_chests:chest_small", param2 = 1, pos = a}
	nodes[key(b)] = {name = "mcl_chests:chest_small", param2 = 1, pos = b}
	-- Someone's chest with things in it, within range, is not to be touched.
	local own = {x = -3, y = 0, z = 0}
	nodes[key(own)] = {name = "mcl_chests:chest_small", param2 = 0, pos = own}
	inventories[key(own)] = 27

	assert(block.setup_house(bench, engine) == 2)
	assert(inventories[key(a)] == 27 and inventories[key(b)] == 27, "both halves can hold things")
	-- The second to be set finds the first on its left, as mcl_chests has it at param2 1.
	assert(nodes[key(a)].name == "mcl_chests:chest_right" and nodes[key(b)].name == "mcl_chests:chest_left")
	assert(nodes[key(a)].param2 == 1 and nodes[key(b)].param2 == 1, "still facing the room")
	assert(nodes[key(own)].name == "mcl_chests:chest_small" and #log == 2, "the player's chest was left alone")

	-- Only once: later a broken chest of the pair is the player's business.
	assert(block.setup_house(bench, engine) == 0 and #log == 2)
end

print("builder_house: ok")
