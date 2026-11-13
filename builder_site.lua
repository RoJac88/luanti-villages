-- Where a Builder puts a building: on ground that fits it as it stands, or nearly. A site
-- may take a small earthwork, at most `limit` dirt blocks broken and `limit` placed, so
-- ground that is almost level still counts; anything more is the player's to clear.
--
-- One read of the map (`snapshot`) answers every candidate, looking only from the top of
-- each column down to its first node that is not open. So everything above a column's
-- ground is open by construction, and a tree or a roof is what the column reports. The
-- planning is plain functions of that snapshot and an `env` of node tests, so tests can
-- stub the engine.
--
-- "Close to the village" is read from the map too, as any structure within `gap` of the
-- footprint. That covers a village with no record, and a building a player has since put
-- up or taken down.
local core = minetest
local materials = dofile(core.get_modpath("living_villages") .. "/builder_materials.lua")

local M = {}

M.config = {
	limit = 12, -- dirt blocks broken, and placed, for one site
	ring = 2, -- cells round the footprint a Builder walks and works from
	-- How far it places a block from: from the ring's outer row for a low block, and for a high
	-- one from scaffolding level with it (scaffold_height), so only across. A block it cannot
	-- reach leaves it stuck for good, so this bounds how wide a building may be.
	reach = 15,
	scaffold_height = 5, -- a block this far above the floor or less is placed from the ground
	ring_step = 1, -- how far that ground may be off the floor
	margin = 3, -- a site stays this far from a structure
	gap = 20, -- and this close to one
	range = 80, -- from the bench: vanilla gives up a jobsite left 100 behind
	-- How far from the bench the ground may lie, and the map is read: room above for the tallest
	-- building (builder_catalog.lua's MAX_HEIGHT) on ground a little above the bench.
	below = 12, above = 40,
}

-- Reads the area once. name_at(x, y, z) is the node there, or nil if it is unloaded or
-- outside the area.
function M.snapshot(area, engine)
	engine = engine or core
	local vm = engine.get_voxel_manip()
	local emin, emax = vm:read_from_map(area.minp, area.maxp)
	local data = vm:get_data()
	local nx, ny = emax.x - emin.x + 1, emax.y - emin.y + 1
	local names, ignore = {}, engine.CONTENT_IGNORE
	local minp, maxp = area.minp, area.maxp
	return {
		minp = minp,
		maxp = maxp,
		name_at = function(x, y, z)
			if x < minp.x or x > maxp.x or y < minp.y or y > maxp.y or z < minp.z or z > maxp.z then return nil end
			local id = data[(z - emin.z) * ny * nx + (y - emin.y) * nx + (x - emin.x) + 1]
			if id == ignore then return nil end
			local name = names[id]
			if not name then
				name = engine.get_name_from_content_id(id)
				names[id] = name
			end
			return name
		end,
	}
end

-- The node tests on the real engine: is_open, is_liquid, is_tree, is_structure, is_track,
-- is_solid, is_protected. A track is ground a Builder may walk but not build on: a path or
-- a field. What is not solid (a crop, a rail) is no ground to stand on at all.
function M.live_env(engine)
	engine = engine or core
	local fragments = dofile(engine.get_modpath("living_villages") .. "/village_fragments.lua")
	local structure = fragments.structure_test(engine)
	local function def_of(name) return engine.registered_nodes[name] end
	local function is_liquid(name)
		local def = def_of(name)
		return def ~= nil and (def.liquidtype or "none") ~= "none"
	end
	return {
		is_liquid = is_liquid,
		is_open = function(name)
			if name == "air" then return true end
			local def = def_of(name)
			return def ~= nil and def.buildable_to == true and not is_liquid(name)
		end,
		is_tree = function(name)
			local groups = (def_of(name) or {}).groups or {}
			return (groups.tree or 0) > 0 or (groups.leaves or 0) > 0 or name:find("leaves", 1, true) ~= nil
		end,
		is_structure = structure,
		is_track = function(name)
			return name == "mcl_core:grass_path" or name:find("^mcl_farming:soil") ~= nil
		end,
		is_solid = function(name)
			local def = def_of(name)
			return def ~= nil and def.walkable ~= false
		end,
		is_protected = function(minp, maxp)
			return engine.is_area_protected ~= nil and engine.is_area_protected(minp, maxp, "", 3) ~= false
		end,
	}
end

-- What stands in a column: {y, name, kind}, kind being ground, track, liquid, tree,
-- structure, obstacle, or unloaded (with no y) if the way down is not known or nothing
-- was found.
local function new_columns(snapshot, env)
	local columns = {}
	local top = snapshot.maxp.y
	local name_at = snapshot.name_at
	return function(x, z)
		local row = columns[z]
		if not row then
			row = {}
			columns[z] = row
		end
		local column = row[x]
		if column then return column end
		column = {kind = "unloaded"}
		for y = top, snapshot.minp.y, -1 do
			local name = name_at(x, y, z)
			if not name then break end
			if not env.is_open(name) then
				local kind = "ground"
				if env.is_liquid(name) then kind = "liquid"
				elseif env.is_tree(name) then kind = "tree"
				elseif env.is_track(name) then kind = "track"
				elseif env.is_structure(name) then kind = "structure"
				elseif not env.is_solid(name) then kind = "obstacle" end
				column = {y = y, name = name, kind = kind}
				break
			end
		end
		row[x] = column
		return column
	end
end

-- Whether any cell a cut would empty touches a liquid, or an unknown node.
local function touches_liquid(snapshot, env, x, y, z)
	for _, offset in ipairs({{1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}, {0, 1, 0}, {0, -1, 0}}) do
		local name = snapshot.name_at(x + offset[1], y + offset[2], z + offset[3])
		if not name or env.is_liquid(name) then return true end
	end
	return false
end

-- The earthwork to bring a footprint to floor `f`, or nil and why it cannot be.
local function earthwork_to(f, box, columns, snapshot, env, limit)
	local cuts, fills = {}, {}
	for z = box.z0, box.z1 do
		for x = box.x0, box.x1 do
			local column = columns(x, z)
			for y = f + 1, column.y do
				if #cuts >= limit then return nil, "too_much_digging" end
				if not materials.is_dirt(snapshot.name_at(x, y, z) or "") then return nil, "not_dirt" end
				if touches_liquid(snapshot, env, x, y, z) then return nil, "beside_water" end
				cuts[#cuts + 1] = {x = x, y = y, z = z}
			end
			for y = column.y + 1, f do
				if #fills >= limit then return nil, "too_much_filling" end
				fills[#fills + 1] = {x = x, y = y, z = z}
			end
		end
	end
	return {cuts = cuts, fills = fills}
end

-- Whether a Builder can walk the ring round a footprint at floor `f`.
local function ring_stands(box, f, columns, config)
	local ring = config.ring
	for z = box.z0 - ring, box.z1 + ring do
		for x = box.x0 - ring, box.x1 + ring do
			if x < box.x0 or x > box.x1 or z < box.z0 or z > box.z1 then
				local column = columns(x, z)
				if (column.kind ~= "ground" and column.kind ~= "track")
						or math.abs(column.y - f) > config.ring_step then
					return false
				end
			end
		end
	end
	return true
end

-- A summed-area table over the snapshot's columns, so a count over any rectangle is four
-- lookups instead of a walk over it.
local function counter(snapshot, columns, kinds, checkpoint)
	local minp, maxp = snapshot.minp, snapshot.maxp
	local sums = {}
	local width = maxp.x - minp.x + 2
	local function index(x, z) return (z - minp.z + 1) * width + (x - minp.x + 1) end
	for z = minp.z - 1, maxp.z do
		if checkpoint then checkpoint() end
		for x = minp.x - 1, maxp.x do
			local value = 0
			if x >= minp.x and z >= minp.z then
				value = (kinds[columns(x, z).kind] and 1 or 0)
					+ sums[index(x - 1, z)] + sums[index(x, z - 1)] - sums[index(x - 1, z - 1)]
			end
			sums[index(x, z)] = value
		end
	end
	return function(x0, z0, x1, z1)
		x0, z0 = math.max(x0, minp.x), math.max(z0, minp.z)
		x1, z1 = math.min(x1, maxp.x), math.min(z1, maxp.z)
		if x0 > x1 or z0 > z1 then return 0 end
		return sums[index(x1, z1)] - sums[index(x0 - 1, z1)] - sums[index(x1, z0 - 1)] + sums[index(x0 - 1, z0 - 1)]
	end
end

local function overlaps_reserved(box, reserved, margin)
	for _, rect in ipairs(reserved or {}) do
		if box.x0 - margin <= rect.x1 and box.x1 + margin >= rect.x0
				and box.z0 - margin <= rect.z1 and box.z1 + margin >= rect.z0 then
			return true
		end
	end
	return false
end

-- The tools one snapshot gives, for evaluate() and search().
function M.survey(snapshot, env, checkpoint)
	local columns = new_columns(snapshot, env)
	return {
		snapshot = snapshot,
		env = env,
		columns = columns,
		-- What a footprint may not stand on, and what counts as the village.
		blocked = counter(snapshot, columns, {
			unloaded = true, liquid = true, tree = true, track = true, structure = true, obstacle = true,
		}, checkpoint),
		structures = counter(snapshot, columns, {structure = true}, checkpoint),
	}
end

-- A building of the given size with its minimum corner at x, z: the site, or nil and why
-- not. `request`: height (cells above the floor), limit, gap, margin, ring, ring_step,
-- reserved (rectangles {x0, z0, x1, z1} other Builders hold).
function M.evaluate(survey, x, z, width, depth, request)
	local config = request
	local box = {x0 = x, z0 = z, x1 = x + width - 1, z1 = z + depth - 1}
	local snapshot, env, columns = survey.snapshot, survey.env, survey.columns
	if survey.blocked(box.x0, box.z0, box.x1, box.z1) > 0 then return nil, "footprint" end
	local margin = config.margin
	if survey.structures(box.x0 - margin, box.z0 - margin, box.x1 + margin, box.z1 + margin) > 0 then
		return nil, "too_close"
	end
	if overlaps_reserved(box, config.reserved, margin) then return nil, "reserved" end
	local gap = config.gap
	if survey.structures(box.x0 - gap, box.z0 - gap, box.x1 + gap, box.z1 + gap) == 0 then return nil, "too_far" end

	local low, high
	for cz = box.z0, box.z1 do
		for cx = box.x0, box.x1 do
			local y = columns(cx, cz).y
			low = math.min(low or y, y)
			high = math.max(high or y, y)
		end
	end
	local limit = config.limit
	if high - low > 2 * limit then return nil, "uneven" end

	-- Each floor it could have, with what that costs, cheapest first; on a tie, the one
	-- that places less.
	local floors = {}
	for f = low, high do
		local cut, fill = 0, 0
		for cz = box.z0, box.z1 do
			for cx = box.x0, box.x1 do
				local y = columns(cx, cz).y
				if y > f then cut = cut + y - f else fill = fill + f - y end
			end
		end
		if cut <= limit and fill <= limit then floors[#floors + 1] = {f = f, cut = cut, fill = fill} end
	end
	if #floors == 0 then return nil, "uneven" end
	table.sort(floors, function(a, b)
		if a.cut + a.fill ~= b.cut + b.fill then return a.cut + a.fill < b.cut + b.fill end
		if a.fill ~= b.fill then return a.fill < b.fill end
		return a.f < b.f
	end)

	local why
	for _, candidate in ipairs(floors) do
		local f = candidate.f
		if f + config.height > snapshot.maxp.y then
			why = "too_high"
		elseif not ring_stands(box, f, columns, config) then
			why = "ring"
		else
			local earthwork, reason = earthwork_to(f, box, columns, snapshot, env, limit)
			if earthwork then
				local minp = {x = box.x0, y = f - limit, z = box.z0}
				local maxp = {x = box.x1, y = f + config.height, z = box.z1}
				if env.is_protected(minp, maxp) then return nil, "protected" end
				local middle = columns(math.floor((box.x0 + box.x1) / 2), math.floor((box.z0 + box.z1) / 2))
				return {
					x = x, z = z, floor = f,
					earthwork = earthwork, blocks = candidate.cut + candidate.fill,
					ground = middle.name,
				}
			end
			why = reason
		end
	end
	return nil, why
end

-- Candidates by distance from `center`, nearest first: one list per whole node of
-- distance, so the list needs no sort that a time-sliced search could not pause in.
local function by_distance(minx, maxx, minz, maxz, center, checkpoint)
	local rings, furthest = {}, 0
	for z = minz, maxz do
		if checkpoint then checkpoint() end
		for x = minx, maxx do
			local d = math.floor(math.sqrt((x - center.x) ^ 2 + (z - center.z) ^ 2))
			local ring = rings[d]
			if not ring then
				ring = {}
				rings[d] = ring
				furthest = math.max(furthest, d)
			end
			ring[#ring + 1] = {x = x, z = z}
		end
	end
	return rings, furthest
end

-- The best site for a building: least earthwork, then nearest to request.center, whose
-- range from request.bench is request.range, and no further than request.within (optional)
-- from request.center, nor nearer than request.keep_away.distance (optional) to any of its
-- spots. `request`, besides evaluate()'s fields: size
-- {x, z}. `checkpoint`, if given, lets the search pause (route_queue.lua). Returns the site
-- with its rotation, or nil, and a report of why candidates failed {reason = count}.
function M.search(survey, request, checkpoint)
	local width, depth = request.size.x, request.size.z
	local largest = math.max(width, depth)
	local bench, range = request.bench, request.range
	-- A building that must serve a part of the village (builder_needs.lua) goes no further
	-- than `within` from request.center, measured to the building's middle.
	local center, within = request.center, request.within
	if within then
		center = {x = center.x - math.floor(width / 2), z = center.z - math.floor(depth / 2)}
	end
	local rings, furthest = by_distance(bench.x - range, bench.x + range - largest + 1,
		bench.z - range, bench.z + range - largest + 1, center, checkpoint)
	if within then furthest = math.min(furthest, within) end
	-- A building kept apart from others of its kind (builder_needs.lua's SPREAD, a lamp).
	local keep_away = request.keep_away
	local function kept_away(x, z, w, l)
		if not keep_away then return true end
		local mx, mz = x + (w - 1) / 2, z + (l - 1) / 2
		local d2 = keep_away.distance * keep_away.distance
		for _, spot in ipairs(keep_away.spots) do
			if (spot.x - mx) ^ 2 + (spot.z - mz) ^ 2 < d2 then return false end
		end
		return true
	end
	-- Its far corner counts: vanilla gives up a jobsite it has walked too far from.
	local function in_range(x, z, w, l)
		local far_x = math.max(math.abs(x - bench.x), math.abs(x + w - 1 - bench.x))
		local far_z = math.max(math.abs(z - bench.z), math.abs(z + l - 1 - bench.z))
		return far_x * far_x + far_z * far_z <= range * range
	end
	local report = {}
	local best
	local count = 0
	for d = 0, furthest do
		for _, candidate in ipairs(rings[d] or {}) do
			count = count + 1
			if checkpoint and count % 32 == 0 then checkpoint() end
			-- Which way round is the position's choice, so a row of sites is not all one way.
			local turned = (candidate.x + candidate.z) % 2 == 1
			for _, sideways in ipairs({turned, not turned}) do
				local w, l = width, depth
				if sideways then w, l = depth, width end
				if (w ~= l or sideways == turned) and in_range(candidate.x, candidate.z, w, l)
					and kept_away(candidate.x, candidate.z, w, l) then
					local site, why = M.evaluate(survey, candidate.x, candidate.z, w, l, request)
					if site then
						if not best or site.blocks < best.blocks then
							local half = (candidate.x * 3 + candidate.z * 5) % 2 == 0
							if sideways then
								site.rotat = half and "90" or "270"
							else
								site.rotat = half and "0" or "180"
							end
							best = site
						end
						-- Nothing beats a level site, and none later is any nearer.
						if best.blocks == 0 then return best, report end
					else
						report[why] = (report[why] or 0) + 1
					end
				end
			end
		end
	end
	return best, report
end

-- The area search() needs a snapshot of.
function M.area(bench, config)
	local reach = config.range + math.max(config.gap, config.ring, config.margin) + 1
	return {
		minp = {x = bench.x - reach, y = bench.y - config.below, z = bench.z - reach},
		maxp = {x = bench.x + reach, y = bench.y + config.above, z = bench.z + reach},
	}
end

-- The much smaller area that evaluate() needs for one site: rechecking it is cheap.
function M.area_of_site(bench, x, z, width, depth, config)
	local reach = math.max(config.gap, config.ring, config.margin) + 1
	return {
		minp = {x = x - reach, y = bench.y - config.below, z = z - reach},
		maxp = {x = x + width - 1 + reach, y = bench.y + config.above, z = z + depth - 1 + reach},
	}
end

return M
