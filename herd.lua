-- The leatherworker's cow herd (docs/villager-economy-design.md, ticket 11e): the only
-- leather a village makes, for the librarian's books, and beef for the butcher.
--
-- A leatherworker with a jobsite keeps up to HERD_SIZE ordinary mobs_mc:cow about it,
-- marked with its villager id in `_villages_herder` (saved on the cow; the herd is found
-- again by scanning, so an unload loses nothing, and without this mod the field is
-- inert). Every STEP_SECONDS it counts the marked cows within SCAN_RADIUS of its jobsite
-- and adopts unmarked adult cows within ADOPT_RADIUS until the herd is full. A herd that
-- has never had a cow gets SEED_COWS beside the jobsite once (`_villages_herd_seeded`), as
-- flock.lua's shepherds get their first sheep, since few villages have cows near. A cow
-- past LEASH with no player within UNSEEN is set back beside the jobsite.
--
-- In the work stage, every BREED_SECONDS (`_villages_herd_next`, game time):
-- * with more than HERD_SIZE adults it slaughters one, as a kill would drop it
--   (mobs_mc/cow+mooshroom.lua): 1 to 3 beef and 0 to 2 leather, into its belongings;
-- * otherwise, with two adults, room for a calf and BREED_WHEAT wheat (a cow's `follow`,
--   one for each parent), it breeds them: the wheat is used and a calf spawned
--   (mcl_mobs.spawn_child), marked as the herd's. So the herd grows to HERD_SIZE adults
--   and a calf, then each new adult is slaughtered.
-- The wheat it buys from farmers: possessions.assess wants HERD_WHEAT of it held.
--
-- With the economy off there is no herd.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")

local COW = "mobs_mc:cow"
local PROFESSION = "leatherworker"
local WHEAT = "mcl_farming:wheat_item"
local BEEF = "mcl_mobitems:beef"
local LEATHER = "mcl_mobitems:leather"
local HERD_SIZE = 4
local SEED_COWS = 2
local BREED_WHEAT = 2
local HERD_WHEAT = 4
local STEP_SECONDS = 10
local BREED_SECONDS = 300
local SCAN_RADIUS = 32
local ADOPT_RADIUS = 16
local LEASH, UNSEEN = 24, 24
-- Where a cow is set down: within this of the jobsite, on walkable ground under two air.
local SPOT_MIN, SPOT_MAX = 2, 6

local M = {HERD_SIZE = HERD_SIZE, SEED_COWS = SEED_COWS, BREED_WHEAT = BREED_WHEAT, HERD_WHEAT = HERD_WHEAT,
	BREED_SECONDS = BREED_SECONDS, PROFESSION = PROFESSION, WHEAT = WHEAT}

local function short_id(id)
	return tostring(id):sub(1, 6)
end

local function walkable(pos)
	local node = core.get_node_or_nil(pos)
	local def = node and core.registered_nodes[node.name]
	return def ~= nil and def.walkable ~= false
end

local function air(pos)
	local node = core.get_node_or_nil(pos)
	return node ~= nil and node.name == "air"
end

-- A free spot near the jobsite to set a cow down on, or nil.
function M.spot(jobsite)
	for r = SPOT_MIN, SPOT_MAX do
		for dx = -r, r do
			for dz = -r, r do
				if math.max(math.abs(dx), math.abs(dz)) == r then
					for dy = 2, -2, -1 do
						local feet = {x = jobsite.x + dx, y = jobsite.y + dy, z = jobsite.z + dz}
						if walkable({x = feet.x, y = feet.y - 1, z = feet.z}) and air(feet)
							and air({x = feet.x, y = feet.y + 1, z = feet.z}) then
							return feet
						end
					end
				end
			end
		end
	end
	return nil
end

