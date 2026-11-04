-- The Builder's data on the real engine, for what the stubbed tests cannot show. After a
-- village is built this waits for the house's ABM and records: the bench, the double chest
-- and their inventories; any item a stock building costs that is not registered; and, for
-- every building of the village, each cell where what building_template.lua predicts
-- differs from what the generator placed, so that the rotated cells a Builder works from
-- are known to be the real ones. Then, with the clock held at work and villagers kept awake,
-- it sets each bench's project to a building (lv_probe_builder_building, by default a small
-- house, which has a door and a bed) and follows it: who claimed the bench, the site, what the status window reports, and, with the
-- bill put in the chests, whether what stands afterwards is what the template says, to the
-- param2. Only runs when lv_probe_builder is set.
local core = minetest

local builder = {}

local WAIT_SECONDS = 30
local SAMPLES = 8
local VILLAGER = "mobs_mc:villager"
local BENCH = "living_villages:builder_block"
local WATCH_SECONDS = 150
local DEFAULT_BUILD_SECONDS = 1500
local DEFAULT_BUILDING = "small_house"
local WATCH_STEP = 5
local WORK_TIME = 0.4

function builder.enabled()
	return (tonumber(core.settings:get("lv_probe_builder")) or 0) > 0
end

local function modules()
	local path = core.get_modpath("living_villages")
	return dofile(path .. "/builder_materials.lua"), dofile(path .. "/building_template.lua")
end

local function entry_of(name)
	for _, entry in ipairs(settlements.schematic_table) do
		if entry.name == name then return entry end
	end
end

local function pos_text(pos) return core.pos_to_string(pos) end

-- Costs that name no registered item, over every building and surface.
local function unknown_items(materials, template)
	local unknown, seen = {}, {}
	for _, entry in ipairs(settlements.schematic_table) do
		for surface in pairs(settlements.surface_mat) do
			local schematic = template.prepare_schematic(entry, surface)
			for _, cell in ipairs(schematic and schematic.data or {}) do
				if not seen[cell.name] then
					seen[cell.name] = true
					if cell.name ~= "air" and not core.registered_nodes[materials.placed(cell.name)] then
						unknown["node " .. materials.placed(cell.name)] = cell.name
					end
					for item in pairs(materials.cost(cell.name) or {}) do
						if not core.registered_items[item] then unknown[item] = cell.name end
					end
					for item in pairs(materials.returns(cell.name) or {}) do
						if not core.registered_items[item] then unknown[item] = cell.name end
					end
				end
			end
		end
	end
	for item in pairs(materials.SALES) do
		if not core.registered_items[item] then unknown[item] = "on sale" end
	end
	return unknown
end

