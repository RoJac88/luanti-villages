-- A villager up and down a column of scaffolding (tools/lv_climb/run.sh). Every second it
-- writes where the villager is and its health to <world>/climb.log, then PASS or FAIL and why.
local core = minetest
local climb = dofile(core.get_modpath("living_villages") .. "/builder_climb.lua")

local LEVELS = tonumber(core.settings:get("lv_climb_levels")) or 12
local HOLD = tonumber(core.settings:get("lv_climb_hold")) or 30
local AFTER = 15
local COLUMN = {x = 4, z = 4}

local out = io.open(core.get_worldpath() .. "/climb.log", "w")
local function log(...)
	out:write(string.format(...), "\n")
	out:flush()
end

local ground, villager, start_health
local phase, phase_at, clock, tick = "load", 0, 0, 0
local failures = {}
local function fail(why)
	failures[#failures + 1] = why
end

local function entity()
	return villager and villager:get_luaentity()
end

local function column()
	local found = {}
	for level = 1, LEVELS do
		found[#found + 1] = core.get_node({x = COLUMN.x, y = ground + level, z = COLUMN.z}).name
	end
	return found
end

local function finish()
	if #failures == 0 then log("PASS") else log("FAIL %s", table.concat(failures, "; ")) end
	out:close()
	core.request_shutdown()
end

-- Where it must be in each phase, checked every second.
local function check(e)
	local pos = villager:get_pos()
	if start_health and e.health ~= start_health then fail(string.format("health %s in %s", tostring(e.health), phase)) end
	local top = ground + LEVELS + 0.5
	if (phase == "hold" or phase == "reloaded") and math.abs(pos.y - top) > 0.01 then
		fail(string.format("at %.2f, not %.2f, in %s", pos.y, top, phase))
	end
	if phase == "after" and math.abs(pos.y - (ground + 0.5)) > 0.05 then
		fail(string.format("at %.2f after coming down", pos.y))
	end
	if math.abs(pos.x - COLUMN.x) > 0.05 or math.abs(pos.z - COLUMN.z) > 0.05 then
		if phase ~= "after" then fail(string.format("off the column at %.2f,%.2f in %s", pos.x, pos.z, phase)) end
	end
	local c = e._villages_climb
	log("%6.1f %-9s y %.3f health %s %s", clock, phase, pos.y, tostring(e.health),
		c and string.format("level %d of %d%s", c.level, c.target,
			c.blocked and " blocked at " .. core.pos_to_string(c.blocked) or "") or "not climbing")
end

core.register_on_mods_loaded(function() core.set_timeofday(0.4) end)

core.register_globalstep(function(dtime)
	clock = clock + dtime
	if phase == "load" then
		for y = -16, 16 * math.ceil((LEVELS + 24) / 16), 16 do
			core.forceload_block({x = COLUMN.x, y = y, z = COLUMN.z}, true)
		end
		if clock < 3 then return end
		for y = 40, -40, -1 do
			local node = core.get_node_or_nil({x = COLUMN.x, y = y, z = COLUMN.z})
			if node and node.name ~= "air" and node.name ~= "ignore" then
				ground = y
				break
			end
		end
		if not ground then return end
		villager = core.add_entity({x = COLUMN.x, y = ground + 0.6, z = COLUMN.z}, "mobs_mc:villager")
		phase, phase_at = "settle", clock
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
		check(e)
	end
	local in_phase = clock - phase_at
	if phase == "settle" and in_phase > 4 then
		villager:set_pos({x = COLUMN.x, y = ground + 0.5, z = COLUMN.z})
		start_health = e.health
		climb.start(e, LEVELS, {dismantle = true})
		climb.face(e, {x = COLUMN.x + 5, y = ground, z = COLUMN.z})
		phase, phase_at = "up", clock
	elseif phase == "up" and climb.arrived(e) then
		log("up %d levels in %.1f s", LEVELS, in_phase)
		for level, name in ipairs(column()) do
			if name ~= climb.SCAFFOLD then fail(string.format("level %d is %s", level, name)) end
		end
		phase, phase_at = "hold", clock
	elseif phase == "up" and in_phase > LEVELS * 2 + 10 then
		fail("never reached the top")
		finish()
	elseif phase == "hold" and in_phase > HOLD then
		-- As an unloaded mapblock would: saved, then made again from what was saved.
		local data, pos = e:get_staticdata(), villager:get_pos()
		villager:remove()
		villager = core.add_entity(pos, "mobs_mc:villager", data)
		phase, phase_at = "reloaded", clock
	elseif phase == "reloaded" and in_phase > AFTER then
		climb.go_to(e, 0)
		phase, phase_at = "down", clock
	elseif phase == "down" and climb.arrived(e) then
		log("down in %.1f s", in_phase)
		if not climb.release(e) then fail("could not let go on the ground") end
		for level, name in ipairs(column()) do
			if name ~= "air" then fail(string.format("level %d left as %s", level, name)) end
		end
		phase, phase_at = "after", clock
	elseif phase == "down" and in_phase > LEVELS * 2 + 10 then
		fail("never came down")
		finish()
	elseif phase == "after" and in_phase > AFTER then
		finish()
	end
end)
