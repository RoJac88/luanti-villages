-- Rent to the Builder's bench (docs/villager-economy-design.md, Rent; ticket 11b). Money
-- went one way: dinner money reaches the food producers and stops there, and a Builder,
-- whose goods no villager buys, ran out. Rent takes it back to the Builder, which spends
-- it on materials, which quarriers and woodcutters spend at the tavern.
--
-- * Landlord. A claimed Builder's bench, not the villager holding it, so the next Builder
--   inherits the income. Benches are learnt from loaded Builders (note_bench, every step
--   of one); a village with no claimed bench collects nothing.
-- * Tenants. A villager whose bed carries `villages_landlord` (LANDLORD, the bench's
--   position), written by mark_beds when the Builder finishes a building; and, in a
--   generated village, farmers and fishermen (FOOD_PRODUCERS), as if their houses had been
--   built for them, owing the nearest claimed bench within VILLAGE_RADIUS of the bed. The
--   Builder, the keeper and its household (possessions.same_house with a keeper's bed,
--   learnt like benches) and children owe nothing.
-- * How much. RENT every RENT_DAYS days of economic clock (economy_clock.lua), so time
--   away from players costs nothing. Owing starts when the landlord is first known; while
--   none is known the clock runs on unbilled.
-- * Arrears. Up to RENT_CAP; past that, forgiven and logged. No eviction. A tenant pays
--   only from emeralds above DINNER (meal.lua's VILLAGER_PRICE), so it eats first.
-- * Paying. settle(members), when a conversation runs its time and before its trades:
--   a tenant of a member Builder's bench hands it what it owes, belongings to belongings.
--   Otherwise, owing anything it can pay, it goes by errand (`_villages_rent_errand`, the
--   chest) in its putter stage: it walks to the bench's nearest chest (farm_stock.find_chests,
--   the Builder's CHEST_RADIUS) and leaves the emeralds there, where builder_market.lua
--   tops the Builder's purse up from. A failed errand waits for the next day. (The probe
--   showed conversations with the Builder too rare, and too often cut short, to rely on.)
--
-- `_villages_rent` is {owed, at = clock reading billed up to, bench, paid = {count, day,
-- how}}. Every payment and forgiveness is logged. Off with the economy.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")

local RENT = 1
local RENT_DAYS = 2
local RENT_CAP = 3
local DINNER = 1
local VILLAGE_RADIUS = 128
local CHEST_RADIUS = 32
local REACH = 3
local MAX_TRIES = 3
local WALK_TIMEOUT = 120
local STEP_SECONDS = 5
local LANDLORD = "villages_landlord"
local BENCH = "living_villages:builder_block"
local EMERALD = "mcl_core:emerald"
local FOOD_PRODUCERS = {farmer = true, fisherman = true}

local M = {
	RENT = RENT, RENT_DAYS = RENT_DAYS, RENT_CAP = RENT_CAP, DINNER = DINNER, LANDLORD = LANDLORD,
	VILLAGE_RADIUS = VILLAGE_RADIUS,
}

local benches, keeper_beds = {}, {}
local walking = setmetatable({}, {__mode = "k"})
local next_step = setmetatable({}, {__mode = "k"})

local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
local function short_id(id) return tostring(id):sub(1, 6) end
local function log(fmt, ...) core.log("action", "[living_villages] " .. string.format(fmt, ...)) end

