-- Run with: lua tests/builder_site.lua
-- Where a Builder may build: every rule a site has, the earthwork limits to the block, and
-- which site wins.
minetest = {get_modpath = function() return "." end, registered_nodes = {}, log = function() end}
local site_finder = dofile("builder_site.lua")

local GRASS, DIRT, STONE = "mcl_core:dirt_with_grass", "mcl_core:dirt", "mcl_core:stone"
local WATER, PATH, WOOD, LEAVES = "mcl_core:water_source", "mcl_core:grass_path", "mcl_core:wood", "mcl_core:leaves"
local CROP, SNOW = "mcl_farming:wheat_1", "mcl_core:snow"

local env = {
	is_open = function(name) return name == "air" or name == SNOW end,
	is_liquid = function(name) return name == WATER end,
	is_tree = function(name) return name == LEAVES end,
	is_structure = function(name) return name == WOOD end,
	is_track = function(name) return name == PATH end,
	is_solid = function(name) return name ~= CROP end,
	is_protected = function() return false end,
}

local function new_world(radius)
	local world = {nodes = {}, heights = {}, unloaded = {}}
	radius = radius or 45
	local function column(x, z) return x .. "," .. z end
	-- The top of the ground at a column, in dirt under grass.
	function world.height(x, z, y) world.heights[column(x, z)] = y end
	function world.set(x, y, z, name) world.nodes[x .. "," .. y .. "," .. z] = name end
	function world.snapshot()
		return {
			minp = {x = -radius, y = -12, z = -radius},
			maxp = {x = radius, y = 24, z = radius},
			name_at = function(x, y, z)
				if world.unloaded[column(x, z)] then return nil end
				if x < -radius or x > radius or z < -radius or z > radius or y < -12 or y > 24 then return nil end
				local set = world.nodes[x .. "," .. y .. "," .. z]
				if set then return set end
				local height = world.heights[column(x, z)] or 0
				if y > height then return "air" end
				return y == height and GRASS or DIRT
			end,
		}
	end
	return world
end

local function request(fields)
	local result = {
		height = 4, limit = 12, gap = 20, margin = 3, ring = 2, ring_step = 1,
		size = {x = 7, z = 7}, range = 40, bench = {x = 0, y = 0, z = 0}, center = {x = 0, y = 0, z = 0},
	}
	for field, value in pairs(fields or {}) do result[field] = value end
	return result
end

-- A building to be near, away from the 7 by 7 site tried at 0,0.
local function with_neighbour(world)
	world.set(15, 1, 3, WOOD)
	return world
end

local function evaluate(world, fields)
	local survey = site_finder.survey(world.snapshot(), env)
	return site_finder.evaluate(survey, 0, 0, 7, 7, request(fields))
end

