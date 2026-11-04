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
--            requires_materials <-> ready
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local census = dofile(core.get_modpath("living_villages") .. "/village_census.lua")
local materials = dofile(core.get_modpath("living_villages") .. "/builder_materials.lua")
local site_finder = dofile(core.get_modpath("living_villages") .. "/builder_site.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local template = dofile(core.get_modpath("living_villages") .. "/building_template.lua")

local M = {}

local BENCH = "living_villages:builder_block"
M.BENCH = BENCH
local PROFESSION = "mason"
local PROJECT = "villages_project"

-- A villager whose bed is this near a free bench takes it at once, ahead of any other
-- job, since farm_jobs.lua would otherwise send it off to the nearest composter for good.
local OWNER_RADIUS = 12
local OWNER_HEIGHT = 4
local CLAIM_RADIUS = 48
local CLAIM_SECONDS = 10
local UNREACHABLE_SECONDS = 300
local TICK_SECONDS = 5
local MATERIALS_SECONDS = 10
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
		session = {next_at = 0, next_claim = 0}
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
	session.skip = session.skip or {}
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

local function schematic_entry(name)
	local settlements = rawget(_G, "settlements")
	for _, entry in ipairs(settlements and settlements.schematic_table or {}) do
		if entry.name == name then return entry end
	end
end

-- Each building's size and how many blocks it takes, the latter for the census to break
-- ties with. Fixed once read, and reading one means serializing its schematic.
local measures = {}
local function measure(name)
	if measures[name] ~= nil then return measures[name] or nil end
	local entry = schematic_entry(name)
	local schematic = entry and template.prepare_schematic(entry, DEFAULT_SURFACE)
	if not schematic then
		measures[name] = false
		return nil
	end
	local blocks = 0
	for _, cell in ipairs(schematic.data) do
		if cell.name ~= "air" then blocks = blocks + 1 end
	end
	measures[name] = {size = schematic.size, blocks = blocks}
	return measures[name]
end

local function totals_of_buildings()
	local totals = {}
	local settlements = rawget(_G, "settlements")
	for _, entry in ipairs(settlements and settlements.schematic_table or {}) do
		local measured = measure(entry.name)
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

local function site_request(bench, building)
	local measured = measure(building)
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
		reserved = live_reservations(record, pos_key(bench)),
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
	local id = table.concat({project.building, pos_key(project.pos), project.rotat, tostring(project.surface_mat),
		#(earthwork.cuts or {}), #(earthwork.fills or {})}, "|")
	local cached = plans[pos_key(bench)]
	if cached and cached.id == id then return cached.plan end
	local entry = schematic_entry(project.building)
	local schematic = entry and template.prepare_schematic(entry, project.surface_mat)
	local cells = schematic and template.world_cells(schematic, project.pos, project.rotat)
	if not cells then return nil end
	local plan = template.plan(cells, {
		floor_y = project.pos.y, surface_mat = project.surface_mat, earthwork = project.earthwork,
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

local function choose(self, bench)
	local record = village_index and village_index.read_village(bench, VILLAGE_RADIUS)
	local settlements = rawget(_G, "settlements")
	local building = census.pick(record, settlements and settlements.schematic_table, totals_of_buildings())
	if not building then return end
	save_project(bench, {state = "finding_site", building = building})
	core.log("action", string.format("[living_villages] builder %s will put up a %s", tostring(self._id), building))
end

local function start_search(self, session, bench, project)
	local request = site_request(bench, project.building)
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
		if not current or current.building ~= project.building then return end
		if not found then
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
	local request = site_request(bench, project.building)
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
	if not report or #report.blocked > 0 or (now >= (session.site_at or 0) and not site_still_good(bench, project)) then
		session.retry_at = nil
		project.state = "finding_site"
		project.pos, project.rotat, project.surface_mat, project.earthwork = nil, nil, nil, nil
		save_project(bench, project)
		return
	end
	if now >= (session.site_at or 0) then session.site_at = now + SITE_RETRY_SECONDS end
	local state = report.short and "requires_materials" or "ready"
	if project.state ~= state then
		project.state = state
		save_project(bench, project)
	end
end

local function tick(self, session, bench, now)
	local project = M.load_project(bench)
	if not project then
		choose(self, bench)
		return
	end
	if project.state == "finding_site" or project.state == "no_site" then
		if not session.searching and now >= (session.retry_at or 0) then
			start_search(self, session, bench, project)
		end
	elseif project.state == "requires_materials" or project.state == "ready" then
		check_materials(self, session, bench, project, now)
	end
end

-- Everything the status window shows.
function M.report(self)
	local bench = M.claimed_bench(self)
	if not bench then return {state = "no_bench"} end
	local project = M.load_project(bench)
	if not project then return {state = "choosing", bench = bench, at_work = common.is_work_time(self)} end
	local report = {
		state = project.state, building = project.building, site = project.pos, bench = bench,
		at_work = common.is_work_time(self),
	}
	local request = site_request(bench, project.building)
	if request then
		report.size = {x = request.size.x, y = request.height + 1, z = request.size.z}
		report.range = request.range
	end
	if project.pos then
		local found = M.materials_report(self, bench, project)
		if found then
			report.rows, report.left, report.total = found.rows, found.left, found.total
			report.blocked = found.blocked[1]
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

function M.install(def, navigation, index)
	navigation_api, village_index = navigation, index
	local status = dofile(core.get_modpath("living_villages") .. "/builder_status.lua")
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
		if not self._villages_builder or not common.is_work_time(self) then return result end
		local bench = M.claimed_bench(self)
		if not bench then return result end
		local session = session_of(self)
		if now >= session.next_at then
			session.next_at = now + TICK_SECONDS
			tick(self, session, bench, now)
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
