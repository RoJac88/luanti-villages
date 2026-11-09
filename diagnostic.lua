-- A read-only, privileged inspector for the existing VoxeLibre Lookup Tool.
-- This intentionally reflects state only; it does not claim, release, or alter
-- beds, jobs, paths, or villager AI.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local cells = dofile(core.get_modpath("living_villages") .. "/cells.lua")
local is_sleep_time = common.is_sleep_time
local is_work_time = common.is_work_time
local is_home_time = common.is_home_time
local is_workstation_node = common.is_workstation_node
local keeper = dofile(core.get_modpath("living_villages") .. "/keeper.lua")
local cleric = dofile(core.get_modpath("living_villages") .. "/cleric.lua")
-- Only for its status line: this copy's reservation table is never used.
local seat = dofile(core.get_modpath("living_villages") .. "/seat.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local economy_clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local market_news = dofile(core.get_modpath("living_villages") .. "/market_news.lua")
local labour = dofile(core.get_modpath("living_villages") .. "/labour.lua")
local production = dofile(core.get_modpath("living_villages") .. "/production.lua")
local BIRTH_RADIUS = 24
local BIRTH_HEIGHT = 12
local BIRTH_INTERVAL_DAYS = 2
local LAST_BIRTH = "villages_last_birth"
local WATER_NEIGHBOR_OFFSETS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
-- Mirror fisherman.lua's own day-to-day search radius, and ask the same
-- cells.lua classifier it does, so "why won't this fisherman
-- go fishing" can be diagnosed candidate by candidate instead of guessed at.
local FISH_SEARCH_RADIUS = 32
local FISH_BELOW_BAND = 6
local FISH_ABOVE_BAND = 2

local function pos_string(pos)
	if not pos then return "none" end
	return string.format("(%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z)
end

local function distance(a, b)
	if not a or not b then return nil end
	local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(x * x + y * y + z * z)
end

local function node_name(pos)
	local node = pos and core.get_node_or_nil(pos)
	return node and node.name or "unloaded"
end

local function loaded_villager(id, near)
	if not id or id == "" or not core.get_objects_inside_radius then return nil end
	for _, object in ipairs(core.get_objects_inside_radius(near, 64)) do
		local entity = object:get_luaentity()
		if entity and entity.name == "mobs_mc:villager" and entity._id == id then
			return entity
		end
	end
end

local function claim_owner(pos, villager, kind)
	if not pos then return "none (no assigned " .. kind .. ")" end
	if not core.get_node_or_nil(pos) then return "unknown (position is unloaded)" end
	local meta = core.get_meta(pos)
	local player = kind == "bed" and meta:get_string("player") or ""
	if player ~= "" then return "player " .. player end
	local owner = meta:get_string("villager")
	if owner == "" then return "unclaimed" end
	if villager and owner == villager._id then return "this villager" end
	local other = loaded_villager(owner, pos)
	if other then
		return "villager " .. owner .. " (loaded " .. (other._profession or "unemployed") .. ")"
	end
	return "villager " .. owner .. " (not loaded nearby)"
end

-- Finds the claiming villager's own entity, if it happens to be loaded near
-- its bed/workstation, so a punched-but-empty bed can point at where its
-- occupant actually is instead of just confirming that it is claimed.
local function claim_owner_entity(pos, kind)
	if not pos or not core.get_node_or_nil(pos) then return nil end
	local meta = core.get_meta(pos)
	local player = kind == "bed" and meta:get_string("player") or ""
	if player ~= "" then return nil end
	local owner = meta:get_string("villager")
	if owner == "" then return nil end
	return loaded_villager(owner, pos)
end

-- A keeper's jukebox (keeper.lua) and a cleric's pulpit (cleric.lua) are
-- jobsites too, though not vanilla ones.
local function is_jobsite_node(name)
	return is_workstation_node(name) or name == "mcl_jukebox:jukebox"
		or name == "living_villages:pulpit"
end

local function status_of_claim(pos, id, kind)
	if not pos then return "none assigned" end
	local node = core.get_node_or_nil(pos)
	if not node then return "assigned position is unloaded" end
	if kind == "jobsite" and not is_jobsite_node(node.name) then
		return "assigned node is not a workstation (" .. node.name .. ")"
	end
	local meta = core.get_meta(pos)
	if meta:get_string("villager") ~= id then
		return "assigned " .. kind .. " is not claimed by this villager"
	end
	return "valid claim"
end

local function bed_status(villager)
	local bed = villager._bed
	if not bed then return "none assigned" end
	local node = core.get_node_or_nil(bed)
	if not node then return "assigned position is unloaded" end
	if core.get_item_group(node.name, "bed") ~= 1 then
		return "assigned node is not a bed bottom (" .. node.name .. ")"
	end
	local meta = core.get_meta(bed)
	if meta:get_string("villager") ~= villager._id then
		return "bed is not claimed by this villager"
	end
	if meta:get_string("player") ~= "" then return "bed is player-owned" end
	local top = mcl_beds.get_bed_top(bed)
	if core.get_meta(top):get_string("player") ~= "" then
		return "bed top is player-owned"
	end
	return "valid claim"
end

local function sleep_status(villager, bed_ok)
	if villager._villages_sleeping then return "sleeping" end
	local route = villager._villages_bed_route
	if route and route.status == "travelling" then return "travelling to bed" end
	if route and route.status == "retry" then return "waiting to retry bed route" end
	if not bed_ok then return "no valid claimed bed" end
	if not is_home_time(villager) then return "waiting for evening" end
	if villager.order ~= "sleep" then return "evening, but no sleep order" end
	local pos = villager.object and villager.object:get_pos()
	local d = distance(pos, villager._bed)
	if d and d >= 2 then return string.format("travelling to bed (%.1f nodes away)", d) end
	if not is_sleep_time(villager) then return "home, waiting for bedtime" end
	return "waiting to enter bed"
end

local function route_status(route)
	if not route then return "none" end
	local details = {}
	if route.id then table.insert(details, "id " .. route.id) end
	if route.started_at then
		table.insert(details, string.format("age %.0fs", math.max(core.get_gametime() - route.started_at, 0)))
	end
	local suffix = #details > 0 and " [" .. table.concat(details, ", ") .. "]" or ""
	if route.status == "travelling" then
		return "travelling to " .. pos_string(route.target) .. suffix
	end
	if route.status == "retry" then
		local remaining = math.max((route.retry_at or core.get_gametime()) - core.get_gametime(), 0)
		local target = route.target and " to " .. pos_string(route.target) or ""
		return string.format("retry in %.0fs%s: %s", remaining, target, route.reason or "unknown failure") .. suffix
	end
	if route.status == "arrived" and route.target then
		return "arrived at " .. pos_string(route.target) .. suffix
	end
	return route.status .. suffix
end

local function planner_status(route)
	local report = route and route.planner
	if not report then return "none" end
	local approaches = {}
	for _, pos in ipairs(report.candidates or {}) do table.insert(approaches, pos_string(pos)) end
	local text = "start " .. pos_string(report.start)
		.. "; approaches " .. (#approaches > 0 and table.concat(approaches, ", ") or "none")
		.. "; " .. (report.status or "unknown") .. " after " .. (report.searched or 0) .. " nodes"
	if report.closest then
		text = text .. "; closest " .. pos_string(report.closest)
			.. " (" .. (report.closest_distance or 0) .. " steps from an approach"
			.. (report.closest_cost and ", route cost " .. string.format("%.2f", report.closest_cost) or "") .. ")"
	end
	return text
end

local function planner_trail(route)
	local report = route and route.planner
	if not report or not report.trail or #report.trail == 0 then return "none" end
	local positions = {}
	for _, pos in ipairs(report.trail) do table.insert(positions, pos_string(pos)) end
	return table.concat(positions, " -> ")
end

local navigation_api

local function workstation_search_status(villager, route)
	if not route or route.status ~= "planning" then return nil end
	local info = navigation_api and navigation_api.job_search_diagnostics(villager, route)
	if not info then return "unavailable" end
	local now = core.get_gametime()
	local function ago(at)
		return at and string.format("%ds ago", math.max(now - at, 0)) or "not yet"
	end
	local submitted = info.submitted_at and (string.format("%ds ago", math.max(now - info.submitted_at, 0))) or "unknown"
	local candidates = info.examined ~= nil and string.format("%d/%d examined", info.examined, info.total or 0)
		or "unknown"
	if info.current_candidate then
		candidates = candidates .. "; current " .. pos_string(info.current_candidate)
	end
	local progress = info.state == "no matching telemetry" and "unknown"
		or string.format("%d nodes searched", info.nodes_searched or 0)
	local lines = {
		string.format("route %s; submitted %s (server game time)", tostring(info.route_id), submitted),
		string.format("queue job %s: %s%s", tostring(info.job_id or "none"), info.job_state,
			info.live and " (live)" or " (not live)"),
		string.format("resumes %d; last resume %s; last progress %s", info.resumes or 0,
			ago(info.last_resume_at), ago(info.last_progress_at)),
		"workstation candidates " .. candidates .. "; planner " .. progress,
		string.format("route queue pending %d; completed in last 60 game seconds %d",
			info.pending or 0, info.completed_last_minute or 0),
	}
	if info.error then table.insert(lines, "queue error: " .. info.error) end
	return table.concat(lines, "; ")
end

-- Set by install: flock.lua's one-line account of a shepherd's flock and grazing (#215).
local flock_status
local farmer
local gossip
local builder

local function work_status(villager, job_ok)
	local route = villager._villages_job_route
	if route and route.status == "travelling" then return "travelling to jobsite" end
	if route and route.status == "retry" then return "waiting to retry jobsite route" end
	if not job_ok then return "no valid claimed jobsite" end
	if not is_work_time(villager) then return "waiting for work period" end
	local pos = villager.object and villager.object:get_pos()
	local d = distance(pos, villager._jobsite)
	if d and d >= 2 then return string.format("travelling to jobsite (%.1f nodes away)", d) end
	if villager.order == "work" then return "working" end
	return "at jobsite"
end

local function target_string(target)
	if type(target) == "table" and target.x then return pos_string(target) end
	return target and tostring(target) or "none"
end

local function walk_failure_string(failure)
	if type(failure) ~= "table" then return "none" end
	return string.format("%s at %s heading for %s (day %s, %02d:%02d)", tostring(failure.reason),
		target_string(failure.pos), target_string(failure.target), tostring(failure.day),
		math.floor((failure.tod or 0) * 24), math.floor((failure.tod or 0) * 1440) % 60)
end

local function last_local_birth(pos)
	if not pos or not core.find_nodes_in_area then return nil end
	local minp = {x = pos.x - BIRTH_RADIUS, y = pos.y - BIRTH_HEIGHT, z = pos.z - BIRTH_RADIUS}
	local maxp = {x = pos.x + BIRTH_RADIUS, y = pos.y + BIRTH_HEIGHT, z = pos.z + BIRTH_RADIUS}
	local latest
	for _, bed in ipairs(core.find_nodes_in_area(minp, maxp, {"group:bed"})) do
		local node = core.get_node_or_nil(bed)
		if node and core.get_item_group(node.name, "bed") == 1 then
			local top = mcl_beds.get_bed_top(bed)
			if core.get_node_or_nil(top) and core.get_meta(bed):get_string("player") == ""
				and core.get_meta(top):get_string("player") == "" then
				local last = tonumber(core.get_meta(bed):get_string(LAST_BIRTH))
				if last and (not latest or last > latest) then latest = last end
			end
		end
	end
	return latest
end

local function birth_status(villager, pos)
	if villager.child then return "not eligible (child)" end
	local day = core.get_day_count()
	local checked = villager._villages_birth_check_day == day and "checked today" or "not checked today"
	local last = last_local_birth(pos)
	if last and day - last < BIRTH_INTERVAL_DAYS then
		return string.format("%s; local cooldown until day %d", checked, last + BIRTH_INTERVAL_DAYS)
	end
	return checked .. "; no local birth cooldown"
end

local function fish_session_status(villager)
	local session = villager._villages_fish_session
	if not session then return "none" end
	local remaining = math.max((session.phase_ends_at or core.get_gametime()) - core.get_gametime(), 0)
	return string.format("%s (next phase in %.0fs)", session.phase or "unknown", remaining)
end

-- fisherman.lua eliminates these in the same order every tick (session,
-- then following/work-time/water, then route, then target, then the
-- no-water retry cooldown), so this retraces that order to explain why a
-- fisherman is or is not fishing right now -- the other Fisherman lines
-- report the same underlying fields, but none of them says which one is
-- the actual reason.
local function fisherman_status(villager)
	if not villager._villages_fisherman then return "not a fisherman" end
	if villager._villages_fish_session then return "fishing" end
	if not villager._jobsite then return "not fishing: no barrel" end
	if villager.following then return "not fishing: following a player" end
	if not is_work_time(villager) then return "not fishing: waiting for work period" end
	local route = villager._villages_fish_route
	if route and route.status == "travelling" then return "travelling to stand" end
	if route and route.status == "retry" then
		local remaining = math.max((route.retry_at or core.get_gametime()) - core.get_gametime(), 0)
		return string.format("not fishing: waiting %.0fs to retry (%s)", remaining, route.reason or "unknown failure")
	end
	if villager._villages_fish_target then return "not fishing: has a stand but no active session" end
	if villager._villages_fish_next and core.get_gametime() < villager._villages_fish_next then
		return "not fishing: no reachable water found nearby, retrying soon"
	end
	return "not fishing: no stand chosen yet"
end

local function barrel_status(villager)
	if not villager._villages_fisherman then return "n/a (not a fisherman)" end
	if not villager._jobsite then return "none assigned" end
	local node = core.get_node_or_nil(villager._jobsite)
	if node and node.name ~= "mcl_barrels:barrel_closed" then
		return "assigned node is not a barrel (" .. node.name .. ")"
	end
	return status_of_claim(villager._jobsite, villager._id, "jobsite")
end

-- Used only to explain per-candidate why a fishing anchor near a fisherman was,
-- or was not, accepted -- not to alter anything. cells.lua is the classifier
-- navigation.lua and fisherman.lua use.
local function fish_is_open(pos, thin)
	return cells.is_open(pos, thin and {thin = true} or nil)
end

local FISH_OFFSET_LABELS = {"+x", "-x", "+z", "-z"}
-- navigation.lua's raised_ok checks the anchor's own height first, then one
-- above it: a natural shore commonly meets the water at the water's own
-- height (its walkable ground, and the stand on it, is the block above).
local FISH_HEIGHTS = {{dy = 0, label = "water-level"}, {dy = 1, label = "+1"}}

local function describe_fish_height(anchor, offset, dy)
	local candidate = {x = anchor.x + offset[1], y = anchor.y + dy, z = anchor.z + offset[2]}
	local above = {x = candidate.x, y = candidate.y + 1, z = candidate.z}
	local reasons = {}
	if not fish_is_open(candidate, true) then
		table.insert(reasons, "not open (" .. node_name(candidate) .. ")")
	end
	if not fish_is_open(above) then
		table.insert(reasons, "blocked above (" .. node_name(above) .. ")")
	end
	if not cells.has_floor(candidate) then
		local support = {x = candidate.x, y = candidate.y - 1, z = candidate.z}
		table.insert(reasons, "not supported (" .. node_name(support) .. ")")
	end
	if #reasons == 0 then return true, "open approach" end
	return false, table.concat(reasons, "; ")
end

local function describe_fish_offset(anchor, offset, label)
	local parts = {}
	for _, height in ipairs(FISH_HEIGHTS) do
		local ok, detail = describe_fish_height(anchor, offset, height.dy)
		table.insert(parts, height.label .. ": " .. detail)
		if ok then break end
	end
	return label .. " (" .. table.concat(parts, "; ") .. ")"
end

local function fish_has_open_approach(pos)
	for _, offset in ipairs(WATER_NEIGHBOR_OFFSETS) do
		for _, dy in ipairs({0, 1}) do
			local candidate = {x = pos.x + offset[1], y = pos.y + dy, z = pos.z + offset[2]}
			if cells.is_open(candidate, {thin = true})
				and cells.is_open({x = candidate.x, y = candidate.y + 1, z = candidate.z})
				and cells.has_floor(candidate) then
				return true
			end
		end
	end
	return false
end

-- The nearest qualifying fishing anchor within fisherman.lua's own search
-- box, broken down candidate by candidate, so this cannot name a tile that
-- the daily pond check rejects.
local function nearest_fish_candidate(pos)
	if not pos or not core.find_nodes_in_area then return "unavailable" end
	local minp = {x = pos.x - FISH_SEARCH_RADIUS, y = pos.y - FISH_BELOW_BAND, z = pos.z - FISH_SEARCH_RADIUS}
	local maxp = {x = pos.x + FISH_SEARCH_RADIUS, y = pos.y + FISH_ABOVE_BAND, z = pos.z + FISH_SEARCH_RADIUS}
	local candidates = {}
	local pond_verdicts, pond_states = {}, {}
	for _, site in ipairs(core.find_nodes_in_area(minp, maxp, {"group:water"})) do
		if common.is_surface_water(site) and fish_has_open_approach(site) then
			candidates[#candidates + 1] = site
		end
	end
	table.sort(candidates, function(a, b) return distance(pos, a) < distance(pos, b) end)
	local remaining = common.fishing_pond_search_cap
	for _, site in ipairs(candidates) do
		local key = site.x .. ":" .. site.y .. ":" .. site.z
		if pond_verdicts[key] == nil then
			local state = pond_states[key]
			local previous_head = state and state.head or 1
			local tiles, qualifies, complete, next_state = common.measure_fishing_pond(site, minp, maxp, state, remaining)
			remaining = remaining - ((next_state.head or previous_head) - previous_head)
			if complete then
				for tile_key in pairs(tiles) do pond_verdicts[tile_key] = qualifies end
			else
				for _, tile in ipairs(next_state.added) do
					pond_states[tile.x .. ":" .. tile.y .. ":" .. tile.z] = next_state
				end
			end
		end
		if remaining <= 0 then break end
	end
	local best, best_index
	for i, site in ipairs(candidates) do
		local key = site.x .. ":" .. site.y .. ":" .. site.z
		if pond_verdicts[key] then
			best, best_index = site, i
			break
		end
	end
	if not best then
		for _, site in ipairs(candidates) do
			local key = site.x .. ":" .. site.y .. ":" .. site.z
			if pond_verdicts[key] == nil then return "bounded pond search incomplete; qualifying status unknown" end
		end
		return "no qualifying, approachable fishing pond found in range"
	end
	local lines = {}
	for i, offset in ipairs(WATER_NEIGHBOR_OFFSETS) do
		table.insert(lines, describe_fish_offset(best, offset, FISH_OFFSET_LABELS[i]))
	end
	local closer_incomplete = false
	for i = 1, best_index - 1 do
		local site = candidates[i]
		if pond_verdicts[site.x .. ":" .. site.y .. ":" .. site.z] == nil then
			closer_incomplete = true
			break
		end
	end
	return string.format("%s [qualifying pond anchor%s] %s",
		pos_string(best), closer_incomplete and "; closer pond search incomplete" or "", table.concat(lines, " | "))
end

local function inspectable_node(pos)
	local node = core.get_node_or_nil(pos)
	if not node then return nil end
	local bed_group = core.get_item_group(node.name, "bed")
	if bed_group == 2 then
		local dir = core.facedir_to_dir(node.param2)
		pos = {x = pos.x - dir.x, y = pos.y - dir.y, z = pos.z - dir.z}
		node = core.get_node_or_nil(pos)
		if not node then return nil end
		bed_group = node and core.get_item_group(node.name, "bed") or 0
	end
	if bed_group == 1 then return "bed", pos, node end
	if is_jobsite_node(node.name) then
		return "workstation", pos, node
	end
end

local function show_form(player, name, lines)
	local form = "formspec_version[4]size[11,8]" ..
		"textarea[0.35,0.3;10.3,6.9;report;;" .. core.formspec_escape(table.concat(lines, "\n")) .. "]" ..
		"button_exit[4,7.35;3,0.5;close;Close]"
	core.show_formspec(player:get_player_name(), name, form)
end

local function visual_status(villager)
	local props = villager.object and villager.object:get_properties()
	if not props then return "unavailable (no live properties)" end
	local textures = props.textures and table.concat(props.textures, ", ") or "none"
	local size = props.visual_size
	local size_string = size and string.format("(%.2f, %.2f, %.2f)",
		size.x or 0, size.y or 0, size.z or (size.y or 0)) or "none"
	return string.format("mesh %s, textures [%s], visual_size %s, is_visible %s",
		props.mesh or "none", textures, size_string,
		props.is_visible == nil and "true (default)" or tostring(props.is_visible))
end

-- What cells.lua, the one passability model (#161), says about the cell a
-- villager's feet are in and the one it is walking to.
local function cell_status(pos)
	if not pos then return "none" end
	local cell = {x = math.floor(pos.x + 0.5), y = math.floor(pos.y + 0.5), z = math.floor(pos.z + 0.5)}
	local text, standable = cells.describe(cell)
	return pos_string(cell) .. (standable and " standable: " or " NOT standable: ") .. text
end

local function show(player, villager)
	local bed_ok = bed_status(villager) == "valid claim"
	local job_ok = status_of_claim(villager._jobsite, villager._id, "jobsite") == "valid claim"
	local pos = villager.object and villager.object:get_pos()
	local path_count = type(villager.waypoints) == "table" and #villager.waypoints or 0
	local profession = villager._profession or "unemployed"
	local age = villager.child and "child" or "adult"
	local birth_check = birth_status(villager, pos)
	local lines = {
		"Villager diagnostics (read-only)",
		"",
		"ID: " .. (villager._id or "unknown"),
		"Profession: " .. profession .. "    Age: " .. age,
		"State: " .. (villager.state or "none") .. "    Order: " .. (villager.order or "none"),
		"Sleep pose: " .. (villager._villages_sleeping and "yes" or "no"),
		"Position: " .. pos_string(pos),
		"Visual: " .. visual_status(villager),
		"",
		"Bed: " .. pos_string(villager._bed) .. " [" .. node_name(villager._bed) .. "]",
		"Bed owner: " .. claim_owner(villager._bed, villager, "bed"),
		"Bed claim: " .. bed_status(villager),
		"Sleep status: " .. sleep_status(villager, bed_ok),
		"Bed route: " .. route_status(villager._villages_bed_route),
		"Planner: " .. planner_status(villager._villages_bed_route),
		"Planner trail: " .. planner_trail(villager._villages_bed_route),
		"",
		"Jobsite: " .. pos_string(villager._jobsite) .. " [" .. node_name(villager._jobsite) .. "]",
		"Jobsite owner: " .. claim_owner(villager._jobsite, villager, "jobsite"),
		"Jobsite claim: " .. status_of_claim(villager._jobsite, villager._id, "jobsite"),
		"Work status: " .. work_status(villager, job_ok),
		"Flock: " .. (flock_status and flock_status(villager) or "off"),
		"Farm: " .. (farmer and farmer.status(villager) or "off"),
		"Farm pouch: " .. (farmer and farmer.pouch_status(villager) or "off"),
		"Food: " .. math.floor(food.points(villager) * 10 + 0.5) / 10 .. " points (" .. food.state(villager) .. ")",
		"Economic clock: " .. math.floor(economy_clock.read(villager)) .. " s",
		"Belongings: " .. possessions.status(villager),
		"Stash: " .. possessions.stash_status(villager),
		"Needs: " .. (select(1, possessions.ledger_status(villager))),
		"Surplus: " .. (select(2, possessions.ledger_status(villager))),
		"Gossip: " .. (gossip and gossip.status(villager) or "off"),
		"Market news: " .. market_news.status(villager),
		"Labour: " .. labour.status(villager),
		"Crafting: " .. production.status(villager),
		"Jobsite route: " .. route_status(villager._villages_job_route),
		"Jobsite planner: " .. planner_status(villager._villages_job_route),
		"Jobsite planner trail: " .. planner_trail(villager._villages_job_route),
		"Job search route: " .. route_status(villager._villages_job_search_route),
		"Job-search queue: " .. (workstation_search_status(villager, villager._villages_job_search_route) or "not planning"),
		"Job-search planner: " .. planner_status(villager._villages_job_search_route),
		"Job-search planner trail: " .. planner_trail(villager._villages_job_search_route),
		"",
		"Fisherman flag: " .. (villager._villages_fisherman and "yes" or "no"),
		"Fishing status: " .. fisherman_status(villager),
		"Fish target: " .. pos_string(villager._villages_fish_target),
		"Fish route: " .. route_status(villager._villages_fish_route),
		"Fish planner: " .. planner_status(villager._villages_fish_route),
		"Fish planner trail: " .. planner_trail(villager._villages_fish_route),
		"Fishing session: " .. fish_session_status(villager),
		"Nearest fish candidate to the barrel: "
			.. (villager._villages_fisherman and (villager._jobsite and nearest_fish_candidate(villager._jobsite) or "no barrel")
				or "n/a (not a fisherman)"),
		"Barrel claim: " .. barrel_status(villager),
		"Composter sought: " .. pos_string(villager._villages_farm_seek),
		"",
		"Holiday: " .. (common.is_holiday() and "yes" or "no")
			.. ", stage " .. common.schedule_stage(nil, villager),
		"Keeper: " .. keeper.status(villager),
		"Cleric: " .. cleric.status(villager),
		"Builder: " .. (builder and builder.status(villager) or "off"),
		"Tavern visit: " .. (villager._villages_tavern_arrived and "at the tavern"
			or villager._villages_tavern_target and ("heading to " .. pos_string(villager._villages_tavern_target))
			or "none"),
		"Tavern route: " .. route_status(villager._villages_tavern_route),
		"Tavern seat: " .. seat.status(villager),
		"Tavern meal: " .. (villager._villages_meal and ("eating " .. villager._villages_meal.item)
			or villager._villages_meal_day == core.get_day_count() and "has eaten tonight" or "not served tonight"),
		"",
		"Cell: " .. cell_status(pos and {x = pos.x, y = common.feet_node(pos), z = pos.z}),
		"Next cell: " .. cell_status(villager.current_target and villager.current_target.pos),
		"Path target: " .. target_string(villager._target) .. "    Waypoints: " .. path_count,
		"Last walk failure: " .. walk_failure_string(villager._villages_last_walk_failure),
		"Births: " .. birth_check,
	}
	show_form(player, "living_villages:diagnostic", lines)
end

local function show_node(player, kind, pos, node)
	local label = kind == "bed" and "Bed" or "Workstation"
	local lines = {
		label .. " diagnostics (read-only)",
		"",
		"Position: " .. pos_string(pos),
		"Node: " .. node.name,
		"Recorded owner: " .. claim_owner(pos, nil, kind),
	}
	local owner = claim_owner_entity(pos, kind)
	if owner then
		local owner_pos = owner.object and owner.object:get_pos()
		table.insert(lines, "Owner position: " .. pos_string(owner_pos))
		if kind == "bed" then
			local bed_ok = bed_status(owner) == "valid claim"
			table.insert(lines, "Owner sleep status: " .. sleep_status(owner, bed_ok))
		else
			local job_ok = status_of_claim(owner._jobsite, owner._id, "jobsite") == "valid claim"
			table.insert(lines, "Owner work status: " .. work_status(owner, job_ok))
			if owner._villages_keeper then
				table.insert(lines, "Keeper: " .. keeper.status(owner))
			end
		end
	end
	table.insert(lines, "")
	table.insert(lines, "Owner resolution is limited to villagers loaded within 64 nodes.")
	show_form(player, "living_villages:" .. kind .. "_diagnostic", lines)
end

local function permitted(player)
	if not player or not player:is_player() or not core.check_player_privs then return false end
	local name = player:get_player_name()
	return core.check_player_privs(name, {server = true})
		or core.check_player_privs(name, {debug = true})
end

local function install(_, flock, nav_api, farm_module, gossip_module, builder_module)
	builder = builder_module
	flock_status = flock and flock.status
	farmer = farm_module
	gossip = gossip_module
	navigation_api = nav_api
	local items = core.registered_items or {}
	for _, name in ipairs({"doc_identifier:identifier_solid", "doc_identifier:identifier_liquid"}) do
		local item = items[name]
		if item and item.on_use then
			local original = item.on_use
			local wrapped = function(stack, player, pointed_thing)
				if permitted(player) and pointed_thing then
					if pointed_thing.type == "object" then
						local object = pointed_thing.ref
						local villager = object and object:get_luaentity()
						if villager and villager.name == "mobs_mc:villager" then
							show(player, villager)
							return stack
						end
					elseif pointed_thing.type == "node" then
						local kind, pos, node = inspectable_node(pointed_thing.under)
						if kind then
							show_node(player, kind, pos, node)
							return stack
						end
					end
				end
				return original(stack, player, pointed_thing)
			end
			if core.override_item then
				core.override_item(name, {on_use = wrapped})
			else
				item.on_use = wrapped
			end
		end
	end
end

return install
