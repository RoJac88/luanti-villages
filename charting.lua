-- Charting (ticket 38a, docs/villager-economy-design.md): finds the ocean temples and
-- woodland cabins a cartographer's explorer maps lead to.
--
-- VoxeLibre places both as engine decorations that keep a spot only if the real terrain
-- passes, so neither can be listed from the seed as Minecraft lists its structures. A
-- structure is known once its land is generated, and so:
-- * Seen sites. mcl_structures.place_structure is looked up on its table at each call, so a
--   wrapper sees every placement, whoever generated the land. Each is logged.
-- * Charts. A village (its village_index record) with a cartographer at tier 3 charts ocean
--   temples, at tier 4 woodland cabins. A chart walks the chunks around the village, nearest
--   first, out to the kind's radius, until it holds MAX_SITES. Each chunk is classified by
--   noise alone (a Lua copy of mapgen v7's terrain height, and core.get_biome_data at that
--   height); only likely ones are generated, one at a time, with a pause between, and the
--   wrapper catches what is placed. A chart never places a structure itself.
-- * Old land. A chunk generated before the mod was installed comes back from disk and fires
--   nothing, so it is scanned for nodes only that structure has.
-- Measured on two seeds (2026-11-21): about 1 ocean chunk in 45 holds a temple, 1
-- RoofedForest chunk in 17 a cabin; 84% and 92% of chunks classified were what they seemed.
local core = minetest
local M = {}

