-- Farmers at work on the real game: VoxeLibre's own crops, composter, bone meal and
-- chests, with the mod's planner, which the stubbed tests cannot show. After a village
-- is built this raises a walled platform over it, away from everything else, and sets up
-- two farms: the stock farm schematic, and a composter on bare dirt beside water, with
-- a few hungry villagers. The clock is held in the work stage. Every 20 s the record notes
-- what each farm holds. Partway the bare farm's farmer is given bone meal, then a chest
-- with bread in it appears in range and the stock farmer is given a surplus to store,
-- and near the end that farmer's claim goes, as when it dies. Only runs when
-- lv_probe_farm is set.
local core = minetest

local farm = {}

local VILLAGER = "mobs_mc:villager"
local COMPOSTER = "mcl_composters:composter"
local CHEST = "mcl_chests:chest_small"
local WORK_TIME = 0.33
local SIZE = 44
local HEADROOM = 6
local SAMPLE_SECONDS = 20
local BONE_MEAL_AT = 120
local CHEST_AT = 240
-- After a farmer's next look for chests, or it composts the surplus before it knows of one.
local SURPLUS_AT = 310
local UNCLAIM_AT = 400
local END_AT = 520

function farm.enabled()
	return (tonumber(core.settings:get("lv_probe_farm")) or 0) > 0
end

local costs = {n = 0, s = 0, worst = 0}

core.register_on_mods_loaded(function()
	if not farm.enabled() then return end
	-- The server has no player, so mcl_mobs would freeze everything.
	local class = mcl_mobs.mob_class
	local original = class.player_in_active_range
	class.player_in_active_range = function(self, ...)
		if self.name == VILLAGER then return true end
		return original(self, ...)
	end
	-- No holiday: the clock is held in the work stage of an ordinary day.
	if mcl_moon then mcl_moon.get_moon_phase = function() return 1 end end
	local def = core.registered_entities[VILLAGER]
	local custom = def.do_custom
	def.do_custom = function(self, dtime)
		local start = os.clock()
		local result = custom(self, dtime)
		local spent = os.clock() - start
		if self._profession == "farmer" then
			costs.n, costs.s = costs.n + 1, costs.s + spent
			costs.worst = math.max(costs.worst, spent)
		end
		return result
	end
end)

local function round3(v) return math.floor(v * 1000 + 0.5) / 1000 end

