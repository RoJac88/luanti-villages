-- The farmer's working day, built on VoxeLibre's legacy villager AI. A claimed
-- composter anchors the farm. About once a second, in the work stage, the farmer
-- does the next job within its reach, or else walks to the most pressing one.
--
-- Vanilla's do_work calls the farmer back to its composter every few seconds, so
-- while it has work here common.activity_override answers for it, as flock.lua
-- does for a shepherd. With nothing to do it lets vanilla have it again, which is
-- also when vanilla's do_work unlocks its trades.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local field = dofile(core.get_modpath("living_villages") .. "/farm_field.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local compost = dofile(core.get_modpath("living_villages") .. "/farm_compost.lua")

local TICK_SECONDS = 1
local IDLE_SECONDS = 5
-- From a cell beside a plot, including diagonally, with room for standing off centre.
local REACH = 2.5
-- A place the farmer could not walk to is left alone for this long.
local SKIP_SECONDS = 60
-- Stay put this long after a job, ready for the next.
local HOLD_SECONDS = 2

local WHEAT = "mcl_farming:wheat_item"
local BREAD = "mcl_farming:bread"
local BONE_MEAL = compost.BONE_MEAL
-- Three wheat to the loaf, as in the crafting recipe. A farmer stops baking at this
-- many loaves, as it has nobody to give them to.
local WHEAT_PER_BREAD = 3
local BREAD_LIMIT = 12
-- What it composts, and how much of each it keeps for sowing and eating. Bread goes
-- to villagers, so it is never composted.
local COMPOST_KEEP = {
	["mcl_farming:wheat_seeds"] = 8,
	["mcl_farming:beetroot_seeds"] = 8,
	["mcl_farming:potato_item"] = 8,
	["mcl_farming:carrot_item"] = 8,
	["mcl_farming:beetroot_item"] = 8,
	[WHEAT] = WHEAT_PER_BREAD,
}
-- It stops composting once it holds this much bone meal, so the surplus is not all
-- turned into something it cannot use.
local BONE_MEAL_LIMIT = 32

-- Live working state. Not saved: a reload clears the farmer's route anyway
-- (navigation.lua), and it picks its next job from what it finds.
local sessions = setmetatable({}, {__mode = "k"})

local function session_of(self)
	local session = sessions[self]
	if not session then
		session = {skip = {}, next_at = 0, hold_until = 0}
		sessions[self] = session
	end
	return session
end

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function valid_farmer(self)
	if self.child or self._profession ~= "farmer" or not self._jobsite or not self._id then return false end
	local node = core.get_node_or_nil(self._jobsite)
	return node and common.is_composter_node(node.name)
		and core.get_meta(self._jobsite):get_string("villager") == self._id
end

local function is_trading(self)
	return self._trading_players ~= nil and next(self._trading_players) ~= nil
end

local function skipped(session, pos, now)
	local until_time = session.skip[key(pos)]
	return until_time ~= nil and until_time > now
end

-- The nearest of the positions it has not given up on.
local function nearest(session, pos, positions, now)
	local best, best_distance
	for _, candidate in ipairs(positions) do
		if not skipped(session, candidate, now) then
			local distance = vector.distance(pos, candidate)
			if not best_distance or distance < best_distance then best, best_distance = candidate, distance end
		end
	end
	return best, best_distance
end

local function face(self, pos, target)
	local dx, dz = target.x - pos.x, target.z - pos.z
	if (dx ~= 0 or dz ~= 0) and self.turn_in_direction then self:turn_in_direction(dx, dz) end
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

local function walk_to(self, session, target, now)
	self._villages_farm_target = vector.new(target)
	self._villages_farm_route = nil
	local started = self:gopath(target, function(entity)
		entity._villages_farm_target = nil
		entity._villages_farm_route = nil
	end, true)
	if started then return true end
	session.skip[key(target)] = now + SKIP_SECONDS
	self._villages_farm_target = nil
	self._villages_farm_route = nil
	return false
end

local function harvest(self, pos)
	local drops = field.harvest(pos)
	if not drops then return end
	for _, drop in ipairs(drops) do stock.add_itemstring(self, drop) end
end

local function plant(self, pos)
	local seed = field.choose_seed(pos, function(name) return stock.count(self, name) end)
	if seed and field.plant(pos, seed) then stock.take(self, seed, 1) end
end

local function has_seed(self)
	for name in pairs(self._villages_farm_pouch or {}) do
		if field.is_seed(name) then return true end
	end
	return false
end

local function fertilise(self, pos)
	if stock.count(self, BONE_MEAL) > 0 and field.fertilise(pos, BONE_MEAL) then
		stock.take(self, BONE_MEAL, 1)
	end
end

local function can_bake(self)
	return stock.count(self, WHEAT) >= WHEAT_PER_BREAD and stock.count(self, BREAD) < BREAD_LIMIT
end

