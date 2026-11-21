-- A dinner that floats (ticket 21e, docs/villager-economy-design.md's Price discovery),
-- priced by what its plate cost (ticket 39b).
--
-- * The plate cost (`_villages_plate_cost`, set by keeper_supply.lua) is the average cost
--   of the dishes the pantry holds, each at what the keeper paid for it: a dish it bought
--   at its price, a potato it baked at what the farm chest asked for it (`note_cost`, into
--   its cost book, cost_book.lua, an average over about COST_KEEP of the last bought). Until one
--   is known it is a meal's food at the keeper's reference price for a loaf (`food_cost`).
-- * Its dinner price is the plate cost times its margin, rounded up to whole emeralds, at
--   least 1, so a plate always covers what it cost. The margin (`_villages_dinner.factor`,
--   MARGIN_START unset) moves once a day, from the evening before: ×MARKUP if a guest who
--   would have paid found no dish, ×MARKDOWN if a hungry guest would not pay while dishes
--   were left, within MARGIN_MIN and MARGIN_MAX. Before ticket 39 the price was the keeper's
--   loaf price times a factor that also rose whenever the keeper paid for food from its
--   float (`dear`, ticket 27), and since ticket 35 it bought loaves at up to that price:
--   the factor fed the loaf price and was applied again, and the cost of a meal went from
--   0.74 to 4.13 while the farm chests held about 900 potatoes (ColonyFood, 2026-11-21).
-- * The price is posted in the jukebox's meta (POSTED), where a guest and a player read it
--   and where the keeper puts it each day and whenever its prices move.
-- * A villager dines when the price is no more than its value for a meal: a loaf's value
--   in its view (ledger.assess: its reference price for food, its urgency, over the money
--   factor). Each evening at the tavern it learns the posted price (LEARN_NEWS), and paying
--   it, LEARN_TRADE, so its reference price for a dinner (ITEM, base ledger.DINNER) is
--   what dinner costs now. `M.scale` is that over ledger.DINNER: savings, the cushion and
--   the other amounts counted in dinners follow it.
-- * Demand (ticket 22c): each evening the keeper counts the meals it served (`served`)
--   and the guests who would have paid but found no dish (`short`); at the day's turn
--   their sum is `demand`, which keeper_supply.lua stocks the pantry to.
--
-- Pure but for the jukebox's meta and the log.
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local prices = dofile(core.get_modpath("living_villages") .. "/prices.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local cost_book = dofile(core.get_modpath("living_villages") .. "/cost_book.lua")

local ITEM = ledger.DINNER_ITEM
local BREAD = "mcl_farming:bread"
local MARKUP, MARKDOWN = 1.1, 0.9
local MARGIN_START, MARGIN_MIN, MARGIN_MAX = 1.1, 1, 2
-- A dish's cost is an average over about this many of the last bought.
local COST_KEEP = cost_book.KEEP
local POSTED = "villages_dinner_price"
local EPSILON = 1e-6

local M = {ITEM = ITEM, MARKUP = MARKUP, MARKDOWN = MARKDOWN, POSTED = POSTED, MARGIN_START = MARGIN_START,
	MARGIN_MIN = MARGIN_MIN, MARGIN_MAX = MARGIN_MAX, COST_KEEP = COST_KEEP}

local function short_id(id)
	return tostring(id):sub(1, 6)
end

-- A meal's food at the keeper's reference prices.
function M.food_cost(keeper)
	return prices.price(keeper and keeper._villages_prices, BREAD) or ledger.DINNER
end

-- `count` of a dish (or what it becomes: a potato as the baked potato) bought for `paid`,
-- into its cost book (cost_book.lua, ticket 43a). Food only (ticket 40d): its armor stand
-- and carpets were noted as dishes.
function M.note_cost(keeper, item, count, paid)
	if not keeper or not food.POINTS[item] then return end
	cost_book.record(keeper, item, count, paid)
end

-- What one of a dish cost the keeper: as noted, or its reference price for it.
function M.dish_cost(keeper, item)
	return cost_book.cost(keeper, item) or prices.price(keeper._villages_prices, item)
end

-- The average cost of `counts` ({dish = count}, what the pantry holds), or nil for none.
function M.plate_cost(keeper, counts)
	local total, cost = 0, 0
	for item, count in pairs(counts) do
		local each = count > 0 and M.dish_cost(keeper, item)
		if each then
			total, cost = total + count, cost + count * each
		end
	end
	return total > 0 and cost / total or nil
end

-- What a plate costs the keeper now (`_villages_plate_cost`), or `food_cost` until known.
function M.plate(keeper)
	return keeper._villages_plate_cost or M.food_cost(keeper)
end

function M.factor(keeper)
	return math.min(math.max((keeper._villages_dinner or {}).factor or MARGIN_START, MARGIN_MIN), MARGIN_MAX)
end

-- The keeper's dinner price, in whole emeralds: the plate cost times its margin, rounded
-- up, so it always covers the plate.
function M.price(keeper)
	return math.max(math.ceil(M.plate(keeper) * M.factor(keeper) - EPSILON), 1)
end

-- Moves the factor for the evening before, once a day, and posts the price at `jukebox`
-- (may be nil). Returns the price.
function M.settle(keeper, jukebox, day)
	local record = keeper._villages_dinner or {}
	if record.day ~= day then
		local before = M.factor(keeper)
		local factor = before
		if record.out then
			factor = factor * MARKUP
		elseif record.turned and next(record.turned) and M.price(keeper) > 1 then
			-- At the 1-emerald floor a markdown changes nothing a guest sees, and would only
			-- leave the margin far to climb back (ticket 22b).
			factor = factor * MARKDOWN
		end
		factor = math.min(math.max(factor, MARGIN_MIN), MARGIN_MAX)
		if record.day and math.abs(factor - before) > EPSILON then
			core.log("action", string.format("[living_villages] keeper %s moved its dinner margin to %.2f (%s)",
				short_id(keeper._id), factor, record.out and "ran out" or "guests turned away"))
		end
		record = {day = day, factor = factor, demand = record.day and M.evening(record) or nil}
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

-- A guest who would have paid found no dish. `id` (may be nil) is counted once a day.
function M.ran_out(keeper, day, id)
	if not keeper then return end
	M.settle(keeper, nil, day)
	local record = keeper._villages_dinner
	record.out = true
	if id then
		record.short = record.short or {}
		record.short[id] = true
	end
end

-- A meal served at the keeper's tavern.
function M.served(keeper, day)
	if not keeper then return end
	M.settle(keeper, nil, day)
	local record = keeper._villages_dinner
	record.served = (record.served or 0) + 1
end

-- The evening's demand in `record`: meals served and guests it ran out on.
function M.evening(record)
	local short = 0
	for _ in pairs(record.short or {}) do short = short + 1 end
	return (record.served or 0) + short
end

-- Meals wanted the last evening the keeper kept (ticket 22c); 0 before any.
function M.demand(keeper)
	return (keeper and keeper._villages_dinner or {}).demand or 0
end

-- Ticket 39c: what a loaf's points cost in the cheapest prepared food offered in `heard`
-- (market news, market_news.heard): its ask per point times a loaf's points. Nil with none.
function M.street_cost(heard)
	local best
	for _, entry in ipairs(heard or {}) do
		local points = food.POINTS[entry.item]
		if entry.kind == "has" and entry.price and entry.price > 0 and points and food.is_prepared(entry.item) then
			local per = entry.price / points
			if not best or per < best then best = per end
		end
	end
	return best and best * food.POINTS[BREAD]
end

-- Whether a villager dines at `price`: no more than a loaf is worth to it. Asked of its
-- view once a day and price (`_villages_dinner_choice`), learning the price the first time.
-- With the `dishes` the pantry offers (ticket 34), a loaf's worth without its own variety
-- times the best variety factor among them (view.variety, variety.lua): a guest tired of
-- every dish on offer values the dinner less. With what it has `heard` (ticket 39c), a
-- loaf's worth scaled down to the cheapest prepared food offered (street_cost), where
-- that is under its reference price for a loaf: it would feed itself for that. Its urgency,
-- money factor and variety apply as before. A dear street loaf no longer makes a dear
-- dinner look fair.
function M.wants(self, price, day, assess, dishes, heard)
	local choice = self._villages_dinner_choice
	if choice and choice.day == day and choice.price == price then return choice.dines end
	local view = assess(self)
	local value = view.value(BREAD) or 0
	if dishes and #dishes > 0 and view.variety then
		local best = 0
		for _, dish in ipairs(dishes) do best = math.max(best, view.variety(dish)) end
		value = value / view.variety(BREAD) * best
	end
	local street = M.street_cost(heard)
	local loaf = prices.price(self._villages_prices, BREAD)
	if street and loaf and street < loaf then value = value * street / loaf end
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
