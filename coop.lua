-- The butcher's chickens (docs/villager-economy-design.md, ticket 24): feathers for the
-- fletcher's arrows, and chicken for its own smoker. No villager made feathers, so a
-- fletcher wanting 4 for its arrows had none to buy (ColonyFood, 2026-11-16).
--
-- A butcher with a jobsite (not the keeper, a butcher underneath with a jukebox) keeps a
-- flock as the leatherworker keeps its herd (herd.lua): ordinary mobs_mc:chicken marked
-- with its villager id in `_villages_coop` (saved on the chicken; found again by scanning
-- within SCAN_RADIUS, so an unload loses nothing, and without this mod the field is inert),
-- bound to the jobsite by herd.keep_near.
--
-- It is never given chickens. While its flock (chicks too) is under MIN_FLOCK, any unmarked
-- chicken or chick that comes within ADOPT_RADIUS of the jobsite joins it: the player lures
-- some there, or hands it eggs.
--
-- In the work stage:
-- * every STEP it picks up the eggs lying within EGG_RADIUS of the jobsite (VoxeLibre's
--   hens lay them as items), up to EGG_KEEP held;
-- * with a flock under MIN_FLOCK, every THROW_SECONDS it throws one egg it holds near the
--   jobsite (mcl_throwing, as a player throws one: a chick one time in eight), and a chick
--   that hatches joins the flock as above;
-- * every TEND_SECONDS (`_villages_coop_next`, game time) it collects a feather from each
--   adult, then with more than COOP_SIZE adults slaughters one, as a kill would drop it
--   (mobs_mc/chicken.lua: a raw chicken and 0 to 2 feathers), or else, with two adults,
--   room for a chick and BREED_SEEDS wheat seeds (a chicken's `follow`), breeds them.
-- The seeds it buys from farmers: possessions.assess wants COOP_SEEDS of them held.
-- Feathers are its own make (ledger.lua's MAKES), so it sells them; eggs have no price, so
-- it keeps them.
--
-- With the economy off there is no flock.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local herd = dofile(core.get_modpath("living_villages") .. "/herd.lua")

local CHICKEN = "mobs_mc:chicken"
local FEATHER = "mcl_mobitems:feather"
local RAW_CHICKEN = "mcl_mobitems:chicken"
local EGG = "mcl_throwing:egg"
local SEEDS = "mcl_farming:wheat_seeds"
local PROFESSION = "butcher"
local COOP_SIZE = 4
local MIN_FLOCK = 2
local BREED_SEEDS = 2
local COOP_SEEDS = 4
local EGG_KEEP = 16
local FEATHER_KEEP = 64
local SCAN_RADIUS = 32
local EGG_RADIUS = 16
local ADOPT_RADIUS = 10
local STEP_SECONDS = 10
local THROW_SECONDS = 20
local TEND_SECONDS = 300

local M = {CHICKEN = CHICKEN, FEATHER = FEATHER, RAW_CHICKEN = RAW_CHICKEN, EGG = EGG, SEEDS = SEEDS,
	COOP_SIZE = COOP_SIZE, MIN_FLOCK = MIN_FLOCK, BREED_SEEDS = BREED_SEEDS, COOP_SEEDS = COOP_SEEDS,
	EGG_KEEP = EGG_KEEP, FEATHER_KEEP = FEATHER_KEEP, SCAN_RADIUS = SCAN_RADIUS, EGG_RADIUS = EGG_RADIUS, ADOPT_RADIUS = ADOPT_RADIUS,
	THROW_SECONDS = THROW_SECONDS, TEND_SECONDS = TEND_SECONDS}

local function short_id(id)
	return tostring(id):sub(1, 6)
end

local function log(fmt, ...)
	core.log("action", "[living_villages] coop: " .. string.format(fmt, ...))
end

-- Whether it keeps a flock: a butcher, not the keeper, grown, with a jobsite.
function M.keeps(self)
	return not self.child and self._id ~= nil and self._profession == PROFESSION and not self._villages_keeper
		and type(self._jobsite) == "table"
end

-- Its flock within SCAN_RADIUS of the jobsite, and the unmarked chickens and chicks within
-- ADOPT_RADIUS it may take on.
function M.scan(self, jobsite)
	local flock, wild = {}, {}
	for _, object in ipairs(core.get_objects_inside_radius(jobsite, SCAN_RADIUS)) do
		local chicken = object:get_luaentity()
		if chicken and chicken.name == CHICKEN and (chicken.health or 1) > 0 then
			if chicken._villages_coop == self._id then
				flock[#flock + 1] = chicken
			elseif not chicken._villages_coop and not chicken.tamed
				and vector.distance(object:get_pos(), jobsite) <= ADOPT_RADIUS then
				wild[#wild + 1] = chicken
			end
		end
	end
	return flock, wild
end

local function adults(flock)
	local list = {}
	for _, chicken in ipairs(flock) do
		if not chicken.child then list[#list + 1] = chicken end
	end
	return list
end

local function mark(self, chicken)
	chicken._villages_coop = self._id
	chicken.persistent = true
end

-- A flock under MIN_FLOCK takes on the chickens near. Returns the flock.
function M.gather(self, flock, wild)
	for _, chicken in ipairs(wild) do
		if #flock >= MIN_FLOCK then break end
		mark(self, chicken)
		flock[#flock + 1] = chicken
		log("butcher %s took on a %s", short_id(self._id), chicken.child and "chick" or "chicken")
	end
	return flock
end

-- Picks up the eggs lying near the jobsite, up to EGG_KEEP held. Returns how many.
function M.collect_eggs(self, jobsite)
	local taken = 0
	for _, object in ipairs(core.get_objects_inside_radius(jobsite, EGG_RADIUS)) do
		local item = object:get_luaentity()
		if item and item.name == "__builtin:item" and type(item.itemstring) == "string" then
			local name, count = item.itemstring:match("^(%S+)%s*(%d*)")
			count = tonumber(count) or 1
			local room = EGG_KEEP - possessions.count(self, EGG)
			if name == EGG and room >= count then
				possessions.add(self, EGG, count)
				object:remove()
				taken = taken + count
			end
		end
	end
	if taken > 0 then log("butcher %s picked up %d egg(s)", short_id(self._id), taken) end
	return taken
end

-- Throws one egg it holds onto a spot near the jobsite. Returns whether it did.
function M.throw_egg(self, jobsite)
	if possessions.count(self, EGG) < 1 or not (mcl_throwing and mcl_throwing.throw) then return false end
	local from = self.object and self.object:get_pos()
	if not from then return false end
	local spot = herd.spot(jobsite) or jobsite
	from = {x = from.x, y = from.y + 1.5, z = from.z}
	possessions.take(self, EGG, 1)
	mcl_throwing.throw(EGG, from, vector.direction(from, spot), nil, self.object)
	log("butcher %s threw an egg toward %s", short_id(self._id), core.pos_to_string(spot))
	return true
end

-- Slaughters one adult: a raw chicken and feathers as its drops would give.
function M.slaughter(self, chicken, random)
	random = random or math.random
	local feathers = random(0, 2)
	possessions.add(self, RAW_CHICKEN, 1)
	if feathers > 0 then possessions.add(self, FEATHER, feathers) end
	chicken._villages_coop = nil
	chicken.object:remove()
	log("butcher %s slaughtered a chicken for 1 chicken and %d feather(s)", short_id(self._id), feathers)
	return feathers
end

-- Breeds two adults on BREED_SEEDS seeds: a chick beside the jobsite. Returns whether it did.
function M.breed(self, jobsite)
	if possessions.count(self, SEEDS) < BREED_SEEDS then return false end
	local spot = herd.spot(jobsite)
	local object = spot and mcl_mobs and mcl_mobs.spawn_child and mcl_mobs.spawn_child(spot, CHICKEN)
	local chick = object and object:get_luaentity()
	if not chick then return false end
	possessions.take(self, SEEDS, BREED_SEEDS)
	mark(self, chick)
	log("butcher %s bred a chick on %d wheat seeds", short_id(self._id), BREED_SEEDS)
	return true
end

-- One tending: a feather from each adult (up to FEATHER_KEEP held), then slaughter past
-- COOP_SIZE adults, else breed with room for a chick.
function M.tend(self, jobsite, flock)
	local grown = adults(flock)
	local feathers = math.min(#grown, math.max(FEATHER_KEEP - possessions.count(self, FEATHER), 0))
	if feathers > 0 then
		possessions.add(self, FEATHER, feathers)
		log("butcher %s collected %d feather(s)", short_id(self._id), feathers)
	end
	if #grown > COOP_SIZE then
		M.slaughter(self, grown[1])
		return "slaughtered"
	end
	if #grown >= 2 and #flock <= COOP_SIZE and M.breed(self, jobsite) then return "bred" end
	return nil
end

local next_step = setmetatable({}, {__mode = "k"})
local next_throw = setmetatable({}, {__mode = "k"})

function M.step(self, now)
	if now < (next_step[self] or 0) then return end
	next_step[self] = now + STEP_SECONDS
	if not M.keeps(self) then return end
	local jobsite = self._jobsite
	local flock, wild = M.scan(self, jobsite)
	flock = M.gather(self, flock, wild)
	herd.keep_near(jobsite, flock)
	if common.schedule_stage(nil, self) ~= "work" then return end
	M.collect_eggs(self, jobsite)
	if #flock < MIN_FLOCK and now >= (next_throw[self] or 0) and M.throw_egg(self, jobsite) then
		next_throw[self] = now + THROW_SECONDS
	end
	if now < (self._villages_coop_next or 0) then return end
	self._villages_coop_next = now + TEND_SECONDS
	M.tend(self, jobsite, flock)
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
	if not M.keeps(self) then return "no coop" end
	local flock = M.scan(self, self._jobsite)
	return string.format("%d chickens (%d grown), %d eggs, %d wheat seeds, %d feathers", #flock, #adults(flock),
		possessions.count(self, EGG), possessions.count(self, SEEDS), possessions.count(self, FEATHER))
end

return M
