-- Who takes which job on the real game: fishermen and their barrels, and unemployed
-- villagers choosing a composter over anything else. After a village is built this
-- raises a walled platform over it, with a pond, and the clock is held in the work
-- stage. Two fishermen work from barrels, one a player has traded with, and an unemployed
-- villager with a bed lives beside the pond. Partway both barrels are broken, and the traded
-- fisherman is then given another. Next a villager appears right beside a free barrel, with a
-- composter over 48 nodes away; and last another right beside a free smoker, with a walled-off
-- composter. Every 10 s the record notes what each villager is doing. Only runs when
-- lv_probe_jobs is set.
local core = minetest

local jobs = {}

local VILLAGER = "mobs_mc:villager"
local COMPOSTER = "mcl_composters:composter"
local BARREL = "mcl_barrels:barrel_closed"
local SMOKER = "mcl_smoker:smoker"
local WORK_TIME = 0.33
local SIZE = 78
local HEADROOM = 6
local SAMPLE_SECONDS = 10
local BARRELS_BROKEN_AT = 150
local NEW_BARREL_AT = 180
local COMPOSTER_AT = 210
local SEALED_AT = 330
local END_AT = 480

function jobs.enabled()
	return (tonumber(core.settings:get("lv_probe_jobs")) or 0) > 0
end

local costs = {n = 0, s = 0, worst = 0}

core.register_on_mods_loaded(function()
	if not jobs.enabled() then return end
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
		if self._probe_jobs then
			costs.n, costs.s = costs.n + 1, costs.s + spent
			costs.worst = math.max(costs.worst, spent)
		end
		return result
	end
end)

local function round3(v) return math.floor(v * 1000 + 0.5) / 1000 end

-- The site's forceloaded blocks stop below the platform, so it holds its own.
local BLOCK = 16
local function forceload_platform(origin)
	for x = origin.x, origin.x + SIZE + BLOCK, BLOCK do
		for y = origin.y, origin.y + HEADROOM + BLOCK, BLOCK do
			for z = origin.z, origin.z + SIZE + BLOCK, BLOCK do
				core.forceload_block({x = x, y = y, z = z}, true)
			end
		end
	end
end

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

local function spawn(pos, id, profession, jobsite, trades)
	local object = core.add_entity(pos, VILLAGER)
	local entity = object and object:get_luaentity()
	if not entity then return nil end
	entity._id, entity._profession, entity._probe_jobs = id, profession, true
	entity._trades = trades
	if jobsite then
		entity._jobsite = jobsite
		core.get_meta(jobsite):set_string("villager", id)
	end
	return entity
end

local function sample(scene, t)
	local record = {t = t, villagers = {}}
	for name, e in pairs(scene.villagers) do
		local pos = e.object and e.object:get_pos()
		if pos then
			local trades = e._trades and core.deserialize(e._trades)
			local locked = 0
			for _, trade in pairs(type(trades) == "table" and trades or {}) do
				if trade.locked then locked = locked + 1 end
			end
			record.villagers[name] = {
				pos = {round3(pos.x), round3(pos.y), round3(pos.z)},
				state = e.state, order = e.order, profession = e._profession,
				flag = e._villages_fisherman, jobsite = e._jobsite and core.pos_to_string(e._jobsite) or nil,
				session = e._villages_fish_session and e._villages_fish_session.phase or nil,
				fish_route = e._villages_fish_route and e._villages_fish_route.status or nil,
				fish_reason = e._villages_fish_route and e._villages_fish_route.reason or nil,
				fish_target = e._villages_fish_target and core.pos_to_string(e._villages_fish_target) or nil,
				seek = e._villages_farm_seek and core.pos_to_string(e._villages_farm_seek) or nil,
				search = e._villages_job_search_route and e._villages_job_search_route.status or nil,
				reason = e._villages_job_search_route and e._villages_job_search_route.reason or nil,
				locked = trades and locked or nil,
				has_trades = e._trades ~= nil,
			}
		else
			record.villagers[name] = {gone = true}
		end
	end
	return record
end

