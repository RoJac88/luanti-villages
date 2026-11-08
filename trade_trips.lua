-- Trade trips (docs/villager-economy-design.md, Exchange between villagers, channel 2;
-- ticket 11): a villager with an urgent need walks to a seller it has heard of and buys.
--
-- Planning. A need is urgent when the buyer's value for it is at least URGENT (2) times
-- its base price (ledger.lua's urgency: it holds under half its target). The seller is
-- one it has heard has the item spare (market news "has" entries, market_news.lua), at
-- a value under the buyer's, whose home (bed) is within TRIP_RADIUS of the buyer. Of
-- those it takes the need worth most (count times value), then the nearest seller. A
-- seller that came to nothing is passed over for SKIP_SECONDS.
--
-- The trip (`_villages_trade_trip`, saved, dropped when the day turns) has legs:
-- * "seller": to the seller's home. If the seller is within SELLER_REACH there, loaded,
--   it is the end-of-conversation trade (exchange.lua) for that one item, from the
--   seller's belongings. If not, or it has none on it, on to its stash.
-- * "stash": to the seller's claimed stash (a chest near its home whose `villages_owner`
--   meta is the seller, possessions.lua). It buys from the chest, at the midpoint of its
--   own value and the value it heard the seller put on the item, paying emeralds into
--   the chest, with exchange.lua's rules: whole emeralds, at least one, both gaining by
--   those values.
-- * "deliver": only a porter's (below). A porter's trip is not dropped with the day: it
--   goes on to deliver, so the purse goes back.
-- A walk is navigation.lua's gopath; one that ends short is tried again, and after
-- MAX_TRIES, or WALK_TIMEOUT with no end at all, the trip fails.
--
-- When. Anyone's own trip in the putter stage, outside a conversation. The Builder,
-- whose bench chests are short (builder_market.lua), also in its work stage, with
-- builder.lua's activity_override keeping vanilla from calling it back to the bench.
--
-- Porters. A nitwit or unemployed villager may choose the porter activity for the day
-- (labour.lua). At the end of a conversation (conversation.lua, after exchange.lua), a
-- porter with no trip is hired by a member that has a job (a jobsite, the keeper or the
-- Builder), an urgent need with a known seller, somewhere to deliver to (its stash, or the
-- Builder's bench chest) and at least PORTER_FEE + 1 emeralds: it hands the porter a purse
-- of up to PURSE emeralds. The porter makes the trip in its work stage, buying with the
-- purse at its client's value, then walks to the delivery chest and leaves the goods and
-- what is left of the purse less PORTER_FEE, which it keeps if it bought anything. A
-- failed trip returns the whole purse.
--
-- With the economy off nothing happens.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local news = dofile(core.get_modpath("living_villages") .. "/market_news.lua")
local exchange = dofile(core.get_modpath("living_villages") .. "/exchange.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")

local URGENT = 2
local TRIP_RADIUS = 64
local SELLER_REACH = 8
-- How near a chest it must stand to reach in; how near a home counts as there.
local REACH = 3
local ARRIVE_REACH = 4
local STASH_SEARCH = 9
local STEP_SECONDS = 2
local PLAN_SECONDS = 30
local WALK_TIMEOUT = 120
local MAX_TRIES = 3
local SKIP_SECONDS = 600
local PORTER_FEE = 1
local PURSE = 8
local EMERALD = "mcl_core:emerald"
local VILLAGER = "mobs_mc:villager"

local M = {
	URGENT = URGENT, TRIP_RADIUS = TRIP_RADIUS, PORTER_FEE = PORTER_FEE, PURSE = PURSE,
	SKIP_SECONDS = SKIP_SECONDS,
}

local function short_id(id)
	return tostring(id):sub(1, 6)
end

local function log(text, ...)
	core.log("action", "[living_villages] trade trip: " .. string.format(text, ...))
end

local function today()
	return core.get_day_count and core.get_day_count() or 0
end

-- Sellers each villager passed over, by "who|item", until when; walks under way, since
-- when; the next plan. In memory only.
local skipped = setmetatable({}, {__mode = "k"})
local walking = setmetatable({}, {__mode = "k"})
local next_step = setmetatable({}, {__mode = "k"})
local next_plan = setmetatable({}, {__mode = "k"})

local function is_skipped(self, who, item)
	local list = skipped[self]
	return list ~= nil and (list[who .. "|" .. item] or 0) > core.get_gametime()
end

local function skip(self, who, item)
	skipped[self] = skipped[self] or {}
	skipped[self][who .. "|" .. item] = core.get_gametime() + SKIP_SECONDS
end

-- The buyer's value over the base price, or 1.
function M.urgency(view, item)
	local price, value = ledger.price(item), view.value(item)
	if not price or price <= 0 or not value then return 1 end
	return value / price
end

-- The trip it would make now, or nil. `from` is where distances count from.
function M.plan(self, view, heard, from)
	local best, best_worth, best_distance
	for item, need in pairs(view.needs) do
		local value = view.value(item)
		if item ~= EMERALD and value and M.urgency(view, item) >= URGENT then
			for _, entry in ipairs(heard) do
				if entry.kind == "has" and entry.item == item and entry.home and entry.who ~= self._id
					and (entry.price or 0) < value and not is_skipped(self, entry.who, item) then
					local distance = vector.distance(from, entry.home)
					local worth = need * value
					if distance <= TRIP_RADIUS and (not best or worth > best_worth
						or (worth == best_worth and distance < best_distance)) then
						best, best_worth, best_distance = entry, worth, distance
					end
				end
			end
		end
	end
	if not best then return nil end
	return {
		item = best.item, who = best.who, home = vector.new(best.home), price = best.price or 0,
		want = view.needs[best.item], leg = "seller", day = today(),
	}
end

-- The loaded adult villager with this _id within SELLER_REACH of pos, or nil.
function M.find_seller(pos, who)
	for _, object in ipairs(core.get_objects_inside_radius(pos, SELLER_REACH)) do
		local entity = object:get_luaentity()
		if entity and entity.name == VILLAGER and entity._id == who and not entity.child then return entity end
	end
	return nil
end

-- The chest near home claimed by `who`, or nil.
function M.find_stash(home, who)
	local minp = {x = home.x - STASH_SEARCH, y = home.y - STASH_SEARCH, z = home.z - STASH_SEARCH}
	local maxp = {x = home.x + STASH_SEARCH, y = home.y + STASH_SEARCH, z = home.z + STASH_SEARCH}
	local best, best_distance
	for _, pos in ipairs(core.find_nodes_in_area(minp, maxp, stock.CHEST_NODES)) do
		if core.get_meta(pos):get_string(possessions.OWNER) == who then
			local distance = vector.distance(pos, home)
			if not best or distance < best_distance then best, best_distance = pos, distance end
		end
	end
	return best
end

local function inventories(chest)
	local list = {}
	for _, half in ipairs(possessions.halves(chest)) do
		local inv = core.get_meta(half):get_inventory()
		if inv then list[#list + 1] = inv end
	end
	return list
end

local function chest_count(chest, item)
	local total = 0
	for _, inv in ipairs(inventories(chest)) do
		for _, stack in ipairs(inv:get_list("main") or {}) do
			if stack:get_name() == item then total = total + stack:get_count() end
		end
	end
	return total
end

-- Puts count of the item into the chest. Returns how many fitted.
local function put(chest, item, count)
	local left = count
	for _, inv in ipairs(inventories(chest)) do
		if left <= 0 then break end
		left = inv:add_item("main", item .. " " .. left):get_count()
	end
	return count - left
end

local function take(chest, item, count)
	local taken = 0
	for _, inv in ipairs(inventories(chest)) do
		if taken >= count then break end
		taken = taken + inv:remove_item("main", item .. " " .. (count - taken)):get_count()
	end
	return taken
end

-- The terms of a sale of up to `want` of `held` at the midpoint of `value` (buyer's) and
-- `price` (seller's), with at most `budget` emeralds: count, pay; or nil.
function M.terms(want, held, value, price, budget)
	if value <= price or held <= 0 or budget < 1 then return nil end
	local unit = (value + price) / 2
	local count = math.min(want, held)
	if count * unit < 1 then count = math.min(math.ceil(1 / unit), held) end
	local pay = math.max(math.floor(count * unit + 0.5), 1)
	if pay > budget then
		count = math.min(count, math.floor(budget / unit))
		pay = math.max(math.floor(count * unit + 0.5), 1)
	end
	if count < 1 or pay > budget or pay > count * value or pay < count * price then return nil end
	return count, pay
end

-- What it may spend and its value for the item, for its own trip or a client's.
local function budget_and_value(self, trip)
	if trip.client then return trip.client.purse - (trip.spent or 0), trip.client.value end
	return possessions.emeralds(self), possessions.assess(self).value(trip.item) or 0
end

-- Buys from the stash. Returns how many it bought.
function M.buy_from_stash(self, trip, chest)
	local budget, value = budget_and_value(self, trip)
	local want = trip.want - (trip.bought or 0)
	local count, pay = M.terms(want, chest_count(chest, trip.item), value, trip.price, budget)
	if not count or possessions.emeralds(self) < pay then return 0 end
	local taken = take(chest, trip.item, count)
	if taken < count then
		if taken > 0 then put(chest, trip.item, taken) end
		return 0
	end
	possessions.take(self, EMERALD, pay)
	local paid = put(chest, EMERALD, pay)
	if paid < pay then possessions.add(self, EMERALD, pay - paid) end
	possessions.add(self, trip.item, count)
	trip.bought, trip.spent = (trip.bought or 0) + count, (trip.spent or 0) + paid
	log("villager %s bought %d %s from %s's stash for %d emerald(s)", short_id(self._id), count, trip.item,
		short_id(trip.who), paid)
	return count
end

-- Buys from the seller in person. Returns how many it bought.
function M.buy_in_person(self, trip, seller)
	local budget, value = budget_and_value(self, trip)
	local view
	if trip.client then
		local item = trip.item
		view = {
			needs = {[item] = trip.want - (trip.bought or 0)}, surplus = {},
			value = function(i)
				if i == item then return value end
				if i == EMERALD then return 1 end
				return nil
			end,
		}
	else
		view = possessions.assess(self)
	end
	local offer = exchange.offer(seller, possessions.assess(seller), self, view, trip.item)
	if not offer or (offer.pay and offer.pay > budget) or (trip.client and not offer.pay) then return 0 end
	if not exchange.settle(offer) then return 0 end
	trip.bought, trip.spent = (trip.bought or 0) + offer.count, (trip.spent or 0) + (offer.pay or 0)
	return offer.count
end

-- A porter leaves the goods and the rest of the purse at the delivery chest.
function M.deliver(self, trip)
	local client = trip.client
	local goods = math.min(trip.bought or 0, possessions.count(self, trip.item))
	local fee = (trip.bought or 0) > 0 and client.fee or 0
	local back = math.max(client.purse - (trip.spent or 0) - fee, 0)
	back = math.min(back, possessions.emeralds(self))
	local left_goods = goods - put(client.deliver, trip.item, goods)
	possessions.take(self, trip.item, goods - left_goods)
	local left_back = back - put(client.deliver, EMERALD, back)
	possessions.take(self, EMERALD, back - left_back)
	log("porter %s delivered %d %s and %d emerald(s) for %s at %s, kept %d", short_id(self._id), goods - left_goods,
		trip.item, back - left_back, short_id(client.id), core.pos_to_string(client.deliver), fee)
end

local function finish(self, now)
	self._villages_trade_trip = nil
	walking[self] = nil
	next_plan[self] = now + PLAN_SECONDS
end

local function fail(self, trip, why, now)
	skip(self, trip.who, trip.item)
	log("villager %s gave up on %s from %s: %s", short_id(self._id), trip.item, short_id(trip.who), why)
	if trip.client and trip.leg ~= "deliver" then
		trip.leg, trip.tries = "deliver", 0
		return
	end
	finish(self, now)
end

local function done_buying(self, trip, now)
	if trip.client then
		trip.leg, trip.tries = "deliver", 0
	else
		finish(self, now)
	end
end

local function walk(self, trip, target, now)
	trip.tries = (trip.tries or 0) + 1
	if trip.tries > MAX_TRIES then return fail(self, trip, "could not get there", now) end
	walking[self] = now
	local started = self:gopath(target, function(entity) walking[entity] = nil end, true)
	if started == false then
		walking[self] = nil
		fail(self, trip, "no way there", now)
	end
end

-- One step of a trip under way.
function M.advance(self, trip, now)
	local pos = self.object:get_pos()
	if not pos then return end
	if trip.leg == "seller" then
		if vector.distance(pos, trip.home) > ARRIVE_REACH then return walk(self, trip, trip.home, now) end
		local seller = M.find_seller(pos, trip.who)
		if seller and M.buy_in_person(self, trip, seller) > 0 then return done_buying(self, trip, now) end
		local stash = M.find_stash(trip.home, trip.who)
		if not stash then return fail(self, trip, seller and "no trade" or "nobody home", now) end
		trip.leg, trip.stash, trip.tries = "stash", stash, 0
		return M.advance(self, trip, now)
	elseif trip.leg == "stash" then
		if vector.distance(pos, trip.stash) > REACH then return walk(self, trip, trip.stash, now) end
		if M.buy_from_stash(self, trip, trip.stash) > 0 then return done_buying(self, trip, now) end
		return fail(self, trip, "nothing to buy in the stash", now)
	elseif trip.leg == "deliver" then
		if vector.distance(pos, trip.client.deliver) > REACH then return walk(self, trip, trip.client.deliver, now) end
		M.deliver(self, trip)
		return finish(self, now)
	end
end

-- Whether a stage lets it go on its trip: its own in the putter stage, the Builder's
-- and a porter's in the work stage too.
local function may_travel(self, trip, stage)
	if stage == "putter" then return true end
	if stage ~= "work" then return false end
	if trip and trip.client then return true end
	return self._villages_builder_wants ~= nil
end

local function busy(self)
	return self._villages_talk ~= nil or self.following ~= nil or self._villages_sleeping
		or (self.state == "gowp" and not walking[self])
end

function M.step(self, now)
	if self.child or not self._id then return end
	local trip = self._villages_trade_trip
	if trip and trip.day ~= today() then
		if trip.client then
			-- A porter still owes its client the purse: it goes to deliver what it has.
			if trip.leg ~= "deliver" then trip.leg, trip.tries = "deliver", 0 end
			trip.day = today()
		else
			log("villager %s dropped yesterday's trip for %s", short_id(self._id), trip.item)
			self._villages_trade_trip, trip = nil, nil
		end
	end
	local stage = common.schedule_stage(nil, self)
	if not may_travel(self, trip, stage) or busy(self) then return end
	if trip and walking[self] then
		if now - walking[self] < WALK_TIMEOUT then return end
		walking[self] = nil
		return fail(self, trip, "the walk never ended", now)
	end
	if not trip then
		if now < (next_plan[self] or 0) then return end
		next_plan[self] = now + PLAN_SECONDS
		local pos = self.object:get_pos()
		if not pos then return end
		trip = M.plan(self, possessions.assess(self), news.heard(self, now), self._bed or pos)
		if not trip then return end
		self._villages_trade_trip = trip
		log("villager %s sets off for %d %s from %s at %s", short_id(self._id), trip.want, trip.item,
			short_id(trip.who), core.pos_to_string(trip.home))
	end
	M.advance(self, trip, now)
end

-- Where a member would have a porter deliver to: its stash, or a Builder's bench chest.
local function delivery(self)
	local stash = self._villages_stash
	if stash and core.get_meta(stash):get_string(possessions.OWNER) == self._id then return vector.new(stash) end
	if self._villages_builder_drop then return vector.new(self._villages_builder_drop) end
	return nil
end

local function is_porter(self)
	local labour = self._villages_labour
	return labour ~= nil and labour.day == today() and labour.activity == "porter"
end

local function has_job(self)
	return self._jobsite ~= nil or self._villages_keeper or self._villages_builder
end

-- At the end of a conversation, each porter with no trip may be hired by another member.
-- Returns the hires made.
function M.hire(members)
	if not clock.enabled() then return {} end
	local now = core.get_gametime()
	local hires = {}
	for _, porter in ipairs(members) do
		if is_porter(porter) and not porter._villages_trade_trip then
			for _, client in ipairs(members) do
				local deliver = client ~= porter and has_job(client) and not client._villages_trade_trip
					and delivery(client)
				local emeralds = deliver and possessions.emeralds(client) or 0
				if deliver and emeralds >= PORTER_FEE + 1 then
					local view = possessions.assess(client)
					local pos = client.object and client.object:get_pos()
					local trip = M.plan(client, view, news.heard(client, now), client._bed or pos or deliver)
					if trip then
						local purse = math.min(emeralds, PURSE)
						possessions.take(client, EMERALD, purse)
						possessions.add(porter, EMERALD, purse)
						trip.client = {
							id = client._id, deliver = deliver, purse = purse, fee = PORTER_FEE,
							value = view.value(trip.item),
						}
						porter._villages_trade_trip = trip
						hires[#hires + 1] = {porter = porter, client = client, trip = trip}
						log("villager %s hired porter %s with %d emerald(s) for %d %s from %s", short_id(client._id),
							short_id(porter._id), purse, trip.want, trip.item, short_id(trip.who))
						break
					end
				end
			end
		end
	end
	return hires
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
			M.step(self, now)
		end
		return result
	end
end

-- One line for the inspector.
function M.status(self)
	local trip = self._villages_trade_trip
	if not trip then return "none" end
	local text = string.format("%s %s from %s (%s)", trip.want, trip.item:gsub("^.*:", ""), short_id(trip.who), trip.leg)
	if trip.client then text = text .. ", porter for " .. short_id(trip.client.id) end
	return text
end

return M