-- Its herd within SCAN_RADIUS of the jobsite: the marked cows, and wild adult ones within
-- ADOPT_RADIUS it may take on.
function M.scan(self, jobsite)
	local herd, wild = {}, {}
	for _, object in ipairs(core.get_objects_inside_radius(jobsite, SCAN_RADIUS)) do
		local cow = object:get_luaentity()
		if cow and cow.name == COW and (cow.health or 1) > 0 then
			if cow._villages_herder == self._id then
				herd[#herd + 1] = cow
			elseif not cow._villages_herder and not cow.child and not cow.tamed
				and vector.distance(object:get_pos(), jobsite) <= ADOPT_RADIUS then
				wild[#wild + 1] = cow
			end
		end
	end
	return herd, wild
end

local function adults(herd)
	local list = {}
	for _, cow in ipairs(herd) do
		if not cow.child then list[#list + 1] = cow end
	end
	return list
end

local function mark(self, cow)
	cow._villages_herder = self._id
	cow.persistent = true
end

-- Fills the herd from wild cows, or seeds it the first time. Returns the herd.
function M.gather(self, jobsite, herd, wild)
	for _, cow in ipairs(wild) do
		if #herd >= HERD_SIZE then break end
		mark(self, cow)
		herd[#herd + 1] = cow
		core.log("action", string.format("[living_villages] herd: leatherworker %s took on a cow", short_id(self._id)))
	end
	if #herd == 0 and not self._villages_herd_seeded then
		self._villages_herd_seeded = true
		for _ = 1, SEED_COWS do
			local spot = M.spot(jobsite)
			local object = spot and core.add_entity(spot, COW)
			local cow = object and object:get_luaentity()
			if cow then
				mark(self, cow)
				herd[#herd + 1] = cow
			end
		end
		core.log("action", string.format("[living_villages] herd: leatherworker %s started a herd of %d at %s",
			short_id(self._id), #herd, core.pos_to_string(jobsite)))
	end
	return herd
end

local function player_near(pos)
	for _, object in ipairs(core.get_objects_inside_radius(pos, UNSEEN)) do
		if object:is_player() then return true end
	end
	return false
end

-- Sets a stray cow no player sees back beside the jobsite.
local function leash(jobsite, herd)
	for _, cow in ipairs(herd) do
		local pos = cow.object:get_pos()
		if pos and vector.distance(pos, jobsite) > LEASH and not player_near(pos) then
			local spot = M.spot(jobsite)
			if spot then cow.object:set_pos(spot) end
		end
	end
end

-- Slaughters one adult: beef and leather as its drops would give, into its belongings.
function M.slaughter(self, cow, random)
	random = random or math.random
	local beef, leather = random(1, 3), random(0, 2)
	possessions.add(self, BEEF, beef)
	if leather > 0 then possessions.add(self, LEATHER, leather) end
	cow._villages_herder = nil
	cow.object:remove()
	core.log("action", string.format("[living_villages] herd: leatherworker %s slaughtered a cow for %d beef and %d leather",
		short_id(self._id), beef, leather))
	return beef, leather
end

-- Breeds two adults on BREED_WHEAT wheat: a calf beside the jobsite. Returns whether it did.
function M.breed(self, jobsite)
	if possessions.count(self, WHEAT) < BREED_WHEAT then return false end
	local spot = M.spot(jobsite)
	local object = spot and mcl_mobs and mcl_mobs.spawn_child and mcl_mobs.spawn_child(spot, COW)
	local calf = object and object:get_luaentity()
	if not calf then return false end
	possessions.take(self, WHEAT, BREED_WHEAT)
	mark(self, calf)
	core.log("action", string.format("[living_villages] herd: leatherworker %s bred a calf on %d wheat",
		short_id(self._id), BREED_WHEAT))
	return true
end

-- One work-stage turn: slaughter past HERD_SIZE adults, else breed with room for a calf.
function M.tend(self, jobsite, herd)
	local grown = adults(herd)
	if #grown > HERD_SIZE then
		M.slaughter(self, grown[1])
		return "slaughtered"
	end
	if #grown >= 2 and #herd <= HERD_SIZE and M.breed(self, jobsite) then return "bred" end
	return nil
end

local next_step = setmetatable({}, {__mode = "k"})

function M.step(self, now)
	if now < (next_step[self] or 0) then return end
	next_step[self] = now + STEP_SECONDS
	local jobsite = self._jobsite
	if self.child or self._profession ~= PROFESSION or not jobsite or not self._id then return end
	local herd, wild = M.scan(self, jobsite)
	herd = M.gather(self, jobsite, herd, wild)
	leash(jobsite, herd)
	if common.schedule_stage(nil, self) ~= "work" then return end
	if now < (self._villages_herd_next or 0) then return end
	self._villages_herd_next = now + BREED_SECONDS
	M.tend(self, jobsite, herd)
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
	if self._profession ~= PROFESSION then return "not a leatherworker" end
	if not self._jobsite then return "no jobsite" end
	local herd = M.scan(self, self._jobsite)
	return string.format("%d cows (%d grown), %d wheat", #herd, #adults(herd), possessions.count(self, WHEAT))
end

return M
