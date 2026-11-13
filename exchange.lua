-- Trade between villagers (docs/villager-economy-design.md, ticket 6), at the end of a
-- conversation that ran its time (conversation.lua), after market news has passed
-- (market_news.lua). They stand together and are loaded, so nothing walks anywhere.
--
-- Each pair in the conversation makes at most one trade: the one that gains the buyer
-- most. A buyer buys an item it needs (its ledger's needs, ledger.lua) that the seller
-- has spare (the seller's surplus) and carries in its belongings, since a stash is not
-- at hand. It pays the seller's asking price (asks.lua), when it values the item at
-- least that much, per item:
--
-- * in emeralds, rounded to a whole one. A sale worth more than the buyer's emeralds
--   shrinks to what they pay for; one worth under one emerald grows to the fewest items
--   that make one, if the seller has them spare. The buyer must still value what it gets
--   at no less than it pays.
-- * in goods, when the buyer has too few emeralds: something the seller needs and the
--   buyer has spare and carries, as many as make up the price, only if both gain by
--   their own values.
--
-- An item with no base price has no ask, and settles as before at the midpoint of the
-- two values, the buyer valuing it above the seller.
--
-- Standing (ticket 11c): a seller that thinks well of the buyer (gossip.lua, a villager
-- subject, such as a donor at the holiday service) asks it less, by up to
-- STANDING_SHIFT at FULL_STANDING. At the midpoint, a buyer that likes the seller pays
-- more too, never past either value.
--
-- Conversions (ticket 15, goods.lua): a seller whose job turns a good into another
-- (a shepherd's wool into string) can sell what the buyer needs from its spare stock of
-- the other, on the spot and for free. It values each made item at the source's value
-- over the ratio, and hands over whole sources' worth: one wool gives four string.
--
-- Goods pass from belongings to belongings (possessions.lua) with food.show_handover's
-- item across. With the economy off nothing is traded.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local gossip = dofile(core.get_modpath("living_villages") .. "/gossip.lua")
local goods_mod = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local asks = dofile(core.get_modpath("living_villages") .. "/asks.lua")

local EMERALD = "mcl_core:emerald"
-- A sale must come to at least this many emeralds before rounding, or it grows: less,
-- rounded up to a whole emerald, would cost the buyer more than it values the goods.
local MIN_SALE = 1
local STANDING_SHIFT = 0.1
-- major_positive's 20 at its multiplier of 5.
local FULL_STANDING = 100

local M = {STANDING_SHIFT = STANDING_SHIFT, FULL_STANDING = FULL_STANDING}

local function short_id(self)
	return tostring(self._id):sub(1, 6)
end

-- How well `self` thinks of `other`, from 0 to 1.
local function standing(self, other)
	if not other._id then return 0 end
	local r = gossip.reputation(self, gossip.villager_subject(other._id))
	return math.min(math.max(r / FULL_STANDING, 0), 1)
end

-- The midpoint price, moved by each side's standing with the other.
function M.unit_price(seller, buyer, to_seller, to_buyer)
	local unit = (to_buyer + to_seller) / 2
	local shift = STANDING_SHIFT * (standing(buyer, seller) - standing(seller, buyer))
	return math.min(math.max(unit * (1 + shift), to_seller), to_buyer)
end

-- What the seller asks this buyer for one of the item: its ask, less for a buyer it
-- thinks well of; nil for an item with no ask.
function M.asking(seller, buyer, item)
	local ask = asks.ask(seller, item)
	if not ask then return nil end
	return ask * (1 - STANDING_SHIFT * standing(seller, buyer))
end

-- How many of the item the villager can hand over now: spare, and carried.
local function spare(self, view, item)
	return math.min(view.surplus[item] or 0, possessions.count(self, item))
end

-- Goods the seller needs that the buyer can give, paying `value` emeralds' worth at the
-- midpoint, so that both gain. Returns item, count or nil.
local function barter(buyer, buyer_view, seller_view, value, buyer_gets_worth)
	local best, best_count, best_gain
	for item in pairs(seller_view.needs) do
		local available = spare(buyer, buyer_view, item)
		local to_buyer, to_seller = buyer_view.value(item), seller_view.value(item)
		if available > 0 and item ~= EMERALD and to_buyer and to_seller and to_seller > to_buyer then
			local count = math.ceil(value / ((to_buyer + to_seller) / 2))
			local buyer_gives = count * to_buyer
			if count <= available and buyer_gives <= buyer_gets_worth then
				local gain = buyer_gets_worth - buyer_gives
				if not best_gain or gain > best_gain or (gain == best_gain and item < best) then
					best, best_count, best_gain = item, count, gain
				end
			end
		end
	end
	return best, best_count
end

-- The best trade of `seller`'s goods to `buyer`, or nil: {seller, buyer, item, count,
-- pay = emeralds | nil, goods = item | nil, goods_count, gain}. With `only`, of that item
-- alone (a trade trip, trade_trips.lua).
function M.offer(seller, seller_view, buyer, buyer_view, only)
	local best
	local conversions = goods_mod.conversions(seller)
	for item, wanted in pairs(buyer_view.needs) do
		if item ~= EMERALD then
			-- What it can sell the item from: its own stock, or a good its job converts.
			-- With `only` (a stall's shown good, or a trip's item), that good or what is made
			-- from it alone.
			local sources = {}
			if not only or item == only then sources[1] = {from = item, ratio = 1} end
			for _, conversion in ipairs(conversions) do
				if conversion.to == item and (not only or item == only or conversion.from == only) then
					sources[#sources + 1] = conversion
				end
			end
			for _, source in ipairs(sources) do
				local trade = M.quote(seller, seller_view, buyer, buyer_view, item, wanted, source.from, source.ratio)
				if trade and (not best or trade.gain > best.gain or (trade.gain == best.gain and item < best.item)) then
					best = trade
				end
			end
		end
	end
	return best
end

-- One candidate sale of `item` made from `from` (itself when ratio is 1), or nil.
function M.quote(seller, seller_view, buyer, buyer_view, item, wanted, from, ratio)
	local stock = spare(seller, seller_view, from)
	local to_buyer = buyer_view.value(item)
	local source_value = seller_view.value(from)
	local to_seller = source_value and source_value / ratio
	if stock <= 0 or not to_buyer then return nil end
	local unit = M.asking(seller, buyer, item)
	local asked = unit ~= nil
	if asked then
		if to_buyer < unit then return nil end
	elseif not to_seller or to_buyer <= to_seller then
		return nil
	else
		unit = M.unit_price(seller, buyer, to_seller, to_buyer)
	end
	local available = stock * ratio
	local count = math.min(wanted, available)
	-- No more than its emeralds pay for (unless it barters, below, for the whole lot).
	local affordable = math.floor(possessions.emeralds(buyer) / unit)
	if affordable >= 1 and count * unit > possessions.emeralds(buyer) then count = affordable end
	if count * unit < MIN_SALE then count = math.min(math.ceil(MIN_SALE / unit), available) end
	-- A converted sale hands over whole sources.
	local from_count = math.ceil(count / ratio)
	count = from_count * ratio
	local value = count * unit
	local worth_to_buyer = count * to_buyer
	-- At an ask the seller takes what it asked; at the midpoint, no less than its value.
	local floor = asked and 0 or count * to_seller
	local trade
	local pay = math.max(math.floor(value + 0.5), 1)
	if pay <= worth_to_buyer and pay >= floor and possessions.emeralds(buyer) >= pay then
		trade = {pay = pay}
	else
		local goods, goods_count = barter(buyer, buyer_view, seller_view, value, worth_to_buyer)
		if goods and goods_count * seller_view.value(goods) >= math.max(floor, asked and value or 0) then
			trade = {goods = goods, goods_count = goods_count}
		end
	end
	if not trade then return nil end
	trade.seller, trade.buyer, trade.item, trade.count = seller, buyer, item, count
	if from ~= item then trade.from, trade.from_count = from, from_count end
	trade.gain = worth_to_buyer - (trade.pay or value)
	return trade
end

local function show(from, to, item)
	local a = from.object and from.object:get_pos()
	local b = to.object and to.object:get_pos()
	if a and b then food.show_handover(a, b, item, to.object) end
end

-- Carries out a trade from offer(). Returns whether it went through.
function M.settle(trade)
	local seller, buyer = trade.seller, trade.buyer
	local from, from_count = trade.from or trade.item, trade.from_count or trade.count
	if possessions.count(seller, from) < from_count then return false end
	if trade.pay and possessions.emeralds(buyer) < trade.pay then return false end
	if trade.goods and possessions.count(buyer, trade.goods) < trade.goods_count then return false end
	possessions.take(seller, from, from_count)
	possessions.add(buyer, trade.item, trade.count)
	show(seller, buyer, trade.item)
	local price
	if trade.pay then
		possessions.take(buyer, EMERALD, trade.pay)
		possessions.add(seller, EMERALD, trade.pay)
		show(buyer, seller, EMERALD)
		price = trade.pay .. " emerald(s)"
	else
		possessions.take(buyer, trade.goods, trade.goods_count)
		possessions.add(seller, trade.goods, trade.goods_count)
		show(buyer, seller, trade.goods)
		price = trade.goods_count .. " " .. trade.goods
	end
	local made = trade.from and string.format(" (from %d %s)", from_count, from) or ""
	asks.sold(seller, trade.item, core.get_day_count and core.get_day_count() or 0)
	core.log("action", string.format("[living_villages] trade: villager %s sold %d %s%s to %s for %s",
		short_id(seller), trade.count, trade.item, made, short_id(buyer), price))
	return true
end

-- Every pair in a finished conversation, each pair at most once. The views are
-- worked out afresh for each pair, so an earlier trade counts. Returns the trades made.
function M.exchange(members)
	if not clock.enabled() then return {} end
	local made = {}
	for i = 1, #members do
		for j = i + 1, #members do
			local a, b = members[i], members[j]
			local view_a, view_b = possessions.assess(a), possessions.assess(b)
			local best = M.offer(a, view_a, b, view_b)
			local other = M.offer(b, view_b, a, view_a)
			if other and (not best or other.gain > best.gain) then best = other end
			if best and M.settle(best) then made[#made + 1] = best end
		end
	end
	return made
end

return M
