-- Run with: lua tests/building_template.lua
-- Stock buildings as a Builder's steps: furnished, swapped and rotated as generated.
local stock_world = dofile("tests/support/stock_world.lua")
local defs = stock_world.defs
stock_world.install(stock_world.new())

local materials = dofile("builder_materials.lua")
local template = dofile("building_template.lua")

local FURNISHERS = {
	tavern = "tavern_schematic.lua", church = "church_schematic.lua", library = "library_schematic.lua",
	belltower = "belltower_schematic.lua",
}
local BUILDINGS = {
	"belltower", "blacksmith", "butcher", "church", "farm", "lamp", "large_house", "library",
	"medium_house", "small_house", "tavern", "well",
}
local ROTATIONS = {"0", "90", "180", "270"}
local FLOOR = 10

local function schematic_of(name, surface)
	local fixture = dofile("tests/fixtures/buildings/" .. name .. ".lua")
	local data = {}
	for i, id in ipairs(fixture.ids) do
		data[i] = {name = fixture.names[id + 1], prob = 255, param2 = fixture.param2[i]}
	end
	local schematic = {size = fixture.size, data = data}
	if FURNISHERS[name] then assert(dofile(FURNISHERS[name])(schematic), name .. " was not furnished") end
	for _, cell in ipairs(schematic.data) do
		cell.name = template.swap_name(cell.name, surface, true)
	end
	return schematic
end

-- Rotates as the engine does (tests/support/stock_world.lua has the same rule).
local function turned_param2(name, param2, quarters)
	local def = defs[name]
	local kind = def and def.paramtype2
	if kind == "facedir" or kind == "colorfacedir" or kind == "4dir" or kind == "color4dir" then
		return param2 - param2 % 4 + (param2 % 4 + quarters) % 4
	end
	return param2
end

local function cells_of(schematic, rotation)
	local quarters = tonumber(rotation) / 90
	local size, cells = schematic.size, {}
	for i, cell in ipairs(schematic.data) do
		local x = (i - 1) % size.x
		local y = math.floor((i - 1) / size.x) % size.y
		local z = math.floor((i - 1) / (size.x * size.y))
		local w = size.x
		local d = size.z
		for _ = 1, quarters do
			x, z = z, w - 1 - x
			w, d = d, w
		end
		cells[#cells + 1] = {
			pos = {x = 100 + x, y = FLOOR + y, z = 100 + z},
			name = cell.name,
			param2 = turned_param2(cell.name, cell.param2, quarters),
		}
	end
	return cells
end

local function plan_of(name, rotation, surface, earthwork)
	local chosen = surface or "mcl_core:dirt_with_grass"
	return template.plan(cells_of(schematic_of(name, chosen), rotation or "0"),
		{floor_y = FLOOR, surface_mat = chosen, earthwork = earthwork})
end

local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end

-- A flat stub map of dirt up to the floor and air above it.
local function new_map()
	local map = {nodes = {}}
	function map.get(pos)
		return map.nodes[key(pos)] or (pos.y <= FLOOR and "mcl_core:dirt" or "air")
	end
	function map.set(pos, name) map.nodes[key(pos)] = name end
	return map
end

-- Carries out a step, as builder.lua will.
local function apply(map, step)
	if step.kind == "cut" or step.kind == "clear" then
		map.set(step.pos, "air")
	else
		map.set(step.pos, step.node.name)
		if step.top then map.set(step.top.pos, step.top.node.name) end
	end
end

local function total(bill)
	local sum = 0
	for _, count in pairs(bill) do sum = sum + count end
	return sum
end