-- The site's forceloaded blocks stop below the platform, so it holds its own, or the
-- farmers would be unloaded with it.
local BLOCK = 16
local function forceload_platform(origin)
	local blocks = {}
	for x = origin.x, origin.x + SIZE + BLOCK, BLOCK do
		for y = origin.y, origin.y + HEADROOM + BLOCK, BLOCK do
			for z = origin.z, origin.z + SIZE + BLOCK, BLOCK do
				local block = {x = x, y = y, z = z}
				if core.forceload_block(block, true) then blocks[#blocks + 1] = block end
			end
		end
	end
	return blocks
end

-- A walled platform high over the village's centre.
local function build_platform(area)
	local cx, cz = math.floor((area.x1 + area.x2) / 2), math.floor((area.z1 + area.z2) / 2)
	local y = area.y2 - HEADROOM - 1
	local origin = {x = cx - SIZE / 2, y = y, z = cz - SIZE / 2}
	forceload_platform(origin)
	for dx = 0, SIZE do
		for dz = 0, SIZE do
			local rim = dx == 0 or dz == 0 or dx == SIZE or dz == SIZE
			core.set_node({x = origin.x + dx, y = y, z = origin.z + dz}, {name = "mcl_core:stone"})
			for dy = 1, HEADROOM do
				core.set_node({x = origin.x + dx, y = y + dy, z = origin.z + dz},
					{name = rim and dy <= 3 and "mcl_core:stone" or "air"})
			end
		end
	end
	return origin
end

local function spawn(pos, id, profession, jobsite, pouch)
	local object = core.add_entity(pos, VILLAGER)
	local entity = object and object:get_luaentity()
	if not entity then return nil end
	entity._id, entity._profession = id, profession
	if jobsite then
		entity._jobsite = jobsite
		core.get_meta(jobsite):set_string("villager", id)
	end
	entity._villages_farm_pouch = pouch
	return entity
end

local function build_scene(origin)
	-- The stock farm, its ground one above the platform; the composter is at (4, 2, 0).
	local stock_at = {x = origin.x + 4, y = origin.y + 1, z = origin.z + 4}
	local mts = core.get_modpath("mcl_villages") .. "/schematics/farm.mts"
	core.place_schematic(stock_at, mts, "0", nil, true)
	local stock_job = {x = stock_at.x + 4, y = stock_at.y + 2, z = stock_at.z}
	-- A way up onto the kerb, level with the crops.
	for dx = 0, 8 do
		core.set_node({x = stock_at.x + dx, y = stock_at.y + 1, z = stock_at.z - 1}, {name = "mcl_core:stone"})
		core.set_node({x = stock_at.x + dx, y = stock_at.y, z = stock_at.z - 2}, {name = "mcl_core:stone"})
	end
	local stock_farmer = spawn({x = stock_job.x + 1, y = stock_job.y, z = stock_job.z - 1},
		"probe-stock-farmer", "farmer", stock_job, {["mcl_farming:wheat_seeds"] = 40})

	-- A composter on bare dirt beside water, away from anything tilled.
	local bare_at = {x = origin.x + 26, y = origin.y, z = origin.z + 8}
	for dx = -6, 6 do
		for dz = -6, 6 do
			core.set_node({x = bare_at.x + dx, y = bare_at.y, z = bare_at.z + dz}, {name = "mcl_core:dirt_with_grass"})
		end
	end
	core.set_node({x = bare_at.x + 2, y = bare_at.y, z = bare_at.z + 2}, {name = "mcl_core:water_source"})
	core.set_node({x = bare_at.x - 2, y = bare_at.y, z = bare_at.z + 3}, {name = "mcl_core:grass_path"})
	local bare_job = {x = bare_at.x, y = bare_at.y + 1, z = bare_at.z}
	core.set_node(bare_job, {name = COMPOSTER})
	local bare_farmer = spawn({x = bare_job.x + 1, y = bare_job.y, z = bare_job.z}, "probe-bare-farmer", "farmer",
		bare_job, {["mcl_farming:potato_item"] = 12, ["mcl_farming:beetroot_seeds"] = 12})

	local hungry = {}
	for i = 1, 3 do
		hungry[i] = spawn({x = origin.x + 10 + i * 3, y = origin.y + 1, z = origin.z + 30}, "probe-hungry-" .. i, "unemployed")
	end
	return {
		farms = {
			{name = "stock", job = stock_job, farmer = stock_farmer},
			{name = "bare", job = bare_job, farmer = bare_farmer},
		},
		hungry = hungry,
		chest = {x = origin.x + 16, y = origin.y + 1, z = origin.z + 8},
	}
end

local function count_nodes(job, names)
	local radius = 8
	local found = core.find_nodes_in_area({x = job.x - radius, y = job.y - 3, z = job.z - radius},
		{x = job.x + radius, y = job.y + 2, z = job.z + radius}, names)
	return #found
end

local MATURE = {"mcl_farming:wheat", "mcl_farming:potato", "mcl_farming:carrot", "mcl_farming:beetroot"}
local GROWING = {"group:plant"}

local function sample(scene, t)
	local record = {t = t, farms = {}, hungry = {}}
	for _, site in ipairs(scene.farms) do
		local e = site.farmer
		local alive = e and e.object and e.object:get_pos() ~= nil
		local pos = alive and e.object:get_pos()
		record.farms[site.name] = {
			alive = alive,
			pos = pos and {round3(pos.x), round3(pos.y), round3(pos.z)} or nil,
			state = alive and e.state or nil,
			order = alive and e.order or nil,
			profession = alive and e._profession or nil,
			jobsite = alive and e._jobsite ~= nil or nil,
			food = alive and e._villages_food or nil,
			pouch = alive and e._villages_farm_pouch or nil,
			route = alive and e._villages_farm_route and e._villages_farm_route.status or nil,
			route_reason = alive and e._villages_farm_route and e._villages_farm_route.reason or nil,
			composter = core.get_node(site.job).name,
			claim = core.get_meta(site.job):get_string("villager"),
			mark = core.get_meta(site.job):get_string("villages_farmer_compost"),
			soil = count_nodes(site.job, {"mcl_farming:soil", "mcl_farming:soil_wet"}),
			mature = count_nodes(site.job, MATURE),
			plants = count_nodes(site.job, GROWING),
			paths = count_nodes(site.job, {"mcl_core:grass_path"}),
		}
	end
	for i, e in ipairs(scene.hungry) do
		record.hungry[i] = e.object and e.object:get_pos() and (e._villages_food or 0) or "gone"
	end
	local node = core.get_node(scene.chest)
	if node.name == CHEST then
		local held = {}
		for _, stack in ipairs(core.get_meta(scene.chest):get_inventory():get_list("main") or {}) do
			if not stack:is_empty() then held[stack:get_name()] = (held[stack:get_name()] or 0) + stack:get_count() end
		end
		record.chest = held
	end
	local dropped = 0
	for _, object in ipairs(core.get_objects_inside_radius(scene.chest, 40)) do
		local entity = object:get_luaentity()
		if entity and entity.name == "__builtin:item" then dropped = dropped + 1 end
	end
	record.ground_items = dropped
	return record
end

function farm.run(area, emit, done)
	core.set_timeofday(WORK_TIME)
	local origin = build_platform(area)
	-- The village's own villagers are below, in deliveries' range, and mostly out of reach,
	-- so this also shows a farmer giving up on those it cannot get to.
	local scene = build_scene(origin)
	local t, unclaimed, chest_placed, bone_mealed, surplus_given = 0, false, false, false, false
	local function step()
		core.set_timeofday(WORK_TIME)
		if t >= BONE_MEAL_AT and not bone_mealed then
			bone_mealed = true
			local e = scene.farms[2].farmer
			if e and e.object:get_pos() then
				e._villages_farm_pouch = e._villages_farm_pouch or {}
				e._villages_farm_pouch["mcl_bone_meal:bone_meal"] = 12
			end
			core.log("action", "[lv_farm] bare farmer given bone meal")
		end
		if t >= CHEST_AT and not chest_placed then
			chest_placed = true
			core.set_node(scene.chest, {name = CHEST})
			core.get_meta(scene.chest):get_inventory():add_item("main", "mcl_farming:bread 6")
			core.get_meta(scene.chest):get_inventory():add_item("main", "mcl_core:iron_ingot 3")
			core.log("action", "[lv_farm] chest placed at " .. core.pos_to_string(scene.chest))
		end
		if t >= SURPLUS_AT and not surplus_given then
			surplus_given = true
			local e = scene.farms[1].farmer
			if e and e.object:get_pos() then
				e._villages_farm_pouch = e._villages_farm_pouch or {}
				e._villages_farm_pouch["mcl_farming:carrot_item"] = 40
				e._villages_farm_pouch["mcl_bone_meal:bone_meal"] = 4
			end
			core.log("action", "[lv_farm] stock farmer given a surplus")
		end
		if t >= UNCLAIM_AT and not unclaimed then
			unclaimed = true
			local site = scene.farms[1]
			-- What vanilla's on_die does to the claim.
			core.get_meta(site.job):set_string("villager", "")
			if site.farmer and site.farmer.object then site.farmer.object:remove() end
			core.log("action", "[lv_farm] stock farmer removed")
		end
		emit(sample(scene, t))
		if t >= END_AT then
			emit({summary = true, farmer_do_custom = {calls = costs.n,
				ms_per_call = costs.n > 0 and round3(costs.s / costs.n * 1000) or 0,
				worst_ms = round3(costs.worst * 1000)}})
			return done()
		end
		t = t + SAMPLE_SECONDS
		core.after(SAMPLE_SECONDS, step)
	end
	-- Hold the clock between samples too.
	local function hold_clock()
		if t < END_AT then
			core.set_timeofday(WORK_TIME)
			core.after(5, hold_clock)
		end
	end
	hold_clock()
	core.after(5, step)
end

return farm
