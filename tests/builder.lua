-- Run with: lua tests/builder.lua
-- The Builder's role: who takes the bench, the project's states up to having all its
-- materials, and what the status window shows and sells.
local support = dofile("tests/support/farm_world.lua")
local world = support.new()
local core = minetest

local BENCH = "living_villages:builder_block"
local WOOD, COBBLE = "mcl_core:wood", "mcl_core:cobble"
local WATER = "mcl_core:water_source"
local BUCKET = "mcl_buckets:bucket_water"
local CHEST = "mcl_chests:chest_small"

world.defs[BENCH] = {groups = {}, is_ground_content = false}
world.defs[WOOD] = {groups = {}, is_ground_content = false}
world.defs[COBBLE] = {groups = {}}
world.defs[CHEST].is_ground_content = false
world.defs[WATER].liquidtype = "source"
world.defs["air"].buildable_to = true
world.defs["air"].walkable = false
world.defs["mcl_buckets:bucket_empty"] = {groups = {}}

local ground = "mcl_core:dirt_with_grass"
local tallest = 3
local function name_of(x, y, z)
	if y > tallest then return "air" end
	local node = world.nodes[x .. "," .. y .. "," .. z]
	if node then return node.name end
	return y <= 0 and ground or "air"
end

core.get_node_or_nil = function(pos)
	return {name = name_of(pos.x, pos.y, pos.z)}
end

