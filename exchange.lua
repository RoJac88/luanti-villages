-- Trade between villagers (docs/villager-economy-design.md, ticket 6), at the end of a
-- conversation that ran its time (conversation.lua), after market news has passed
-- (market_news.lua). They stand together and are loaded, so nothing walks anywhere.
--
-- Each pair in the conversation makes at most one trade: the one that gains the two of
-- them most. A buyer buys an item it needs (its ledger's needs, ledger.lua) that the
-- seller has spare (the seller's surplus) and carries in its belongings, since a stash
-- is not at hand. It happens only when the buyer values the item above the seller, and
-- settles at the midpoint of the two values, per item:
--
-- * in emeralds, rounded to a whole one. A sale worth more than the buyer's emeralds
--   shrinks to what they pay for; one worth under one emerald grows to the fewest items
--   that make one, if the seller has them spare. Both must still gain:
--   the buyer values what it gets at no less than it pays, the seller at no more.
-- * in goods, when the buyer has too few emeralds: something the seller needs and the
--   buyer has spare and carries, as many as make up the midpoint value, again only if
--   both gain by their own values.
--
-- Standing (ticket 11c): a trader that thinks well of the other (gossip.lua, a villager
-- subject, such as a donor at the holiday service) moves the price toward it, by up to
-- STANDING_SHIFT of the midpoint at FULL_STANDING, but never past either value: a seller
-- that likes the buyer charges less, a buyer that likes the seller pays more.
--
-- Goods pass from belongings to belongings (possessions.lua) with food.show_handover's
-- item across. With the economy off nothing is traded.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local gossip = dofile(core.get_modpath("living_villages") .. "/gossip.lua")

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
	for item, wanted in pairs(buyer_view.needs) do
		local available = item ~= EMERALD and (not only or item == only) and spare(seller, seller_view, item) or 0
		local to_buyer, to_seller = buyer_view.value(item), seller_view.value(item)
		if available > 0 and to_buyer and to_seller and to_buyer > to_seller then
			local unit = M.unit_price(seller, buyer, to_seller, to_buyer)
			local count = math.min(wanted, available)
			-- No more than its emeralds pay for (unless it barters, below, for the whole lot).
			local affordable = math.floor(possessions.emeralds(buyer) / unit)
			if affordable >= 1 and count * unit > possessions.emeralds(buyer) then count = affordable end
			if count * unit < MIN_SALE then count = math.min(math.ceil(MIN_SALE / unit), available) end
			local value = count * unit
			local worth_to_buyer, worth_to_seller = count * to_buyer, count * to_seller
			local trade
			local pay = math.max(math.floor(value + 0.5), 1)
			if pay <= worth_to_buyer and pay >= worth_to_seller and possessions.emeralds(buyer) >= pay then
				trade = {pay = pay}
			else
				local goods, goods_count = barter(buyer, buyer_view, seller_view, value, worth_to_buyer)
				if goods and goods_count * seller_view.value(goods) >= worth_to_seller then
					trade = {goods = goods, goods_count = goods_count}
				end
			end
			if trade then
				trade.seller, trade.buyer, trade.item, trade.count = seller, buyer, item, count
				trade.gain = worth_to_buyer - worth_to_seller
				if not best or trade.gain > best.gain or (trade.gain == best.gain and item < best.item) then best = trade end
			end
		end
	end
	return best
end

local function show(from, to, item)
	local a = from.object and from.object:get_pos()
	local b = to.object and to.object:get_pos()
	if a and b then food.show_handover(a, b, item, to.object) end
end

-- Carries out a trade from offer(). Returns whether it went through.
function M.settle(trade)
	local seller, buyer = trade.seller, trade.buyer
	if possessions.count(seller, trade.item) < trade.count then return false end
	if trade.pay and possessions.emeralds(buyer) < trade.pay then return false end
	if trade.goods and possessions.count(buyer, trade.goods) < trade.goods_count then return false end
	possessions.take(seller, trade.item, trade.count)
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
	core.log("action", string.format("[living_villages] trade: villager %s sold %d %s to %s for %s",
		short_id(seller), trade.count, trade.item, short_id(buyer), price))
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
