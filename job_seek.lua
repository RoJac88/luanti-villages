-- Unemployed villagers take up farming first: a free composter they can reach
-- comes ahead of any other job, and they look for one further away than for
-- anything else.
--
-- VoxeLibre's get_a_job (mobs_mc/villager.lua:1206) claims whichever workstation
-- it finds beside the villager, or walks it to the nearest of any type. So, as in
-- child_jobs.lua, while there is a composter to go to the villager carries a
-- traded-looking `_trades` for the length of the vanilla call, which makes
-- get_a_job ask for the jobsites of its own profession, and "unemployed" has none.
-- keeper.lua and cleric.lua read `_villages_farm_seek` and stand aside as well.
--
-- A composter it turns out not to be able to reach, it stops waiting for: the
-- other jobs are open to it again for a while.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")

local COMPOSTER = "mcl_composters:composter"
-- A trade list with one traded entry, in the form core.deserialize reads.
local TRADED = "return {{traded_once = true, tier = 0}}"
-- One search reads a large box of nodes, so it is not repeated often.
local SCAN_SECONDS = 20
local SCAN_JITTER = 10
local TRIP_SECONDS = 5
local UNREACHABLE_SECONDS = 300

local M = {}

-- Per villager, kept out of the save.
local searches = setmetatable({}, {__mode = "k"})

local function eligible(self)
	return not self.child and self._id ~= nil and not self._jobsite and self._profession == "unemployed"
end

local function free_composter(pos)
	local node = pos and core.get_node_or_nil(pos)
	return node ~= nil and node.name == COMPOSTER and core.get_meta(pos):get_string("villager") == ""
end

local function nearest_free_composter(pos, minp, maxp)
	local best, best_distance
	for _, site in ipairs(core.find_nodes_in_area(minp, maxp, {COMPOSTER})) do
		if free_composter(site) then
			local distance = vector.distance(pos, site)
			if not best or distance < best_distance then best, best_distance = site, distance end
		end
	end
	return best
end

local function employ(self, pos)
	if not free_composter(pos) or not eligible(self) then return false end
	core.get_meta(pos):set_string("villager", self._id)
	self._jobsite = {x = pos.x, y = pos.y, z = pos.z}
	self._profession = "farmer"
	self._villages_farm_seek = nil
	core.log("action", string.format("[living_villages] villager %s became farmer of the composter at %s",
		tostring(self._id), core.pos_to_string(pos)))
	return true
end

local function employ_adjacent(self)
	local pos = self.object:get_pos()
	if not pos then return false end
	local near = nearest_free_composter(pos, vector.subtract(pos, 1), vector.add(pos, 1))
	return near ~= nil and employ(self, near)
end

-- The composter this villager is after: the one it has, while that is still free,
-- or else the nearest, looked for once in a while.
local function composter_sought(self, search, now)
	if now < (search.blocked_until or 0) then return nil end
	if free_composter(self._villages_farm_seek) then return self._villages_farm_seek end
	-- Someone else got there first; there may be another.
	if self._villages_farm_seek then search.next_scan = nil end
	if now < (search.next_scan or 0) then return nil end
	search.next_scan = now + SCAN_SECONDS + math.random() * SCAN_JITTER
	local pos = self.object:get_pos()
	if not pos then return nil end
	local minp, maxp = common.farm_job_box(pos)
	return nearest_free_composter(pos, minp, maxp)
end

local function seek(self, search, navigation, now)
	local route = self._villages_job_search_route
	if route and route.status == "retry" then
		-- The pathfinder needs a moment; that says nothing about the composter.
		if route.reason == "pathfinder cooldown" and now < route.retry_at then return end
		self._villages_job_search_route = nil
		-- navigation.lua could not find a way to any free composter, or lost it.
		if search.trip_started and route.reason ~= "pathfinder cooldown" then
			search.trip_started = nil
			self._villages_farm_seek = nil
			search.blocked_until = now + UNREACHABLE_SECONDS
			return
		end
	end
	if now < (search.next_trip or 0) then return end
	search.next_trip = now + TRIP_SECONDS
	if employ_adjacent(self) then return end
	search.trip_started = true
	navigation.seek_composter(self, self._villages_farm_seek, employ_adjacent)
end

function M.install(def, navigation)
	local original_custom = def.do_custom

	def.do_custom = function(self, dtime)
		if not eligible(self) then
			self._villages_farm_seek = nil
			return original_custom(self, dtime)
		end
		local search = searches[self]
		if not search then
			search = {}
			searches[self] = search
		end
		local now = core.get_gametime()
		self._villages_farm_seek = composter_sought(self, search, now)
		if not self._villages_farm_seek then return original_custom(self, dtime) end

		local trades = self._trades
		self._trades = TRADED
		local result = original_custom(self, dtime)
		self._trades = trades

		if result == false or self.following or self.state == "gowp" then return result end
		if common.is_work_time(self) or common.schedule_stage(nil, self) == "free" then
			seek(self, search, navigation, now)
		end
		return result
	end
end

return M
