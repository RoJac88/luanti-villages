-- The Builder: a villager who claims a bench (builder_block.lua) and adds buildings to its
-- village, from materials the player leaves in chests near the bench. VoxeLibre cannot be
-- given a new profession (see keeper.lua), so this is a role on a vanilla mason, for the
-- outfit. It has no trades: `_trades` stays nil, and a right-click opens its status window
-- (builder_status.lua) in place of vanilla's handler. So it counts as untraded, and
-- vanilla's validate_jobsite makes it unemployed the moment its bench goes.
--
-- The project is kept in the bench's meta, not on the villager, so that whoever claims the
-- bench next carries on. What is built so far is not kept at all: building_template.lua
-- reads it from the world.
--
--   choosing -> finding_site <-> no_site
--                    |
--                    v
--            requires_materials <-> collecting <-> building
--                                        |             |
--                                     blocked <--------+
--                                                      v
--                                     returning -> choosing
--
-- Like a farmer, it works out of range of vanilla's commute: while it has work to do
-- activity_override answers for it, and its trips use the farm trip's fields, which
-- navigation.lua and the modules that leave a working villager alone already know.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local census = dofile(core.get_modpath("living_villages") .. "/village_census.lua")
local materials = dofile(core.get_modpath("living_villages") .. "/builder_materials.lua")
local site_finder = dofile(core.get_modpath("living_villages") .. "/builder_site.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local template = dofile(core.get_modpath("living_villages") .. "/building_template.lua")
local catalog = dofile(core.get_modpath("living_villages") .. "/builder_catalog.lua")

local M = {}

local BENCH = "living_villages:builder_block"
M.BENCH = BENCH
local PROFESSION = "mason"
local PROJECT = "villages_project"
-- Which schematics this bench builds from: catalog.SCHEMEDIT, catalog.FOLDER, or nothing
-- for the stock buildings, so that a bench from before this existed goes on as it did.
local SOURCE = "villages_source"

-- A villager whose bed is this near a free bench takes it at once, ahead of any other
-- job, since farm_jobs.lua would otherwise send it off to the nearest composter for good.
local OWNER_RADIUS = 12
local OWNER_HEIGHT = 4
local CLAIM_RADIUS = 48
local CLAIM_SECONDS = 10
local UNREACHABLE_SECONDS = 300
local TICK_SECONDS = 5
local WORK_TICK_SECONDS = 1
local MATERIALS_SECONDS = 10
local COMPARE_SECONDS = 10
local HOLD_SECONDS = 2
local CHEST_REACH = 3
local SKIP_SECONDS = 60
local DEFER_SECONDS = 10
-- Walks to a site before giving up on one it has never reached, and how long it then keeps away.
local SITE_ATTEMPTS = 5
local AVOID_SECONDS = 1800
local DEFAULT_CAPACITY = 256
local DEFAULT_BLOCK_SECONDS = 1
local SITE_RETRY_SECONDS = 60
local VILLAGE_RADIUS = 128
local DEFAULT_CHEST_RADIUS = 32
local BUY_DISTANCE = 10
local DEFAULT_SURFACE = "mcl_core:dirt_with_grass"

local navigation_api, village_index

-- Per villager, kept out of the save.
local sessions = setmetatable({}, {__mode = "k"})

local function session_of(self)
	local session = sessions[self]
	if not session then
		session = {next_at = 0, next_claim = 0, skip = {}, hold_until = 0}
		sessions[self] = session
	end
	return session
end

local function pos_key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function setting_number(name, default)
	return tonumber(core.settings and core.settings:get(name)) or default
end

local function chest_radius()
	return setting_number("living_villages_builder_chest_radius", DEFAULT_CHEST_RADIUS)
end

local function is_bench(pos)
	local node = pos and core.get_node_or_nil(pos)
	return node ~= nil and node.name == BENCH
end

local function is_free(pos)
	return is_bench(pos) and core.get_meta(pos):get_string("villager") == ""
end

function M.claimed_bench(self)
	local pos = self._jobsite
	return is_bench(pos) and core.get_meta(pos):get_string("villager") == self._id and pos or nil
end

local function eligible(self)
	return not self.child and self._id ~= nil and not self._jobsite and self._profession == "unemployed"
end

function M.employ(self, pos)
	if not is_free(pos) or not eligible(self) then return false end
	core.get_meta(pos):set_string("villager", self._id)
	self._jobsite = {x = pos.x, y = pos.y, z = pos.z}
	self._profession = PROFESSION
	self._villages_builder = true
	self._villages_farm_seek = nil
	core.log("action", string.format("[living_villages] villager %s became builder of the bench at %s",
		tostring(self._id), core.pos_to_string(pos)))
	return true
end

-- The free bench nearest pos in the box, or nil.
local function nearest_free(pos, radius, height, skip, now)
	local minp = {x = pos.x - radius, y = pos.y - height, z = pos.z - radius}
	local maxp = {x = pos.x + radius, y = pos.y + height, z = pos.z + radius}
	local best, best_distance
	for _, bench in ipairs(core.find_nodes_in_area(minp, maxp, {BENCH})) do
		if is_free(bench) and (not skip or (skip[pos_key(bench)] or 0) <= now) then
			local distance = vector.distance(pos, bench)
			if not best or distance < best_distance then best, best_distance = bench, distance end
		end
	end
	return best
end

-- The villager of the house takes its bench without walking there: it lives beside it, and
-- this has to come before any other job.
local function claim_as_owner(self)
	if not self._bed then return false end
	local bench = nearest_free(self._bed, OWNER_RADIUS, OWNER_HEIGHT)
	return bench ~= nil and M.employ(self, bench)
end

-- Anyone else out of work may walk over for a bench no one has taken.
local function seek_bench(self, session, now)
	local pos = self.object:get_pos()
	if not pos then return end
	local bench = nearest_free(pos, CLAIM_RADIUS, CLAIM_RADIUS, session.skip, now)
	if not bench then return end
	if vector.distance(pos, bench) < 2 then
		M.employ(self, bench)
		return
	end
	local started = self:gopath(bench, function(entity)
		local here = entity.object:get_pos()
		if here and vector.distance(here, bench) < 2.5 then M.employ(entity, bench) end
	end, true)
	if started == false then session.skip[pos_key(bench)] = now + UNREACHABLE_SECONDS end
end

function M.load_project(bench)
	local text = core.get_meta(bench):get_string(PROJECT)
	return text ~= "" and core.deserialize(text) or nil
end

local function save_project(bench, project)
	core.get_meta(bench):set_string(PROJECT, project and core.serialize(project) or "")
end

local function set_state(bench, project, state)
	project.state = state
	save_project(bench, project)
end

-- Tells a project in hand from one that is waiting, and the turn that works on it.
local WORKING = {collecting = true, building = true, blocked = true, returning = true}
local work

local function is_solid_node(name)
	local def = core.registered_nodes[name]
	return def ~= nil and def.walkable ~= false and (def.liquidtype or "none") == "none"
end

local function schematic_entry(name)
	local settlements = rawget(_G, "settlements")
	for _, entry in ipairs(settlements and settlements.schematic_table or {}) do
		if entry.name == name then return entry end
	end
end

-- A building's size and how many blocks it takes, the latter for the census to break ties
-- with. Fixed once read, and reading one means serializing its schematic. `project` needs only
-- its building, or its copy of a schematic (schem): that holds its own measure, keyed by content.
-- A copy whose nodes have since gone, with their mod, measures as nothing, so it is dropped
-- rather than built with holes.
local measures = {}
local function measure(project)
	local id = project.schem or project.building
	if measures[id] ~= nil then return measures[id] or nil end
	measures[id] = false
	if project.schem then
		local schematic = core.read_schematic(catalog.snapshot_path(project.schem), {})
		local measured = schematic and catalog.measure(schematic)
		if measured and #measured.unknown == 0 and #measured.no_item == 0 then measures[id] = measured end
		return measures[id] or nil
	end
	local entry = schematic_entry(project.building)
	local schematic = entry and template.prepare_schematic(entry, DEFAULT_SURFACE)
	if not schematic then return nil end
	local blocks, bill = 0, {}
	for _, cell in ipairs(schematic.data) do
		if cell.name ~= "air" then blocks = blocks + 1 end
		for item, count in pairs(materials.cost(cell.name) or {}) do bill[item] = (bill[item] or 0) + count end
	end
	measures[id] = {size = schematic.size, blocks = blocks, materials = catalog.sorted_materials(bill)}
	return measures[id]
end

local function totals_of_buildings()
	local totals = {}
	local settlements = rawget(_G, "settlements")
	for _, entry in ipairs(settlements and settlements.schematic_table or {}) do
		local measured = measure({building = entry.name})
		totals[entry.name] = measured and measured.blocks
	end
	return totals
end

-- Other Builders' sites: a bench that has gone holds nothing.
local function live_reservations(record, own_key)
	local rects = {}
	for key, rect in pairs(record and record.reserved or {}) do
		if key ~= own_key then
			local node = core.get_node_or_nil(rect.bench)
			if not node or node.name == BENCH then rects[#rects + 1] = rect end
		end
	end
	return rects
end

local function reserve(bench, rect)
	if not village_index then return end
	village_index.update_village(bench, VILLAGE_RADIUS, function(record)
		record.reserved = record.reserved or {}
		-- A bench that has gone holds nothing any more.
		for key, held in pairs(record.reserved) do
			local node = core.get_node_or_nil(held.bench)
			if node and node.name ~= BENCH then record.reserved[key] = nil end
		end
		record.reserved[pos_key(bench)] = rect
	end)
end

-- Adds the sites this bench has found it cannot walk to, while it keeps away from them.
local function with_avoided(rects, bench)
	local now = core.get_gametime()
	for _, rect in ipairs((M.load_project(bench) or {}).avoid or {}) do
		if rect.expires > now then rects[#rects + 1] = rect end
	end
	return rects
end

local function site_request(bench, project)
	local measured = measure(project)
	if not measured then return nil end
	local config = site_finder.config
	local record = village_index and village_index.read_village(bench, VILLAGE_RADIUS)
	local center = record and record.center or bench
	return {
		size = {x = measured.size.x, z = measured.size.z},
		height = measured.size.y - 1,
		limit = setting_number("living_villages_builder_earthwork_limit", config.limit),
		gap = setting_number("living_villages_builder_site_gap", config.gap),
		margin = config.margin,
		ring = config.ring,
		ring_step = config.ring_step,
		range = config.range,
		bench = bench,
		center = center,
		reserved = with_avoided(live_reservations(record, pos_key(bench)), bench),
	}
end

-- The ground's own surface if a village can have it, else what the village stands on.
local function surface_for(site, record)
	local settlements = rawget(_G, "settlements")
	if settlements and settlements.surface_mat and settlements.surface_mat[site.ground] then return site.ground end
	local first = record and record.buildings and record.buildings[1]
	return first and first.surface_mat or DEFAULT_SURFACE
end

-- A site's plan, built once per project: reading it through a VoxelManip is not free.
local plans = {}
local function plan_of(bench, project)
	if not project.pos then return nil end
	local earthwork = project.earthwork or {}
	local id = table.concat({project.building, tostring(project.schem), tostring(project.seed), pos_key(project.pos),
		project.rotat, tostring(project.surface_mat), #(earthwork.cuts or {}), #(earthwork.fills or {})}, "|")
	local cached = plans[pos_key(bench)]
	if cached and cached.id == id then return cached.plan end
	local custom = project.schem ~= nil
	local schematic
	if not custom then
		local entry = schematic_entry(project.building)
		schematic = entry and template.prepare_schematic(entry, project.surface_mat)
	elseif measure(project) then
		schematic = template.prepare_custom(catalog.snapshot_path(project.schem), project.seed)
	end
	local cells = schematic and template.world_cells(schematic, project.pos, project.rotat, nil, custom)
	if not cells then return nil end
	local plan = template.plan(cells, {
		floor_y = project.pos.y, surface_mat = project.surface_mat, earthwork = project.earthwork, custom = custom,
	})
	plans[pos_key(bench)] = {id = id, plan = plan}
	return plan
end

local function name_at(pos)
	local node = core.get_node_or_nil(pos)
	return node and node.name or nil
end

-- What the project still needs, against what the chests and the pouch hold. `rows` is one
-- per item, sorted: {item, need, in_chests, carried, missing}.
function M.materials_report(self, bench, project)
	local plan = plan_of(bench, project)
	if not plan then return nil end
	local missing_steps, blocked = template.compare(plan, name_at)
	local chests = stock.find_chests(bench, chest_radius())
	local rows, short = {}, false
	for item, need in pairs(template.bill(missing_steps)) do
		local in_chests = 0
		for _, chest in ipairs(chests) do in_chests = in_chests + stock.chest_count(chest, item) end
		local carried = stock.count(self, item)
		local missing = math.max(0, need - in_chests - carried)
		short = short or missing > 0
		rows[#rows + 1] = {item = item, need = need, in_chests = in_chests, carried = carried, missing = missing}
	end
	table.sort(rows, function(a, b) return a.item < b.item end)
	return {
		rows = rows, short = short, steps = missing_steps, blocked = blocked,
		total = #plan.steps, left = #missing_steps, chests = chests,
	}
end

function M.source_of(bench)
	local source = core.get_meta(bench):get_string(SOURCE)
	if source == catalog.SCHEMEDIT or source == catalog.FOLDER then return source end
	return nil
end

-- A project nothing has been done for yet is dropped, so the new source takes effect at once.
-- One under way is finished first.
local NOT_STARTED = {finding_site = true, no_site = true, requires_materials = true}
function M.set_source(bench, source)
	if source ~= catalog.SCHEMEDIT and source ~= catalog.FOLDER then source = nil end
	if M.source_of(bench) == source then return end
	core.get_meta(bench):set_string(SOURCE, source or "")
	local project = M.load_project(bench)
	if not (project and NOT_STARTED[project.state]) then return end
	save_project(bench, nil)
	if village_index then
		village_index.update_village(bench, VILLAGE_RADIUS, function(record)
			if record.reserved then record.reserved[pos_key(bench)] = nil end
		end)
	end
end

local function pick_from(scan, record, source)
	local weights, totals = {}, {}
	for _, entry in ipairs(scan.entries) do
		if not entry.problem and entry.weight > 0 then
			weights[entry.name] = entry.weight
			totals[entry.name] = entry.measured.blocks
		end
	end
	return census.pick_custom(weights, census.custom_counts(record, source), totals)
end

-- What a bench could build from a source, for its menu: {rows, directory, manifest_problem}.
-- A row is {name, share, built, is_next, size, blocks, materials}, and for a directory weight,
-- problem and image too. The stock buildings have no weights: a village's mix sets their shares.
function M.options(bench, source)
	local record = village_index and village_index.read_village(bench, VILLAGE_RADIUS)
	local rows = {}
	if source == catalog.SCHEMEDIT or source == catalog.FOLDER then
		local scan = catalog.scan(source)
		local built = census.custom_counts(record, source)
		local next_name = pick_from(scan, record, source)
		for _, entry in ipairs(scan.entries) do
			local measured = entry.measured or {}
			rows[#rows + 1] = {
				name = entry.name, weight = entry.weight, share = entry.share, built = built[entry.name] or 0,
				is_next = entry.name == next_name, problem = entry.problem,
				size = measured.size, blocks = measured.blocks, materials = measured.materials, image = entry.image,
			}
		end
		return {rows = rows, directory = scan.directory, manifest_problem = scan.manifest_problem}
	end
	local settlements = rawget(_G, "settlements")
	local schematic_table = settlements and settlements.schematic_table
	local shares = census.shares(record, schematic_table) or {}
	local counts = census.current(record)
	local next_name = census.pick(record, schematic_table, totals_of_buildings())
	for name, share in pairs(shares) do
		local measured = measure({building = name}) or {}
		rows[#rows + 1] = {
			name = name, share = share, built = counts[name] or 0, is_next = name == next_name,
			size = measured.size, blocks = measured.blocks, materials = measured.materials,
		}
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return {rows = rows}
end

-- The next schematic of a source. Nothing to build is said in the status window, and never
-- quietly made up with stock buildings the player turned away from.
local function choose_custom(self, session, bench, source, record)
	local scan = catalog.scan(source)
	local name = pick_from(scan, record, source)
	session.no_projects = name == nil or nil
	if not name then return end
	local hash = catalog.take_snapshot(scan.directory, name)
	if not hash then
		core.log("error", "[living_villages] could not copy schematic " .. name .. " for a project")
		return
	end
	save_project(bench, {
		state = "finding_site", building = name, source = source, schem = hash,
		seed = math.random(0, 2147483647),
	})
	core.log("action", string.format("[living_villages] builder %s will put up %s from %s", tostring(self._id), name, source))
end

local function choose(self, session, bench)
	local record = village_index and village_index.read_village(bench, VILLAGE_RADIUS)
	local source = M.source_of(bench)
	if source then return choose_custom(self, session, bench, source, record) end
	session.no_projects = nil
	local settlements = rawget(_G, "settlements")
	local building = census.pick(record, settlements and settlements.schematic_table, totals_of_buildings())
	if not building then return end
	save_project(bench, {state = "finding_site", building = building})
	core.log("action", string.format("[living_villages] builder %s will put up a %s", tostring(self._id), building))
end

local function start_search(self, session, bench, project)
	local request = site_request(bench, project)
	if not request then
		save_project(bench, nil)
		return
	end
	session.searching = true
	local config = site_finder.config
	local function finish(found, report)
		session.searching = false
		session.retry_at = core.get_gametime() + SITE_RETRY_SECONDS
		session.site_report = report
		local current = M.load_project(bench)
		if not current or current.building ~= project.building or current.schem ~= project.schem then return end
		if not found then
			-- Why, for whoever looks into a Builder that will not start.
			local reasons = {}
			for reason, count in pairs(report or {}) do reasons[#reasons + 1] = reason .. " " .. count end
			table.sort(reasons)
			core.log("action", string.format("[living_villages] builder %s found no site for a %s: %s",
				tostring(self._id), project.building, table.concat(reasons, ", ")))
			current.state = "no_site"
			save_project(bench, current)
			return
		end
		local record = village_index and village_index.read_village(bench, VILLAGE_RADIUS)
		current.state = "requires_materials"
		current.pos = {x = found.x, y = found.floor, z = found.z}
		current.rotat = found.rotat
		current.surface_mat = surface_for(found, record)
		current.earthwork = found.earthwork
		save_project(bench, current)
		local turned = found.rotat == "90" or found.rotat == "270"
		local w = turned and request.size.z or request.size.x
		local d = turned and request.size.x or request.size.z
		reserve(bench, {bench = bench, x0 = found.x, z0 = found.z, x1 = found.x + w - 1, z1 = found.z + d - 1})
		core.log("action", string.format("[living_villages] builder %s chose %s for a %s (%d blocks of earthwork)",
			tostring(self._id), core.pos_to_string(current.pos), current.building, found.blocks))
	end
	local queue = navigation_api and navigation_api.route_queue
	local checkpoint = queue and queue.checkpoint
	local function search()
		local snapshot = site_finder.snapshot(site_finder.area(bench, config))
		if checkpoint then checkpoint() end
		return site_finder.search(site_finder.survey(snapshot, site_finder.live_env(core), checkpoint), request, checkpoint)
	end
	if not queue then return finish(search()) end
	queue.submit(search, finish, {on_error = function(message)
		core.log("error", "[living_villages] builder's site search failed: " .. tostring(message))
		session.searching = false
		session.retry_at = core.get_gametime() + SITE_RETRY_SECONDS
	end})
end

-- A site nothing has been done to yet is free to go bad: a player may have built there in
-- the meantime. Then it finds another.
local function site_still_good(bench, project)
	local request = site_request(bench, project)
	if not request then return false end
	local turned = project.rotat == "90" or project.rotat == "270"
	local w = turned and request.size.z or request.size.x
	local d = turned and request.size.x or request.size.z
	local area = site_finder.area_of_site(bench, project.pos.x, project.pos.z, w, d, site_finder.config)
	local survey = site_finder.survey(site_finder.snapshot(area), site_finder.live_env(core))
	local site = site_finder.evaluate(survey, project.pos.x, project.pos.z, w, d, request)
	return site ~= nil and site.floor == project.pos.y
end

local function check_materials(self, session, bench, project, now)
	if now < (session.materials_at or 0) then return end
	session.materials_at = now + MATERIALS_SECONDS
	local report = M.materials_report(self, bench, project)
	if project.started then
		if report and #report.blocked == 0 and not report.short then
			set_state(bench, project, "collecting")
			session.queue = nil
		elseif report and #report.blocked > 0 then
			project.blocked_at = report.blocked[1]
			set_state(bench, project, "blocked")
		end
		return
	end
	if not report or #report.blocked > 0 or (now >= (session.site_at or 0) and not site_still_good(bench, project)) then
		session.retry_at = nil
		project.state = "finding_site"
		project.pos, project.rotat, project.surface_mat, project.earthwork = nil, nil, nil, nil
		save_project(bench, project)
		return
	end
	if now >= (session.site_at or 0) then session.site_at = now + SITE_RETRY_SECONDS end
	if report.short then return end
	-- Nothing has been touched until now, so a project waiting for materials leaves no scar.
	project.started = true
	set_state(bench, project, "collecting")
	session.queue = nil
end

local function reach_of()
	return setting_number("living_villages_builder_reach", site_finder.config.reach)
end

local function hold_still(self)
	self.state = "stand"
	self.order = "stand"
	self.object:set_velocity(vector.zero())
end

local function release(self, session)
	session.away = false
	session.hold_until = 0
	if self.order == "stand" then self.order = nil end
end

-- A trip by the farm trip's fields. Returns whether it set off; a place it cannot walk to
-- is left alone for a while.
local function walk_to(self, session, target, now)
	self._villages_farm_target = vector.new(target)
	self._villages_farm_route = nil
	local started = self:gopath(target, function(entity)
		entity._villages_farm_target = nil
		entity._villages_farm_route = nil
	end, true)
	if started then return true end
	session.skip[pos_key(target)] = now + SKIP_SECONDS
	self._villages_farm_target = nil
	self._villages_farm_route = nil
	return false
end

local function footprint_of(project)
	local measured = measure(project)
	if not measured then return nil end
	local size = template.rotated_size(measured.size, project.rotat)
	return {
		x0 = project.pos.x, z0 = project.pos.z,
		x1 = project.pos.x + size.x - 1, z1 = project.pos.z + size.z - 1,
	}
end

local function is_solid_at(pos)
	local name = name_at(pos)
	local def = name and core.registered_nodes[name]
	return def ~= nil and def.walkable ~= false
end

local function is_clear_at(pos)
	local name = name_at(pos)
	if name == "air" then return true end
	local def = name and core.registered_nodes[name]
	return def ~= nil and def.walkable == false and (def.liquidtype or "none") == "none"
end

-- Where to stand in a column of the ring: a clear cell and the one above it, over ground.
local function stand_in_column(x, z, floor_y)
	for y = floor_y + 2, floor_y, -1 do
		local cell = {x = x, y = y, z = z}
		if is_clear_at(cell) and is_clear_at({x = x, y = y + 1, z = z})
			and is_solid_at({x = x, y = y - 1, z = z}) then
			return cell
		end
	end
end

-- The cell on the ring's outer row nearest `pos` it can reach it from. The outer row, so
-- that a route ending a cell short of it still ends outside the footprint.
local function ring_spot(session, box, floor_y, pos, now)
	local ring = site_finder.config.ring
	local spots = {}
	for z = box.z0 - ring, box.z1 + ring do
		for x = box.x0 - ring, box.x1 + ring do
			if x == box.x0 - ring or x == box.x1 + ring or z == box.z0 - ring or z == box.z1 + ring then
				spots[#spots + 1] = {x = x, z = z, d = (x - pos.x) ^ 2 + (z - pos.z) ^ 2}
			end
		end
	end
	table.sort(spots, function(a, b) return a.d < b.d end)
	local reach = reach_of()
	for _, spot in ipairs(spots) do
		local cell = stand_in_column(spot.x, spot.z, floor_y)
		if cell and vector.distance(cell, pos) <= reach and (session.skip[pos_key(cell)] or 0) <= now then
			return cell
		end
	end
end

local function inside(box, pos)
	return pos.x >= box.x0 - 0.5 and pos.x <= box.x1 + 0.5 and pos.z >= box.z0 - 0.5 and pos.z <= box.z1 + 0.5
end

-- Whether a player or mob stands in the cell. Only those: a dropped item or a chest's own
-- display entity, which never goes away, is nothing to wait for.
local function occupied(pos)
	for _, object in ipairs(core.get_objects_inside_radius(pos, 2.5)) do
		local entity = object.get_luaentity and object:get_luaentity()
		if not entity or entity.is_mob then
			local at = object:get_pos()
			if at and math.abs(at.x - pos.x) < 0.8 and math.abs(at.z - pos.z) < 0.8
				and at.y > pos.y - 2 and at.y < pos.y + 0.5 then
				return true
			end
		end
	end
	return false
end

-- What the next steps call for that the pouch does not hold, and the batch itself.
local function wanted_for(self, missing)
	local batch = template.next_batch(missing, setting_number("living_villages_builder_capacity", DEFAULT_CAPACITY))
	local wanted, any = {}, false
	for item, count in pairs(batch) do
		local short = count - stock.count(self, item)
		if short > 0 then
			wanted[item] = short
			any = true
		end
	end
	return wanted, any, batch
end

local function chest_sound(pos)
	core.sound_play("default_chest_close", {pos = pos, gain = 0.3, max_hear_distance = 16}, true)
end

-- Puts back what the batch has no use for, such as an empty bucket.
local function deposit(self, chest, keep)
	for item, count in pairs(self._villages_farm_pouch or {}) do
		local spare = count - (keep and keep[item] or 0)
		if spare > 0 then stock.put_in_chest(self, chest, item, spare) end
	end
end

local function collect(self, session, bench, project, now)
	local wanted, any, batch = wanted_for(self, session.queue)
	if not any then
		session.stuck = nil
		set_state(bench, project, "building")
		return
	end
	local here = self.object:get_pos()
	local best, best_distance, out_of_reach
	for _, chest in ipairs(stock.find_chests(bench, chest_radius())) do
		local holds = false
		for item in pairs(wanted) do
			if stock.chest_count(chest, item) > 0 then holds = true end
		end
		if holds and (session.skip[pos_key(chest)] or 0) > now then
			out_of_reach = true
		elseif holds then
			local distance = vector.distance(here, chest)
			if not best or distance < best_distance then best, best_distance = chest, distance end
		end
	end
	if not best then
		-- Taken away since, or out of its reach for now.
		session.stuck = out_of_reach and "chest" or nil
		session.materials_at = 0
		set_state(bench, project, "requires_materials")
		return
	end
	if best_distance <= CHEST_REACH then
		deposit(self, best, batch)
		for item, count in pairs(wanted) do stock.take_from_chest(self, best, item, count) end
		chest_sound(best)
		session.hold_until = now + HOLD_SECONDS
		return
	end
	if walk_to(self, session, best, now) then session.stuck = nil else session.stuck = "chest" end
end

-- The search only reads the ground, so it can choose a site across a river or up a cliff.
-- Nothing has been done to it yet, so it looks for another. The site is not ruled out for
-- good, as the player may make a way there.
local function give_up_site(self, session, bench, project, box)
	core.log("action", string.format("[living_villages] builder %s cannot get to %s for a %s",
		tostring(self._id), core.pos_to_string(project.pos), project.building))
	box.expires = core.get_gametime() + AVOID_SECONDS
	project.avoid = project.avoid or {}
	table.insert(project.avoid, box)
	project.pos, project.rotat, project.surface_mat, project.earthwork = nil, nil, nil, nil
	project.started, project.reached = nil, nil
	session.queue, session.spot, session.site_attempts, session.retry_at = nil, nil, 0, nil
	session.stuck = nil
	set_state(bench, project, "finding_site")
end

local function finish_building(self, session, bench, project)
	local key = pos_key(bench)
	if village_index then
		village_index.update_village(bench, VILLAGE_RADIUS, function(record)
			if project.schem then
				census.add_built_custom(record, project.source, project.building)
			else
				census.add_built(record, project.building)
			end
			if record.reserved then record.reserved[key] = nil end
		end)
	end
	core.log("action", string.format("[living_villages] builder %s finished a %s at %s",
		tostring(self._id), project.building, core.pos_to_string(project.pos)))
	session.queue = nil
	set_state(bench, project, "returning")
end

local function return_leftovers(self, session, bench, now)
	if stock.total(self) == 0 then
		save_project(bench, nil)
		return
	end
	local here = self.object:get_pos()
	local chest = stock.find_chests(bench, chest_radius())[1]
	if chest and (session.skip[pos_key(chest)] or 0) <= now then
		if vector.distance(here, chest) > CHEST_REACH then
			if walk_to(self, session, chest, now) then return end
		else
			deposit(self, chest)
			chest_sound(chest)
			session.hold_until = now + HOLD_SECONDS
		end
	end
	-- No chest it can reach, or none with room: not worth keeping a whole village waiting for.
	if stock.total(self) > 0 and (not chest or vector.distance(here, chest) <= CHEST_REACH
		or (session.skip[pos_key(chest)] or 0) > now) then
		stock.drop_all(self, here)
	end
end

local function make_step(self, step, plan)
	if step.kind == "cut" or step.kind == "clear" then
		core.remove_node(step.pos)
		core.sound_play("default_dig_crumbly", {pos = step.pos, gain = 0.5, max_hear_distance = 16}, true)
		return true
	end
	for item, count in pairs(step.cost or {}) do
		if stock.count(self, item) < count then return false end
	end
	for item, count in pairs(step.cost or {}) do stock.take(self, item, count) end
	core.set_node(step.pos, step.node)
	if step.top then
		local top_missing = template.compare({
			steps = {{kind = "place", pos = step.top.pos, node = step.top.node}},
			surface_mat = plan.surface_mat, cut_at = plan.cut_at,
		}, name_at)
		if #top_missing > 0 then core.set_node(step.top.pos, step.top.node) end
	end
	for item, count in pairs(step.returns or {}) do stock.add(self, item, count) end
	local def = core.registered_nodes[step.node.name]
	local sound = def and def.sounds and def.sounds.place
	if sound then core.sound_play(sound, {pos = step.pos, max_hear_distance = 16}, true) end
	return true
end

-- The first step it can do now: past a cell someone stands in for a moment, though not
-- to a liquid while anything else is left, or the water would run out of unfinished walls.
local function next_step(session, now)
	local passed = false
	for _, step in ipairs(session.queue) do
		if (session.deferred[pos_key(step.pos)] or 0) > now then
			passed = true
		elseif step.pass == template.PASS_LIQUID and passed then
			return nil
		else
			return step
		end
	end
end

-- A step like this one, as good to do next, that it can reach from where it stands. Any
-- order within a layer is safe, and walking round a building for each row is what takes time.
local function reachable_alike(session, step, standing, reach, now)
	for _, other in ipairs(session.queue) do
		if other.pass == step.pass and other.kind == step.kind and other.pos.y == step.pos.y
			and (session.deferred[pos_key(other.pos)] or 0) <= now
			and vector.distance(standing, other.pos) <= reach then
			return other
		end
	end
end

local function drop_from_queue(session, step)
	for i, queued in ipairs(session.queue) do
		if queued == step then
			table.remove(session.queue, i)
			return
		end
	end
end

local function build(self, session, bench, project, plan, now)
	if now < (session.next_place or 0) then
		session.hold_until = now + HOLD_SECONDS
		return
	end
	local step = next_step(session, now)
	if not step then
		session.stuck = "occupied"
		return
	end
	local here = self.object:get_pos()
	local box = footprint_of(project)
	local at_spot = session.spot and vector.distance(here, session.spot) <= CHEST_REACH
	if at_spot and not project.reached then
		project.reached = true
		save_project(bench, project)
	end
	local standing = at_spot and session.spot or here
	if project.reached and not inside(box, here) then
		step = reachable_alike(session, step, standing, reach_of(), now) or step
	end
	if not project.reached or inside(box, here) or vector.distance(standing, step.pos) > reach_of() then
		session.site_attempts = (session.site_attempts or 0) + 1
		if not project.reached and session.site_attempts > SITE_ATTEMPTS then
			return give_up_site(self, session, bench, project, box)
		end
		local spot = ring_spot(session, box, project.pos.y, step.pos, now)
		if not spot then
			session.stuck = "site"
			return
		end
		session.spot = spot
		if walk_to(self, session, spot, now) then session.stuck = nil else session.stuck = "site" end
		return
	end
	session.site_attempts = 0

	-- It may have changed since the last look.
	local missing, blocked = template.compare({
		steps = {step}, surface_mat = plan.surface_mat, cut_at = plan.cut_at,
	}, name_at)
	if #blocked > 0 or core.is_protected(step.pos, "") then
		project.blocked_at = step.pos
		set_state(bench, project, "blocked")
		return
	end
	if #missing == 0 then
		drop_from_queue(session, step)
		return
	end
	local placing_solid = step.node and is_solid_node(step.node.name)
	if placing_solid and occupied(step.pos) then
		session.deferred[pos_key(step.pos)] = now + DEFER_SECONDS
		return
	end
	if not make_step(self, step, plan) then
		set_state(bench, project, "collecting")
		return
	end
	drop_from_queue(session, step)
	session.stuck = nil
	session.next_place = now + setting_number("living_villages_builder_block_seconds", DEFAULT_BLOCK_SECONDS)
	session.hold_until = now + HOLD_SECONDS
end

-- A started project's turn: what is left is read from the world, not remembered.
function work(self, session, bench, project, now)
	session.deferred = session.deferred or {}
	if project.state == "returning" then
		return return_leftovers(self, session, bench, now)
	end
	local plan = plan_of(bench, project)
	if not plan then
		save_project(bench, nil)
		return
	end
	local looked = false
	if not session.queue or now >= (session.queue_at or 0) or #session.queue == 0 then
		looked = true
		local missing, blocked = template.compare(plan, name_at)
		session.queue, session.queue_at = missing, now + COMPARE_SECONDS
		if #blocked > 0 then
			project.blocked_at = blocked[1]
			set_state(bench, project, "blocked")
			return
		end
		if #missing == 0 then return finish_building(self, session, bench, project) end
	end
	if project.state == "blocked" then
		if looked then
			project.blocked_at = nil
			set_state(bench, project, "collecting")
		end
		return
	end
	if project.state == "collecting" then
		collect(self, session, bench, project, now)
	elseif project.state == "building" then
		build(self, session, bench, project, plan, now)
	end
end

local function tick(self, session, bench, now)
	local project = M.load_project(bench)
	if not project then
		choose(self, session, bench)
		session.next_at = now + TICK_SECONDS
		release(self, session)
		return
	end
	if project.state == "finding_site" or project.state == "no_site" then
		if not session.searching and now >= (session.retry_at or 0) then
			start_search(self, session, bench, project)
		end
	elseif project.state == "requires_materials" then
		check_materials(self, session, bench, project, now)
	else
		work(self, session, bench, project, now)
	end
	session.away = WORKING[(M.load_project(bench) or {}).state] == true
	if not session.away then release(self, session) end
	session.next_at = now + (session.away and WORK_TICK_SECONDS or TICK_SECONDS)
end

-- Everything the status window shows.
function M.report(self)
	local bench = M.claimed_bench(self)
	if not bench then return {state = "no_bench"} end
	local project = M.load_project(bench)
	if not project then
		return {
			state = "choosing", bench = bench, at_work = common.is_work_time(self),
			no_projects = session_of(self).no_projects,
		}
	end
	local report = {
		state = project.state, building = project.building, site = project.pos, bench = bench,
		at_work = common.is_work_time(self), currency = materials.EMERALD,
	}
	if project.blocked_at and project.state == "blocked" then report.blocked = project.blocked_at end
	report.stuck = session_of(self).stuck
	local request = site_request(bench, project)
	if request then
		report.size = {x = request.size.x, y = request.height + 1, z = request.size.z}
		report.range = request.range
	end
	if project.pos then
		local found = M.materials_report(self, bench, project)
		if found then
			report.rows, report.left, report.total = found.rows, found.left, found.total
			report.blocked = report.blocked or found.blocked[1]
			for _, row in ipairs(found.rows) do
				row.price = row.missing > 0 and materials.SALES[row.item] or nil
			end
		end
		report.earthwork = project.earthwork and (#project.earthwork.cuts + #project.earthwork.fills) or 0
	end
	return report
end

-- Sells a player one of what the project lacks and cannot easily be had. It goes in the
-- nearest chest with room, where the Builder will find it, or else to the player.
-- Returns true, or false and a reason (a message id for builder_status.lua).
function M.buy(self, player, item)
	local price = materials.SALES[item]
	if not price then return false, "not_for_sale" end
	local bench = M.claimed_bench(self)
	local project = bench and M.load_project(bench)
	local found = project and project.pos and M.materials_report(self, bench, project)
	if not found then return false, "not_needed" end
	local needed = false
	for _, row in ipairs(found.rows) do
		if row.item == item and row.missing > 0 then needed = true end
	end
	if not needed then return false, "not_needed" end
	local here, there = self.object:get_pos(), player:get_pos()
	if not here or vector.distance(here, there) > BUY_DISTANCE then return false, "too_far" end
	local inv = player:get_inventory()
	local payment = materials.EMERALD .. " " .. price
	if not inv:contains_item("main", payment) then return false, "no_emeralds" end
	inv:remove_item("main", payment)
	local placed = false
	for _, chest in ipairs(found.chests) do
		if stock.add_to_chest(chest, item) then
			placed = true
			break
		end
	end
	if not placed then
		local left = inv:add_item("main", item)
		if not left:is_empty() then core.add_item(there, left) end
	end
	core.log("action", string.format("[living_villages] %s bought %s from builder %s for %d emeralds",
		player:get_player_name(), item, tostring(self._id), price))
	return true, placed and "in_chest" or "in_inventory"
end

-- common.activity_override: a Builder with a project in hand is not called back to its bench.
function M.activity_override(villager, stage)
	if stage ~= "work" then return nil end
	local session = sessions[villager]
	if session and session.away then return "build" end
	return nil
end

function M.install(def, navigation, index)
	navigation_api, village_index = navigation, index
	local status = dofile(core.get_modpath("living_villages") .. "/builder_status.lua")
	dofile(core.get_modpath("living_villages") .. "/builder_giveme.lua").install(M)
	if core.override_item then dofile(core.get_modpath("living_villages") .. "/builder_bench_menu.lua").install(M) end
	local original_activate = def.on_activate
	local original_custom = def.do_custom
	local original_gopath = def.gopath
	local original_rightclick = def.on_rightclick

	-- The flag is saved like any other field; recover it for a Builder that lost it.
	def.on_activate = function(self, staticdata, dtime)
		local result = original_activate(self, staticdata, dtime)
		if not self.child and self._profession == PROFESSION and self._id and M.claimed_bench(self) then
			self._villages_builder = true
		end
		return result
	end

	def.do_custom = function(self, dtime)
		local now = core.get_gametime()
		-- Before the jobs inside: a house's own villager is never offered another one.
		if self._bed and eligible(self) then
			local session = session_of(self)
			if now >= session.next_claim then
				session.next_claim = now + CLAIM_SECONDS
				claim_as_owner(self)
			end
		end
		local result = original_custom(self, dtime)
		if self._villages_builder and self._profession ~= PROFESSION then
			-- Vanilla took the job away with the bench. What it carried is not lost.
			self._villages_builder = nil
			stock.drop_all(self, self.object:get_pos())
			core.log("action", string.format("[living_villages] villager %s is no longer a builder", tostring(self._id)))
		end
		if result == false or self.following or self.state == "gowp" then return result end
		if eligible(self) then
			if not self._villages_farm_seek and (common.is_work_time(self) or common.schedule_stage(nil, self) == "free") then
				local session = session_of(self)
				if now >= (session.next_seek or 0) then
					session.next_seek = now + CLAIM_SECONDS
					seek_bench(self, session, now)
				end
			end
			return result
		end
		if not self._villages_builder then return result end
		local session = session_of(self)
		local bench = M.claimed_bench(self)
		if not bench or not common.is_work_time(self) then
			if session.away then release(self, session) end
			return result
		end
		-- The way the farmer does it: a trip that ended is looked at, and one still being
		-- planned is waited for.
		if self._villages_farm_target then
			local route = self._villages_farm_route
			if route and route.status == "planning" then return result end
			if route and route.status == "retry" then
				session.skip[pos_key(self._villages_farm_target)] = now + SKIP_SECONDS
			end
			self._villages_farm_target = nil
			self._villages_farm_route = nil
		end
		if now >= session.next_at then tick(self, session, bench, now) end
		if self.state ~= "gowp" and session.hold_until >= now then
			hold_still(self)
			-- As for a fishing session: do_states would turn a standing villager away.
			return false
		end
		return result
	end

	-- A Builder works only at a bench; refuse vanilla's trips to any other workstation
	-- rather than walk there and release it on arrival (as keeper.lua).
	def.gopath = function(self, target, callback_arrived, prioritised, market_token)
		if self._villages_builder and target then
			local node = core.get_node_or_nil(target)
			if node and common.is_workstation_node(node.name) then return false end
		end
		return original_gopath(self, target, callback_arrived, prioritised, market_token)
	end

	def.on_rightclick = function(self, clicker)
		if self._villages_builder and not self.child and clicker and clicker.is_player and clicker:is_player() then
			status.show(clicker:get_player_name(), self, M)
			return
		end
		return original_rightclick(self, clicker)
	end
end

-- One line for the Lookup Tool inspector (diagnostic.lua).
function M.status(self)
	if not self._villages_builder then return "not a builder" end
	local bench = M.claimed_bench(self)
	if not bench then return "no claimed bench" end
	local project = M.load_project(bench)
	if not project then return "choosing what to build" end
	return project.state .. " (" .. project.building
		.. (project.pos and (" at " .. core.pos_to_string(project.pos)) or "") .. ")"
end

return M