-- A VoxelManip that reads the world on demand, as a whole search area would be slow to copy.
local ids, id_names = {}, {}
local function id_of(name)
	if not ids[name] then
		id_names[#id_names + 1] = name
		ids[name] = #id_names
	end
	return ids[name]
end
core.CONTENT_IGNORE = id_of("ignore")
core.get_name_from_content_id = function(id) return id_names[id] end
core.get_voxel_manip = function()
	local vm = {}
	function vm:read_from_map(minp, maxp)
		self.minp, self.maxp = minp, maxp
		local nx, ny = maxp.x - minp.x + 1, maxp.y - minp.y + 1
		self.data = setmetatable({}, {__index = function(_, i)
			i = i - 1
			local z, rest = math.floor(i / (nx * ny)), i % (nx * ny)
			local y, x = math.floor(rest / nx), rest % nx
			return id_of(name_of(minp.x + x, minp.y + y, minp.z + z))
		end})
		-- A building's own box is small enough to copy, and a blank needs its length.
		local volume = nx * ny * (maxp.z - minp.z + 1)
		if volume <= 4096 then
			for i = 1, volume do rawset(self.data, i, self.data[i]) end
		end
		return minp, maxp
	end
	function vm:get_data() return self.data end
	function vm:set_data(data) self.data = data end
	function vm:get_param2_data() return setmetatable({}, {__index = function() return 0 end}) end
	return vm
end
-- Square schematics only, so a rotation changes nothing a test looks at.
core.place_schematic_on_vmanip = function(vm, pos, schematic)
	local size, minp, maxp = schematic.size, vm.minp, vm.maxp
	local nx, ny = maxp.x - minp.x + 1, maxp.y - minp.y + 1
	for i, cell in ipairs(schematic.data) do
		local index = i - 1
		local x, y, z = index % size.x, math.floor(index / size.x) % size.y, math.floor(index / (size.x * size.y))
		local at = (pos.z + z - minp.z) * ny * nx + (pos.y + y - minp.y) * nx + (pos.x + x - minp.x) + 1
		if cell.prob ~= 0 then rawset(vm.data, at, id_of(cell.name)) end
	end
	return true
end

-- A 5 by 5 hut: a ground layer, cobble walls with air inside, and one pool of water.
local function hut()
	local data = {}
	for z = 0, 4 do
		for y = 0, 2 do
			for x = 0, 4 do
				local name = "air"
				if y == 0 then name = "mcl_core:dirt"
				elseif x == 0 or x == 4 or z == 0 or z == 4 then name = COBBLE
				elseif y == 1 and x == 2 and z == 2 then name = WATER end
				data[#data + 1] = {name = name, prob = 255, param2 = 0}
			end
		end
	end
	return {size = {x = 5, y = 3, z = 5}, data = data}
end
TEST_HUT = hut
core.serialize_schematic = function() return "schematic = TEST_HUT()" end

local stored = {}
core.serialize = function(value)
	stored[#stored + 1] = value
	return "stored " .. #stored
end
local function deep(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for field, inner in pairs(value) do copy[field] = deep(inner) end
	return copy
end
core.deserialize = function(text) return deep(stored[tonumber(text:match("%d+"))]) end
core.pos_to_string = function(pos) return "(" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ")" end
core.formspec_escape = function(text) return text end
core.colorize = function(_, text) return text end
core.get_translator = function()
	return function(message, ...)
		local args = {...}
		return (message:gsub("@(%d)", function(i) return args[tonumber(i)] end))
	end
end
local shown, closed, receive = {}, 0, nil
core.show_formspec = function(name, form, text) shown[#shown + 1] = {name = name, form = form, text = text} end
core.close_formspec = function() closed = closed + 1 end
core.register_on_player_receive_fields = function(fn) receive = fn end
core.register_on_leaveplayer = function() end

settlements = {
	schematic_table = {{name = "hut", mts = "hut.mts", max_num = 1}, {name = "builder_house", mts = "hut.mts", max_num = 0}},
	surface_mat = {["mcl_core:dirt_with_grass"] = true, ["mcl_core:sand"] = true},
}

local builder = dofile("builder.lua")
local stock = dofile("farm_stock.lua")
local market = dofile("market.lua")

local records = {}
local index = {
	read_village = function() return records[1] end,
	update_village = function(pos, _, change)
		records[1] = records[1] or {center = pos}
		change(records[1])
		return records[1]
	end,
}

local vanilla = {clicks = 0, walks = {}}
local def = {
	on_activate = function() end,
	do_custom = function() return true end,
	on_rightclick = function() vanilla.clicks = vanilla.clicks + 1 end,
	gopath = function(self, target, arrived)
		vanilla.walks[#vanilla.walks + 1] = target
		if self.fail_walks then return false end
		self.object:set_pos({x = target.x + 1, y = target.y, z = target.z})
		if arrived then arrived(self, target) end
		return true
	end,
}
builder.install(def, nil, index)

local serial = 0
local function villager(pos, fields)
	serial = serial + 1
	local entity = support.farmer(world, pos, {_id = "v" .. serial, _profession = "unemployed"})
	entity.gopath = def.gopath
	for field, value in pairs(fields or {}) do entity[field] = value end
	return entity
end
local function advance(entity, seconds)
	world.now = world.now + (seconds or 5)
	def.do_custom(entity, 1)
end
local function clear_map()
	world.nodes, world.metas, records[1] = {}, {}, nil
	ground = "mcl_core:dirt_with_grass"
end
local function place_bench(pos)
	world.set(pos, BENCH)
	return pos
end
local BENCH_POS = {x = 0, y = 1, z = 0}

-- A villager of the house takes the bench at once; a bed further away does not.
do
	clear_map()
	place_bench(BENCH_POS)
	local far = villager({x = 30, y = 1, z = 30}, {_bed = {x = 30, y = 1, z = 30}})
	far.fail_walks = true
	world.now = 1000
	def.do_custom(far, 1)
	assert(far._jobsite == nil and not far._villages_builder, "its bed is not by the bench")
	local owner = villager({x = 40, y = 1, z = 40}, {_bed = {x = 3, y = 1, z = 3}, _villages_farm_seek = {x = 9, y = 1, z = 9}})
	def.do_custom(owner, 1)
	assert(owner._villages_builder and owner._profession == "mason" and owner._villages_farm_seek == nil)
	assert(owner._trades == nil, "it has no trades, so losing the bench unemploys it")
	assert(vector.distance(owner._jobsite, BENCH_POS) == 0)
	assert(world.meta(BENCH_POS).fields.villager == owner._id)
	assert(builder.claimed_bench(owner))

	-- It is taken now.
	local late = villager({x = 2, y = 1, z = 2}, {_bed = {x = 3, y = 1, z = 3}})
	world.now = world.now + 100
	def.do_custom(late, 1)
	assert(late._jobsite == nil)
	assert(not builder.employ(late, BENCH_POS))
end

-- Not everyone can be a Builder.
do
	clear_map()
	place_bench(BENCH_POS)
	local bed = {x = 3, y = 1, z = 3}
	for _, fields in ipairs({{child = true}, {_profession = "farmer"}, {_jobsite = {x = 9, y = 9, z = 9}}, {_id = false}}) do
		fields._bed = bed
		local entity = villager({x = 2, y = 1, z = 2}, fields)
		if entity._id == false then entity._id = nil end
		world.now = world.now + 100
		def.do_custom(entity, 1)
		assert(not entity._villages_builder)
	end
	assert(world.meta(BENCH_POS).fields.villager == nil)
end

-- Anyone else out of work may walk over, at work or free hours, unless a composter comes first.
do
	clear_map()
	place_bench(BENCH_POS)
	vanilla.walks = {}
	local seeker = villager({x = 20, y = 1, z = 0}, {_villages_farm_seek = {x = 25, y = 1, z = 0}})
	world.now = world.now + 100
	def.do_custom(seeker, 1)
	assert(#vanilla.walks == 0, "the farm comes first")
	seeker._villages_farm_seek = nil
	world.now = world.now + 100
	def.do_custom(seeker, 1)
	assert(#vanilla.walks == 1 and seeker._villages_builder, "it walked there and took it")

	-- A bench it cannot reach is left alone for a while, and tried again after that.
	clear_map()
	place_bench(BENCH_POS)
	vanilla.walks = {}
	local stuck = villager({x = 20, y = 1, z = 0})
	stuck.fail_walks = true
	world.now = world.now + 100
	def.do_custom(stuck, 1)
	assert(#vanilla.walks == 1)
	world.now = world.now + 20
	def.do_custom(stuck, 1)
	assert(#vanilla.walks == 1, "not yet")
	world.now = world.now + 300
	def.do_custom(stuck, 1)
	assert(#vanilla.walks == 2)
end

-- What a project goes through, and what is kept.
local function hired()
	clear_map()
	place_bench(BENCH_POS)
	world.set({x = 2, y = 1, z = 0}, WOOD)
	local entity = villager({x = 1, y = 1, z = 1}, {_bed = {x = 2, y = 1, z = 2}})
	world.now = world.now + 100
	def.do_custom(entity, 1)
	assert(entity._villages_builder)
	return entity
end

do
	local entity = hired()
	-- Its first look round, the moment it is hired, picks a building: never its own house.
	local project = builder.load_project(BENCH_POS)
	assert(project.state == "finding_site" and project.building == "hut")
	assert(builder.status(entity):find("finding_site", 1, true))

	-- With no chests there is a bill to pay, and the site is held for it.
	advance(entity)
	project = builder.load_project(BENCH_POS)
	assert(project.state == "requires_materials", project.state)
	assert(project.pos and project.pos.y == 0 and project.rotat and project.surface_mat == "mcl_core:dirt_with_grass")
	assert(records[1].reserved["0,1,0"].x0 == project.pos.x and records[1].reserved["0,1,0"].x1 == project.pos.x + 4)
	advance(entity, 10)

	local report = builder.report(entity)
	assert(report.state == "requires_materials" and report.building == "hut" and report.earthwork == 0)
	local rows = {}
	for _, row in ipairs(report.rows) do rows[row.item] = row end
	assert(rows[COBBLE].need == 32 and rows[COBBLE].missing == 32 and rows[COBBLE].price == nil)
	assert(rows[BUCKET].need == 1 and rows[BUCKET].price == 1, "water can be bought")
	assert(report.left == 33 and report.total > report.left, "the air it wants inside is already there")

	-- Chests near the bench count; so does what it carries; and not one chest further.
	world.set({x = 40, y = 1, z = 0}, CHEST)
	support.chest(world, {x = 40, y = 1, z = 0}, CHEST, {COBBLE .. " 64"})
	support.chest(world, {x = -14, y = 1, z = 0}, CHEST, {COBBLE .. " 20"})
	stock.add(entity, COBBLE, 2)
	report = builder.report(entity)
	for _, row in ipairs(report.rows) do rows[row.item] = row end
	assert(rows[COBBLE].in_chests == 20 and rows[COBBLE].carried == 2 and rows[COBBLE].missing == 10)
	advance(entity, 10)
	assert(builder.load_project(BENCH_POS).state == "requires_materials")

	-- Off work nothing moves.
	support.chest(world, {x = -14, y = 1, z = 1}, CHEST, {COBBLE .. " 10", BUCKET})
	world.time = 0.9
	advance(entity, 20)
	assert(builder.load_project(BENCH_POS).state == "requires_materials")
	assert(builder.report(entity).at_work == false)
	world.time = 0.4

	-- Everything there: the work begins, and nothing has been touched before that.
	assert(not builder.load_project(BENCH_POS).started)
	advance(entity, 10)
	local started = builder.load_project(BENCH_POS)
	assert(started.state == "collecting" and started.started)
end

-- No site: it stays on the same building, and looks again in a while.
do
	local entity = hired()
	ground = WATER
	advance(entity)
	advance(entity)
	local project = builder.load_project(BENCH_POS)
	assert(project.state == "no_site" and project.building == "hut")
	local report = builder.report(entity)
	assert(report.size.x == 5 and report.size.y == 3 and report.size.z == 5 and report.range == 80)

	ground = "mcl_core:dirt_with_grass"
	advance(entity, 30)
	assert(builder.load_project(BENCH_POS).state == "no_site", "not looked again yet")
	advance(entity, 31)
	assert(builder.load_project(BENCH_POS).state == "requires_materials", "the player cleared a spot")
end

-- A site spoiled before anything was built: it looks for another.
do
	local entity = hired()
	advance(entity)
	advance(entity)
	local first = builder.load_project(BENCH_POS)
	assert(first.state == "requires_materials")
	world.set({x = first.pos.x + 2, y = 1, z = first.pos.z + 2}, WOOD)
	advance(entity, 61)
	local project = builder.load_project(BENCH_POS)
	assert(project.state == "finding_site" and project.pos == nil and project.building == "hut")
	advance(entity, 61)
	project = builder.load_project(BENCH_POS)
	assert(project.state == "requires_materials")
	assert(project.pos.x ~= first.pos.x or project.pos.z ~= first.pos.z)
end

-- A second bench does not take the first one's site, unless that bench has gone.
do
	local entity = hired()
	advance(entity)
	advance(entity)
	local first = builder.load_project(BENCH_POS)
	local other_pos = {x = 1, y = 1, z = -8}
	place_bench(other_pos)
	local other = villager({x = 1, y = 1, z = -7}, {_bed = {x = 1, y = 1, z = -6}})
	-- This one is not in range of the first bench's bed test.
	world.now = world.now + 100
	def.do_custom(other, 1)
	assert(other._villages_builder and vector.distance(other._jobsite, other_pos) == 0)
	advance(other)
	advance(other)
	local second = builder.load_project(other_pos)
	assert(second.state == "requires_materials")
	assert(math.abs(second.pos.x - first.pos.x) >= 8 or math.abs(second.pos.z - first.pos.z) >= 8, "they keep apart")
end

-- Buying: only what the project still lacks, on sale, with the money, from close by.
local shoppers = 0
local function shopper(pos, emeralds)
	shoppers = shoppers + 1
	local inv = support.chest(world, {x = 99, y = 99, z = shoppers})
	if emeralds > 0 then inv:add_item("main", "mcl_core:emerald " .. emeralds) end
	local player = {
		inv = inv,
		is_player = function() return true end,
		get_player_name = function() return "singleplayer" end,
		get_pos = function() return pos end,
		get_inventory = function() return inv end,
	}
	return player
end

do
	local entity = hired()
	advance(entity)
	advance(entity)
	local near = {x = 2, y = 1, z = 2}
	local ok, why = builder.buy(entity, shopper(near, 5), COBBLE)
	assert(not ok and why == "not_for_sale", "cobble is not hard to come by")
	ok, why = builder.buy(entity, shopper(near, 0), BUCKET)
	assert(not ok and why == "no_emeralds")
	ok, why = builder.buy(entity, shopper({x = 50, y = 1, z = 50}, 5), BUCKET)
	assert(not ok and why == "too_far")
	ok, why = builder.buy(entity, shopper(near, 5), "mcl_core:emerald")
	assert(not ok and why == "not_for_sale")
	ok, why = builder.buy(entity, shopper(near, 5), "mcl_buckets:bucket_lava")
	assert(not ok and why == "not_needed", "the project wants no lava")

	-- No chest: the player keeps it.
	local player = shopper(near, 5)
	ok, why = builder.buy(entity, player, BUCKET)
	assert(ok and why == "in_inventory")
	assert(player.inv:contains_item("main", "mcl_core:emerald 4") and not player.inv:contains_item("main", "mcl_core:emerald 5"))
	assert(player.inv:contains_item("main", BUCKET))

	-- A chest: it goes there, and then it is no longer lacking, so it cannot be bought again.
	support.chest(world, {x = -14, y = 1, z = 0}, CHEST)
	player = shopper(near, 5)
	ok, why = builder.buy(entity, player, BUCKET)
	assert(ok and why == "in_chest")
	assert(stock.chest_count({x = -14, y = 1, z = 0}, BUCKET) == 1)
	ok, why = builder.buy(entity, player, BUCKET)
	assert(not ok and why == "not_needed")
	assert(player.inv:contains_item("main", "mcl_core:emerald 4"), "and is not charged for it")

	-- A full chest and a full player: it lands at the player's feet, not nowhere.
	world.meta({x = -14, y = 1, z = 0}).inv:remove_item("main", BUCKET)
	for slot = 1, 27 do world.meta({x = -14, y = 1, z = 0}).inv:set_stack("main", slot, COBBLE .. " 64") end
	player = shopper(near, 1)
	local real_add = player.inv.add_item
	player.inv.add_item = function(self, list, item)
		if item == BUCKET then return support.stack(item) end
		return real_add(self, list, item)
	end
	world.dropped = {}
	ok, why = builder.buy(entity, player, BUCKET)
	assert(ok and why == "in_inventory" and #world.dropped == 1)
end

-- The window: a right-click on a Builder, and only on a Builder.
do
	local entity = hired()
	advance(entity)
	advance(entity)
	vanilla.clicks = 0
	shown = {}
	local player = shopper({x = 2, y = 1, z = 2}, 5)
	def.on_rightclick(entity, player)
	assert(vanilla.clicks == 0 and #shown == 1)
	local text = shown[1].text
	assert(shown[1].form == "living_villages:builder_status")
	assert(text:find("Hut", 1, true) and text:find("Waiting for materials", 1, true))
	assert(text:find("item_image", 1, true) and text:find(COBBLE, 1, true) and text:find(BUCKET, 1, true))
	assert(text:find("buy_", 1, true) and text:find("refresh", 1, true))
	assert(text:find("^formspec_version%[4%]"))

	-- A Buy button works by the row's item, and the window comes back with the news.
	local field = text:match("(buy_%d+)")
	shown = {}
	assert(receive(player, "living_villages:builder_status", {[field] = "Buy"}) == true)
	assert(#shown == 1 and shown[1].text:find("in your inventory", 1, true))

	-- A field the window never sent buys nothing.
	shown = {}
	assert(receive(player, "living_villages:builder_status", {buy_99 = "Buy"}) == true)
	assert(#shown == 0)

	-- Refresh; someone else's form; and a villager gone with the window open.
	assert(receive(player, "other:form", {refresh = "x"}) == false)
	assert(receive(player, "living_villages:builder_status", {refresh = "Refresh"}) == true and #shown == 1)
	assert(shown[1].text:find("It is off work", 1, true) == nil)
	local object = entity.object
	entity.object = {get_pos = function() return nil end}
	shown, closed = {}, 0
	assert(receive(player, "living_villages:builder_status", {refresh = "Refresh"}) == true)
	assert(#shown == 0 and closed == 1)
	entity.object = object
	assert(receive(player, "living_villages:builder_status", {quit = "true"}) == true)

	-- Everyone else still gets vanilla's window.
	local other = villager({x = 2, y = 1, z = 2}, {_profession = "farmer"})
	def.on_rightclick(other, player)
	assert(vanilla.clicks == 1)
end

-- The window's words for each state, and a table only while it waits for materials.
do
	local status = dofile("builder_status.lua")
	local form = status.formspec({state = "no_site", building = "small_house", size = {x = 7, y = 5, z = 9}, range = 80})
	assert(form:find("Small house", 1, true) and form:find("7 by 9", 1, true) and form:find("within 80 nodes", 1, true))
	assert(not form:find("item_image", 1, true))
	form = status.formspec({state = "no_bench"})
	assert(form:find("no bench", 1, true))
	form = status.formspec({state = "building", left = 10, total = 40, rows = {{item = COBBLE, need = 1, in_chests = 1, carried = 0, missing = 0}}})
	assert(form:find("Done: 30 of 40", 1, true) and not form:find("item_image", 1, true))
	form = status.formspec({state = "blocked", blocked = {x = 1, y = 2, z = 3}})
	assert(form:find("(1,2,3)", 1, true))
	-- Enough rows to scroll.
	local rows = {}
	for i = 1, 20 do rows[i] = {item = "x:" .. i, need = 1, in_chests = 0, carried = 0, missing = 1} end
	form = status.formspec({state = "requires_materials", rows = rows})
	assert(form:find("scrollbar[", 1, true) and form:find("scroll_container_end[]", 1, true))
	assert(not form:find("Price each", 1, true), "no price column when nothing is on sale")
	-- What is on sale says what one costs, in emeralds, and the button how many it buys.
	rows = {
		{item = "x:lantern", need = 3, in_chests = 0, carried = 0, missing = 3, price = 4},
		{item = "x:bucket", need = 1, in_chests = 0, carried = 0, missing = 1, price = 1},
	}
	form = status.formspec({state = "requires_materials", rows = rows, currency = "mcl_core:emerald"})
	assert(form:find("Price each", 1, true) and form:find("Buy 1", 1, true) and not form:find("Buy:", 1, true))
	assert(form:find(";mcl_core:emerald]", 1, true))
	assert(form:find("tooltip[buy_1;One costs 4 emeralds", 1, true))
	assert(form:find("tooltip[buy_2;One costs 1 emerald.", 1, true))
	rows = {rows[1]}
	form = status.formspec({state = "requires_materials", rows = rows})
	assert(not form:find("scrollbar[", 1, true))
end

-- Losing the bench: vanilla takes the job, and this drops what it carried.
do
	local entity = hired()
	stock.add(entity, COBBLE, 3)
	world.dropped = {}
	-- As vanilla's remove_job leaves it.
	entity._jobsite, entity._profession = nil, "unemployed"
	world.nodes["0,1,0"] = nil
	advance(entity)
	assert(not entity._villages_builder and #world.dropped == 1 and stock.total(entity) == 0)
end

-- A Builder keeps out of other trades' ways, and they out of its.
do
	local entity = hired()
	local stone = {x = 5, y = 1, z = 5}
	world.set(stone, "mcl_stonecutter:stonecutter")
	vanilla.walks = {}
	assert(def.gopath(entity, stone) == false and #vanilla.walks == 0)
	assert(def.gopath(entity, BENCH_POS) == true)
	local ok, why = market.eligible(entity)
	assert(ok == false and why == "builder")
end

-- The flag comes back with the villager, and only for one with its bench.
do
	local entity = hired()
	entity._villages_builder = nil
	def.on_activate(entity, "", 0)
	assert(entity._villages_builder)
	local mason = villager({x = 1, y = 1, z = 1}, {_profession = "mason"})
	def.on_activate(mason, "", 0)
	assert(not mason._villages_builder)
end

-- Runs it until the test's condition, a second at a time.
local function run_until(entity, done, limit)
	for _ = 1, limit or 600 do
		if done() then return true end
		advance(entity, 1)
	end
	return done()
end

local function project_gone_or(state)
	return function()
		local project = builder.load_project(BENCH_POS)
		return not project or project.state == state
	end
end

-- A project with a site of the test's choosing, with some earthwork to do.
local SITE = {x = 10, y = 0, z = 10}
local function prepared(earthwork)
	local entity = hired()
	world.set({x = 2, y = 1, z = 0}, WOOD)
	local project = {
		state = "requires_materials", building = "hut", pos = SITE, rotat = "0",
		surface_mat = "mcl_core:dirt_with_grass", earthwork = earthwork or {cuts = {}, fills = {}},
	}
	world.meta(BENCH_POS).fields.villages_project = core.serialize(project)
	records[1] = {center = BENCH_POS, buildings = {{name = "hut", pos = BENCH_POS}}, reserved = {["0,1,0"] = {bench = BENCH_POS}}}
	return entity
end
local function built_right()
	for z = 0, 4 do
		for y = 1, 2 do
			for x = 0, 4 do
				local name = world.name({x = SITE.x + x, y = y, z = SITE.z + z})
				local wall = x == 0 or x == 4 or z == 0 or z == 4
				local want = wall and COBBLE or (y == 1 and x == 2 and z == 2 and WATER) or "air"
				if name ~= want then return false, name .. " wanted " .. want end
			end
		end
	end
	return true
end

-- The whole job, from a stocked chest: earthwork, then solids, then water last, all from the
-- ring and in reach, one block a second, with the leftovers and the empty bucket put back.
do
	local bump, hole = {x = 11, y = 1, z = 11}, {x = 12, y = 0, z = 12}
	local entity = prepared({cuts = {bump}, fills = {hole}})
	world.set(bump, "mcl_core:dirt")
	world.nodes["12,0,12"] = {name = "air"}
	local chest = {x = 0, y = 1, z = 6}
	support.chest(world, chest, CHEST)

	-- Waiting for materials leaves the site as it was.
	advance(entity, 11)
	assert(builder.load_project(BENCH_POS).state == "requires_materials")
	assert(world.name(bump) == "mcl_core:dirt" and world.name(hole) == "air")
	assert(not builder.activity_override(entity, "work"), "it waits at its bench")

	world.meta(chest).inv:add_item("main", COBBLE .. " 40")
	world.meta(chest).inv:add_item("main", BUCKET)

	local order = {}
	local real_set, real_remove = core.set_node, core.remove_node
	local furthest, last_at, fastest = 0, nil, 99
	local function note(pos, kind)
		order[#order + 1] = kind
		furthest = math.max(furthest, vector.distance(entity.object:get_pos(), pos))
		if last_at then fastest = math.min(fastest, world.now - last_at) end
		last_at = world.now
	end
	core.set_node = function(pos, node)
		note(pos, node.name)
		return real_set(pos, node)
	end
	core.remove_node = function(pos)
		note(pos, "removed")
		return real_remove(pos)
	end
	assert(run_until(entity, project_gone_or("returning")))
	assert(builder.activity_override(entity, "work") == "build", "not called back while it works")
	assert(run_until(entity, function() return stock.total(entity) == 0 and not builder.load_project(BENCH_POS) end))
	core.set_node, core.remove_node = real_set, real_remove

	assert(built_right())
	assert(order[1] == "removed" and order[2] == "mcl_core:dirt", "earthwork first")
	assert(world.name(bump) == "air" and world.name(hole) == "mcl_core:dirt")
	assert(order[#order] == WATER, "water last")
	assert(furthest <= 14 and fastest >= 1, "in reach, and at its pace: " .. furthest .. " " .. fastest)
	assert(stock.chest_count(chest, COBBLE) == 8, "what it did not use stays in the chest")
	assert(stock.chest_count(chest, "mcl_buckets:bucket_empty") == 1, "and the bucket comes back")

	-- It counts in the census, gives up its reservation, and moves on.
	assert(records[1].built.hut == 1 and records[1].reserved["0,1,0"] == nil)
	advance(entity, 6)
	local following = builder.load_project(BENCH_POS)
	assert(following.building == "hut" and following.state ~= "returning" and not following.started)
	assert(not builder.activity_override(entity, "work"), "back to its bench while it thinks")
end

-- A small capacity means more trips, never too much carried at once, and the same result.
do
	world.settings.living_villages_builder_capacity = "10"
	local entity = prepared()
	local chest = {x = 0, y = 1, z = 6}
	support.chest(world, chest, CHEST, {COBBLE .. " 32", BUCKET})
	local heaviest = 0
	assert(run_until(entity, function()
		heaviest = math.max(heaviest, stock.total(entity))
		return project_gone_or("returning")()
	end, 900))
	assert(heaviest == 10 and built_right())
	world.settings.living_villages_builder_capacity = nil
end

-- With a short reach it does what it can from where it stands before walking on, and every
-- layer still finishes before the one above it starts.
do
	world.settings.living_villages_builder_reach = "6"
	local entity = prepared()
	local chest = {x = 0, y = 1, z = 6}
	support.chest(world, chest, CHEST, {COBBLE .. " 32", BUCKET})
	local real_set = core.set_node
	local top_layer_began, order_kept = false, true
	core.set_node = function(pos, node)
		if pos.y == 2 and node.name == COBBLE then top_layer_began = true end
		if pos.y == 1 and node.name == COBBLE and top_layer_began then order_kept = false end
		return real_set(pos, node)
	end
	local walks_before = #vanilla.walks
	assert(run_until(entity, project_gone_or("returning")))
	core.set_node = real_set
	assert(built_right() and order_kept)
	assert(#vanilla.walks - walks_before <= 10, "walks: " .. (#vanilla.walks - walks_before))
	world.settings.living_villages_builder_reach = nil
end

-- Something foreign in a cell, once started: it stops and says where, and carries on when it goes.
do
	local entity = prepared()
	local chest = {x = 0, y = 1, z = 6}
	support.chest(world, chest, CHEST, {COBBLE .. " 32", BUCKET})
	assert(run_until(entity, function() return builder.load_project(BENCH_POS).state == "building" end))
	local cell = {x = SITE.x + 2, y = 2, z = SITE.z}
	world.set(cell, "mcl_core:stone")
	assert(run_until(entity, function() return builder.load_project(BENCH_POS).state == "blocked" end, 30))
	local report = builder.report(entity)
	assert(report.blocked and report.blocked.x == cell.x and report.blocked.y == cell.y and report.blocked.z == cell.z)
	assert(builder.load_project(BENCH_POS).pos.x == SITE.x, "a started site is not given up")
	world.nodes[cell.x .. ",2," .. cell.z] = nil
	assert(run_until(entity, project_gone_or("returning")))
	assert(built_right())
end

-- Griefing and a new Builder: nothing is remembered, so both just work from what is there.
do
	local entity = prepared()
	local chest = {x = 0, y = 1, z = 6}
	support.chest(world, chest, CHEST, {COBBLE .. " 20", BUCKET})
	-- Not enough: it will not start.
	advance(entity, 11)
	assert(builder.load_project(BENCH_POS).state == "requires_materials")
	world.meta(chest).inv:add_item("main", COBBLE .. " 13")
	assert(run_until(entity, function()
		return world.name({x = SITE.x + 4, y = 1, z = SITE.z}) == COBBLE
	end))
	-- Its successor, with its pouch dropped where the first died, finds the rest in the chest.
	for item, count in pairs(entity._villages_farm_pouch) do
		world.meta(chest).inv:add_item("main", item .. " " .. count)
	end
	entity._villages_farm_pouch = nil
	world.meta(BENCH_POS).fields.villager = nil
	local next_one = villager({x = 1, y = 1, z = 1}, {_bed = {x = 2, y = 1, z = 2}})
	world.now = world.now + 100
	def.do_custom(next_one, 1)
	assert(next_one._villages_builder)
	-- Someone takes a block away: it goes back.
	world.nodes[(SITE.x + 4) .. ",1," .. SITE.z] = nil
	assert(run_until(next_one, project_gone_or("returning")))
	assert(built_right(), "rebuilt and finished by the next one")
end

-- A chest emptied mid-job sends it back to waiting; a mob in a cell only makes it wait.
do
	local entity = prepared()
	local chest = {x = 0, y = 1, z = 6}
	support.chest(world, chest, CHEST, {COBBLE .. " 32", BUCKET})
	local first = {x = SITE.x, y = 1, z = SITE.z}
	local mob = {get_pos = function() return {x = first.x, y = 1, z = first.z} end, get_luaentity = function() return {name = "mobs_mc:cow", is_mob = true} end}
	table.insert(world.objects, mob)
	assert(run_until(entity, function() return builder.load_project(BENCH_POS).state == "building" end))
	for _ = 1, 8 do advance(entity, 1) end
	assert(world.name(first) == "air", "not on top of a cow")
	assert(world.name({x = SITE.x + 1, y = 1, z = SITE.z}) == COBBLE, "it goes on with the next")
	mob.get_pos = function() return nil end

	entity._villages_farm_pouch = nil
	world.meta(chest).inv:remove_item("main", COBBLE .. " 64")
	assert(run_until(entity, function() return builder.load_project(BENCH_POS).state == "requires_materials" end, 40))
	assert(builder.load_project(BENCH_POS).started)
	local report = builder.report(entity)
	assert(report.state == "requires_materials" and report.rows[1].missing > 0)
	for i = #world.objects, 1, -1 do
		if world.objects[i] == mob then table.remove(world.objects, i) end
	end
end

-- A chest's display entity is always there, and is no one to wait for (seen on a blacksmith,
-- whose window sits over its chest). Someone who stays in the way is, and it says so.
do
	local entity = prepared()
	local chest = {x = 0, y = 1, z = 6}
	support.chest(world, chest, CHEST, {COBBLE .. " 32", BUCKET})
	local below = {x = SITE.x, y = 1, z = SITE.z}
	local display = {get_pos = function() return below end, get_luaentity = function() return {name = "mcl_chests:chest"} end}
	table.insert(world.objects, display)
	assert(run_until(entity, project_gone_or("returning")))
	assert(built_right())
	display.get_pos = function() return nil end

	entity = prepared()
	support.chest(world, chest, CHEST, {COBBLE .. " 32", BUCKET})
	local water_cell = {x = SITE.x + 2, y = 1, z = SITE.z + 2}
	local player = {get_pos = function() return below end, is_player = function() return true end}
	table.insert(world.objects, player)
	assert(run_until(entity, function() return builder.report(entity).stuck == "occupied" end))
	assert(world.name(below) == "air", "not on top of a player")
	assert(world.name(water_cell) == "air", "and the water waits for the walls")
	assert(dofile("builder_status.lua").formspec(builder.report(entity)):find("standing where", 1, true))
	player.get_pos = function() return nil end
	assert(run_until(entity, project_gone_or("returning")))
	assert(built_right())
end

-- A site it has never got to, however near its bench, is untouched, and it finds another.
-- It keeps away from that one for a while, not for good.
do
	local entity = prepared()
	local chest = {x = 0, y = 1, z = 6}
	support.chest(world, chest, CHEST, {COBBLE .. " 32", BUCKET})
	assert(run_until(entity, function() return builder.load_project(BENCH_POS).state == "building" end))
	-- The chest is in reach of its first walk, so the failure is only to the site.
	entity.fail_walks = true
	assert(run_until(entity, function() return builder.load_project(BENCH_POS).state == "finding_site" end, 30))
	local project = builder.load_project(BENCH_POS)
	assert(project.pos == nil and not project.started and #project.avoid == 1)
	assert(project.avoid[1].x0 == SITE.x and project.avoid[1].expires > world.now)
	for z = 0, 4 do
		for x = 0, 4 do assert(world.name({x = SITE.x + x, y = 1, z = SITE.z + z}) == "air", "not a block placed") end
	end
	entity.fail_walks = nil
	assert(run_until(entity, function() return builder.load_project(BENCH_POS).pos ~= nil end, 90))
	local next_site = builder.load_project(BENCH_POS).pos
	assert(next_site.x + 4 < SITE.x - 3 or next_site.x > SITE.x + 7 or next_site.z + 4 < SITE.z - 3 or next_site.z > SITE.z + 7)
end

-- Nowhere to stand: it says so rather than wandering.
do
	local entity = prepared()
	local chest = {x = 0, y = 1, z = 6}
	support.chest(world, chest, CHEST, {COBBLE .. " 32", BUCKET})
	assert(run_until(entity, function() return world.name({x = SITE.x, y = 1, z = SITE.z}) == COBBLE end))
	-- From the ring it can reach all of this hut, so take it away first.
	entity.object:set_pos({x = -30, y = 1, z = -30})
	entity.fail_walks = true
	assert(run_until(entity, function() return builder.report(entity).stuck == "site" end, 60))
	assert(builder.load_project(BENCH_POS).pos.x == SITE.x, "what it has begun, it keeps")
	local form = dofile("builder_status.lua").formspec(builder.report(entity))
	assert(form:find("cannot get to the site", 1, true))
	entity.fail_walks = nil
end

-- /giveme build_project_materials: what the nearest waiting Builder lacks, and nothing else.
do
	local command = {params = "<ItemString>", func = function(_, param) return true, "engine: " .. param end}
	core.registered_chatcommands = {giveme = command}
	core.override_chatcommand = function(name, redefinition)
		assert(name == "giveme")
		for field, value in pairs(redefinition) do command[field] = value end
	end
	local giveme = dofile("builder_giveme.lua")
	giveme.install(builder)
	local near = {x = 2, y = 1, z = 2}
	local player = shopper(near, 0)
	core.get_player_by_name = function() return player end
	local function run(param) return command.func("singleplayer", param) end

	-- Anything else is the engine's.
	local ok, message = run("mcl_core:dirt 5")
	assert(ok and message == "engine: mcl_core:dirt 5")

	-- Nobody near.
	local before = #world.objects
	for i = before, 1, -1 do world.objects[i] = nil end
	ok, message = run("build_project_materials")
	assert(not ok and message:find("No Builder", 1, true))

	-- A Builder that is not waiting for materials: a warning, and nothing given.
	local entity = hired()
	assert(builder.report(entity).state ~= "requires_materials")
	ok, message = run(" build_project_materials ")
	assert(not ok and message:find("not waiting", 1, true) and message:find(builder.report(entity).state, 1, true))
	assert(not player.inv:contains_item("main", COBBLE))

	-- Waiting: only what the chests and the pouch do not cover.
	advance(entity)
	advance(entity)
	assert(builder.report(entity).state == "requires_materials")
	support.chest(world, {x = -14, y = 1, z = 0}, CHEST, {COBBLE .. " 20"})
	stock.add(entity, COBBLE, 2)
	ok, message = run("build_project_materials")
	assert(ok and message:find("Added 11 items to your inventory", 1, true) and message:find("hut", 1, true), message)
	assert(player.inv:contains_item("main", COBBLE .. " 10") and not player.inv:contains_item("main", COBBLE .. " 11"))
	assert(player.inv:contains_item("main", BUCKET))

	-- A second run gives no more, and nothing went to the chests or the state.
	ok, message = run("build_project_materials")
	assert(ok and message:find("already hold", 1, true) and not player.inv:contains_item("main", COBBLE .. " 11"))
	assert(stock.chest_count({x = -14, y = 1, z = 0}, COBBLE) == 20 and stock.count(entity, COBBLE) == 2)
	assert(builder.report(entity).state == "requires_materials")

	-- What the player already holds is not given again: part of it, then more than enough.
	player = shopper(near, 0)
	player.inv:add_item("main", COBBLE .. " 4")
	ok, message = run("build_project_materials")
	assert(ok and message:find("Added 7 items", 1, true), message)
	assert(player.inv:contains_item("main", COBBLE .. " 10") and not player.inv:contains_item("main", COBBLE .. " 11"))
	player = shopper(near, 0)
	player.inv:add_item("main", COBBLE .. " 15")
	ok, message = run("build_project_materials")
	assert(ok and message:find("Added 1 item to", 1, true), message)
	assert(player.inv:contains_item("main", COBBLE .. " 15") and not player.inv:contains_item("main", COBBLE .. " 16"))
	assert(player.inv:contains_item("main", BUCKET))

	-- The nearest that is waiting, past one that is not: the state of the first does not stop it.
	local idle = villager({x = 2, y = 1, z = 3})
	idle._villages_builder = true
	local report = builder.report
	builder.report = function(self)
		if self == idle then return {state = "building"} end
		return report(self)
	end
	player = shopper(near, 0)
	ok = run("build_project_materials")
	assert(ok and player.inv:contains_item("main", BUCKET))
	builder.report = report

	-- An inventory with no room says what it left.
	player = shopper(near, 0)
	player.inv.lists.main = {}
	ok, message = run("build_project_materials")
	assert(ok and message:find("Added 0 items", 1, true) and message:find(COBBLE .. " 10", 1, true), message)
end

-- A bench set to a directory of schematics.
do
	local WORLD = "/world"
	local DIR = WORLD .. "/schems"
	local files, schematics = {}, {}
	local LOOM, FLOWING = "mcl_loom:loom", "mcl_core:water_flowing"
	world.defs[LOOM] = {groups = {}}
	world.defs[FLOWING] = {groups = {not_in_creative_inventory = 1}, liquidtype = "flowing"}

	local real_open = io.open
	io.open = function(path, mode)
		local content = files[path]
		if not path:find("^" .. WORLD) then return real_open(path, mode) end
		if content == nil then return nil end
		return {
			seek = function(_, whence) return whence == "end" and #content or 0 end,
			read = function() return content end,
			close = function() end,
		}
	end
	core.get_worldpath = function() return WORLD end
	core.mkdir = function() return true end
	core.sha1 = function(content) return "h" .. content:gsub("%W", "_") end
	core.safe_file_write = function(path, content)
		files[path] = content
		return true
	end
	core.parse_json = function() return nil end
	core.get_dir_list = function(directory)
		local found = {}
		for path in pairs(files) do
			local dir, file = path:match("^(.*)/([^/]+)$")
			if dir == directory then found[#found + 1] = file end
		end
		return found
	end
	core.read_schematic = function(path)
		local make = schematics[files[path]]
		return make and make()
	end
	-- A ground layer, a floor of one row, a loom, a void over a node of the world's, a stair
	-- a stock swap would turn to a slab, and flowing water.
	local PRESERVED = "mcl_core:wood"
	local function cabin()
		local data = {}
		for z = 0, 2 do
			for y = 0, 1 do
				for x = 0, 2 do
					local name, prob = "air", 254
					if y == 0 then name = "mcl_core:dirt"
					elseif x == 0 and z == 0 then name = LOOM
					elseif x == 1 and z == 0 then name, prob = "air", 0
					elseif x == 2 and z == 0 then name = FLOWING
					elseif x == 0 and z == 1 then name = COBBLE end
					data[#data + 1] = {name = name, prob = prob, param2 = 0}
				end
			end
		end
		return {size = {x = 3, y = 2, z = 3}, data = data}
	end
	local function add(name, make)
		files[DIR .. "/" .. name .. ".mts"] = name
		schematics[name] = make
	end
	add("cabin", cabin)
	local CATALOG = dofile("builder_catalog.lua")

	-- Set it and the next project comes from there, from its own copy.
	local entity = hired()
	local before = builder.load_project(BENCH_POS)
	assert(before.building == "hut" and before.state == "finding_site")
	assert(builder.source_of(BENCH_POS) == nil)
	builder.set_source(BENCH_POS, CATALOG.SCHEMEDIT)
	assert(builder.source_of(BENCH_POS) == CATALOG.SCHEMEDIT)
	assert(builder.load_project(BENCH_POS) == nil, "a project nothing was done for is dropped")
	advance(entity, 6)
	local project = builder.load_project(BENCH_POS)
	assert(project.building == "cabin" and project.source == CATALOG.SCHEMEDIT, tostring(project.building))
	assert(project.schem == "hcabin" and project.seed)
	assert(files[CATALOG.snapshot_path("hcabin")] == "cabin", "copied")

	-- Deleting the original changes nothing for a project that has its copy.
	files[DIR .. "/cabin.mts"] = nil
	assert(run_until(entity, project_gone_or("requires_materials")))
	project = builder.load_project(BENCH_POS)
	assert(project.state == "requires_materials" and project.pos, project.state)

	-- The bill has the job block, and neither the void nor the flow.
	local report = builder.report(entity)
	local needs = {}
	for _, row in ipairs(report.rows) do needs[row.item] = row.need end
	assert(needs[LOOM] == 1 and needs[COBBLE] == 1, "job block and wall")
	assert(not needs[FLOWING] and not needs["mcl_buckets:bucket_water"])

	-- Well clear of the site, which a chest in the footprint would spoil.
	local chest = {x = project.pos.x + 9, y = 1, z = project.pos.z}
	support.chest(world, chest, CHEST)
	world.meta(chest).inv:add_item("main", COBBLE .. " 1")
	world.meta(chest).inv:add_item("main", LOOM .. " 1")
	assert(run_until(entity, function() return builder.load_project(BENCH_POS).state ~= "requires_materials" end))
	local kept = builder.load_project(BENCH_POS).pos
	assert(kept and kept.x == project.pos.x and kept.z == project.pos.z, "the same site")

	-- A node put in the void cell once work is under way is left standing, and in the way of
	-- nothing. The stub places a schematic unrotated, so the cell is known.
	local origin = project.pos
	local void_at = {x = origin.x + 1, y = origin.y + 1, z = origin.z}
	world.set(void_at, PRESERVED)
	assert(run_until(entity, function() return not builder.load_project(BENCH_POS) end, 900), "it finishes")
	assert(world.name(void_at) == PRESERVED, "a void leaves what is there")
	assert(world.name({x = origin.x, y = origin.y + 1, z = origin.z}) == LOOM, "the job block is built")
	assert(world.name({x = origin.x, y = origin.y + 1, z = origin.z + 1}) == COBBLE)
	assert(world.name({x = origin.x + 2, y = origin.y + 1, z = origin.z}) == "air", "no flow is placed")
	assert(stock.chest_count(chest, LOOM) == 0, "and paid for")

	-- It counts apart from the stock mix.
	assert(records[1].built_custom.schemedit.cabin == 1)
	assert(not (records[1].built and records[1].built.cabin))

	-- A directory with nothing to build says so, and does not fall back on stock buildings.
	entity = hired()
	files = {}
	builder.set_source(BENCH_POS, CATALOG.SCHEMEDIT)
	advance(entity, 6)
	assert(builder.load_project(BENCH_POS) == nil)
	report = builder.report(entity)
	assert(report.state == "choosing" and report.no_projects)

	-- Unknown nodes keep a schematic from being picked.
	add("alien", function()
		return {size = {x = 1, y = 1, z = 1}, data = {{name = "nope:gone", prob = 254, param2 = 0}}}
	end)
	advance(entity, 6)
	assert(builder.load_project(BENCH_POS) == nil and builder.report(entity).no_projects)

	-- Back to stock, and the note goes.
	builder.set_source(BENCH_POS, "nonsense")
	assert(builder.source_of(BENCH_POS) == nil)
	advance(entity, 6)
	assert(builder.load_project(BENCH_POS).building == "hut" and not builder.report(entity).no_projects)

	-- A project already building is finished first: only one not started gives way.
	add("cabin", cabin)
	project = builder.load_project(BENCH_POS)
	project.state = "building"
	world.meta(BENCH_POS).fields.villages_project = core.serialize(project)
	builder.set_source(BENCH_POS, CATALOG.SCHEMEDIT)
	assert(builder.load_project(BENCH_POS).state == "building")

	-- What the bench's window reads: the stock mix, with no weights, and what is next.
	do
		local stock_options = builder.options(BENCH_POS, "stock")
		assert(#stock_options.rows >= 1 and stock_options.directory == nil)
		local hut_row = stock_options.rows[1]
		assert(hut_row.name == "hut" and hut_row.share == 1 and hut_row.is_next and hut_row.weight == nil)
		assert(hut_row.size.x == 5 and hut_row.blocks > 0)
		assert(hut_row.materials[1].item == COBBLE and hut_row.materials[1].count > 1, "what it is mostly made of")

		-- A directory's, with what was built and why one cannot be.
		records[1] = records[1] or {center = BENCH_POS}
		records[1].built_custom = {schemedit = {cabin = 2}, folder = {cabin = 9}}
		local listed = builder.options(BENCH_POS, CATALOG.SCHEMEDIT)
		assert(listed.directory == DIR and listed.manifest_problem == nil)
		local by_name = {}
		for _, row in ipairs(listed.rows) do by_name[row.name] = row end
		assert(by_name.cabin.is_next and by_name.cabin.weight == 1 and by_name.cabin.share == 1 and by_name.cabin.built == 2)
		assert(by_name.cabin.size.x == 3 and by_name.cabin.materials[1].item)
		assert(by_name.alien.problem.code == "unknown_nodes" and not by_name.alien.is_next and by_name.alien.share == 0)
		assert(#builder.options(BENCH_POS, CATALOG.FOLDER).rows == 0)
	end

	-- A copy whose nodes have gone is dropped rather than built with holes.
	builder.set_source(BENCH_POS, nil)
	files[CATALOG.snapshot_path("halien")] = "alien"
	local stranded = {state = "finding_site", building = "alien", source = CATALOG.SCHEMEDIT, schem = "halien", seed = 1}
	world.meta(BENCH_POS).fields.villages_project = core.serialize(stranded)
	world.now = world.now + 100
	advance(entity, 6)
	local after = builder.load_project(BENCH_POS)
	assert(not after or after.building ~= "alien", "dropped")

	io.open = real_open
end

print("builder: ok")