-- Seconds of game time in a game day (food.lua's rule), or nil while time stands still.
local function day_seconds()
	local speed = core.settings and tonumber(core.settings:get("time_speed")) or 72
	if speed <= 0 then return nil end
	return 86400 / speed
end

-- A position written by core.pos_to_string, or nil.
local function to_pos(text)
	local x, y, z = (text or ""):match("^%((%-?[%d.]+),%s*(%-?[%d.]+),%s*(%-?[%d.]+)%)$")
	return x and {x = tonumber(x), y = tonumber(y), z = tonumber(z)} or nil
end

local function claimed(pos)
	local node = pos and core.get_node_or_nil(pos)
	return node ~= nil and node.name == BENCH and core.get_meta(pos):get_string("villager") ~= ""
end

-- A loaded Builder's bench, so food producers can find their landlord.
function M.note_bench(pos)
	if pos then benches[key(pos)] = vector.new(pos) end
end

function M.note_keeper(self)
	if self._bed then keeper_beds[self._id] = vector.new(self._bed) end
end

-- Forgets what was noted (tests).
function M.reset()
	benches, keeper_beds = {}, {}
end

local function exempt(self)
	if self.child or not self._id or not self._bed or self._villages_builder or self._villages_keeper then return true end
	for _, bed in pairs(keeper_beds) do
		if possessions.same_house(bed, self._bed) then return true end
	end
	return false
end

-- The bench this villager owes rent to, or nil.
function M.landlord(self)
	if exempt(self) then return nil end
	local meta = core.get_meta(self._bed)
	local tagged = meta and to_pos(meta:get_string(LANDLORD))
	if tagged and claimed(tagged) then return tagged end
	if not FOOD_PRODUCERS[self._profession] then return nil end
	local best, best_distance
	for k, pos in pairs(benches) do
		if not claimed(pos) then
			benches[k] = nil
		else
			local distance = vector.distance(pos, self._bed)
			if distance <= VILLAGE_RADIUS and (not best or distance < best_distance) then best, best_distance = pos, distance end
		end
	end
	return best
end

-- Bills the clock run since it last did. Returns what it owes.
function M.accrue(self)
	local rent = self._villages_rent
	local now, day = clock.read(self), day_seconds()
	local bench = day and M.landlord(self)
	if not bench then
		-- Nothing owed for time without a landlord.
		if rent then rent.at, rent.bench = now, nil end
		return rent and rent.owed or 0
	end
	if not rent then
		rent = {owed = 0, at = now}
		self._villages_rent = rent
	end
	rent.bench = vector.new(bench)
	local period = RENT_DAYS * day
	local due = math.floor((now - rent.at) / period)
	if due > 0 then
		rent.at = rent.at + due * period
		rent.owed = rent.owed + due * RENT
		if rent.owed > RENT_CAP then
			log("villager %s owed %d rent to the bench at %s; %d forgiven", short_id(self._id), rent.owed,
				core.pos_to_string(bench), rent.owed - RENT_CAP)
			rent.owed = RENT_CAP
		end
	end
	return rent.owed
end

-- What it can pay now: what it owes, from emeralds above a dinner.
function M.payable(self)
	local rent = self._villages_rent
	if not rent or rent.owed <= 0 then return 0 end
	return math.max(math.min(rent.owed, possessions.emeralds(self) - DINNER), 0)
end

local function paid(self, count, how)
	local rent = self._villages_rent
	rent.owed = rent.owed - count
	rent.paid = {count = count, day = core.get_day_count(), how = how}
end

-- When a conversation runs its time: tenants pay a member Builder of their landlord's bench.
-- Returns how many emeralds changed hands.
function M.settle(members)
	if not clock.enabled() then return 0 end
	local total = 0
	for _, builder in ipairs(members) do
		local bench = builder._villages_builder and builder._jobsite
		if bench and claimed(bench) and core.get_meta(bench):get_string("villager") == builder._id then
			for _, tenant in ipairs(members) do
				if tenant ~= builder then
					M.accrue(tenant)
					local rent = tenant._villages_rent
					local count = rent and rent.bench and vector.distance(rent.bench, bench) == 0 and M.payable(tenant) or 0
					if count > 0 then
						possessions.take(tenant, EMERALD, count)
						possessions.add(builder, EMERALD, count)
						paid(tenant, count, "in person")
						total = total + count
						log("villager %s paid %d emerald(s) rent to builder %s in person, owes %d", short_id(tenant._id),
							count, short_id(builder._id), rent.owed)
					end
				end
			end
		end
	end
	return total
end

local function put(chest, count)
	local inv = core.get_meta(chest):get_inventory()
	if not inv then return 0 end
	return count - inv:add_item("main", EMERALD .. " " .. count):get_count()
end

local function drop_errand(self, why)
	local errand = self._villages_rent_errand
	self._villages_rent_errand = nil
	walking[self] = nil
	if self._villages_rent then self._villages_rent.errand_day = core.get_day_count() end
	if why then
		log("villager %s gave up paying rent at %s: %s", short_id(self._id),
			errand and core.pos_to_string(errand.chest) or "?", why)
	end
end

local function busy(self)
	return self._villages_talk ~= nil or self.following ~= nil or self._villages_sleeping
		or self._villages_trade_trip ~= nil or (self.state == "gowp" and not walking[self])
end

-- One step of the errand, or of deciding on one.
function M.step(self, now)
	if self.child or not self._id then return end
	M.accrue(self)
	local rent, errand = self._villages_rent, self._villages_rent_errand
	if common.schedule_stage(nil, self) ~= "putter" then
		if errand then drop_errand(self) end
		return
	end
	if busy(self) then return end
	if errand and walking[self] then
		if now - walking[self] < WALK_TIMEOUT then return end
		return drop_errand(self, "the walk never ended")
	end
	if not errand then
		if not rent or not rent.bench or M.payable(self) < 1
			or rent.errand_day == core.get_day_count() then
			return
		end
		local chest = stock.find_chests(rent.bench, CHEST_RADIUS)[1]
		if not chest then return end
		errand = {chest = vector.new(chest), tries = 0}
		self._villages_rent_errand = errand
		log("villager %s sets off to pay %d emerald(s) rent at %s", short_id(self._id), M.payable(self),
			core.pos_to_string(chest))
	end
	local pos = self.object:get_pos()
	if not pos then return end
	if vector.distance(pos, errand.chest) > REACH then
		errand.tries = errand.tries + 1
		if errand.tries > MAX_TRIES then return drop_errand(self, "could not get there") end
		walking[self] = now
		local started = self:gopath(errand.chest, function(entity) walking[entity] = nil end, true)
		if started == false then return drop_errand(self, "no way there") end
		return
	end
	local count = M.payable(self)
	local moved = count > 0 and put(errand.chest, count) or 0
	if moved > 0 then
		possessions.take(self, EMERALD, moved)
		paid(self, moved, "by errand")
		log("villager %s paid %d emerald(s) rent into the chest at %s, owes %d", short_id(self._id), moved,
			core.pos_to_string(errand.chest), rent.owed)
		self._villages_rent_errand = nil
		return
	end
	drop_errand(self, count > 0 and "the chest is full" or "nothing to pay")
end

-- When a Builder finishes a building: its beds owe rent to the bench.
function M.mark_beds(bench, minp, maxp)
	local count = 0
	for _, pos in ipairs(core.find_nodes_in_area(minp, maxp, {"group:bed"})) do
		core.get_meta(pos):set_string(LANDLORD, core.pos_to_string(bench))
		count = count + 1
	end
	return count
end

function M.install(def)
	if not clock.enabled() then return end
	local original = def.do_custom
	def.do_custom = function(self, dtime)
		local result = original(self, dtime)
		if result == false then return result end
		local now = core.get_gametime()
		if now >= (next_step[self] or 0) then
			next_step[self] = now + STEP_SECONDS
			if self._villages_builder then M.note_bench(self._jobsite) end
			if self._villages_keeper then M.note_keeper(self) end
			M.step(self, now)
		end
		return result
	end
end

-- One line for the inspector.
function M.status(self)
	local rent = self._villages_rent
	if not rent or not rent.bench then return "none" end
	local text = string.format("owes %d to the bench at %s", rent.owed, core.pos_to_string(rent.bench))
	if rent.paid then text = text .. string.format(", paid %d on day %d (%s)", rent.paid.count, rent.paid.day, rent.paid.how) end
	if self._villages_rent_errand then text = text .. ", on its way to pay" end
	return text
end

return M