-- The name swaps, as place_schematics makes them.
do
	local swap = template.swap_name
	assert(swap("mcl_core:stonebrickcarved", "mcl_core:dirt_with_grass", true) == "mcl_villages:stonebrickcarved")
	assert(swap("mcl_stairs:stair_wood_outer", "mcl_core:dirt_with_grass", true) == "mcl_stairs:slab_wood")
	assert(swap("mcl_stairs:stair_stone_rough_outer", "mcl_core:dirt_with_grass", true) == "air")
	assert(swap("mcl_core:dirt_with_grass", "mcl_core:sand", true) == "mcl_core:sand")
	assert(swap("mcl_core:wood", "mcl_core:podzol", true) == "mcl_core:sprucewood")
	assert(swap("mcl_core:tree", "mcl_core:snow", true) == "mcl_core:sprucetree")
	assert(swap("mcl_core:wood", "mcl_core:sand", true) == "mcl_core:sandstonesmooth")
	assert(swap("mcl_core:cobble", "mcl_core:redsand", true) == "mcl_core:sandstone")
	assert(swap("mcl_core:tree", "mcl_core:sand", true) == "mcl_core:sandstonecarved")
	assert(swap("mcl_core:brick_block", "mcl_core:sand", true) == "mcl_core:redsandstone")
	-- A lamp's entry has rplc = false: the wood stays, the rest still swaps.
	assert(swap("mcl_core:wood", "mcl_core:sand", false) == "mcl_core:wood")
	assert(swap("mcl_core:dirt_with_grass", "mcl_core:sand", false) == "mcl_core:sand")
	assert(swap("mcl_core:wood", "mcl_core:dirt_with_grass", true) == "mcl_core:wood")
	-- Agrees with the swaps tests/support/stock_world.lua makes in every building.
	assert(swap("mcl_core:cobble", nil, true) == "mcl_core:cobble")
end