-- Each cell of a building where the prediction and the map differ.
local function compare_building(building, template)
	local entry = entry_of(building.name)
	if not entry then return {error = "no schematic_table entry"} end
	local schematic = template.prepare_schematic(entry, building.surface_mat)
	if not schematic then return {error = "cannot read the schematic"} end
	local cells = template.world_cells(schematic, building.pos, building.rotat)
	if not cells then return {error = "cannot place it on a VoxelManip"} end
	local result = {name = building.name, rotat = building.rotat, cells = #cells, wrong = 0, wrong_param2 = 0, kinds = {}, samples = {}}
	for _, cell in ipairs(cells) do
		local node = core.get_node(cell.pos)
		-- The generator swaps ground in and out per building (ground_layer.lua, loomless_house.lua).
		if cell.pos.y ~= building.pos.y then
			if node.name ~= cell.name then
				result.wrong = result.wrong + 1
				local kind = cell.name .. " -> " .. node.name
				result.kinds[kind] = (result.kinds[kind] or 0) + 1
			elseif node.param2 ~= cell.param2 then
				result.wrong_param2 = result.wrong_param2 + 1
				local kind = cell.name .. " param2"
				result.kinds[kind] = (result.kinds[kind] or 0) + 1
				if #result.samples < SAMPLES then
					result.samples[#result.samples + 1] = pos_text(cell.pos) .. " " .. cell.name
						.. " wants " .. cell.param2 .. " has " .. node.param2
				end
			end
		end
	end
	return result
end

-- The Builder's house: the bench, and each chest near it with its inventory.
local function search_box(info)
	local minp, maxp
	for _, building in ipairs(info) do
		local low, high = vector.offset(building.pos, -2, -2, -2), vector.offset(building.pos, 16, 16, 16)
		minp = minp and {x = math.min(minp.x, low.x), y = math.min(minp.y, low.y), z = math.min(minp.z, low.z)} or low
		maxp = maxp and {x = math.max(maxp.x, high.x), y = math.max(maxp.y, high.y), z = math.max(maxp.z, high.z)} or high
	end
	return minp, maxp
end

local function check_houses(info)
	local houses = {}
	local minp, maxp = search_box(info)
	for _, bench in ipairs(core.find_nodes_in_area(minp, maxp, {"living_villages:builder_block"})) do
		local chests = {}
		local low, high = vector.offset(bench, -6, -2, -6), vector.offset(bench, 6, 2, 6)
		for _, pos in ipairs(core.find_nodes_in_area(low, high, {"mcl_chests:chest_small", "mcl_chests:chest_left", "mcl_chests:chest_right"})) do
			local node = core.get_node(pos)
			chests[#chests + 1] = {
				pos = pos_text(pos), name = node.name, param2 = node.param2,
				size = core.get_meta(pos):get_inventory():get_size("main"),
			}
		end
		houses[#houses + 1] = {bench = pos_text(bench), chests = chests}
	end
	return houses
end

core.register_on_mods_loaded(function()
	if not builder.enabled() then return end
	-- The server has no player, so mcl_mobs would freeze everything.
	local class = mcl_mobs.mob_class
	local original = class.player_in_active_range
	class.player_in_active_range = function(self, ...)
		if self.name == VILLAGER then return true end
		return original(self, ...)
	end
	-- No holiday: the clock is held in the work stage of an ordinary day.
	if mcl_moon then mcl_moon.get_moon_phase = function() return 1 end end
end)

local function villager_with_id(pos, id)
	for _, object in ipairs(core.get_objects_inside_radius(pos, 64)) do
		local entity = object:get_luaentity()
		if entity and entity.name == VILLAGER and entity._id == id then return entity end
	end
end

-- Everyone about the bench, as it might matter who did not claim it and why.
local function people_near(pos)
	local people = {}
	for _, object in ipairs(core.get_objects_inside_radius(pos, 64)) do
		local entity = object:get_luaentity()
		if entity and entity.name == VILLAGER then
			people[#people + 1] = {
				id = entity._id, profession = entity._profession, child = entity.child or nil,
				bed = entity._bed and pos_text(entity._bed) or nil,
				jobsite = entity._jobsite and pos_text(entity._jobsite) or nil,
				seek = entity._villages_farm_seek and pos_text(entity._villages_farm_seek) or nil,
			}
		end
	end
	return people
end

-- What one bench came to.
local function bench_outcome(bench, roles, status_module)
	local owner = core.get_meta(bench):get_string("villager")
	local outcome = {
		bench = pos_text(bench), owner = owner ~= "" and owner or nil, people = people_near(bench),
		project = roles.load_project(bench),
	}
	local entity = owner ~= "" and villager_with_id(bench, owner)
	if entity then
		outcome.flag, outcome.profession, outcome.trades = entity._villages_builder, entity._profession, entity._trades
		local report = roles.report(entity)
		outcome.report = report
		outcome.form_bytes = #status_module.formspec(report)
	end
	return outcome
end

-- Puts the whole bill in the chests by the bench, as a player would.
local function stock_chests(bench, report)
	local chests = core.find_nodes_in_area(vector.offset(bench, -6, -2, -6), vector.offset(bench, 6, 2, 6),
		{"mcl_chests:chest_left", "mcl_chests:chest_right", "mcl_chests:chest_small"})
	local lost = {}
	for _, row in ipairs(report.rows or {}) do
		local left = row.need
		for _, chest in ipairs(chests) do
			if left > 0 then
				local stack = core.get_meta(chest):get_inventory():add_item("main", row.item .. " " .. left)
				left = stack:get_count()
			end
		end
		if left > 0 then lost[row.item] = left end
	end
	return lost
end

-- Gives a level site something to do: a dirt bump on its floor and a dip in it, in the
-- middle where a site's search would have allowed them, and the project's list of them.
local function roughen(bench, project)
	local at = project.pos
	local bump = {x = at.x + 1, y = at.y + 1, z = at.z + 1}
	local dip = {x = at.x + 2, y = at.y, z = at.z + 1}
	core.set_node(bump, {name = "mcl_core:dirt"})
	core.remove_node(dip)
	project.earthwork = {cuts = {bump}, fills = {dip}}
	core.get_meta(bench):set_string("villages_project", core.serialize(project))
end

-- Each cell where the finished building differs from its template: what the Builder placed
-- against what the same plan asks for.
local function check_built(project, template)
	local entry = entry_of(project.building)
	local schematic = template.prepare_schematic(entry, project.surface_mat)
	local cells = template.world_cells(schematic, project.pos, project.rotat)
	local plan = template.plan(cells, {
		floor_y = project.pos.y, surface_mat = project.surface_mat, earthwork = project.earthwork,
	})
	local missing, blocked = template.compare(plan, function(pos) return core.get_node(pos).name end)
	local result = {left = #missing, blocked = #blocked, wrong_param2 = 0, samples = {}, cells = {}}
	-- What it has not done, what is there instead, and who stands around it.
	for i = 1, math.min(#missing, SAMPLES) do
		local step = missing[i]
		local near = {}
		for _, object in ipairs(core.get_objects_inside_radius(step.pos, 2.5)) do
			local entity = object:get_luaentity()
			near[#near + 1] = (entity and entity.name or "player") .. " " .. pos_text(vector.round(object:get_pos()))
		end
		result.cells[i] = {
			pos = pos_text(step.pos), kind = step.kind, pass = step.pass, want = step.node and step.node.name,
			found = core.get_node(step.pos).name, near = near,
		}
	end
	for _, step in ipairs(plan.steps) do
		if step.kind == "place" then
			local node = core.get_node(step.pos)
			if node.param2 ~= step.node.param2 then
				result.wrong_param2 = result.wrong_param2 + 1
				if #result.samples < SAMPLES then
					result.samples[#result.samples + 1] = pos_text(step.pos) .. " " .. step.node.name
						.. " wants " .. step.node.param2 .. " has " .. node.param2
				end
			end
		end
	end
	return result
end

-- A flat, clear piece of ground beside the bench, as a player makes for a Builder with no
-- site. It may cut into what stands there: this world is thrown away.
local function make_platform(bench)
	local size = 24
	local x0, z0 = bench.x + 10, bench.z + 10
	-- Anyone standing there would be buried.
	for _, object in ipairs(core.get_objects_inside_radius(bench, 80)) do
		local at, entity = object:get_pos(), object:get_luaentity()
		if entity and entity.name == VILLAGER and at.x >= x0 - 13 and at.x <= x0 + size + 13
			and at.z >= z0 - 13 and at.z <= z0 + size + 13 then
			object:set_pos(vector.offset(bench, 0, 1, 0))
		end
	end
	for x = x0, x0 + size do
		for z = z0, z0 + size do
			for y = bench.y - 6, bench.y - 1 do
				core.set_node({x = x, y = y, z = z}, {name = "mcl_core:dirt"})
			end
			core.set_node({x = x, y = bench.y, z = z}, {name = "mcl_core:dirt_with_grass"})
			for y = bench.y + 1, bench.y + 24 do
				core.remove_node({x = x, y = y, z = z})
			end
		end
	end
	-- Slopes up to it, or a Builder could not walk onto it.
	for x = x0 - 12, x0 + size + 12 do
		for z = z0 - 12, z0 + size + 12 do
			local away = math.max(x0 - x, x - x0 - size, z0 - z, z - z0 - size)
			if away > 0 then
				local top = bench.y - away
				for y = top, top - 12, -1 do
					local name = core.get_node({x = x, y = y, z = z}).name
					if name == "air" or name:find("leaves", 1, true) then
						core.set_node({x = x, y = y, z = z}, {name = y == top and "mcl_core:dirt_with_grass" or "mcl_core:dirt"})
					elseif y < top then
						break
					end
				end
			end
		end
	end
end

-- Follows every bench through its project, or until time is up.
local function watch(area, record, emit, done)
	local path = core.get_modpath("living_villages")
	local roles = dofile(path .. "/builder.lua")
	local _, template = modules()
	-- Only for formspec(): this copy's window is never shown, so its handler has no state.
	local status_module = dofile(path .. "/builder_status.lua")
	local benches = core.find_nodes_in_area(area.minp, area.maxp, {BENCH})
	local started = core.get_gametime()
	local outcomes, sited = {}, {}
	for _, bench in ipairs(benches) do
		if core.settings:get_bool("lv_probe_builder_platform", false) then make_platform(bench) end
		core.get_meta(bench):set_string("villages_project",
			core.serialize({state = "finding_site", building = core.settings:get("lv_probe_builder_building") or DEFAULT_BUILDING}))
	end
	local function finish()
		record.benches = {}
		for i, bench in ipairs(benches) do
			local outcome = outcomes[i] or bench_outcome(bench, roles, status_module)
			if sited[i] then
				outcome.built = check_built(sited[i], template)
				for _, cell in ipairs(sited[i].earthwork and sited[i].earthwork.fills or {}) do
					outcome.filled = core.get_node(cell).name
				end
				outcome.after = roles.load_project(bench)
			end
			record.benches[#record.benches + 1] = outcome
		end
		record.watched_seconds = core.get_gametime() - started
		core.log("action", string.format("[lv_builder] %d benches followed for %d s",
			#benches, record.watched_seconds))
		emit(record)
		done()
	end
	local function step()
		core.set_timeofday(WORK_TIME)
		local waiting = false
		local limit = WATCH_SECONDS
		for i, bench in ipairs(benches) do
			local project = roles.load_project(bench)
			if sited[i] then
				limit = WATCH_SECONDS + (tonumber(core.settings:get("lv_probe_builder_build_seconds")) or DEFAULT_BUILD_SECONDS)
				-- It moves on to another building, at another site, when this one is done.
				if project and project.pos and vector.equals(project.pos, sited[i].pos)
					and project.state ~= "returning" then
					waiting = true
				end
				if project then outcomes[i].last_state = project.state end
			elseif project and project.state == "requires_materials" and project.pos then
				-- Waited for its first look at the materials, so the bill reads as a player sees it.
				local outcome = bench_outcome(bench, roles, status_module)
				outcomes[i] = outcome
				if outcome.report then
					if core.settings:get_bool("lv_probe_builder_earthwork", false) then roughen(bench, project) end
					outcome.not_stocked = stock_chests(bench, outcome.report)
					sited[i] = project
					waiting = true
				end
			else
				waiting = project == nil or project.state ~= "no_site"
			end
		end
		if not waiting or core.get_gametime() - started >= limit then return finish() end
		for i, bench in ipairs(benches) do
			local owner = core.get_meta(bench):get_string("villager")
			local entity = owner ~= "" and villager_with_id(bench, owner)
			if entity and sited[i] then
				local trail = outcomes[i].trail or {}
				outcomes[i].trail = trail
				local at = pos_text(vector.round(entity.object:get_pos()))
				if trail[#trail] ~= at then trail[#trail + 1] = at end
				while #trail > 12 do table.remove(trail, 1) end
				outcomes[i].pouch = entity._villages_farm_pouch
			end
		end
		core.after(WATCH_STEP, step)
	end
	step()
end

function builder.run(_, info, emit, done)
	local materials, template = modules()
	core.after(WAIT_SECONDS, function()
		local record = {
			probe = "builder",
			houses = check_houses(info),
			unknown = unknown_items(materials, template),
			buildings = {},
		}
		local wrong = 0
		for _, building in ipairs(info) do
			local result = compare_building(building, template)
			record.buildings[#record.buildings + 1] = result
			wrong = wrong + (result.wrong or 0) + (result.wrong_param2 or 0)
		end
		core.log("action", string.format("[lv_builder] %d houses, %d buildings, %d cells differ",
			#record.houses, #record.buildings, wrong))
		local minp, maxp = search_box(info)
		watch({minp = minp, maxp = maxp}, record, emit, done)
	end)
end

return builder