function jobs.run(area, emit, done)
	core.set_timeofday(WORK_TIME)
	local origin = build_platform(area)
	local y = origin.y + 1
	local function at(dx, dz, dy) return {x = origin.x + dx, y = y + (dy or 0), z = origin.z + dz} end
	-- The pond, with its surface level with the floor and a bed under it.
	for dx = 8, 14 do
		for dz = 8, 14 do
			core.set_node({x = origin.x + dx, y = origin.y, z = origin.z + dz}, {name = "mcl_core:water_source"})
			core.set_node({x = origin.x + dx, y = origin.y - 1, z = origin.z + dz}, {name = "mcl_core:stone"})
		end
	end
	local barrel_one, barrel_two = at(24, 11), at(24, 18)
	core.set_node(barrel_one, {name = BARREL})
	core.set_node(barrel_two, {name = BARREL})
	local traded = core.serialize({{traded_once = true, tier = 1, locked = true, trade_counter = 5,
		wanted = {"mcl_core:emerald"}, offered = "mcl_fishing:fish_raw"}})
	local bed = at(16, 24)
	core.set_node(bed, {name = "mcl_beds:bed_red_bottom"})
	local scene = {villagers = {
		untraded_fisher = spawn(at(25, 11), "probe-fisher", "fisherman", barrel_one),
		traded_fisher = spawn(at(25, 18), "probe-traded", "fisherman", barrel_two, traded),
		pond_idler = spawn(at(16, 22), "probe-idler", "unemployed"),
	}}
	if scene.villagers.pond_idler then
		scene.villagers.pond_idler._bed = bed
		core.get_meta(bed):set_string("villager", "probe-idler")
	end
	local box_ms
	local t, broken, rebarrelled, offered, sealed = 0, false, false, false, false
	local function step()
		core.set_timeofday(WORK_TIME)
		if t >= BARRELS_BROKEN_AT and not broken then
			broken = true
			core.set_node(barrel_one, {name = "air"})
			core.set_node(barrel_two, {name = "air"})
			core.log("action", "[lv_jobs] barrels broken")
		end
		if t >= NEW_BARREL_AT and not rebarrelled then
			rebarrelled = true
			local e = scene.villagers.traded_fisher
			local pos = e and e.object and e.object:get_pos()
			if pos then
				core.set_node({x = math.floor(pos.x + 0.5) + 1, y = math.floor(pos.y + 0.5), z = math.floor(pos.z + 0.5)},
					{name = BARREL})
			end
			core.log("action", "[lv_jobs] a new barrel beside the traded fisherman")
		end
		if t >= COMPOSTER_AT and not offered then
			offered = true
			core.set_node(at(72, 62), {name = COMPOSTER})
			core.set_node(at(40, 40), {name = BARREL})
			scene.villagers.chooser = spawn(at(41, 40), "probe-chooser", "unemployed")
			core.log("action", "[lv_jobs] a villager beside a free barrel, and a far composter")
		end
		if t >= SEALED_AT and not sealed then
			sealed = true
			local c = at(60, 10)
			for dx = -2, 2 do
				for dz = -2, 2 do
					if math.max(math.abs(dx), math.abs(dz)) == 2 then
						for dy = 0, 3 do core.set_node({x = c.x + dx, y = c.y + dy, z = c.z + dz}, {name = "mcl_core:stone"}) end
					end
				end
			end
			core.set_node(c, {name = COMPOSTER})
			core.set_node(at(50, 30), {name = SMOKER})
			scene.villagers.walled_out = spawn(at(51, 30), "probe-walled", "unemployed")
			core.log("action", "[lv_jobs] a villager beside a free smoker, and a sealed composter")
		end
		emit(sample(scene, t))
		if t >= END_AT then
			local c = at(39, 39)
			local start = os.clock()
			local radius = 96
			core.find_nodes_in_area({x = c.x - radius, y = c.y - 24, z = c.z - radius},
				{x = c.x + radius, y = c.y + 24, z = c.z + radius}, {COMPOSTER})
			box_ms = round3((os.clock() - start) * 1000)
			emit({summary = true, do_custom = {calls = costs.n,
				ms_per_call = costs.n > 0 and round3(costs.s / costs.n * 1000) or 0,
				worst_ms = round3(costs.worst * 1000)}, composter_scan_ms = box_ms})
			return done()
		end
		t = t + SAMPLE_SECONDS
		core.after(SAMPLE_SECONDS, step)
	end
	local function hold_clock()
		if t < END_AT then
			core.set_timeofday(WORK_TIME)
			core.after(5, hold_clock)
		end
	end
	hold_clock()
	core.after(5, step)
end

return jobs
