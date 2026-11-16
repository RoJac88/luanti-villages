-- The butcher's chickens (docs/villager-economy-design.md, ticket 24): feathers for the
-- fletcher's arrows. No villager made feathers, so a fletcher wanting 4 for its arrows had
-- none to buy (ColonyFood, 2026-11-16, where the player keeps chickens in the butcher's
-- house).
--
-- A butcher with a jobsite (not the keeper, a butcher underneath with a jukebox) collects,
-- in its work stage every COLLECT_SECONDS (`_villages_coop_next`, game time), one feather
-- for each adult mobs_mc:chicken within RADIUS of its jobsite, at most COOP_SIZE, into its
-- belongings, while it holds fewer than KEEP. It keeps no flock of its own: the chickens
-- are whatever the player or the world put there, and none is bred, marked or killed, so
-- without this mod nothing is left behind. Feathers are its own make (ledger.lua's MAKES),
-- so it sells them and never buys them.
--
-- With the economy off there are no feathers.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")

local CHICKEN = "mobs_mc:chicken"
local FEATHER = "mcl_mobitems:feather"
local PROFESSION = "butcher"
local RADIUS = 16
local COOP_SIZE = 8
local KEEP = 64
local STEP_SECONDS = 10
local COLLECT_SECONDS = 150

local M = {CHICKEN = CHICKEN, FEATHER = FEATHER, RADIUS = RADIUS, COOP_SIZE = COOP_SIZE, KEEP = KEEP,
	COLLECT_SECONDS = COLLECT_SECONDS}

-- The adult chickens within RADIUS of pos, at most COOP_SIZE.
function M.count(pos)
	local found = 0
	for _, object in ipairs(core.get_objects_inside_radius(pos, RADIUS)) do
		local entity = object:get_luaentity()
		if entity and entity.name == CHICKEN and not entity.child then
			found = found + 1
			if found >= COOP_SIZE then break end
		end
	end
	return found
end

-- Whether it keeps a coop: a butcher, not the keeper, grown, with a jobsite.
local function keeps(self)
	return not self.child and self._id ~= nil and self._profession == PROFESSION and not self._villages_keeper
		and type(self._jobsite) == "table"
end

-- One collection: a feather a chicken, up to KEEP held. Returns how many it took.
function M.collect(self, chickens)
	local room = KEEP - possessions.count(self, FEATHER)
	local feathers = math.min(chickens, math.max(room, 0))
	if feathers <= 0 then return 0 end
	possessions.add(self, FEATHER, feathers)
	core.log("action", string.format("[living_villages] coop: butcher %s collected %d feather(s) from %d chicken(s)",
		tostring(self._id):sub(1, 6), feathers, chickens))
	return feathers
end

local next_step = setmetatable({}, {__mode = "k"})

function M.step(self, now)
	if now < (next_step[self] or 0) then return end
	next_step[self] = now + STEP_SECONDS
	if not keeps(self) or common.schedule_stage(nil, self) ~= "work" then return end
	if now < (self._villages_coop_next or 0) then return end
	self._villages_coop_next = now + COLLECT_SECONDS
	local chickens = M.count(self._jobsite)
	if chickens > 0 then M.collect(self, chickens) end
end

function M.install(def)
	if not clock.enabled() then return end
	local original = def.do_custom
	def.do_custom = function(self, dtime)
		local result = original(self, dtime)
		M.step(self, core.get_gametime())
		return result
	end
end

-- One line for the inspector.
function M.status(self)
	if not keeps(self) then return "no coop" end
	return string.format("%d chickens, %d feathers", M.count(self._jobsite), possessions.count(self, FEATHER))
end

return M