-- Every building at every rotation: the ground stays ground, profession blocks are
-- left out, and the pairs are found.
for _, name in ipairs(BUILDINGS) do
	local base = plan_of(name, "0")
	for _, rotation in ipairs(ROTATIONS) do
		local plan = plan_of(name, rotation)
		assert(#plan.steps == #base.steps, name)
		local bill = template.bill(plan.steps)
		assert(total(bill) == total(template.bill(base.steps)), name .. " costs the same at " .. rotation)
		for item in pairs(bill) do
			assert(not materials.excluded(item), name .. " pays for " .. item)
		end
		local door_tops, bed_tops = 0, 0
		for _, step in ipairs(plan.steps) do
			if step.kind == "place" then
				assert(not materials.excluded(step.node.name), name .. " places " .. step.node.name)
				assert(not materials.is_top_half(step.node.name), name .. ": a top half is placed with its bottom half")
				if materials.is_bottom_half(step.node.name) then
					assert(step.top, name .. " at " .. rotation .. ": " .. step.node.name .. " at " .. key(step.pos) .. " has no other half")
					assert(materials.is_top_half(step.top.node.name), name)
					if step.node.name:find("door") then door_tops = door_tops + 1 else bed_tops = bed_tops + 1 end
				end
				if step.pos.y == FLOOR then
					assert(not materials.is_dirt(step.node.name), name .. " builds its ground layer")
				end
			end
		end
		local schematic = schematic_of(name, "mcl_core:dirt_with_grass")
		local stock_doors, stock_beds = 0, 0
		for _, cell in ipairs(schematic.data) do
			if cell.name:find("_door_t_%d$") then stock_doors = stock_doors + 1 end
			if cell.name == "mcl_beds:bed_red_top" then stock_beds = stock_beds + 1 end
		end
		assert(door_tops == stock_doors and bed_tops == stock_beds, name .. ": unpaired halves at " .. rotation)
	end
end

-- The bills that matter: beds and doors are paid once, profession blocks not at all.
do
	local bill = template.bill(plan_of("small_house").steps)
	assert(bill["mcl_beds:bed_red_bottom"] == 1)
	assert(bill["mcl_doors:wooden_door"] == 1)
	assert(bill["mcl_loom:loom"] == nil)
	assert(bill["mcl_core:cobble"] == 42 and bill["mcl_core:wood"] == 39)

	local farm = template.bill(plan_of("farm").steps)
	assert(farm["mcl_buckets:bucket_water"] == 5, "a bucket per source")
	assert(farm["mcl_farming:wheat_seeds"] == 13)
	assert(farm["mcl_composters:composter"] == nil)
	assert(farm["mcl_core:dirt"] == 20, "the soil, and not the ground layer")

	local tower = template.bill(plan_of("belltower").steps)
	assert(tower["mcl_bells:bell"] == 1)
	assert(tower["mcl_core:stonebrick"] > 0, "its posts stand on the ground layer too")

	local smith = template.bill(plan_of("blacksmith").steps)
	assert(smith["mcl_buckets:bucket_lava"] == 4)
	assert(smith["mcl_blast_furnace:blast_furnace"] == nil)

	local house = template.bill(plan_of("large_house").steps)
	assert(house["mcl_flowers:allium"] == 3)
	assert(house["mcl_flowerpots:flower_pot"] >= 3)
	assert(house["mcl_beds:bed_red_bottom"] == 2)

	-- The church keeps no pulpit and the tavern no jukebox.
	assert(template.bill(plan_of("church").steps)["living_villages:pulpit"] == nil)
	assert(template.bill(plan_of("tavern").steps)["mcl_jukebox:jukebox"] == nil)
end

-- A surface changes the materials, as it does for a generated building.
do
	local sand = template.bill(plan_of("small_house", "0", "mcl_core:sand").steps)
	assert(sand["mcl_core:sandstonesmooth"] == 39 and sand["mcl_core:wood"] == nil)
	assert(sand["mcl_core:sandstone"] > 0 and sand["mcl_core:cobble"] == nil)
	local spruce = template.bill(plan_of("small_house", "0", "mcl_core:podzol").steps)
	assert(spruce["mcl_core:sprucewood"] == 39 and spruce["mcl_core:wood"] == nil)
end

-- Order: what hangs on something comes after it, and liquids come last.
for _, name in ipairs(BUILDINGS) do
	local plan = plan_of(name, "90")
	local previous
	for _, step in ipairs(plan.steps) do
		if previous then
			assert(step.pass >= previous.pass, name .. ": passes are in order")
			if step.pass == previous.pass and step.pass ~= template.PASS_CLEAR then
				assert(step.pos.y >= previous.pos.y, name .. ": each pass goes bottom-up")
			end
		end
		previous = step
		if step.kind == "place" then
			local node = step.node.name
			if defs[node] and (defs[node].liquidtype or "none") ~= "none" then
				assert(step.pass == template.PASS_LIQUID, node)
			elseif defs[node] and defs[node].groups and (defs[node].groups.attached_node or 0) > 0 then
				assert(step.pass == template.PASS_ATTACHED, name .. ": " .. node)
			end
		end
	end
end

-- A source takes no param2 from its schematic, which holds 7 where a generated one has 0.
do
	local sources = 0
	for _, step in ipairs(plan_of("well", "90").steps) do
		if step.kind == "place" and step.node.name == "mcl_core:water_source" then
			sources = sources + 1
			assert(step.node.param2 == 0)
		end
	end
	assert(sources == 4)
end

-- Built from nothing on flat ground, every building comes out complete, for exactly its
-- bill, at every rotation.
for _, name in ipairs(BUILDINGS) do
	for _, rotation in ipairs(ROTATIONS) do
		local plan = plan_of(name, rotation)
		local map = new_map()
		local missing, blocked = template.compare(plan, map.get)
		assert(#blocked == 0, name .. " is blocked on flat ground at " .. rotation)
		local bill = template.bill(missing)
		assert(total(bill) == total(template.bill(plan.steps)), name .. ": the whole bill is due")
		for _, step in ipairs(missing) do apply(map, step) end
		missing, blocked = template.compare(plan, map.get)
		assert(#missing == 0, name .. " at " .. rotation .. ": " .. #missing .. " left, first "
			.. (missing[1] and (missing[1].kind .. " " .. key(missing[1].pos)) or ""))
		assert(#blocked == 0, name)
	end
end

-- Progress needs no saving: a part-built house owes what is left, whichever part that
-- is, and a block taken away is owed again, for its own item only.
do
	local plan = plan_of("small_house", "180")
	local whole = total(template.bill(plan.steps))
	local map = new_map()
	local missing = template.compare(plan, map.get)
	local done = 0
	for i = 1, 40 do
		apply(map, missing[i])
		for _ in pairs(missing[i].cost or {}) do done = done + 1 end
	end
	local after = template.compare(plan, map.get)
	assert(total(template.bill(after)) == whole - done, "only what is left is owed")

	for _, step in ipairs(after) do apply(map, step) end
	assert(#template.compare(plan, map.get) == 0)

	-- A griefed cobble wall.
	local cobble
	for _, step in ipairs(plan.steps) do
		if step.kind == "place" and step.node.name == "mcl_core:cobble" then cobble = step break end
	end
	map.set(cobble.pos, "air")
	local again = template.compare(plan, map.get)
	assert(#again == 1 and again[1].pos == cobble.pos)
	assert(template.bill(again)["mcl_core:cobble"] == 1)
end

-- States a built thing gets into later are not damage.
do
	local plan = plan_of("small_house")
	local map = new_map()
	for _, step in ipairs((template.compare(plan, map.get))) do apply(map, step) end
	for _, step in ipairs(plan.steps) do
		if step.kind == "place" and step.node.name == "mcl_doors:wooden_door_b_1" then
			map.set(step.pos, "mcl_doors:wooden_door_b_2")
			map.set(step.top.pos, "mcl_doors:wooden_door_t_2")
		end
	end
	assert(#template.compare(plan, map.get) == 0, "an open door is the door")
end

-- A profession block the player adds to a finished building is left alone.
do
	local plan = plan_of("small_house")
	local schematic = schematic_of("small_house", "mcl_core:dirt_with_grass")
	local cells = cells_of(schematic, "0")
	local map = new_map()
	for _, step in ipairs((template.compare(plan, map.get))) do apply(map, step) end
	for _, cell in ipairs(cells) do
		if cell.name == "mcl_loom:loom" then map.set(cell.pos, "mcl_loom:loom") end
	end
	local missing, blocked = template.compare(plan, map.get)
	assert(#missing == 0 and #blocked == 0)
end

-- A half-built door is finished free, for the half it lacks.
do
	local plan = plan_of("small_house")
	local map = new_map()
	for _, step in ipairs((template.compare(plan, map.get))) do apply(map, step) end
	for _, step in ipairs(plan.steps) do
		if step.top then map.set(step.top.pos, "air") break end
	end
	local missing, blocked = template.compare(plan, map.get)
	assert(#missing == 1 and #blocked == 0)
	assert(next(template.bill(missing)) == nil, "already paid for")
	apply(map, missing[1])
	assert(#template.compare(plan, map.get) == 0)
end

-- Plants are cleared and paid nothing for; anything else is in the way, and says where.
do
	local plan = plan_of("small_house")
	local map = new_map()
	local step_at
	for _, step in ipairs(plan.steps) do
		if step.kind == "clear" then step_at = step break end
	end
	assert(step_at)
	assert(defs["mcl_flowers:tallgrass"] == nil or defs["mcl_flowers:tallgrass"].buildable_to)
	defs["test:plant"] = {buildable_to = true}
	defs["test:rock"] = {buildable_to = false, walkable = true}
	map.set(step_at.pos, "test:plant")
	local missing, blocked = template.compare(plan, map.get)
	assert(#blocked == 0)
	local cleared = false
	for _, step in ipairs(missing) do
		if step.kind == "clear" and key(step.pos) == key(step_at.pos) then cleared = true end
	end
	assert(cleared, "a plant in the way is cleared")

	map.set(step_at.pos, "test:rock")
	missing, blocked = template.compare(plan, map.get)
	assert(#blocked == 1 and key(blocked[1]) == key(step_at.pos), "a rock is reported")

	local place
	for _, step in ipairs(plan.steps) do
		if step.kind == "place" and step.node.name == "mcl_core:cobble" and step.pos.y > FLOOR then place = step break end
	end
	map.set(step_at.pos, "air")
	map.set(place.pos, "test:rock")
	missing, blocked = template.compare(plan, map.get)
	assert(#blocked == 1 and key(blocked[1]) == key(place.pos), "and so is one in a wall's place")
	defs["test:plant"], defs["test:rock"] = nil, nil
end

-- A post in the ground layer goes in where the dirt is, which is not "in the way".
do
	local plan = plan_of("belltower")
	local map = new_map()
	local _, blocked = template.compare(plan, map.get)
	assert(#blocked == 0)
	local posts = 0
	for _, step in ipairs(plan.steps) do
		if step.kind == "place" and step.pos.y == FLOOR then posts = posts + 1 end
	end
	assert(posts == 4)
end

-- On sand the ground it goes in is sand, and that is not in the way either.
do
	local plan = plan_of("belltower", "0", "mcl_core:sand")
	local map = new_map()
	local get = function(pos)
		return pos.y == FLOOR and "mcl_core:sand" or map.get(pos)
	end
	local missing, blocked = template.compare(plan, get)
	assert(#blocked == 0, "sand under a post: " .. #blocked)
	local posts = 0
	for _, step in ipairs(missing) do
		if step.kind == "place" and step.pos.y == FLOOR then posts = posts + 1 end
	end
	assert(posts == 4)
end

-- Water a building's own source sends into an empty cell is not work left to do, which
-- would never end, but a source wanted in that cell still is.
do
	defs["test:flowing"] = {liquidtype = "flowing", buildable_to = true}
	local plan = plan_of("well")
	local map = new_map()
	for _, step in ipairs((template.compare(plan, map.get))) do apply(map, step) end
	local empty, source
	for _, step in ipairs(plan.steps) do
		if step.kind == "clear" then empty = empty or step end
		if step.kind == "place" and step.node.name == "mcl_core:water_source" then source = source or step end
	end
	map.set(empty.pos, "test:flowing")
	local missing, blocked = template.compare(plan, map.get)
	assert(#missing == 0 and #blocked == 0, "flow in an empty cell")
	map.set(source.pos, "test:flowing")
	missing, blocked = template.compare(plan, map.get)
	assert(#missing == 1 and missing[1] == source and #blocked == 0, "a source flowed over")
	defs["test:flowing"] = nil
end

-- Unloaded cells are neither missing nor in the way, yet.
do
	local plan = plan_of("lamp")
	local missing, blocked = template.compare(plan, function() return nil end)
	assert(#missing == 0 and #blocked == 0)
end

-- Earthwork: a bump and a dip level out, first of all and for free, whatever the bill.
do
	local cuts = {{x = 101, y = FLOOR + 1, z = 101}, {x = 102, y = FLOOR + 1, z = 101}}
	local fills = {{x = 103, y = FLOOR - 1, z = 103}, {x = 103, y = FLOOR, z = 103}}
	local plain = template.bill(plan_of("small_house").steps)
	local plan = plan_of("small_house", "0", nil, {cuts = cuts, fills = fills})
	assert(total(template.bill(plan.steps)) == total(plain), "earthwork is free")
	assert(plan.steps[1].kind == "cut" and plan.steps[2].kind == "cut")
	assert(plan.steps[3].kind == "fill" and plan.steps[3].pos.y == FLOOR - 1, "fills go bottom-up")
	assert(plan.steps[4].kind == "fill" and plan.steps[4].pos.y == FLOOR)

	local map = new_map()
	map.set(cuts[1], "mcl_core:dirt_with_grass")
	map.set(cuts[2], "mcl_core:dirt")
	map.set(fills[1], "air")
	map.set(fills[2], "air")
	local missing, blocked = template.compare(plan, map.get)
	assert(#blocked == 0, "planned cuts are not foreign blocks: " .. #blocked)
	assert(missing[1].kind == "cut" and missing[2].kind == "cut" and missing[3].kind == "fill" and missing[4].kind == "fill")
	for _, step in ipairs(missing) do apply(map, step) end
	missing, blocked = template.compare(plan, map.get)
	assert(#missing == 0 and #blocked == 0)
	assert(map.get(fills[2]) == "mcl_core:dirt")

	-- Stone where a cut was planned is still in the way: only dirt is cut.
	local stone_plan = plan_of("small_house", "0", nil, {cuts = {cuts[1]}})
	local stone_map = new_map()
	defs["test:rock"] = {buildable_to = false, walkable = true}
	stone_map.set(cuts[1], "test:rock")
	local _, stuck = template.compare(stone_plan, stone_map.get)
	local found = false
	for _, pos in ipairs(stuck) do found = found or key(pos) == key(cuts[1]) end
	assert(found, "a rock is not dirt")
	defs["test:rock"] = nil
end

-- A cut where the building itself wants dirt is no cut, or it would dig it up forever.
do
	local name = "butcher"
	local schematic = schematic_of(name, "mcl_core:dirt_with_grass")
	local spot
	for _, cell in ipairs(cells_of(schematic, "0")) do
		if cell.pos.y > FLOOR and materials.is_dirt(cell.name) then spot = cell.pos break end
	end
	assert(spot, "the butcher has a garden")
	local plan = plan_of(name, "0", nil, {cuts = {spot}})
	local map = new_map()
	map.set(spot, "mcl_core:dirt_with_grass")
	local missing = template.compare(plan, map.get)
	for _, step in ipairs(missing) do
		assert(not (step.kind == "cut" and key(step.pos) == key(spot)))
		apply(map, step)
	end
	assert(#template.compare(plan, map.get) == 0)
end

-- A batch pays for the next steps in order, never past capacity, and covers a pair once.
do
	local plan = plan_of("church")
	local map = new_map()
	local missing = template.compare(plan, map.get)
	local batch, count = template.next_batch(missing, 256)
	assert(count == 256 and total(batch) == 256)
	assert(batch["mcl_core:cobble"] > 0)
	local all, whole = template.next_batch(missing, 100000)
	assert(whole == total(template.bill(plan.steps)))
	for item, n in pairs(batch) do assert(all[item] >= n, item) end
	local none, zero = template.next_batch({}, 256)
	assert(next(none) == nil and zero == 0)
end

-- The real path: the engine rotates on a VoxelManip that is read and never written.
do
	local schematic = schematic_of("lamp", "mcl_core:dirt_with_grass")
	local written, placed_at = false, nil
	local ids, names = {air = 1}, {"air"}
	local function id_of(name)
		if not ids[name] then
			names[#names + 1] = name
			ids[name] = #names
		end
		return ids[name]
	end
	local engine = {
		registered_nodes = defs,
		get_item_group = minetest.get_item_group,
		get_name_from_content_id = function(id) return names[id] end,
	}
	local data, param2, emin, emax
	function engine.get_voxel_manip()
		return {
			read_from_map = function(_, p1, p2)
				-- A VoxelManip reads whole blocks, so it reaches past what was asked for.
				emin = {x = p1.x - 3, y = p1.y - 2, z = p1.z - 1}
				emax = {x = p2.x + 2, y = p2.y + 3, z = p2.z + 4}
				return emin, emax
			end,
			get_data = function() return data end,
			get_param2_data = function() return param2 end,
			write_to_map = function() written = true end,
		}
	end
	function engine.place_schematic_on_vmanip(_, pos, schem, rotation, replacements, force)
		placed_at = pos
		assert(schem == schematic and rotation == "90" and replacements == nil and force == true)
		data, param2 = {}, {}
		local nx, ny = emax.x - emin.x + 1, emax.y - emin.y + 1
		local nz = emax.z - emin.z + 1
		for i = 1, nx * ny * nz do data[i], param2[i] = id_of("air"), 0 end
		for _, cell in ipairs(cells_of(schem, rotation)) do
			local x = cell.pos.x - 100 + pos.x
			local y = cell.pos.y - FLOOR + pos.y
			local z = cell.pos.z - 100 + pos.z
			local i = (z - emin.z) * ny * nx + (y - emin.y) * nx + (x - emin.x) + 1
			data[i], param2[i] = id_of(cell.name), cell.param2
		end
		return true
	end

	local pos = {x = 100, y = FLOOR, z = 100}
	local cells = assert(template.world_cells(schematic, pos, "90", engine))
	assert(placed_at == pos and not written, "the map is untouched")
	local size = template.rotated_size(schematic.size, "90")
	assert(size.x == schematic.size.z and size.z == schematic.size.x)
	assert(#cells == size.x * size.y * size.z)
	local want = {}
	for _, cell in ipairs(cells_of(schematic, "90")) do want[key(cell.pos)] = cell end
	for _, cell in ipairs(cells) do
		local expected = want[key(cell.pos)]
		assert(expected and expected.name == cell.name and expected.param2 == cell.param2, key(cell.pos))
	end

	function engine.place_schematic_on_vmanip() return nil end
	assert(template.world_cells(schematic, pos, "90", engine) == nil, "cannot be placed")
end

-- A schematic is copied before its names are swapped; the entry stays as it was.
do
	local entry = {mts = "x.mts", rplc = true}
	local serialized = 'schematic = {size = {x = 1, y = 1, z = 2}, data = {'
		.. '{name = "mcl_core:wood", prob = 255, param2 = 0}, {name = "mcl_core:dirt_with_grass", prob = 255, param2 = 0}}}'
	local engine = {serialize_schematic = function(mts, format)
		assert(mts == "x.mts" and format == "lua")
		return serialized
	end}
	local copy = assert(template.prepare_schematic(entry, "mcl_core:sand", engine))
	assert(copy.data[1].name == "mcl_core:sandstonesmooth" and copy.data[2].name == "mcl_core:sand")
	assert(entry.mts == "x.mts")
	engine.serialize_schematic = function() return nil end
	assert(template.prepare_schematic(entry, "mcl_core:sand", engine) == nil)
end

print("building_template: ok")
