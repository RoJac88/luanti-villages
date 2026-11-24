local core = minetest
-- Commissions (docs/villager-economy-design.md, ticket 26b): portering with a craft in the
-- middle. A porter is paid to walk, and walking is cheap: in ColonyFood (days 570-693)
-- villagers portered on 565 days and were hired 19 times, always for bread, fish or wheat
-- the client could have fetched itself. What a rich villager cannot get is a good nobody
-- has, while the poorest cannot pay for the inputs to make it. So a client with no seller
-- to send a porter to pays one up front to make a labour recipe's output (recipes.lua's
-- `labour`) and bring it.
--
-- The offer (M.offer). Of the client's urgent needs (urgency at least trade_trips.URGENT)
-- that a labour recipe makes, the one it gains most on. The price is the recipe's inputs
-- at the client's prices (possessions.prices_of, a category or any log or planks at its
-- cheapest member) times PRICE_SLACK, plus the porter's fee, at most the purse; the client
-- pays it only when one craft's worth of the output is worth that much to it.
--
-- The commission (`_villages_commission` on the worker, saved): {index (in recipes.labour),
-- item, count (one craft's output), client, deliver (the client's chest), price, day (the
-- hire's)}. While it lasts the worker's labour plan is the recipe (possessions.labour_plan),
-- its inputs capped as if the output sold at the price; the output is a need it holds back
-- at the price; it goes portering every day; it plans trade trips for the inputs in its work
-- stage too; and it crafts at home as any labourer does. The price is its own money, but
-- it is not counted in what it has to spend (possessions.money) while undelivered.
--
-- Delivery and expiry (trade_trips.step). Holding the count, it takes the porter's
-- delivery leg to the client's chest with the goods and no change: what it did not spend
-- of the price is its pay. Not delivered once WORK_DAYS of its work stages have passed
-- since the hire (`worked`, `worked_day`, counted by M.worked from trade_trips.step), or
-- MAX_DAYS days, it takes the price, or what it still holds of it, back to the chest
-- instead, and keeps any inputs. Work stages, not days: hires fall at the evening tavern,
-- so "the day after the hire" left one work stage, none when that day was a holiday (every
-- fourth), and all four of ColonyFood's first commissions ran out (2026-11-19).
--
-- A crafter's commission (E12). A jobsite crafter is hired the same way for a good of its
-- own trade (recipes[profession], up to its tier) that it holds none of and its client
-- has heard no one offer (trade_trips.hire): `trade` names the list `index` is in. The
-- price is the same reckoning, with no porter's purse, and the client must hold it all:
-- in lv_pair e11b rich villagers wanted iron axes at 1,500-5,000 while the smiths, at 36-83
-- emeralds, could tell of their want of ingots only at that much (market_news.lua), under
-- what one costs, and no iron was bought or made. Paid first, a smith bids for its inputs
-- with the client's money. Its inputs may not exist yet, so it lasts TRADE_WORK_DAYS work
-- stages, at most TRADE_MAX_DAYS days.
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local recipes = dofile(core.get_modpath("living_villages") .. "/recipes.lua")

local PRICE_SLACK = 1.25
-- How long a commission lasts: WORK_DAYS of the worker's work stages, at most MAX_DAYS
-- days counting the hire's.
local WORK_DAYS = 2
local MAX_DAYS = 6
local TRADE_WORK_DAYS = 4
local TRADE_MAX_DAYS = 8

local M = {PRICE_SLACK = PRICE_SLACK, WORK_DAYS = WORK_DAYS, MAX_DAYS = MAX_DAYS,
	TRADE_WORK_DAYS = TRADE_WORK_DAYS, TRADE_MAX_DAYS = TRADE_MAX_DAYS}

local function today()
	return core.get_day_count and core.get_day_count() or 0
end

-- What a recipe's inputs cost at `price_of`, each at its cheapest member; nil if one has no
-- price at all.
function M.cost(recipe, price_of)
	local total = 0
	for _, input in ipairs(recipe.from) do
		local best
		for item in pairs(ledger.members_of(input) or {[input[1]] = true}) do
			local price = price_of(item)
			if price and (not best or price < best) then best = price end
		end
		if not best then return nil end
		total = total + best * input[2]
	end
	return total
end

-- The commission a client would pay for, or nil: {index, recipe, item, count, price, value}.
-- `view` is its ledger view, `price_of` its prices, `emeralds` what it holds, `urgent` the
-- least urgency, `fee` and `purse` the porter's, `urgency` trade_trips.urgency, `pending` a
-- good it already has a commission out for. `list` (default recipes.labour) and `goods`
-- (default M.goods()) for a crafter's (E12): its recipes and the goods it would make.
function M.offer(view, price_of, emeralds, urgent, fee, purse, urgency, pending, list, goods)
	local best, best_gain
	goods = goods or M.goods()
	for index, recipe in ipairs(list or recipes.labour) do
		local item = recipe.makes
		local need = view.needs[item] or 0
		if need > 0 and item ~= pending and goods[item] and urgency(view, item) >= urgent then
			local value = view.value(item)
			local cost = M.cost(recipe, price_of)
			if value and cost then
				local price = math.min(math.ceil(cost * PRICE_SLACK) + fee, purse)
				local worth = value * math.min(need, recipe.count)
				local gain = worth - price
				if price <= emeralds and gain >= 0 and (not best or gain > best_gain) then
					best, best_gain = {index = index, recipe = recipe, item = item, count = recipe.count, price = price,
						value = value}, gain
				end
			end
		end
	end
	return best
end

-- A commission's recipe: in its crafter's trade list (E12), else in recipes.labour.
function M.recipe(c)
	local list = recipes[c.trade or "labour"]
	return list and c.index and list[c.index] or nil
end

-- Its commission, if it has one under way (not yet delivered or returned), else nil.
function M.of(self)
	local c = self._villages_commission
	if type(c) ~= "table" or not M.recipe(c) then return nil end
	return c
end

-- Its labour commission (ticket 26b), else nil: a crafter's (E12) is no labour plan.
function M.labour_of(self)
	local c = M.of(self)
	if c and c.trade then return nil end
	return c
end

-- Counts `day` as one of the commission's work days, once: called in the worker's work stage.
function M.worked(c, day)
	day = day or today()
	if c.worked_day == day then return end
	c.worked, c.worked_day = (c.worked or 0) + 1, day
end

-- Whether a commission has run out: its last work day over, or MAX_DAYS days.
function M.expired(c, day)
	day = day or today()
	local max_days, work_days = MAX_DAYS, WORK_DAYS
	if c.trade then max_days, work_days = TRADE_MAX_DAYS, TRADE_WORK_DAYS end
	if day > c.day + max_days - 1 then return true end
	return (c.worked or 0) >= work_days and day > c.worked_day
end

-- The emeralds of a commission's price it still holds back from its own spending.
function M.reserve(self, emeralds)
	local c = M.of(self)
	if not c then return 0 end
	return math.min(c.price, emeralds)
end

-- The caps of its commissioned recipe's inputs: the output at what one is paid.
function M.caps(c, price_of)
	local recipe = M.recipe(c)
	local unit = c.price / math.max(c.count, 1)
	return ledger.imputed({recipe}, function(item)
		if item == c.item then return math.max(price_of(item) or 0, unit) end
		return price_of(item)
	end, 5)
end

-- What a jobsite crafter may be commissioned for (E12): its trade, that trade's recipes
-- and {item = true} of their goods up to its tier; nil for one with no trade list of its
-- own (an alchemist, keeper or Builder, a child, one with no jobsite) or one already on
-- a commission.
function M.crafter(self)
	if self.child or not self._jobsite or self._villages_alchemist or self._villages_keeper
		or self._villages_builder or M.of(self) then return nil end
	local trade = self._profession
	local list = trade and trade ~= "labour" and recipes[trade]
	if type(list) ~= "table" or not list[1] or not list[1].makes then return nil end
	local tier, goods = self._max_trade_tier or 1, {}
	for _, recipe in ipairs(list) do
		if (recipe.tier or 1) <= tier then goods[recipe.makes] = true end
	end
	return trade, list, goods
end

-- The labour recipes' goods, {item = true}: their outputs that no labour recipe takes in
-- (not planks, sticks or torches). A need for one is work for a porter, and only these are
-- commissioned: a crafter short of sticks makes its own.
local GOODS
function M.goods()
	if GOODS then return GOODS end
	local inputs = {}
	for _, recipe in ipairs(recipes.labour) do
		for _, input in ipairs(recipe.from) do inputs[input[1]] = true end
	end
	GOODS = {}
	for _, recipe in ipairs(recipes.labour) do
		if not inputs[recipe.makes] then GOODS[recipe.makes] = true end
	end
	return GOODS
end

return M
