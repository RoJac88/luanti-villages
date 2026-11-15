-- A villager taking up an alchemist's stand (tools/lv_alchemist/run.sh). Every second it
-- writes the villager's stage, role and distance from the stand to <world>/alchemist.log,
-- then PASS or FAIL and why.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")

local STAND = "living_villages:alchemy_stand"
local SPAWN = {x = 2, z = 3}
local BED = {x = 2, z = 6}
local STAND_AT = {x = 10, z = 6}
-- At time_speed 0 a working day is reckoned at the default 72: a nugget each 29 s.
local SEEK_LIMIT, WALK_LIMIT, TAVERN_HOLD, AFTER = 120, 90, 75, 10
local NUGGET, COBBLE, MIN_NUGGETS = "mcl_core:iron_nugget", "mcl_core:cobble", 2

local out = io.open(core.get_worldpath() .. "/alchemist.log", "w")
local function log(...)
	out:write(string.format(...), "\n")
	out:flush()
end

local ground, villager, stand
local phase, phase_at, clock, tick = "load", 0, 0, 0
local failures = {}
local function fail(why) failures[#failures + 1] = why end

local function entity() return villager and villager:get_luaentity() end

local function finish()
	if #failures == 0 then log("PASS") else log("FAIL %s", table.concat(failures, "; ")) end
	out:close()
	core.request_shutdown()
end

local function distance()
	local pos = villager:get_pos()
	return pos and vector.distance(pos, stand) or math.huge
end

local function next_phase(name)
	log("%6.1f -> %s", clock, name)
	phase, phase_at = name, clock
end

core.register_on_mods_loaded(function()
	-- The server has no player, so mcl_mobs would freeze everything.
	local class = mcl_mobs.mob_class
	local original = class.player_in_active_range
	class.player_in_active_range = function(self, ...)
		if self.name == "mobs_mc:villager" then return true end
		return original(self, ...)
	end
	-- No holiday: an ordinary day's timetable throughout.
	if mcl_moon then mcl_moon.get_moon_phase = function() return 1 end end
end)

core.register_globalstep(function(dtime)
	clock = clock + dtime
	if phase == "load" then
		for x = -16, 16, 16 do
			for y = -16, 16, 16 do core.forceload_block({x = x, y = y, z = 8}, true) end
		end
		if clock < 3 then return end
		for y = 40, -40, -1 do
			local node = core.get_node_or_nil({x = 0, y = y, z = 0})
			if node and node.name ~= "air" and node.name ~= "ignore" then ground = y break end
		end
		if not ground then return end
		local bed = {x = BED.x, y = ground + 1, z = BED.z}
		core.set_node(bed, {name = "mcl_beds:bed_red_bottom", param2 = 0})
		core.set_node({x = BED.x, y = ground + 1, z = BED.z + 1}, {name = "mcl_beds:bed_red_top", param2 = 0})
		stand = {x = STAND_AT.x, y = ground + 1, z = STAND_AT.z}
		core.set_node(stand, {name = STAND})
		villager = core.add_entity({x = SPAWN.x, y = ground + 1.5, z = SPAWN.z}, "mobs_mc:villager")
		next_phase("settle")
		return
	end
	local e = entity()
	if not e then
		fail("the villager is gone in " .. phase)
		return finish()
	end
	tick = tick + dtime
	if tick >= 1 then
		tick = 0
		log("%6.1f %-8s stage %-7s %-10s role %-5s jobsite %s distance %.1f cobble %d nuggets %d", clock, phase,
			common.schedule_stage(nil, e), tostring(e._profession), tostring(e._villages_alchemist == true),
			e._jobsite and core.pos_to_string(e._jobsite) or "none", distance(),
			possessions.count(e, COBBLE), possessions.count(e, NUGGET))
	end
	local in_phase = clock - phase_at
	if phase == "settle" and in_phase > 2 and e._id then
		-- Out of work, with a bed: job_seek.lua should find the stand from it.
		local bed = {x = BED.x, y = ground + 1, z = BED.z}
		if e._jobsite then core.get_meta(e._jobsite):set_string("villager", "") end
		e._profession, e._jobsite, e._trades = "unemployed", nil, nil
		e._bed = bed
		core.get_meta(bed):set_string("villager", e._id)
		-- The work stage, when job_seek.lua looks for a job block.
		core.set_timeofday(9600 / 24000)
		next_phase("seek")
	elseif phase == "seek" and e._villages_alchemist then
		log("took the stand in %.1f s", in_phase)
		if e._profession ~= "cleric" then fail("profession " .. tostring(e._profession)) end
		if core.get_meta(stand):get_string("villager") ~= e._id then fail("the stand does not name it") end
		-- Stone to work (ticket 20c): four cobble a nugget.
		possessions.add(e, COBBLE, 40)
		next_phase("walk")
	elseif phase == "seek" and in_phase > SEEK_LIMIT then
		fail("never took the stand")
		finish()
	elseif phase == "walk" and distance() <= 3 then
		log("at the stand in %.1f s", in_phase)
		local textures = villager:get_properties().textures
		if not (textures and textures[1] and textures[1]:find("profession_cleric.png^[multiply", 1, true)) then
			fail("not in the alchemist's robe: " .. tostring(textures and textures[1]))
		end
		-- Tavern time: the others go to dinner, it keeps working.
		core.set_timeofday(16000 / 24000)
		next_phase("tavern")
	elseif phase == "walk" and in_phase > WALK_LIMIT then
		fail("never reached the stand")
		finish()
	elseif phase == "tavern" then
		local stage = common.schedule_stage(nil, e)
		if stage ~= "work" then fail("stage " .. stage .. " at tavern time") end
		if in_phase > 5 and distance() > 4 then fail(string.format("left the stand at tavern time (%.1f)", distance())) end
		if in_phase > TAVERN_HOLD then
			local nuggets = possessions.count(e, NUGGET)
			log("made %d nugget(s) in %.0f s at the stand", nuggets, in_phase)
			if nuggets < MIN_NUGGETS then fail(string.format("made %d nugget(s), not %d", nuggets, MIN_NUGGETS)) end
			local data, pos = e:get_staticdata(), villager:get_pos()
			villager:remove()
			villager = core.add_entity(pos, "mobs_mc:villager", data)
			next_phase("reloaded")
		end
	elseif phase == "reloaded" and in_phase > 3 then
		if not e._villages_alchemist or e._profession ~= "cleric" then fail("lost the role when made again") end
		core.remove_node(stand)
		next_phase("dug")
	elseif phase == "dug" and in_phase > AFTER then
		if e._villages_alchemist then fail("still an alchemist with its stand dug") end
		if e._profession ~= "unemployed" then fail("profession " .. tostring(e._profession) .. " with its stand dug") end
		finish()
	end
end)
