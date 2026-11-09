-- A villager out of work (a child grown up, or one whose job block is gone) takes
-- the free job block nearest its bed, of any kind (job_blocks.lua): a workstation,
-- the Builder's bench, the tavern's jukebox or the church's pulpit. VoxeLibre's
-- get_a_job (mobs_mc/villager.lua:1206) would take whichever is beside it, or the
-- nearest to where it stands, so the job would depend on where it was walking.
--
-- While it has a block to go to the villager carries a traded-looking `_trades` for
-- the length of the vanilla call, as in child_jobs.lua, which makes get_a_job ask
-- for the jobsites of its own profession, and "unemployed" has none. It walks there
-- (navigation.seek_job) and claims the block on arrival. `_villages_farm_seek`,
-- a saved name from when this was farming only, holds the block: keeper.lua,
-- cleric.lua and builder.lua stand aside while it is set.
--
-- A block it turns out not to be able to reach is passed over for a while and the
-- next nearest tried.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local job_blocks = dofile(core.get_modpath("living_villages") .. "/job_blocks.lua")

-- A trade list with one traded entry, in the form core.deserialize reads.
local TRADED = "return {{traded_once = true, tier = 0}}"
-- One search reads a large box of nodes, so it is not repeated often.
local SCAN_SECONDS = 20
local SCAN_JITTER = 10
local TRIP_SECONDS = 5
local UNREACHABLE_SECONDS = 300
-- Close enough to claim: beside the block, as a planned approach ends.
local REACH = 2.5

local M = {}

-- Per villager, kept out of the save.
local searches = setmetatable({}, {__mode = "k"})

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

-- Where its job should be near: its bed, or where it stands if it has none.
local function home(self)
	return self._bed or self.object:get_pos()
end

local function claim_near(self, site, roles)
	local pos = self.object:get_pos()
	return site ~= nil and pos ~= nil and vector.distance(pos, site) <= REACH and job_blocks.claim(self, site, roles)
end

-- The block this villager is after: the one it has, while that is still free, or
-- else the nearest to its bed, looked for once in a while.
local function sought(self, search, roles, now)
	local current = self._villages_farm_seek
	local function skipped(site)
		return (search.skip[key(site)] or 0) > now
	end
	if current and not skipped(current) and job_blocks.is_free(current, roles) then return current end
	-- Someone else got there first; there may be another.
	if current then search.next_scan = nil end
	if now < (search.next_scan or 0) then return nil end
	search.next_scan = now + SCAN_SECONDS + math.random() * SCAN_JITTER
	local from = home(self)
	if not from then return nil end
	local minp, maxp = common.farm_job_box(from)
	local sites = core.find_nodes_in_area(minp, maxp, job_blocks.search_nodes(roles))
	return job_blocks.nearest_free(from, sites, roles, skipped)
end

local function give_up(self, search, now)
	search.trip_started = nil
	if self._villages_farm_seek then
		search.skip[key(self._villages_farm_seek)] = now + UNREACHABLE_SECONDS
	end
	self._villages_farm_seek = nil
	search.next_scan = nil
end

local function seek(self, search, navigation, roles, now)
	for _, field in ipairs({"_villages_job_search_route", "_villages_goto_route"}) do
		local route = self[field]
		if route and route.status == "retry" then
			-- The pathfinder needs a moment; that says nothing about the block.
			if route.reason == "pathfinder cooldown" and now < route.retry_at then return end
			self[field] = nil
			-- navigation.lua could not find a way to it, or lost it.
			if search.trip_started and route.reason ~= "pathfinder cooldown" then
				give_up(self, search, now)
				return
			end
		end
	end
	if now < (search.next_trip or 0) then return end
	search.next_trip = now + TRIP_SECONDS
	local site = self._villages_farm_seek
	if claim_near(self, site, roles) then return end
	search.trip_started = true
	local started = navigation.seek_job(self, site, function(entity)
		claim_near(entity, site, roles)
	end)
	if started == false then give_up(self, search, now) end
end

-- roles: as job_blocks.lua takes it, filled in as the roles are installed.
function M.install(def, navigation, roles)
	local original_custom = def.do_custom

	def.do_custom = function(self, dtime)
		if self[job_blocks.LEFT_UNEMPLOYED] and self._profession == "unemployed" and not self._jobsite then
			-- Vanilla's get_a_job would take the nearest block; it is meant to stay out of work.
			local trades = self._trades
			self._trades = TRADED
			local result = original_custom(self, dtime)
			self._trades = trades
			self._villages_farm_seek = nil
			return result
		end
		if not job_blocks.eligible(self) then
			self._villages_farm_seek = nil
			return original_custom(self, dtime)
		end
		local search = searches[self]
		if not search then
			search = {skip = {}}
			searches[self] = search
		end
		local now = core.get_gametime()
		local site = sought(self, search, roles, now)
		if site ~= self._villages_farm_seek then search.trip_started = nil end
		self._villages_farm_seek = site
		if not site then return original_custom(self, dtime) end

		local trades = self._trades
		self._trades = TRADED
		local result = original_custom(self, dtime)
		self._trades = trades

		if result == false or self.following or self.state == "gowp" then return result end
		if not job_blocks.eligible(self) then return result end
		if common.is_work_time(self) or common.schedule_stage(nil, self) == "free" then
			seek(self, search, navigation, roles, now)
		end
		return result
	end
end

return M