-- The item it has most of beyond what it keeps, or nil.
local function surplus_item(self)
	if stock.count(self, BONE_MEAL) >= BONE_MEAL_LIMIT then return nil end
	local best, best_extra = nil, 0
	for name, keep in pairs(COMPOST_KEEP) do
		-- Wheat is for bread while there is room for more.
		if name ~= WHEAT or not can_bake(self) then
			local extra = stock.count(self, name) - keep
			if extra > best_extra or (extra == best_extra and best and name < best) then
				best, best_extra = name, extra
			end
		end
	end
	return best_extra > 0 and best or nil
end

local function composter_has_work(self, name)
	if compost.is_ready(name) or can_bake(self) then return true end
	return compost.takes_items(name) and surplus_item(self) ~= nil
end

-- One thing at the composter: take the bone meal, bake a loaf or add an item.
local function work_composter(self, pos)
	local collected = compost.collect(pos)
	if collected then
		stock.add(self, collected)
		return
	end
	if can_bake(self) then
		stock.take(self, WHEAT, WHEAT_PER_BREAD)
		stock.add(self, BREAD)
		return
	end
	local node = core.get_node_or_nil(pos)
	local item = surplus_item(self)
	if item and node and compost.takes_items(node.name) and compost.add_item(pos, item) then
		stock.take(self, item, 1)
	end
end

-- The jobs, most pressing first. wanted says whether to do that kind
-- of job at all now, and each kind lists its places. Tilling waits until there are
-- seeds for what it opens up, and nothing already open is left unsown.
local function plot_jobs(self, farm)
	local seeds = has_seed(self)
	local composter = core.get_node_or_nil(self._jobsite).name
	compost.nudge(self._jobsite, composter)
	return {
		{positions = farm.mature, wanted = stock.has_harvest_room(self), work = harvest},
		{positions = farm.empty, wanted = seeds, work = plant},
		{
			positions = seeds and #farm.empty == 0 and field.tillable(self._jobsite, farm.soil) or {},
			wanted = seeds,
			work = function(_, pos) field.till(pos, #farm.soil) end,
		},
		{
			positions = field.least_grown(farm.growing),
			wanted = stock.count(self, BONE_MEAL) > 0,
			work = fertilise,
		},
		{positions = {self._jobsite}, wanted = composter_has_work(self, composter), work = work_composter},
	}
end

-- One job within reach, or one walk to the most pressing job. Returns "worked",
-- "walking", or nil for nothing to do.
local function next_step(self, session, pos, now)
	local jobs = plot_jobs(self, field.scan(self._jobsite))
	for _, job in ipairs(jobs) do
		if job.wanted then
			local target, distance = nearest(session, pos, job.positions, now)
			if target and distance <= REACH then
				face(self, pos, target)
				job.work(self, target)
				return "worked"
			end
		end
	end
	for _, job in ipairs(jobs) do
		if job.wanted then
			-- A plot it cannot reach gives way to the next nearest, a tick later.
			local target = nearest(session, pos, job.positions, now)
			if target then
				if walk_to(self, session, target, now) then return "walking" end
				return "worked"
			end
		end
	end
	return nil
end

local function tick(self, session, now)
	if self._villages_farm_target then
		local route = self._villages_farm_route
		if route and route.status == "planning" then return end
		if route and route.status == "retry" then
			session.skip[key(self._villages_farm_target)] = now + SKIP_SECONDS
		end
		self._villages_farm_target = nil
		self._villages_farm_route = nil
	end
	if now < session.next_at then return end
	session.next_at = now + TICK_SECONDS
	local pos = self.object:get_pos()
	if not pos then return end
	local step = next_step(self, session, pos, now)
	if step == "worked" then
		session.away = true
		session.hold_until = now + HOLD_SECONDS
	elseif step == "walking" then
		session.away = true
		session.hold_until = 0
	else
		release(self, session)
		session.next_at = now + IDLE_SECONDS
	end
end

local M = {}

-- common.activity_override: a farmer with work in its field is not called back.
function M.activity_override(villager, stage)
	if stage ~= "work" then return nil end
	local session = sessions[villager]
	if session and session.away then return "farm" end
	return nil
end

function M.install(def)
	local original_custom = def.do_custom
	local original_die = def.on_die

	def.do_custom = function(self, dtime)
		local result = original_custom(self, dtime)
		if result == false then return result end
		if not common.is_work_time(self) or not valid_farmer(self) or self.following or is_trading(self) then
			local session = sessions[self]
			if session and session.away then release(self, session) end
			return result
		end
		if self.state == "gowp" then return result end

		local session = session_of(self)
		local now = core.get_gametime()
		tick(self, session, now)
		if self.state ~= "gowp" and session.hold_until >= now then
			hold_still(self)
			-- As for a fishing session: do_states would turn a standing villager away.
			return false
		end
		return result
	end

	def.on_die = function(self, pos, cause)
		stock.drop_all(self, pos or self.object:get_pos())
		if original_die then return original_die(self, pos, cause) end
	end
end

M.sessions = sessions
return M
