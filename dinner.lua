-- A dinner that floats (ticket 21e, docs/villager-economy-design.md's Price discovery).
-- The keeper prices dinner as a seller prices any good:
--
-- * Its food cost is a meal's food at its own reference price (prices.lua): a loaf's, as a
--   guest values a meal. keeper_supply.lua pays a farm chest that for each meal the food
--   it takes makes (a potato is one, a carrot a quarter), so what the tavern pays its
--   farmers moves with what food trades for. Not the potato's own price: at vanilla's a
--   potato is a quarter of a loaf, and the dinner would have fallen from 18 to 2 at once.
-- * Its dinner price is the food cost times its dinner factor, in whole emeralds, at
--   least 1. The factor (`_villages_dinner.factor`, 1 unset) moves once a day, from the
--   evening before: ×MARKUP if a guest who would have paid found no dish, else ×MARKDOWN
--   if a hungry guest would not pay while dishes were left, within asks.MIN and asks.MAX.
-- * The price is posted in the jukebox's meta (POSTED), where a guest and a player read it
--   and where the keeper puts it each day and whenever its prices move.
-- * A villager dines when the price is no more than its value for a meal: a loaf's value
--   in its view (ledger.assess: its reference price for food, its urgency, over the money
--   factor). Each evening at the tavern it learns the posted price (LEARN_NEWS), and paying
--   it, LEARN_TRADE, so its reference price for a dinner (ITEM, base ledger.DINNER) is
--   what dinner costs now. `M.scale` is that over ledger.DINNER: savings, the cushion and
--   the other amounts counted in dinners follow it.
--
-- Pure but for the jukebox's meta and the log.
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local prices = dofile(core.get_modpath("living_villages") .. "/prices.lua")
local asks = dofile(core.get_modpath("living_villages") .. "/asks.lua")

local ITEM = ledger.DINNER_ITEM
local BREAD = "mcl_farming:bread"
local MARKUP, MARKDOWN = 1.1, 0.9
local POSTED = "villages_dinner_price"

local M = {ITEM = ITEM, MARKUP = MARKUP, MARKDOWN = MARKDOWN, POSTED = POSTED}

local function short_id(id)
	return tostring(id):sub(1, 6)
end

-- A meal's food at the keeper's reference prices.
function M.food_cost(keeper)
	return prices.price(keeper and keeper._villages_prices, BREAD) or ledger.DINNER
end

function M.factor(keeper)
	return (keeper._villages_dinner or {}).factor or 1
end

-- The keeper's dinner price, in whole emeralds.
function M.price(keeper)
	return math.max(math.floor(M.food_cost(keeper) * M.factor(keeper) + 0.5), 1)
end

-- Moves the factor for the evening before, once a day, and posts the price at `jukebox`
-- (may be nil). Returns the price.
function M.settle(keeper, jukebox, day)
	local record = keeper._villages_dinner or {}
	if record.day ~= day then
		local factor = record.factor or 1
		if record.out then
			factor = factor * MARKUP
		elseif record.turned and next(record.turned) and M.price(keeper) > 1 then
			-- At the 1-emerald floor a markdown changes nothing a guest sees, and would only
			-- leave the factor far to climb back (ticket 22b).
			factor = factor * MARKDOWN
		end
		factor = math.min(math.max(factor, asks.MIN), asks.MAX)
		if record.day and factor ~= (record.factor or 1) then
			core.log("action", string.format("[living_villages] keeper %s moved its dinner factor to %.2f (%s)",
				short_id(keeper._id), factor, record.out and "ran out" or "guests turned away"))
		end
		record = {day = day, factor = factor}
		keeper._villages_dinner = record
	end
	local price = M.price(keeper)
	if jukebox then
		local meta = core.get_meta(jukebox)
		if meta:get_string(POSTED) ~= tostring(price) then meta:set_string(POSTED, tostring(price)) end
	end
	-- What it sells for is what it reckons a dinner is worth.
	if math.abs(M.reference(keeper) - price) > 0.01 then prices.learn(keeper, ITEM, price, 1) end
	return price
end

-- The posted price at `jukebox`, settled first when its keeper is at hand; nil if none
-- was ever posted.
function M.posted(jukebox, keeper, day)
	if keeper then return M.settle(keeper, jukebox, day) end
	local price = tonumber(core.get_meta(jukebox):get_string(POSTED))
	return price and price >= 1 and math.floor(price) or nil
end

-- A hungry guest would not pay while dishes were left.
function M.turned(keeper, id, day)
	if not keeper then return end
	M.settle(keeper, nil, day)
	local record = keeper._villages_dinner
	record.turned = record.turned or {}
	record.turned[id] = true
end

-- A guest who would have paid found no dish.
function M.ran_out(keeper, day)
	if not keeper then return end
	M.settle(keeper, nil, day)
	keeper._villages_dinner.out = true
end

-- Whether a villager dines at `price`: no more than a loaf is worth to it. Asked of its
-- view once a day and price (`_villages_dinner_choice`), learning the price the first time.
function M.wants(self, price, day, assess)
	local choice = self._villages_dinner_choice
	if choice and choice.day == day and choice.price == price then return choice.dines end
	local value = assess(self).value(BREAD) or 0
	local dines = value >= price
	if not choice or choice.day ~= day then prices.learn(self, ITEM, price, prices.LEARN_NEWS) end
	self._villages_dinner_choice = {day = day, price = price, dines = dines}
	return dines
end

-- It paid `price` for a dinner.
function M.paid(self, price)
	prices.learn(self, ITEM, price)
end

-- Its reference price for a dinner, and that over ledger.DINNER: the amounts counted in
-- dinners (savings, the cushion, the comfort step, a stake) are multiplied by it.
function M.reference(self)
	return prices.price(self and self._villages_prices, ITEM) or ledger.DINNER
end

function M.scale(self)
	return M.reference(self) / ledger.DINNER
end

return M