M.KINDS = {
	ocean_temple = {
		label = "ocean temple", radius = 3000, tier = 3,
		-- 589 to 600 of these in either schematic, and no other structure has them.
		signature = {nodes = {"mcl_ocean:prismarine", "mcl_ocean:prismarine_brick"}, min = 150},
	},
	woodland_cabin = {
		label = "woodland cabin", radius = 6000, tier = 4,
		-- The cabin has 48 cobbled deepslate, the outpost 310 stripped dark oak, and each one
		-- wither skeleton head (the parrot's perch): the head tells it from a player's build.
		signature = {nodes = {"mcl_deepslate:deepslate_cobbled", "mcl_core:stripped_dark_oak"}, min = 24,
			marker = "mcl_heads:wither_skeleton"},
	},
}
M.ORDER = {"ocean_temple", "woodland_cabin"}
M.MAX_SITES = 3
-- One structure seen twice (generated, then scanned) is one site.
M.SAME_SITE = 48
-- Signature nodes within this of each other are one structure.
M.CLUSTER = 24
-- Samples a side per chunk; a chunk is deep ocean if OCEAN_SHARE of them lie below sea
-- level - OCEAN_DEPTH, RoofedForest if FOREST_SHARE are that biome on land.
M.SAMPLES = 4
M.OCEAN_SHARE, M.OCEAN_DEPTH = 12, 6
M.FOREST_SHARE = 8
-- Chunks classified a step, at most.
M.SLICE = 100
-- What is generated of a chunk (the ground and the structures on it), and what is scanned.
M.GEN_Y = {-32, 47}
M.SCAN_Y = {-32, 79}

local function key(pos)
	return math.floor(pos.x) .. "," .. math.floor(pos.y) .. "," .. math.floor(pos.z)
end
M.key = key

local function flat_distance(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end
M.flat_distance = flat_distance

-- Mapchunks are aligned so that block (0,0,0) sits in the middle of one (village_index.lua).
function M.chunk_geometry(chunksize)
	local size = 16 * (chunksize or 5)
	return size, 16 * math.floor((chunksize or 5) / 2)
end

function M.chunk_of(x, z, size, offset)
	return math.floor((x + offset) / size), math.floor((z + offset) / size)
end

function M.chunk_min(cx, cz, size, offset)
	return cx * size - offset, cz * size - offset
end

-- Chunk offsets {dx, dz} within r chunks, nearest first (ties by dx, then dz), so a chart's
-- cursor means the same after a restart.
local offset_cache = {}
function M.offsets(r)
	if offset_cache[r] then return offset_cache[r] end
	local list = {}
	for dx = -r, r do
		for dz = -r, r do
			local d = dx * dx + dz * dz
			if d <= r * r then list[#list + 1] = {dx, dz, d} end
		end
	end
	table.sort(list, function(a, b)
		if a[3] ~= b[3] then return a[3] < b[3] end
		if a[1] ~= b[1] then return a[1] < b[1] end
		return a[2] < b[2]
	end)
	offset_cache[r] = list
	return list
end

function M.radius_chunks(kind, size)
	return math.ceil(M.KINDS[kind].radius / size)
end

-- MapgenV7::baseTerrainLevelAtPoint. `noise(name, x, z, persist)` is the 2D value of the
-- world's `mgv7_np_<name>` noise, with its persistence replaced when `persist` is given.
function M.base_level(noise, x, z)
	local hselect = math.max(0, math.min(1, noise("height_select", x, z)))
	local persist = noise("terrain_persist", x, z)
	local base = noise("terrain_base", x, z, persist)
	local alt = noise("terrain_alt", x, z, persist)
	if alt > base then return alt end
	return base * hselect + alt * (1 - hselect)
end

-- Whether chunk (cx, cz) is likely to hold `kind`'s land. env: size, offset, water_level,
-- level(x, z) (base_level) and biome(x, y, z) (a biome name or nil).
function M.likely(kind, cx, cz, env)
	local x0, z0 = M.chunk_min(cx, cz, env.size, env.offset)
	local step = env.size / M.SAMPLES
	local hits = 0
	for i = 0, M.SAMPLES - 1 do
		for j = 0, M.SAMPLES - 1 do
			local x, z = math.floor(x0 + (i + 0.5) * step), math.floor(z0 + (j + 0.5) * step)
			local h = env.level(x, z)
			if kind == "ocean_temple" then
				if h < env.water_level - M.OCEAN_DEPTH then hits = hits + 1 end
			elseif h > env.water_level + 1 and env.biome(x, math.floor(h), z) == "RoofedForest" then
				hits = hits + 1
			end
		end
	end
	return hits >= (kind == "ocean_temple" and M.OCEAN_SHARE or M.FOREST_SHARE)
end

-- Structures among signature nodes: clusters of `positions` (each joins the first cluster
-- whose first node is within CLUSTER), those of at least `min`, and with a marker within
-- CLUSTER of their centre when the signature has one. Returns their centres.
function M.clusters(signature, positions, markers)
	local groups = {}
	for _, p in ipairs(positions) do
		local joined
		for _, g in ipairs(groups) do
			if math.abs(p.x - g.first.x) <= M.CLUSTER and math.abs(p.z - g.first.z) <= M.CLUSTER
				and math.abs(p.y - g.first.y) <= M.CLUSTER then
				g.n, g.x, g.y, g.z = g.n + 1, g.x + p.x, g.y + p.y, g.z + p.z
				joined = true
				break
			end
		end
		if not joined then groups[#groups + 1] = {first = p, n = 1, x = p.x, y = p.y, z = p.z} end
	end
	local centres = {}
	for _, g in ipairs(groups) do
		if g.n >= signature.min then
			local c = {x = math.floor(g.x / g.n + 0.5), y = math.floor(g.y / g.n + 0.5), z = math.floor(g.z / g.n + 0.5)}
			local marked = not signature.marker
			for _, m in ipairs(markers or {}) do
				if vector.distance(m, c) <= M.CLUSTER then marked = true break end
			end
			if marked then centres[#centres + 1] = c end
		end
	end
	return centres
end

-- A chart: one village's search for one kind.
function M.new_chart(kind, center)
	return {kind = kind, center = {x = center.x, y = center.y, z = center.z}, cursor = 0, sites = {}, done = false}
end

function M.wants(chart)
	return not chart.done and #chart.sites < M.MAX_SITES
end

-- Adds a site the chart doesn't hold, within its radius, while it wants more. True if added.
function M.add_site(chart, pos)
	if #chart.sites >= M.MAX_SITES then return false end
	if flat_distance(pos, chart.center) > M.KINDS[chart.kind].radius then return false end
	for _, site in ipairs(chart.sites) do
		if vector.distance(site.pos, pos) <= M.SAME_SITE then return false end
	end
	chart.sites[#chart.sites + 1] = {pos = {x = pos.x, y = pos.y, z = pos.z}}
	table.sort(chart.sites, function(a, b) return flat_distance(a.pos, chart.center) < flat_distance(b.pos, chart.center) end)
	return true
end

-- The next chunk to generate: walks the cursor past unlikely chunks, at most `budget` of them.
-- Returns its index and chunk (the cursor stays before it until `passed`), or nil: out of
-- budget, or at the radius (the chart is then done).
function M.next_chunk(chart, env, budget)
	local list = M.offsets(M.radius_chunks(chart.kind, env.size))
	local ccx, ccz = M.chunk_of(chart.center.x, chart.center.z, env.size, env.offset)
	local i = chart.cursor
	for _ = 1, budget do
		i = i + 1
		local o = list[i]
		if not o then
			chart.cursor, chart.done = #list, true
			return nil
		end
		local cx, cz = ccx + o[1], ccz + o[2]
		if M.likely(chart.kind, cx, cz, env) then return i, cx, cz end
		chart.cursor = i
	end
	return nil
end

function M.passed(chart, index)
	if index > chart.cursor then chart.cursor = index end
end

-- How far the search has got: chunks passed of all within the radius.
function M.progress(chart, size)
	return chart.cursor, #M.offsets(M.radius_chunks(chart.kind, size))
end

-- A line for the chat command. `maps`: drawn maps by site key (ticket 38b).
function M.describe(chart, size, maps)
	local kind = M.KINDS[chart.kind]
	local passed, total = M.progress(chart, size)
	local sites = {}
	for _, site in ipairs(chart.sites) do
		sites[#sites + 1] = string.format("%s (%d away%s)", key(site.pos), flat_distance(site.pos, chart.center),
			maps and not maps[key(site.pos)] and ", not drawn yet" or "")
	end
	local state = chart.done and (#chart.sites == 0 and string.format("none within %d", kind.radius) or "done")
		or (#chart.sites >= M.MAX_SITES and "full" or string.format("searching, %d/%d chunks", passed, total))
	return string.format("%s: %s; %s", kind.label, #sites > 0 and table.concat(sites, ", ") or "no sites", state)
end

-- The engine side --------------------------------------------------------------------

-- env for likely() from the running world: mapgen v7's noises, or nil on another mapgen.
local function world_env(engine)
	if engine.get_mapgen_setting("mg_name") ~= "v7" then return nil end
	local size, offset = M.chunk_geometry(tonumber(engine.get_mapgen_setting("chunksize")))
	local params, fixed = {}, {}
	local function noise(name, x, z, persist)
		local np = params[name]
		if not np then
			np = engine.get_mapgen_setting_noiseparams("mgv7_np_" .. name)
			params[name] = np
		end
		if persist then
			local copy = {}
			for k, v in pairs(np) do copy[k] = v end
			copy.persistence, copy.persist = persist, persist
			return engine.get_perlin(copy):get_2d({x = x, y = z})
		end
		fixed[name] = fixed[name] or engine.get_perlin(np)
		return fixed[name]:get_2d({x = x, y = z})
	end
	return {
		size = size, offset = offset,
		water_level = tonumber(engine.get_mapgen_setting("water_level")) or 0,
		level = function(x, z) return M.base_level(noise, x, z) end,
		biome = function(x, y, z)
			local data = engine.get_biome_data({x = x, y = y, z = z})
			return data and engine.get_biome_name(data.biome)
		end,
	}
end
M.world_env = world_env

-- deps: village_index (read_village, update_village), storage, structures (mcl_structures),
-- engine (core), explorer_map (explorer_map.lua, by default).
function M.install(deps)
	local engine = deps.engine or core
	local structures = deps.structures
	local storage = deps.storage
	local villages = deps.village_index
	local maps_module = deps.explorer_map or dofile(core.get_modpath("living_villages") .. "/explorer_map.lua")
	if not structures or not structures.place_structure or not storage then return false end
	local mg = engine.get_mapgen_setting("mg_name")
	if mg == "singlenode" or mg == "flat" then return false end
	local kinds = {}
	for _, name in ipairs(M.ORDER) do
		if structures.registered_structures and structures.registered_structures[name]
			and not (structures.is_disabled and structures.is_disabled(name)) then
			kinds[name] = true
		end
	end
	local state = engine.deserialize(storage:get_string("charting")) or {}
	state.seen = state.seen or {}
	state.charts = state.charts or {}
	-- Drawn maps by site key (ticket 38b), and the number for the next one's id.
	state.maps = state.maps or {}
	state.map_seq = state.map_seq or 0
	local function save() storage:set_string("charting", engine.serialize(state)) end
	local env = world_env(engine)
	local size = env and env.size or M.chunk_geometry(tonumber(engine.get_mapgen_setting("chunksize")))

	local function offer(name, pos)
		for _, chart in pairs(state.charts) do
			if chart.kind == name and M.add_site(chart, pos) then
				engine.log("action", string.format("[living_villages] charted %s at %s for the village at %s",
					M.KINDS[name].label, key(pos), key(chart.center)))
			end
		end
	end

	local function note_seen(name, pos)
		for _, seen in ipairs(state.seen) do
			if seen.name == name and vector.distance(seen.pos, pos) <= M.SAME_SITE then return end
		end
		state.seen[#state.seen + 1] = {name = name, pos = {x = pos.x, y = pos.y, z = pos.z}}
		offer(name, pos)
		save()
	end

	local place = structures.place_structure
	structures.place_structure = function(pos, def, ...)
		local ok = place(pos, def, ...)
		if ok and def and kinds[def.name] then note_seen(def.name, pos) end
		return ok
	end

	-- The chart for a village, made (and the seen sites offered) at first need.
	local function chart_for(name, center)
		local id = name .. "@" .. key(center)
		local chart = state.charts[id]
		if not chart then
			chart = M.new_chart(name, center)
			-- Other mapgens chart only from seen sites: nothing to classify by.
			if not env then chart.done = true end
			state.charts[id] = chart
			for _, seen in ipairs(state.seen) do
				if seen.name == name then M.add_site(chart, seen.pos) end
			end
			engine.log("action", string.format("[living_villages] charting %ss around %s",
				M.KINDS[name].label, key(center)))
			save()
		end
		return chart
	end

	-- Cartographers start their village's charts.
	local VILLAGE_RADIUS = 160
	local function enlist()
		for _, entity in pairs(engine.luaentities or {}) do
			if entity.name == "mobs_mc:villager" and entity._profession == "cartographer" and not entity.child
				and entity.object then
				local pos = entity.object:get_pos()
				local tier = entity._max_trade_tier or 1
				if pos then
					for _, name in ipairs(M.ORDER) do
						if kinds[name] and tier >= M.KINDS[name].tier then
							local village = villages.read_village(pos, VILLAGE_RADIUS)
								or villages.update_village(vector.round(pos), VILLAGE_RADIUS, function() end)
							chart_for(name, village.center)
						end
					end
				end
			end
		end
	end

	local function scan(name, minp, maxp)
		local signature = M.KINDS[name].signature
		local positions = engine.find_nodes_in_area(minp, maxp, signature.nodes)
		if #positions < signature.min then return end
		local markers = signature.marker and engine.find_nodes_in_area(minp, maxp, {signature.marker}) or nil
		for _, centre in ipairs(M.clusters(signature, positions, markers)) do note_seen(name, centre) end
	end

	local PAUSE = tonumber(engine.settings:get("living_villages_charting_pause")) or 2
	local busy, wait, enlist_wait = false, 0, 0
	local turn = 0
	-- A site with no map yet, nearest charts first: {kind, pos}, or nil. One that failed to
	-- draw waits for a restart.
	local draw_failed = {}
	local function undrawn()
		local ids = {}
		for id in pairs(state.charts) do ids[#ids + 1] = id end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local chart = state.charts[id]
			for _, site in ipairs(chart.sites) do
				local k = key(site.pos)
				if not state.maps[k] and not draw_failed[k] then return chart.kind, site.pos end
			end
		end
	end

	local function draw()
		local kind, pos = undrawn()
		if not kind then return false end
		busy = true
		state.map_seq = state.map_seq + 1
		local k = key(pos)
		maps_module.draw(engine, kind, pos, state.map_seq, function(info)
			if info then
				state.maps[k] = info
				engine.log("action", string.format("[living_villages] drew the %s map of %s as %s",
					M.KINDS[kind].label, k, info.id))
			else
				draw_failed[k] = true
				engine.log("warning", "[living_villages] couldn't generate the land to draw the map of " .. k)
			end
			save()
			busy, wait = false, PAUSE
		end)
		return true
	end

	local function work()
		-- Maps first: a site found is sold only once drawn.
		if draw() then return end
		if not env then return end
		local ids = {}
		for id, chart in pairs(state.charts) do
			if M.wants(chart) then ids[#ids + 1] = id end
		end
		if #ids == 0 then return end
		table.sort(ids)
		turn = turn % #ids + 1
		local chart = state.charts[ids[turn]]
		local index, cx, cz = M.next_chunk(chart, env, M.SLICE)
		if not index then
			if chart.done then
				engine.log("action", "[living_villages] charting finished: " .. M.describe(chart, size))
			end
			save()
			return
		end
		busy = true
		local x0, z0 = M.chunk_min(cx, cz, env.size, env.offset)
		local minp = {x = x0, y = M.GEN_Y[1], z = z0}
		local maxp = {x = x0 + env.size - 1, y = M.GEN_Y[2], z = z0 + env.size - 1}
		local generated, failed = false, false
		engine.emerge_area(minp, maxp, function(_, action, remaining)
			if action == engine.EMERGE_GENERATED then generated = true end
			if action == engine.EMERGE_CANCELLED or action == engine.EMERGE_ERRORED then failed = true end
			if remaining > 0 then return end
			local function finish()
				if not failed then M.passed(chart, index) end
				save()
				busy, wait = false, PAUSE
			end
			if generated or failed then return finish() end
			-- Old land: load the rest of its height and scan it.
			local smin = {x = minp.x, y = M.SCAN_Y[1], z = minp.z}
			local smax = {x = maxp.x, y = M.SCAN_Y[2], z = maxp.z}
			engine.emerge_area(smin, smax, function(_, _, left)
				if left > 0 then return end
				scan(chart.kind, smin, smax)
				finish()
			end)
		end)
	end

	engine.register_globalstep(function(dtime)
		enlist_wait = enlist_wait - dtime
		if enlist_wait <= 0 then
			enlist_wait = 30
			enlist()
		end
		if busy then return end
		wait = wait - dtime
		if wait > 0 then return end
		wait = 0.5
		work()
	end)

	engine.register_chatcommand("living_villages_charts", {
		params = "[start [<x>,<z>] | give]",
		description = "List each village's explorer map charts: sites found and how far each search has got"
			.. " (\"start\": chart both kinds around you, or x,z, as a tier 4 cartographer would;"
			.. " \"give\": every drawn map of the village nearest you)",
		privs = {debug = true},
		func = function(name, param)
			local verb, where = (param or ""):match("^%s*(%S*)%s*(.-)%s*$")
			if verb == "start" then
				local x, z = where:match("^(%-?%d+)%s*,%s*(%-?%d+)$")
				local center
				if x then
					center = {x = tonumber(x), y = 0, z = tonumber(z)}
				else
					local player = engine.get_player_by_name and engine.get_player_by_name(name)
					if not player then return false, "Give x,z, or run it in game." end
					center = vector.round(player:get_pos())
				end
				local started = {}
				for _, kind in ipairs(M.ORDER) do
					if kinds[kind] then
						chart_for(kind, center)
						started[#started + 1] = M.KINDS[kind].label .. "s"
					end
				end
				if #started == 0 then return false, "Neither structure is enabled." end
				return true, string.format("Charting %s around %s.", table.concat(started, " and "), key(center))
			elseif verb == "give" then
				local player = engine.get_player_by_name and engine.get_player_by_name(name)
				if not player then return false, "Run it in game." end
				local pos = player:get_pos()
				local best
				for _, chart in pairs(state.charts) do
					local d = flat_distance(chart.center, pos)
					if not best or d < best then best = d end
				end
				if not best then return false, "No charts yet." end
				local given = 0
				for _, chart in pairs(state.charts) do
					if flat_distance(chart.center, pos) == best then
						for _, site in ipairs(chart.sites) do
							local info = state.maps[key(site.pos)]
							if info then
								local stack = maps_module.item(ItemStack, info, engine.pos_to_string, engine.colorize)
								local left = player:get_inventory():add_item("main", stack)
								if left:is_empty() then given = given + 1 end
							end
						end
					end
				end
				return true, string.format("Gave %d explorer map(s).", given)
			elseif verb ~= "" then
				return false, "Unknown option: " .. verb
			end
			local ids = {}
			for id in pairs(state.charts) do ids[#ids + 1] = id end
			if #ids == 0 then return true, "No charts yet: a village starts one when its cartographer reaches tier 3." end
			table.sort(ids)
			local lines = {}
			for _, id in ipairs(ids) do
				local chart = state.charts[id]
				lines[#lines + 1] = string.format("Village at %s, %s", key(chart.center), M.describe(chart, size, state.maps))
			end
			lines[#lines + 1] = string.format("%d structure(s) seen in all.", #state.seen)
			return true, table.concat(lines, "\n")
		end,
	})

	M.state = state
	return true
end

return M
