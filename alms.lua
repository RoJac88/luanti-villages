-- Donations and alms (docs/villager-economy-design.md, ticket 11c): a safety net for
-- villagers who run out of money, and the cleric's income.
--
-- The cleric does it all, in the holiday social stage after the service (common.lua),
-- while the congregation is kept about the pulpit (church.lua): every RECHECK_SECONDS it
-- looks at the villagers within REACH of the pulpit it claimed (cleric.lua).
--
-- Donating. Each villager there with more than SAVINGS emeralds gives a tenth of the
-- excess, at least 1, once a holiday (`_villages_donated` holds the day). The cleric
-- keeps half, rounded down, in its belongings and puts the rest in its alms fund
-- (`_villages_alms`). Every other villager there sees it and notes good gossip about the
-- donor (gossip.lua, a villager subject): minor_positive, which spreads in conversation,
-- and major_positive too for MAJOR or more, which as in Java is never passed on (its
-- sharing cost is above its maximum). That standing moves the donor's prices with them
-- (exchange.lua).
--
-- Alms. Each villager there that cannot pay for a dinner (ledger.DINNER) is topped up to
-- two dinners' worth from the fund, as far as it goes, once a holiday
-- (`_villages_alms_got`). Donations are taken first, so today's gifts can go out today;
-- what is left waits for the next holiday.
--
-- SAVINGS and MAJOR are in dinners, which carry ledger.SCALE (ticket 11h): the design's
-- 8 and 5 emeralds were written before money was scaled.
--
-- With the economy off nothing is given.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local cleric = dofile(core.get_modpath("living_villages") .. "/cleric.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")

local EMERALD = ledger.EMERALD
local DINNER = ledger.DINNER
local SAVINGS = 8 * DINNER
local MAJOR = 2 * DINNER
local ALMS_TO = 2 * DINNER
-- church.lua's SOCIAL_RADIUS, which keeps the congregation this near the pulpit.
local REACH = 12
local RECHECK_SECONDS = 1
local VILLAGER = "mobs_mc:villager"

local M = {SAVINGS = SAVINGS, MAJOR = MAJOR, ALMS_TO = ALMS_TO, REACH = REACH}

local function short_id(id)
	return tostring(id):sub(1, 6)
end

-- What a villager with `emeralds` gives.
function M.donation(emeralds)
	if emeralds <= SAVINGS then return 0 end
	return math.max(math.floor((emeralds - SAVINGS) / 10), 1)
end

-- Takes the donor's gift, if it owes one today. `witnesses` note it. Returns the gift.
function M.collect(priest, donor, witnesses, day, gossip)
	if donor._villages_donated == day then return 0 end
	donor._villages_donated = day
	local gift = M.donation(possessions.emeralds(donor))
	if gift == 0 then return 0 end
	possessions.take(donor, EMERALD, gift)
	local kept = math.floor(gift / 2)
	if kept > 0 then possessions.add(priest, EMERALD, kept) end
	priest._villages_alms = (priest._villages_alms or 0) + gift - kept
	donor._villages_gave = {count = gift, day = day}
	core.log("action", string.format("[living_villages] alms: villager %s gave %d emerald(s) to cleric %s (kept %d, fund %d)",
		short_id(donor._id), gift, short_id(priest._id), kept, priest._villages_alms))
	if gossip then
		local subject = gossip.villager_subject(donor._id)
		for _, other in ipairs(witnesses) do
			if other ~= donor then
				gossip.add(other, subject, "minor_positive")
				if gift >= MAJOR then gossip.add(other, subject, "major_positive") end
			end
		end
	end
	return gift
end

-- Tops a villager that cannot pay for a dinner up to ALMS_TO, once today. Returns the alms.
function M.give(priest, poor, day)
	if poor == priest or poor._villages_alms_got == day then return 0 end
	local has = possessions.emeralds(poor)
	if has >= DINNER then return 0 end
	local alms = math.min(ALMS_TO - has, priest._villages_alms or 0)
	if alms <= 0 then return 0 end
	poor._villages_alms_got = day
	priest._villages_alms = priest._villages_alms - alms
	if priest._villages_alms <= 0 then priest._villages_alms = nil end
	possessions.add(poor, EMERALD, alms)
	core.log("action", string.format("[living_villages] alms: cleric %s gave %d emerald(s) to villager %s (had %d, fund %d)",
		short_id(priest._id), alms, short_id(poor._id), has, priest._villages_alms or 0))
	return alms
end

-- The adult villagers within REACH of the pulpit, the cleric among them.
local function congregation(pulpit)
	local list = {}
	for _, object in ipairs(core.get_objects_inside_radius(pulpit, REACH)) do
		local entity = object:get_luaentity()
		if entity and entity.name == VILLAGER and entity._id and not entity.child then list[#list + 1] = entity end
	end
	table.sort(list, function(a, b) return a._id < b._id end)
	return list
end

-- Donations first, then alms, among `list`.
function M.hold(priest, list, day, gossip)
	for _, villager in ipairs(list) do
		if villager ~= priest then M.collect(priest, villager, list, day, gossip) end
	end
	for _, villager in ipairs(list) do M.give(priest, villager, day) end
end

local next_check = setmetatable({}, {__mode = "k"})

function M.step(self, now, gossip)
	if now < (next_check[self] or 0) then return end
	next_check[self] = now + RECHECK_SECONDS
	if self._profession ~= "cleric" or self.child then return end
	if common.schedule_stage(nil, self) ~= "social" then return end
	local pulpit = cleric.claimed_pulpit(self)
	if not pulpit then return end
	M.hold(self, congregation(pulpit), core.get_day_count(), gossip)
end

function M.install(def, gossip)
	if not clock.enabled() then return end
	local original = def.do_custom
	def.do_custom = function(self, dtime)
		local result = original(self, dtime)
		M.step(self, core.get_gametime(), gossip)
		return result
	end
end

-- One line for the inspector: what it last gave or got, and a cleric's fund.
function M.status(self)
	local parts = {}
	if self._villages_gave then
		parts[#parts + 1] = string.format("gave %d on day %d", self._villages_gave.count, self._villages_gave.day)
	end
	if self._villages_alms_got then parts[#parts + 1] = "alms on day " .. self._villages_alms_got end
	if self._profession == "cleric" then parts[#parts + 1] = "alms fund " .. (self._villages_alms or 0) end
	return #parts > 0 and table.concat(parts, ", ") or "none"
end

return M
