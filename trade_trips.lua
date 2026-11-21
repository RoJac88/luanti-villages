-- Trade trips (docs/villager-economy-design.md, Exchange between villagers, channel 2;
-- ticket 11): a villager with an urgent need walks to a seller it has heard of and buys.
--
-- Planning. A need is urgent when the buyer's value for it is at least URGENT (2) times
-- its base price (ledger.lua's urgency: it holds under half its target). The seller is
-- one it has heard has the item spare (market news "has" entries, market_news.lua), at
-- a value under the buyer's, whose home (bed) is within TRIP_RADIUS of the buyer. Of
-- those it takes the need worth most (count times value), then the nearest seller. A
-- seller that came to nothing is passed over for SKIP_SECONDS. With no emerald it plans
-- no trip of its own: it could buy nothing there.
--
-- The trip (`_villages_trade_trip`, saved, dropped when the day turns) has legs:
-- * "seller": to the seller's home. If the seller is within SELLER_REACH there, loaded,
--   it is the end-of-conversation trade (exchange.lua) for that one item, from the
--   seller's belongings. If it is out but loaded within TRIP_RADIUS of its home, the
--   buyer goes after it ("chase", to where it stands, at most CHASES times as it moves):
--   villagers carry what they sell. If it is nowhere near, or has none on it, on to its
--   stash.
-- * "stash": to the seller's claimed stash (a chest near its home whose `villages_owner`
--   meta is the seller, possessions.lua). It buys from the chest, at the midpoint of its
--   own value and the value it heard the seller put on the item, paying emeralds into
--   the chest, with exchange.lua's rules: whole emeralds, at least one, both gaining by
--   those values.
-- * "deliver": only a porter's (below). A porter's trip is not dropped with the day: it
--   goes on to deliver, so the purse goes back.
-- A walk is navigation.lua's gopath; one that ends short is tried again. One that cannot
-- start, or ends short MAX_TRIES times, or has no end at all after WALK_TIMEOUT, falls
-- back: from the seller's home to the seller where it is, from there to its stash. Only
-- a stash, or a porter's delivery, it cannot reach fails the trip. A seller is walked to
-- at the cell it stands in (cells.standing_cell), not its rounded position.
--
-- When. Anyone plans its own trip in the putter stage, outside a conversation; the
-- Builder, whose bench chests are short (builder_market.lua), also in its work stage, and
-- so does the alchemist (ticket 24), whose timetable has no putter time to speak of and
-- which hears of every seller (market_news.overhear). A
-- trip under way goes on in the work stage too (the putter stage is about 75 s, too
-- short for most trips), with M.activity_override, or builder.lua's for the Builder,
-- keeping vanilla from calling it back to its jobsite. It is dropped once the day after
-- the one it was planned on is over.
-- Planning. Only news whose count can make up a sale under M.terms, at the seller's asking
-- price (asks.lua, heard in the news) and within its emeralds: a seller with too little
-- spare to come to a whole emerald could not sell (run 34's wool trip). One short of
-- emeralds for all it wants buys as many as they pay for.
--
-- Porters. A nitwit or unemployed villager may choose the porter activity for the day
-- (labour.lua). At the end of a conversation (conversation.lua, after exchange.lua), a
-- porter with no trip is hired by a member that has a job (a jobsite, the keeper or the
-- Builder), an urgent need with a known seller, somewhere to deliver to (its stash, or the
-- Builder's bench chest) and at least PORTER_FEE + 1 emeralds: it hands the porter a purse
-- for the lot at its value for it and the fee, up to PURSE emeralds (M.purse_for), once a
-- day. The porter makes the trip in its work stage, buying with the purse at its client's
-- value, then walks to the delivery chest and leaves the goods and what is left of the
-- purse less PORTER_FEE, which it keeps if it bought anything. A
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
local prices = dofile(core.get_modpath("living_villages") .. "/prices.lua")
local dinner = dofile(core.get_modpath("living_villages") .. "/dinner.lua")
local asks = dofile(core.get_modpath("living_villages") .. "/asks.lua")
local alchemist = dofile(core.get_modpath("living_villages") .. "/alchemist.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local cells = dofile(core.get_modpath("living_villages") .. "/cells.lua")
local goods_mod = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local commission = dofile(core.get_modpath("living_villages") .. "/commission.lua")
-- As builder_market.lua splits them.
local PLANKS_PER_LOG = 4

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
local CHASES = 3
local SKIP_SECONDS = 600
-- A seller whose stash it found empty is passed over for a game day (at the default
-- time_speed), and the news of its spare forgotten (ticket 12b: run on 2026-11-11 had
-- 15 trips to the butcher's empty stash for cooked porkchop it had heard was spare).
local EMPTY_SKIP_SECONDS = 1200
-- In emeralds at ledger.SCALE (ticket 11h).
local PORTER_FEE = 1 * ledger.SCALE
local PURSE = 8 * ledger.SCALE
local EMERALD = "mcl_core:emerald"
local VILLAGER = "mobs_mc:villager"

local M = {
	URGENT = URGENT, TRIP_RADIUS = TRIP_RADIUS, PORTER_FEE = PORTER_FEE, PURSE = PURSE,
	SKIP_SECONDS = SKIP_SECONDS, EMPTY_SKIP_SECONDS = EMPTY_SKIP_SECONDS, PLAN_SECONDS = PLAN_SECONDS,
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
-- Sellers passed over for too few, logged once a day each: villager -> {key = day}.
local logged_short = setmetatable({}, {__mode = "k"})

local function is_skipped(self, who, item)
	local list = skipped[self]
	return list ~= nil and (list[who .. "|" .. item] or 0) > core.get_gametime()
end

local function skip(self, who, item, seconds)
	skipped[self] = skipped[self] or {}
	skipped[self][who .. "|" .. item] = core.get_gametime() + (seconds or SKIP_SECONDS)
end

-- Forgets what it heard of `who` having `item` spare: it has seen otherwise.
local function forget_spare(self, who, item)
	local list = self._villages_market_news
	if not list then return end
	local kept = {}
	for _, entry in ipairs(list) do
		if not (entry.kind == "has" and entry.who == who and entry.item == item) then kept[#kept + 1] = entry end
	end
	self._villages_market_news = #kept > 0 and kept or nil
end

-- The buyer's value over the base price, or 1.
-- How urgent a need is: the view's own (ledger.lua), not capped by what a good that
-- wears out is worth (run 46: a hoe, worth 1.6 times its price, never made a trip).
function M.urgency(view, item)
	if view.urgency then return view.urgency(item) end
	local price, value = ledger.price(item), view.value(item)
	if not price or price <= 0 or not value then return 1 end
	return value / price
end

-- Logs, once a day per seller and item, a seller passed over as too few for a sale: the
-- count heard and, when the seller is loaded near its home, what it carries now (ticket
-- 11g: whether heard counts lag behind sellers still gathering).
local function log_short(self, entry, need, value)
	local seen = logged_short[self] or {}
	logged_short[self] = seen
	local key = entry.who .. " " .. entry.item
	if seen[key] == today() then return end
	seen[key] = today()
	local seller = M.locate(entry.home, entry.who)
	local now = seller and tostring(possessions.count(seller, entry.item)) or "unknown"
	log("villager %s passes over %s's %s: heard %d spare (carries %s now), needs %d, worth %.2f each to it, asked %.2f, has %d emerald(s)",
		short_id(self._id), short_id(entry.who), entry.item, entry.count or 0, now, need, value, entry.price or 0,
		possessions.emeralds(self))
end

-- The trip it would make now, or nil. `from` is where distances count from.
function M.plan(self, view, heard, from)
	local best, best_worth, best_distance
	for item, need in pairs(view.needs) do
		local value = view.value(item)
		if item ~= EMERALD and value and M.urgency(view, item) >= URGENT then
			for _, entry in ipairs(heard) do
				if entry.kind == "has" and entry.item == item and entry.home and entry.who ~= self._id
					and (entry.price or 0) <= value and not is_skipped(self, entry.who, item)
					and vector.distance(from, entry.home) <= TRIP_RADIUS
					and (M.terms(need, entry.count or 0, value, entry.price or 0, possessions.emeralds(self))
						or log_short(self, entry, need, value)) then
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
		-- A product the seller makes on sale (ticket 29): its sources, as told.
		from = best.from, ratio = best.ratio, takes = best.takes, reserve = best.reserve,
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

-- The loaded adult villager with this _id within TRIP_RADIUS of home, or nil.
function M.locate(home, who)
	for _, object in ipairs(core.get_objects_inside_radius(home, TRIP_RADIUS)) do
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

-- The terms of a sale of up to `want` of `held` at `price` (the seller's ask), to a buyer
-- that values one at `value`, with at most `budget` emeralds: count, pay; or nil.
function M.terms(want, held, value, price, budget)
	if value < price or price <= 0 or held <= 0 or budget < 1 then return nil end
	local unit = price
	local count = math.min(want, held)
	if count * unit < 1 then count = math.min(math.ceil(1 / unit), held) end
	local pay = math.max(math.floor(count * unit + 0.5), 1)
	if pay > budget then
		count = math.min(count, math.floor(budget / unit))
		pay = math.max(math.floor(count * unit + 0.5), 1)
	end
	-- Rounded to whole emeralds, the pay may fall half an emerald short of the ask.
	if count < 1 or pay > budget or pay < count * price - 0.5 then return nil end
	return count, pay
end

-- What it may spend and its value for the item, for its own trip or a client's.
local function budget_and_value(self, trip)
	if trip.client then return trip.client.purse - (trip.spent or 0), trip.client.value end
	return possessions.emeralds(self), possessions.assess(self).value(trip.item) or 0
end

-- Buys from the stash. Returns how many it bought, and with none why not.
-- A trip for a product made on sale (an ingot from nine nuggets, ticket 29) takes the
-- sources when the stash holds none of the product: whole lots of `takes`, none of the
-- `reserve`, at the told price for each product.
function M.buy_from_stash(self, trip, chest)
	local budget, value = budget_and_value(self, trip)
	local want = trip.want - (trip.bought or 0)
	local held = chest_count(chest, trip.item)
	local conversion
	if held == 0 and trip.from and trip.ratio then
		conversion = {ratio = trip.ratio, takes = trip.takes, reserve = trip.reserve}
		held = goods_mod.yield(conversion, chest_count(chest, trip.from))
	end
	local count, pay = M.terms(want, held, value, trip.price, budget)
	local item, taking = trip.item, count
	if count and conversion then
		-- Whole batches only: the products a whole number of `takes` sources give.
		local gives = goods_mod.yield(conversion, (conversion.takes or 1) + (conversion.reserve or 0))
		count = math.floor(count / gives) * gives
		pay = count >= 1 and math.max(math.floor(count * trip.price + 0.5), 1) or nil
		if not pay or pay > budget then count = nil end
		item, taking = trip.from, count and goods_mod.sources_for(conversion, count)
	end
	if not count or possessions.emeralds(self) < pay then
		return 0, string.format("stash holds %d%s, %d wanted, worth %.2f each to it, asked %.2f, budget %d", held,
			conversion and (" from " .. trip.from) or "", want, value, trip.price, budget)
	end
	local taken = take(chest, item, taking)
	if taken < taking then
		if taken > 0 then put(chest, item, taken) end
		return 0, "the stash came up short"
	end
	possessions.take(self, EMERALD, pay)
	local paid = put(chest, EMERALD, pay)
	if paid < pay then possessions.add(self, EMERALD, pay - paid) end
	possessions.add(self, trip.item, count)
	-- Its reference price learns what it paid (ticket 21b), and an alchemist's book (ticket 30).
	prices.learn(self, trip.item, paid / count)
	alchemist.bought(self, possessions.held(self), trip.item, count, paid)
	-- A keeper's dish costs what it paid (dinner.note_cost, ticket 39b).
	if self._villages_keeper then dinner.note_cost(self, trip.item, count, paid) end
	-- The seller, away from its stash but loaded, counts the sale as one made to its face
	-- (ticket 30): its ask and reference price learn it, and an alchemist keeps the price.
	-- Without it the alchemist's stash sales taught it nothing, and its takings never set its bids.
	local seller = trip.home and M.locate(trip.home, trip.who)
	if seller then
		local day = core.get_day_count and core.get_day_count() or 0
		asks.sold(seller, trip.item, day, count, paid / count)
		if item ~= trip.item then asks.sold(seller, item, day, taking, paid / taking) end
	end
	trip.bought, trip.spent = (trip.bought or 0) + count, (trip.spent or 0) + paid
	log("villager %s bought %d %s from %s's stash for %d emerald(s)", short_id(self._id), count, trip.item,
		short_id(trip.who), paid)
	return count
end

-- The seller's ask for the item to its face: the lowest of its own stock's and of each
-- product it makes on sale that it has the sources for (goods.lua), as exchange.offer
-- would sell it. Without the conversions an alchemist holding only nuggets asked an
-- ingot's base price, 149, for the 16 it told (ticket 29).
local function in_person_ask(seller, buyer, item, seller_view, bid)
	local best = possessions.count(seller, item) > 0 and exchange.asking(seller, buyer, item, seller_view, nil, bid) or nil
	for _, conversion in ipairs(goods_mod.conversions(seller)) do
		local sources = possessions.count(seller, conversion.from) - (conversion.reserve or 0)
		if conversion.to == item and sources > 0 and goods_mod.yield(conversion, sources) >= 1 then
			local unit = exchange.asking(seller, buyer, item, seller_view, conversion, bid)
			if unit and (not best or unit < best) then best = unit end
		end
	end
	return best or exchange.asking(seller, buyer, item, seller_view, nil, bid)
end

-- Buys from the seller in person. Returns how many it bought. It asks for no more than
-- its budget covers at the seller's ask (the midpoint for an item with none), so a lot
-- it cannot afford whole is bought in part.
function M.buy_in_person(self, trip, seller)
	local budget, value = budget_and_value(self, trip)
	local item = trip.item
	local seller_view = possessions.assess(seller)
	local seller_value = seller_view.value(item) or 0
	local unit = in_person_ask(seller, self, item, seller_view, math.min(value, budget))
		or (value + seller_value) / 2
	if unit <= 0 then return 0, "no price" end
	if value < unit then return 0, string.format("asks %.2f each, over our %.2f", unit, value) end
	if budget < 1 then return 0, "no budget" end
	local own = not trip.client and possessions.assess(self) or nil
	local need = trip.client and (trip.want - (trip.bought or 0)) or (own.needs[item] or 0)
	need = math.min(need, math.floor(budget / unit))
	if need < 1 then return 0, string.format("needs none at %.2f each", unit) end
	local view = {
		needs = {[item] = need}, surplus = own and own.surplus or {},
		value = own and own.value or function(i)
			if i == item then return value end
			if i == EMERALD then return 1 end
			return nil
		end,
	}
	local offer = exchange.offer(seller, seller_view, self, view, item)
	if not offer then
		-- Spells out what exchange.offer weighed, to tell a seller with none spare from
		-- one that has them but won't sell at our value.
		return 0, string.format("no offer: seller has %d spare of %d carried, values %.2f each to our %.2f, we have %d emerald(s)",
			seller_view.surplus[item] or 0, possessions.count(seller, item), seller_value, view.value(item) or 0,
			possessions.emeralds(self))
	end
	if (offer.pay and offer.pay > budget) or (trip.client and not offer.pay) then
		return 0, "offer over budget"
	end
	if not exchange.settle(offer) then return 0, "settle failed" end
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
	local planks = client.split and goods_mod.SPECIES[trip.item]
	local left_goods
	if planks then
		-- Logs for a Builder go in as the planks they split into (builder_market.lua).
		-- A chest with room for part of a log's planks takes that log whole.
		local placed = put(client.deliver, planks, goods * PLANKS_PER_LOG)
		left_goods = goods - math.ceil(placed / PLANKS_PER_LOG)
	else
		left_goods = goods - put(client.deliver, trip.item, goods)
	end
	possessions.take(self, trip.item, goods - left_goods)
	local left_back = back - put(client.deliver, EMERALD, back)
	possessions.take(self, EMERALD, back - left_back)
	-- A full chest: what did not go in is the client's, handed over in person if it is
	-- about (else the porter keeps it, logged). In ColonyFood (2026-11-19) a commissioned
	-- armor stand met a stash with no free slot, and the porter kept the stand and the price.
	if left_goods > 0 or left_back > 0 then
		local owner = M.locate(client.deliver, client.id)
		if owner then
			possessions.take(self, trip.item, left_goods)
			possessions.add(owner, trip.item, left_goods)
			possessions.take(self, EMERALD, left_back)
			possessions.add(owner, EMERALD, left_back)
			log("porter %s handed %d %s and %d emerald(s) to %s in person, its chest at %s full",
				short_id(self._id), left_goods, trip.item, left_back, short_id(client.id),
				core.pos_to_string(client.deliver))
		else
			log("porter %s could not leave %d %s and %d emerald(s) for %s, its chest at %s full and it away",
				short_id(self._id), left_goods, trip.item, left_back, short_id(client.id),
				core.pos_to_string(client.deliver))
		end
	end
	if trip.commission then
		log("commission: porter %s delivered %d %s and %d emerald(s) for %s at %s", short_id(self._id),
			goods - left_goods, trip.item, back - left_back, short_id(client.id), core.pos_to_string(client.deliver))
		return
	end
	log("porter %s delivered %d %s and %d emerald(s) for %s at %s, kept %d", short_id(self._id), goods - left_goods,
		trip.item, back - left_back, short_id(client.id), core.pos_to_string(client.deliver), fee)
end

local function finish(self, now)
	self._villages_trade_trip = nil
	walking[self] = nil
	next_plan[self] = now + PLAN_SECONDS
end

local function fail(self, trip, why, now, empty)
	if empty then
		skip(self, trip.who, trip.item, EMPTY_SKIP_SECONDS)
		forget_spare(self, trip.who, trip.item)
	else
		skip(self, trip.who, trip.item)
	end
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

local LEG_NAMES = {seller = "home", chase = "whereabouts", stash = "stash", deliver = "delivery"}

-- A leg it cannot walk is not the end of the trip: from the seller's home it goes after
-- the seller where it is, and from there to the seller's stash. Only a stash or a
-- porter's delivery it cannot reach ends the trip. In ColonyFood (2026-11-14) 78 food
-- trips ended at the first walk that could not start, most of them chasing a farmer a
-- few steps away in its field, with the farmer's stash never tried.
local function fall_back(self, trip, why, now)
	log("villager %s cannot reach %s's %s (%s)", short_id(self._id), short_id(trip.who),
		LEG_NAMES[trip.leg] or tostring(trip.leg), why)
	walking[self] = nil
	if trip.leg == "seller" and M.locate(trip.home, trip.who) then
		trip.leg, trip.tries, trip.chases = "chase", 0, 0
		return M.advance(self, trip, now)
	end
	if trip.leg == "seller" or trip.leg == "chase" then return M.to_stash(self, trip, now, why) end
	return fail(self, trip, why, now)
end

local function walk(self, trip, target, now)
	trip.tries = (trip.tries or 0) + 1
	if trip.tries > MAX_TRIES then return fall_back(self, trip, "could not get there", now) end
	walking[self], trip.target = now, target
	-- A lost walk is walked again on the next step, as long as the tries last.
	local started = self:gopath(target, {
		arrived = function(entity)
			walking[entity], trip.lost = nil, nil
		end,
		lost = function(entity, reason)
			walking[entity] = nil
			trip.lost = reason
		end,
	}, true)
	if started == false then
		walking[self] = nil
		fall_back(self, trip, trip.lost and ("no way there; the last walk was " .. trip.lost) or "no way there", now)
	end
end

-- On to the seller's stash, or give up with `why` if it has none.
function M.to_stash(self, trip, now, why)
	local stash = M.find_stash(trip.home, trip.who)
	if not stash then return fail(self, trip, why, now) end
	trip.leg, trip.stash, trip.tries, trip.why = "stash", stash, 0, why
	return M.advance(self, trip, now)
end

-- Whether a villager on a trip stands where its leg's walk was taking it.
function M.at_leg_end(self, trip)
	local pos = self.object:get_pos()
	if not pos then return false end
	local target, reach
	if trip.leg == "seller" then
		target, reach = trip.home, ARRIVE_REACH
	elseif trip.leg == "chase" then
		local seller = M.locate(trip.home, trip.who)
		target, reach = seller and seller.object:get_pos(), SELLER_REACH
	elseif trip.leg == "stash" then
		target, reach = trip.stash, REACH
	elseif trip.leg == "deliver" then
		target, reach = trip.client and trip.client.deliver, REACH
	end
	return target ~= nil and vector.distance(pos, target) <= reach
end

-- One step of a trip under way.
function M.advance(self, trip, now)
	local pos = self.object:get_pos()
	if not pos then return end
	if trip.leg == "seller" then
		if vector.distance(pos, trip.home) > ARRIVE_REACH then return walk(self, trip, trip.home, now) end
		local seller = M.find_seller(pos, trip.who)
		local bought, why = 0, nil
		if seller then bought, why = M.buy_in_person(self, trip, seller) end
		if bought > 0 then return done_buying(self, trip, now) end
		if not seller and M.locate(trip.home, trip.who) then
			trip.leg, trip.tries, trip.chases = "chase", 0, 0
			return M.advance(self, trip, now)
		end
		return M.to_stash(self, trip, now, seller and ("no trade: " .. tostring(why)) or "nobody home")
	elseif trip.leg == "chase" then
		local seller = M.locate(trip.home, trip.who)
		local at = seller and seller.object:get_pos()
		if not at then return M.to_stash(self, trip, now, "lost sight of the seller") end
		if vector.distance(pos, at) <= SELLER_REACH then
			local bought, why = M.buy_in_person(self, trip, seller)
			if bought > 0 then return done_buying(self, trip, now) end
			return M.to_stash(self, trip, now, "no trade: " .. tostring(why))
		end
		trip.chases = (trip.chases or 0) + 1
		if trip.chases > CHASES then return M.to_stash(self, trip, now, "could not catch the seller") end
		trip.tries = 0
		-- The cell it stands in, not its rounded position: on farmland that is the soil.
		return walk(self, trip, cells.standing_cell(at), now)
	elseif trip.leg == "stash" then
		if vector.distance(pos, trip.stash) > REACH then return walk(self, trip, trip.stash, now) end
		local bought, why = M.buy_from_stash(self, trip, trip.stash)
		if bought > 0 then return done_buying(self, trip, now) end
		return fail(self, trip, "nothing to buy in the stash (" .. tostring(why) .. "; before it, " .. tostring(trip.why) .. ")", now, true)
	elseif trip.leg == "deliver" then
		if vector.distance(pos, trip.client.deliver) > REACH then return walk(self, trip, trip.client.deliver, now) end
		M.deliver(self, trip)
		return finish(self, now)
	end
end

-- Whether a stage lets it go on a trip: plan one in the putter stage (the Builder and the
-- alchemist in the work stage too), and go on with one under way in either.
local function may_travel(self, trip, stage)
	if stage == "putter" then return true end
	if stage ~= "work" then return false end
	return trip ~= nil or self._villages_alchemist or commission.of(self) ~= nil or self._villages_builder_wants ~= nil or self._villages_builder_logs ~= nil
		or self._villages_builder_wool ~= nil
end

-- common.activity_override: a villager on a trip in its work stage is not called back to
-- its jobsite ("putter" is no order to vanilla). The Builder has builder.lua's.
function M.activity_override(villager, stage)
	if stage == "work" and villager._villages_trade_trip and not villager._villages_builder then return "putter" end
	return nil
end

local function busy(self)
	return self._villages_talk ~= nil or self.following ~= nil or self._villages_sleeping
		or (self.state == "gowp" and not walking[self])
end

function M.step(self, now)
	if self.child or not self._id then return end
	local trip = self._villages_trade_trip
	-- A porter's purse goes back the day after; anyone else's trip lasts a day longer.
	if trip and today() > trip.day + (trip.client and 0 or 1) then
		if trip.client then
			-- A porter still owes its client the purse: it goes to deliver what it has.
			if trip.leg ~= "deliver" then trip.leg, trip.tries = "deliver", 0 end
			trip.day = today()
		else
			log("villager %s dropped an unfinished trip for %s from day %d", short_id(self._id), trip.item, trip.day)
			self._villages_trade_trip, trip = nil, nil
		end
	end
	local stage = common.schedule_stage(nil, self)
	-- A commission's time is counted in work stages (commission.expired).
	local working_on = stage == "work" and commission.of(self)
	if working_on then commission.worked(working_on, today()) end
	if not may_travel(self, trip, stage) or busy(self) then return end
	if trip and walking[self] then
		-- Arrived, whatever the walk reports: the probe saw a walk's callback go unfired and
		-- the trip time out by the seller's door.
		if not M.at_leg_end(self, trip) then
			-- A seller that moved on: aimed afresh, as another chase (run 33's Builder
			-- timed out walking to where a gathering nitwit had stood).
			local seller = trip.leg == "chase" and trip.target and M.locate(trip.home, trip.who)
			local at = seller and seller.object:get_pos()
			if at and vector.distance(at, trip.target) > SELLER_REACH then
				walking[self] = nil
				return M.advance(self, trip, now)
			end
			if now - walking[self] < WALK_TIMEOUT then return end
			walking[self] = nil
			return fall_back(self, trip, "the walk never ended", now)
		end
		walking[self] = nil
	end
	-- A commission made, or run out: to the client's chest with the goods, or the price.
	local commissioned = not trip and commission.of(self)
	if commissioned then
		local made = possessions.count(self, commissioned.item) >= commissioned.count
		if made or commission.expired(commissioned, today()) then
			trip = M.commission_delivery(self, commissioned, made)
			self._villages_trade_trip, self._villages_commission = trip, nil
			if made then
				log("commission: porter %s made %d %s for %s", short_id(self._id), commissioned.count,
					commissioned.item, short_id(commissioned.client))
			else
				log("commission: porter %s ran out of time on %s for %s, returns %d emerald(s)", short_id(self._id),
					commissioned.item, short_id(commissioned.client), trip.client.purse)
			end
		end
	end
	if not trip then
		if now < (next_plan[self] or 0) then return end
		next_plan[self] = now + PLAN_SECONDS
		local pos = self.object:get_pos()
		-- With no emerald it could buy nothing when it got there.
		if not pos or possessions.emeralds(self) < 1 then return end
		trip = M.plan(self, possessions.assess(self), news.heard(self, now), self._bed or pos)
		if not trip then return end
		self._villages_trade_trip = trip
		log("villager %s sets off for %d %s from %s at %s", short_id(self._id), trip.want, trip.item,
			short_id(trip.who), core.pos_to_string(trip.home))
	end
	M.advance(self, trip, now)
end

-- The delivery leg of a commission (ticket 26b): the goods with no change once made, or
-- else the price, or what it still holds of it, and no goods.
function M.commission_delivery(self, c, made)
	return {
		item = c.item, who = c.client, home = vector.new(c.deliver), want = c.count, price = 0,
		leg = "deliver", tries = 0, day = today(), commission = true,
		bought = made and c.count or 0, spent = 0,
		client = {id = c.client, deliver = vector.new(c.deliver), fee = 0,
			purse = made and 0 or math.min(c.price, possessions.emeralds(self)), value = c.price / math.max(c.count, 1)},
	}
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

-- The purse a client hands a porter for a trip: the lot at the client's value for it (the
-- most the porter pays, buy_in_person), and the fee; at most PURSE. It used to be the
-- whole PURSE: a farmer sent 512 for one poppy, and the rest came back into its stash,
-- where nothing took it out (ColonyFood, 2026-11-14). Since the money factor (ticket
-- 21a) a rich client's value runs well over the price, so the lot is reckoned at no more
-- than the price heard, with PRICE_SLACK for an ask that rose since.
local PRICE_SLACK = 1.25
function M.purse_for(trip, value)
	local unit = value or 0
	if trip.price and trip.price > 0 then unit = math.min(unit, trip.price * PRICE_SLACK) end
	return math.min(math.ceil((trip.want or 0) * unit) + PORTER_FEE, PURSE)
end

-- At the end of a conversation, each porter with no trip may be hired by another member.
-- Returns the hires made.
function M.hire(members)
	if not clock.enabled() then return {} end
	local now = core.get_gametime()
	local hires = {}
	for _, porter in ipairs(members) do
		if is_porter(porter) and not porter._villages_trade_trip and not commission.of(porter) then
			for _, client in ipairs(members) do
				-- One porter a day: with the purse no longer all it has, it could send a second
				-- for the same need.
				local deliver = client ~= porter and has_job(client) and not client._villages_trade_trip
					and client._villages_porter_day ~= today() and delivery(client)
				local emeralds = deliver and possessions.emeralds(client) or 0
				if deliver and emeralds >= PORTER_FEE + 1 then
					local view = possessions.assess(client)
					local pos = client.object and client.object:get_pos()
					local trip = M.plan(client, view, news.heard(client, now), client._bed or pos or deliver)
					if trip then
						local purse = math.min(emeralds, M.purse_for(trip, view.value(trip.item)))
						possessions.take(client, EMERALD, purse)
						possessions.add(porter, EMERALD, purse)
						client._villages_porter_day = today()
						trip.client = {
							id = client._id, deliver = deliver, purse = purse, fee = PORTER_FEE,
							value = view.value(trip.item),
							-- A Builder takes logs as planks.
							split = client._villages_builder and true or nil,
						}
						porter._villages_trade_trip = trip
						-- What portering pays, for its choice of work (labour.lua).
						local record = porter._villages_porter_record or {days = 1, hires = 0}
						record.hires = record.hires + 1
						porter._villages_porter_record = record
						hires[#hires + 1] = {porter = porter, client = client, trip = trip}
						log("villager %s hired porter %s with %d emerald(s) for %d %s from %s", short_id(client._id),
							short_id(porter._id), purse, trip.want, trip.item, short_id(trip.who))
						break
					end
					-- No seller to send it to: a commission to make it (ticket 26b).
					-- Not a second for a good it has one out for.
					local out = client._villages_commissioned
					local pending = type(out) == "table" and not commission.expired(out, today()) and out.item or nil
					local offer = commission.offer(view, possessions.prices_of(client), emeralds, URGENT, PORTER_FEE, PURSE,
						M.urgency, pending)
					if offer then
						possessions.take(client, EMERALD, offer.price)
						possessions.add(porter, EMERALD, offer.price)
						client._villages_porter_day = today()
						client._villages_commissioned = {item = offer.item, day = today()}
						porter._villages_commission = {
							index = offer.index, item = offer.item, count = offer.count, client = client._id,
							deliver = deliver, price = offer.price, day = today(),
						}
						local record = porter._villages_porter_record or {days = 1, hires = 0}
						record.hires = record.hires + 1
						porter._villages_porter_record = record
						hires[#hires + 1] = {porter = porter, client = client, commission = porter._villages_commission}
						log("villager %s commissioned porter %s with %d emerald(s) for %d %s", short_id(client._id),
							short_id(porter._id), offer.price, offer.count, offer.item)
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