-- Level ground beside a building is a site that wants nothing done to it.
do
	local site = assert(evaluate(with_neighbour(new_world())))
	assert(site.floor == 0 and site.blocks == 0 and site.ground == GRASS)
	assert(#site.earthwork.cuts == 0 and #site.earthwork.fills == 0)
	-- Snow and the like are built over.
	local world = with_neighbour(new_world())
	world.set(3, 1, 3, SNOW)
	assert(evaluate(world), "snow is open")
end

-- Near a building, but not on top of one.
do
	local _, why = evaluate(new_world())
	assert(why == "too_far", why)
	local world = new_world()
	world.set(27, 1, 3, WOOD) -- 21 from the footprint's edge at 6
	_, why = evaluate(world)
	assert(why == "too_far", why)
	world = new_world()
	world.set(26, 1, 3, WOOD) -- 20
	assert(evaluate(world), "exactly the gap")

	world = new_world()
	world.set(9, 1, 3, WOOD) -- 3
	_, why = evaluate(world)
	assert(why == "too_close", why)
	world = new_world()
	world.set(10, 1, 3, WOOD) -- 4
	assert(evaluate(world), "just past the margin")

	world = with_neighbour(new_world())
	world.set(3, 1, 3, WOOD)
	_, why = evaluate(world)
	assert(why == "footprint", why)
end

-- What the footprint may not stand on.
do
	for _, name in ipairs({WATER, PATH, LEAVES, CROP}) do
		local world = with_neighbour(new_world())
		world.set(3, name == CROP and 1 or 0, 3, name)
		local _, why = evaluate(world)
		assert(why == "footprint", name .. ": " .. tostring(why))
	end
	local world = with_neighbour(new_world())
	world.unloaded["3,3"] = true
	local _, why = evaluate(world)
	assert(why == "footprint", why)
	-- Something overhead counts for the column: a tree over it.
	world = with_neighbour(new_world())
	world.set(3, 3, 3, LEAVES)
	_, why = evaluate(world)
	assert(why == "footprint", why)
end

-- Earthwork: 12 of either is allowed, 13 is not, and each is counted alone.
do
	local function raise(world, count, height)
		local placed = 0
		for z = 0, 6 do
			for x = 0, 6 do
				if placed < count then
					world.height(x, z, height)
					placed = placed + 1
				end
			end
		end
		return world
	end
	local site = assert(evaluate(raise(with_neighbour(new_world()), 12, 1)))
	assert(site.floor == 0 and #site.earthwork.cuts == 12 and #site.earthwork.fills == 0 and site.blocks == 12)
	assert(site.earthwork.cuts[1].y == 1, "the bump goes, down to the floor")
	local _, why = evaluate(raise(with_neighbour(new_world()), 13, 1))
	assert(why == "uneven", why)

	site = assert(evaluate(raise(with_neighbour(new_world()), 12, -1)))
	assert(site.floor == 0 and #site.earthwork.fills == 12 and #site.earthwork.cuts == 0)
	assert(site.earthwork.fills[1].y == 0, "the dip is filled up to the floor")
	_, why = evaluate(raise(with_neighbour(new_world()), 13, -1))
	assert(why == "uneven", why)

	-- One deep hole counts each block, so it can use up the allowance by itself.
	local world = with_neighbour(new_world())
	world.height(3, 3, -12)
	site = assert(evaluate(world))
	assert(#site.earthwork.fills == 12)
	world = with_neighbour(new_world())
	world.height(3, 3, -13)
	-- Below the snapshot: a column with no ground known.
	world.set(3, -12, 3, "air")
	_, why = evaluate(world)
	assert(why == "footprint" or why == "uneven", why)

	-- A setting of 0 asks for level ground.
	_, why = evaluate(raise(with_neighbour(new_world()), 1, 1), {limit = 0})
	assert(why == "uneven", why)

	-- Both at once, within each limit: the floor is the one that changes least.
	world = with_neighbour(new_world())
	raise(world, 3, 1)
	world.height(6, 6, -1)
	site = assert(evaluate(world))
	assert(site.floor == 0 and #site.earthwork.cuts == 3 and #site.earthwork.fills == 1)
	-- More of the footprint high than low: the floor rises to meet it.
	world = with_neighbour(new_world())
	for z = 0, 6 do
		for x = 0, 6 do world.height(x, z, 1) end
	end
	for x = 0, 6 do
		for z = -2, 8 do
			if z < 0 or z > 6 then world.height(x, z, 1) end
		end
	end
	world.height(3, 3, 0)
	site = assert(evaluate(world))
	assert(site.floor == 1 and #site.earthwork.fills == 1 and #site.earthwork.cuts == 0)
end

-- Only dirt may be dug, and never beside water, which would run into the hole.
do
	local world = with_neighbour(new_world())
	world.height(3, 3, 1)
	world.set(3, 1, 3, STONE)
	local _, why = evaluate(world)
	assert(why == "not_dirt", why)

	world = with_neighbour(new_world())
	world.height(3, 3, 1)
	world.set(3, 1, 4, WATER)
	_, why = evaluate(world)
	assert(why == "footprint", why) -- standing water shows from the top, too

	world = with_neighbour(new_world())
	world.height(3, 3, 2)
	world.height(3, 4, 2)
	world.set(3, 1, 4, WATER) -- buried in the neighbouring column
	_, why = evaluate(world)
	assert(why == "beside_water", why)
end

-- The Builder's ring stays as it is: it must be walkable, and close to the floor.
do
	local world = with_neighbour(new_world())
	world.height(-1, 3, 2)
	local _, why = evaluate(world)
	assert(why == "ring", why)
	world = with_neighbour(new_world())
	world.height(-2, 3, -2)
	_, why = evaluate(world)
	assert(why == "ring", why)
	world = with_neighbour(new_world())
	world.height(-1, 3, 1)
	world.height(8, 3, -1)
	assert(evaluate(world), "a step either way is walkable")
	world = with_neighbour(new_world())
	world.set(-1, 0, 3, PATH)
	assert(evaluate(world), "a path round it is the best thing to work from")
	world = with_neighbour(new_world())
	world.set(-1, 0, 3, WATER)
	_, why = evaluate(world)
	assert(why == "ring", why)
	world = with_neighbour(new_world())
	world.height(-3, 3, 5)
	assert(evaluate(world), "past the ring is no concern of this")
end

-- Headroom, others' land and others' projects.
do
	local _, why = evaluate(with_neighbour(new_world()), {height = 25})
	assert(why == "too_high", why)

	local asked
	local protected = setmetatable({is_protected = function(minp, maxp)
		asked = {minp = minp, maxp = maxp}
		return true
	end}, {__index = env})
	local survey = site_finder.survey(with_neighbour(new_world()).snapshot(), protected)
	_, why = site_finder.evaluate(survey, 0, 0, 7, 7, request())
	assert(why == "protected", why)
	assert(asked.minp.x == 0 and asked.maxp.x == 6 and asked.maxp.y == 4 and asked.minp.y == -12)

	_, why = evaluate(with_neighbour(new_world()), {reserved = {{x0 = 9, z0 = 0, x1 = 12, z1 = 6}}})
	assert(why == "reserved", why)
	assert(evaluate(with_neighbour(new_world()), {reserved = {{x0 = 10, z0 = 0, x1 = 12, z1 = 6}}}))
end

-- The search: nearest level site, with a site that wants earthwork only as a last resort.
do
	local world = new_world()
	world.set(0, 1, 0, WOOD)
	local calls = 0
	local survey = site_finder.survey(world.snapshot(), env, function() calls = calls + 1 end)
	local site = assert(site_finder.search(survey, request({range = 30}), function() calls = calls + 1 end))
	assert(site.blocks == 0 and calls > 32, "it pauses while it reads and while it looks")
	local middle = {x = site.x + 3, z = site.z + 3}
	assert(math.abs(middle.x) + math.abs(middle.z) <= 12, "right beside the building it found")
	assert(site.rotat == "0" or site.rotat == "90" or site.rotat == "180" or site.rotat == "270")

	-- A closer bumpy site loses to a further level one.
	world = new_world()
	world.set(0, 1, 0, WOOD)
	for z = -12, 12 do
		for x = -12, 12 do
			if (x + z) % 7 == 0 and math.abs(x) > 0 then world.height(x, z, 1) end
		end
	end
	survey = site_finder.survey(world.snapshot(), env)
	site = assert(site_finder.search(survey, request({range = 30})))
	assert(site.blocks == 0, "level beats near")
	assert(math.abs(site.x + 3) > 12 or math.abs(site.z + 3) > 12)

	-- With nothing level, the least earthwork is what it takes.
	world = new_world()
	world.set(0, 1, 0, WOOD)
	for z = -45, 45 do
		for x = -45, 45 do
			if (x * 3 + z) % 9 == 0 and not (x == 0 and z == 0) then world.height(x, z, 1) end
		end
	end
	survey = site_finder.survey(world.snapshot(), env)
	site = site_finder.search(survey, request({range = 30}))
	assert(site and site.blocks > 0 and site.blocks <= 12, "almost level will do")

	-- Nothing at all, and the report says what stopped it.
	world = new_world()
	local found, report = site_finder.search(site_finder.survey(world.snapshot(), env), request({range = 20}))
	assert(found == nil and report.too_far > 0)
end

-- All of it stays in range: vanilla takes the job away from a villager far from its bench.
do
	local world = new_world()
	world.set(0, 1, 0, WOOD)
	-- Only the far ends of the map are free.
	for z = -45, 45 do
		for x = -45, 45 do
			if x * x + z * z < 25 * 25 and not (x == 0 and z == 0) then world.set(x, 0, z, WATER) end
		end
	end
	local survey = site_finder.survey(world.snapshot(), env)
	assert(site_finder.search(survey, request({range = 24, gap = 40})) == nil)
	local site = assert(site_finder.search(survey, request({range = 40, gap = 40})))
	for _, corner in ipairs({{site.x, site.z}, {site.x + 6, site.z}, {site.x, site.z + 6}, {site.x + 6, site.z + 6}}) do
		assert(corner[1] ^ 2 + corner[2] ^ 2 <= 40 ^ 2)
	end
end

-- A long building fits a slot one way round, and says which.
do
	local world = new_world()
	world.set(0, 1, 0, WOOD)
	for z = -45, 45 do
		for x = -45, 45 do
			local in_slot = x >= 5 and x <= 19 and z >= 10 and z <= 20
			if not in_slot and not (x == 0 and z == 0) then world.set(x, 0, z, WATER) end
		end
	end
	-- The slot is 15 by 11. With 2 cells of ring, 11 by 3 fits lying along x and not along z.
	local survey = site_finder.survey(world.snapshot(), env)
	local wide = assert(site_finder.search(survey, request({size = {x = 11, z = 3}, gap = 40})))
	assert(wide.rotat == "0" or wide.rotat == "180", wide.rotat)
	local tall = assert(site_finder.search(survey, request({size = {x = 3, z = 11}, gap = 40})))
	assert(tall.rotat == "90" or tall.rotat == "270", tall.rotat)
end

-- A square building takes each candidate once, and one read of a site agrees with the search.
do
	local world = new_world()
	world.set(0, 1, 0, WOOD)
	local survey = site_finder.survey(world.snapshot(), env)
	local request_fields = request({range = 30})
	local site = assert(site_finder.search(survey, request_fields))
	local again = assert(site_finder.evaluate(survey, site.x, site.z, 7, 7, request_fields))
	assert(again.floor == site.floor and again.blocks == site.blocks)
	local config = site_finder.config
	local area = site_finder.area_of_site({x = 0, y = 0, z = 0}, site.x, site.z, 7, 7, config)
	assert(area.minp.x == site.x - config.gap - 1 and area.maxp.z == site.z + 6 + config.gap + 1)
	local whole = site_finder.area({x = 0, y = 0, z = 0}, config)
	assert(whole.minp.x == -(config.range + config.gap + 1) and whole.maxp.y == config.above)
end

-- The snapshot over a VoxelManip: names by position, and nil where nothing is loaded.
do
	local names = {[1] = "air", [2] = STONE, [127] = "ignore"}
	local data = {}
	for i = 1, 27 do data[i] = 1 end
	data[1 + 1 * 3 + 2 * 9 + 1] = 2 -- x 1, y 1, z 2 of the 3-cube at the origin
	data[1] = 127
	local engine = {
		CONTENT_IGNORE = 127,
		get_name_from_content_id = function(id) return names[id] end,
		get_voxel_manip = function()
			return {
				read_from_map = function() return {x = 0, y = 0, z = 0}, {x = 2, y = 2, z = 2} end,
				get_data = function() return data end,
			}
		end,
	}
	local snapshot = site_finder.snapshot({minp = {x = 0, y = 0, z = 0}, maxp = {x = 2, y = 2, z = 2}}, engine)
	assert(snapshot.name_at(1, 1, 2) == STONE and snapshot.name_at(2, 2, 2) == "air")
	assert(snapshot.name_at(0, 0, 0) == nil, "unloaded")
	assert(snapshot.name_at(3, 0, 0) == nil and snapshot.name_at(0, -1, 0) == nil, "outside what was read")
end

print("builder_site: ok")
