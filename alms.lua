-- Donations and alms (docs/villager-economy-design.md, ticket 11c): a safety net for
-- villagers who run out of money, and the cleric's income.
--
-- The cleric does it all, in the holiday social stage after the service (common.lua),
-- while the congregation is kept about the pulpit (church.lua): every RECHECK_SECONDS it
-- looks at the villagers within REACH of the pulpit it claimed (cleric.lua).
--
-- Donating. Each villager there with more than SAVINGS emeralds gives a tenth of the
-- excess, at least 1, once a holiday (`_villages_donated` holds the day). The cleric
-- keeps KEEP_SHARE (a tenth, rounded down; half until ticket 19, when the cleric held a
-- third of a village's money) in its belongings and puts the rest in its alms fund
-- (`_villages_alms`). Every other villager there sees it and notes good gossip about the
-- donor (gossip.lua, a villager subject): minor_positive, which spreads in conversation,
-- and major_positive too for MAJOR or more, which as in Java is never passed on (its
-- sharing cost is above its maximum). That standing moves the donor's prices with them
-- (exchange.lua).
--
-- Alms. Each villager there with less than two dinners' worth (ALMS_TO; one dinner until
-- ticket 19) is topped up to it from the fund, as far as it goes, once a holiday
-- (`_villages_alms_got`). Donations are taken first, so today's gifts can go out today;
-- what is left waits for the next holiday.
--
-- A craftsman's stake (ColonyFood, 2026-11-14). A tool smith with one emerald could not
-- buy the cobble and sticks for the stone hoe a farmer wanted, nor a butcher the beef
-- piling up at the leatherworker's, so they made nothing and starved. One with a recipe at
-- its tier (recipes.lua; not the keeper or a Builder, who have the tavern's and the
-- bench's money) is topped up past ALMS_TO by the price of CRAFT_BATCH crafts of its
-- cheapest recipe, fuel too, at base prices (ledger.price), at most STAKE_CAP. Everyone's
-- ALMS_TO is given first, the stakes after. When the fund runs short the cleric gives from
-- its own emeralds over SAVINGS: it held 610 it had no use for.
--
-- A fund that spends down (ticket 22a; ColonyFood, 2026-11-15: villagers gave 1,337 over
-- 13 days and the cleric gave 18 back, so the village's money drained into the fund). Its
-- target is FUND_HOLIDAYS holidays of alms for the congregation it sees: each one's
-- ALMS_TO and stake (M.level), at its own dinner scale. A donation is taken only while the
-- fund is under the target, and no more than it lacks; over it donors keep their money and
-- spend it. What the fund holds over the target goes out after the alms and stakes,
-- poorest first, topping villagers up toward SAVINGS at the old dinner (18), not at their
-- own dinner scale: with dinner at 1 that was 8 emeralds, and a fund of 1,702 gave 15
-- (ColonyFood, 2026-11-15).
--
-- The rich give more (ticket 37b): donations are progressive, a tenth of savings from 8 to
-- 24 dinners, a fifth from 24 to 64 and three tenths past 64 (BANDS), at least 1, in place
-- of a tenth of all past 8. A librarian paid for a Mending book gives back a good share of
-- it, to go round as alms.
--
-- Rotten flesh (ticket 37b). The fund's target adds FLESH_RESERVE (12 dinners) to its
-- holidays of alms, so the cleric can buy the flesh players sell it (trade_window.lua). The
-- alms part is noted at each service (`_villages_alms_need`); the flesh budget is the fund
-- past it and the cleric's own emeralds past SAVINGS (`flesh_budget`), paid fund first
-- (`pay_flesh`). Until its first service it pays only from its own. Leather it sells comes
-- back to its own emeralds, which alms draw on past SAVINGS too.
--
-- News. Each villager there also swaps market news with the cleric once a holiday
-- (`_villages_church_news`), as diners do with the keeper (meal.lua): the service is no
-- time for conversations, and the social stage after it lasts seconds, so the cleric
-- carries what one churchgoer needs to another that has it.
--
-- SAVINGS and MAJOR are in dinners, which carry ledger.SCALE (ticket 11h): the design's
-- 8 and 5 emeralds were written before money was scaled. Since ticket 21e every amount
-- here counts dinners at the villager's own reference price for one (dinner.scale): the
-- donor's, the poor's, the cleric's.
--
-- With the economy off nothing is given.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local cleric = dofile(core.get_modpath("living_villages") .. "/cleric.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local news = dofile(core.get_modpath("living_villages") .. "/market_news.lua")
local dinner = dofile(core.get_modpath("living_villages") .. "/dinner.lua")

local EMERALD = ledger.EMERALD
local DINNER = ledger.DINNER
local SAVINGS = 8 * DINNER
local MAJOR = 2 * DINNER
local ALMS_TO = 2 * DINNER
local KEEP_SHARE = 0.1
-- church.lua's SOCIAL_RADIUS, which keeps the congregation this near the pulpit.
local REACH = 12
local RECHECK_SECONDS = 1
local VILLAGER = "mobs_mc:villager"
local CRAFT_BATCH = 4
local STAKE_CAP = 3 * DINNER
local FUND_HOLIDAYS = 4
-- Progressive donations: the share of savings from each band's start, in dinners.
local BANDS = {{from = 8, share = 0.1}, {from = 24, share = 0.2}, {from = 64, share = 0.3}}
local FLESH_RESERVE = 12 * DINNER
local COAL = "mcl_core:coal_lump"
local recipes = dofile(core.get_modpath("living_villages") .. "/recipes.lua")

local M = {SAVINGS = SAVINGS, MAJOR = MAJOR, ALMS_TO = ALMS_TO, KEEP_SHARE = KEEP_SHARE, REACH = REACH,
	FLESH_RESERVE = FLESH_RESERVE, BANDS = BANDS,
	CRAFT_BATCH = CRAFT_BATCH, STAKE_CAP = STAKE_CAP, FUND_HOLIDAYS = FUND_HOLIDAYS}

local function short_id(id)
	return tostring(id):sub(1, 6)
end

-- What a villager with `emeralds` gives, its dinners at `scale` (dinner.scale, 1 unset):
-- each band's share of what it holds in that band (BANDS), at least 1 past SAVINGS.
function M.donation(emeralds, scale)
	scale = scale or 1
	local savings = SAVINGS * scale
	if emeralds <= savings then return 0 end
	local gift = 0
	for i, band in ipairs(BANDS) do
		local from = band.from * DINNER * scale
		local to = BANDS[i + 1] and BANDS[i + 1].from * DINNER * scale or math.huge
		if emeralds > from then gift = gift + (math.min(emeralds, to) - from) * band.share end
	end
	return math.max(math.floor(gift), 1)
end

-- Puts `gift` emeralds a player donated (trade_window.lua, ticket 36) with the cleric:
-- KEEP_SHARE in its belongings, the rest in its alms fund, as a villager's donation.
-- Returns what it kept.
function M.receive(priest, gift)
	local kept = math.floor(gift * KEEP_SHARE)
	if kept > 0 then possessions.add(priest, EMERALD, kept) end
	priest._villages_alms = (priest._villages_alms or 0) + gift - kept
	core.log("action", string.format("[living_villages] alms: a player gave %d emerald(s) to cleric %s (kept %d, fund %d)",
		gift, short_id(priest._id), kept, priest._villages_alms))
	return kept
end

-- Takes the donor's gift, if it owes one today, no more than `room` (what the fund lacks
-- of its target; nil, no limit). `witnesses` note it. Returns the gift.
function M.collect(priest, donor, witnesses, day, gossip, room)
	if donor._villages_donated == day then return 0 end
	donor._villages_donated = day
	local scale = dinner.scale(donor)
	local gift = M.donation(possessions.emeralds(donor), scale)
	if room then gift = math.min(gift, math.max(math.ceil(room), 0)) end
	if gift == 0 then return 0 end
	possessions.take(donor, EMERALD, gift)
	local kept = math.floor(gift * KEEP_SHARE)
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
				if gift >= MAJOR * scale then gossip.add(other, subject, "major_positive") end
			end
		end
	end
	return gift
end

-- A craftsman's stake (see above): 0 for one with no recipe to make.
function M.stake(villager)
	if villager.child or villager._villages_keeper or villager._villages_builder then return 0 end
	local tier = villager._max_trade_tier or 1
	local cheapest
	for _, recipe in ipairs(recipes[villager._profession] or {}) do
		if (recipe.tier or 1) <= tier then
			local cost = recipe.fuel and (ledger.price(COAL) or 0) * recipe.fuel or 0
			for _, input in ipairs(recipe.from) do
				local price = ledger.price(input[1])
				if not price then cost = nil; break end
				cost = cost + price * input[2]
			end
			if cost and (not cheapest or cost < cheapest) then cheapest = cost end
		end
	end
	if not cheapest then return 0 end
	return math.min(math.ceil(cheapest * CRAFT_BATCH), math.ceil(STAKE_CAP * dinner.scale(villager)))
end

-- The most alms a villager gets in a holiday: ALMS_TO and its stake, at its dinner scale.
function M.level(villager)
	return math.ceil(ALMS_TO * dinner.scale(villager)) + M.stake(villager)
end

-- The fund's target among `list`: FUND_HOLIDAYS holidays of everyone's level but the
-- cleric's own.
function M.fund_target(priest, list)
	local total = 0
	for _, villager in ipairs(list) do
		if villager ~= priest then total = total + M.level(villager) end
	end
	return FUND_HOLIDAYS * total
end

-- The cleric's own emeralds over SAVINGS.
local function own_spare(priest)
	return math.max(math.floor(possessions.emeralds(priest) - SAVINGS * dinner.scale(priest)), 0)
end

-- The fund's whole target among `list`: its alms (M.fund_target) and the flesh reserve.
function M.target(priest, list)
	return M.fund_target(priest, list) + M.flesh_reserve(priest)
end

-- What the cleric can give: its fund, then its own emeralds over SAVINGS.
local function can_give(priest)
	return (priest._villages_alms or 0) + own_spare(priest)
end

-- The flesh reserve, at the cleric's dinner scale.
function M.flesh_reserve(priest)
	return math.ceil(FLESH_RESERVE * dinner.scale(priest))
end

-- What the cleric can pay for rotten flesh: the fund past its alms part (none before its
-- first service) and its own emeralds over SAVINGS.
function M.flesh_budget(priest)
	local need = priest._villages_alms_need
	local fund = need and math.max(math.floor((priest._villages_alms or 0) - need), 0) or 0
	return fund + own_spare(priest)
end

-- Pays `amount` for flesh: from the fund past its alms part first, then its own emeralds.
-- Returns whether the budget covered it.
function M.pay_flesh(priest, amount)
	if M.flesh_budget(priest) < amount then return false end
	local need = priest._villages_alms_need
	local from_fund = need and math.min(amount, math.max(math.floor((priest._villages_alms or 0) - need), 0)) or 0
	if from_fund > 0 then
		priest._villages_alms = priest._villages_alms - from_fund
		if priest._villages_alms <= 0 then priest._villages_alms = nil end
	end
	if amount > from_fund then possessions.take(priest, EMERALD, amount - from_fund) end
	return true
end

local function pay_out(priest, amount)
	local from_fund = math.min(amount, priest._villages_alms or 0)
	priest._villages_alms = (priest._villages_alms or 0) - from_fund
	if priest._villages_alms <= 0 then priest._villages_alms = nil end
	if amount > from_fund then possessions.take(priest, EMERALD, amount - from_fund) end
end

-- Tops a villager up to `upto` (ALMS_TO, or with its stake, M.stake), once today for each
-- level, giving at most `limit` (nil, no limit). Returns the alms.
function M.give(priest, poor, day, upto, limit)
	upto = upto or math.ceil(ALMS_TO * dinner.scale(poor))
	if poor == priest or (poor._villages_alms_got == day and (poor._villages_alms_upto or ALMS_TO) >= upto) then
		return 0
	end
	local has = possessions.emeralds(poor)
	if has >= upto then return 0 end
	local alms = math.min(upto - has, can_give(priest), limit or math.huge)
	if alms <= 0 then return 0 end
	poor._villages_alms_got, poor._villages_alms_upto = day, upto
	pay_out(priest, alms)
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

-- Swaps market news with the cleric, once a holiday. Returns whether it did.
function M.church_news(priest, villager, day)
	if villager == priest or villager._villages_church_news == day then return false end
	villager._villages_church_news = day
	news.exchange({villager, priest})
	return true
end

-- Donations first, then alms, then news, among `list`. An alchemist (ticket 20) never goes
-- to church, so one that happens to stand near the pulpit neither gives nor gets.
function M.hold(priest, list, day, gossip)
	local members = {}
	for _, villager in ipairs(list) do
		if not villager._villages_alchemist then members[#members + 1] = villager end
	end
	list = members
	local need = M.fund_target(priest, list)
	priest._villages_alms_need = need
	local target = need + M.flesh_reserve(priest)
	for _, villager in ipairs(list) do
		if villager ~= priest then
			M.collect(priest, villager, list, day, gossip, target - (priest._villages_alms or 0))
		end
	end
	for _, villager in ipairs(list) do M.give(priest, villager, day) end
	for _, villager in ipairs(list) do
		local stake = M.stake(villager)
		if stake > 0 then M.give(priest, villager, day, M.level(villager)) end
	end
	-- The fund over its target goes out, poorest first, toward each one's savings.
	local poorest = {}
	for _, villager in ipairs(list) do
		if villager ~= priest then poorest[#poorest + 1] = villager end
	end
	table.sort(poorest, function(a, b)
		local ea, eb = possessions.emeralds(a), possessions.emeralds(b)
		if ea ~= eb then return ea < eb end
		return a._id < b._id
	end)
	for _, villager in ipairs(poorest) do
		local over = (priest._villages_alms or 0) - target
		if over <= 0 then break end
		M.give(priest, villager, day, SAVINGS, math.floor(over))
	end
	for _, villager in ipairs(list) do M.church_news(priest, villager, day) end
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
