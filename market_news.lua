-- Market news (docs/villager-economy-design.md, ticket 5): who needs what and who has
-- what to spare, passed from villager to villager when a conversation runs its time
-- (conversation.lua), as gossip about players is (gossip.lua). There is no village-wide
-- market: each villager knows only what it has heard, and a villager who talks a lot
-- hears of trades sooner.
--
-- A villager's own news is its ledger's (possessions.assess, ledger.lua) top OWN_ITEMS
-- needs and surpluses, the top OWN_ITEMS spare goods of its trade (ledger.outputs) by
-- what they fetch at its ask, and any other surplus it has heard someone needs, worked out fresh
-- when it talks, with hops 0. What it has heard is
-- `_villages_market_news`, a list of at most NEWS_ENTRIES entries:
--
--   {item, who = <villager _id>, kind = "has" | "needs", count, price = <in emeralds: what
--    who asks for one it has (asks.lua), or its value to who of one it needs>, budget =
--    <who's emeralds, for a need: prices.lua counts it only as far as who can pay>, home =
--    <who's bed>, heard = <game time it was first told>, hops}
--
-- In a finished conversation each member tells each other up to NEWS_SHARE entries,
-- its own and its hearsay, picked at random weighted by the listener's interest: an
-- item the listener needs offered, or an item it has spare wanted, weighs INTEREST_MATCH
-- times more; so does an entry that completes a trade the listener has already heard of
-- (an offer of what it heard someone needs, or a want of what it heard someone has), so
-- news of supply and demand finds its way through villagers who want neither (ticket 11);
-- fresher news and news from fewer hops away weigh more. Passing news on
-- costs a hop. The listener keeps the freshest entry per (item, who, kind) and never
-- one about itself. News older than NEWS_DAYS game days is forgotten when the list is
-- next read; past NEWS_ENTRIES the least interesting entries go.
--
-- A keeper notes each dish it hears offered (`_villages_known_dishes`, ticket 35), and
-- keeps a few of each in its pantry (keeper_supply.lua). Anyone notes a good it hears
-- offered that nothing in the village makes (`_villages_heard_offered`, item to the day
-- last heard, ticket 39e), so a vanilla want for it counts again while some is about.
--
-- Hearsay ages by game time, since it describes the world rather than the villager.
-- With the economy off nothing is told or kept.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local prices = dofile(core.get_modpath("living_villages") .. "/prices.lua")
local asks = dofile(core.get_modpath("living_villages") .. "/asks.lua")
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local recipes = dofile(core.get_modpath("living_villages") .. "/recipes.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local COAL = "mcl_core:coal_lump"

local NEWS_ENTRIES = 24
local NEWS_SHARE = 6
local NEWS_DAYS = 2
local OWN_ITEMS = 3
local INTEREST_MATCH = 4
-- Freshness never falls below this share, so old news can still be told.
local MIN_FRESHNESS = 0.1
local DEFAULT_TIME_SPEED = 72
-- The alchemist overhears (ticket 24): every OVERHEAR_SECONDS, every loaded adult's own
-- news, kept up to OVERHEAR_ENTRIES; and they overhear its own (ticket 26a).
local OVERHEAR_SECONDS = 60
local OVERHEAR_ENTRIES = 96
local VILLAGER = "mobs_mc:villager"

local M = {
	NEWS_ENTRIES = NEWS_ENTRIES, NEWS_SHARE = NEWS_SHARE, NEWS_DAYS = NEWS_DAYS, OWN_ITEMS = OWN_ITEMS,
	OVERHEAR_SECONDS = OVERHEAR_SECONDS, OVERHEAR_ENTRIES = OVERHEAR_ENTRIES,
}

local function short_id(id)
	return tostring(id):sub(1, 6)
end

-- Seconds of game time news lasts.
local function lifetime()
	local speed = core.settings and tonumber(core.settings:get("time_speed")) or DEFAULT_TIME_SPEED
	if speed <= 0 then speed = DEFAULT_TIME_SPEED end
	return NEWS_DAYS * 86400 / speed
end
M.lifetime = lifetime

-- One villager's need for a category (ticket 15) is one entry, whichever member it names.
local function same(a, b)
	if a.who ~= b.who or a.kind ~= b.kind then return false end
	if a.group or b.group then return a.group == b.group end
	return a.item == b.item
end

-- The items an entry is about: its own, or every member of its category.
local function items_of(entry)
	if entry.group and goods.CATEGORIES[entry.group] then return goods.CATEGORIES[entry.group] end
	return {[entry.item] = true}
end
M.items_of = items_of

-- What a list of entries says is needed and had: {needs = {item = true}, has = {...}}.
function M.wanted_and_had(list)
	local known = {needs = {}, has = {}}
	for _, entry in ipairs(list or {}) do
		for item in pairs(items_of(entry)) do known[entry.kind][item] = true end
	end
	return known
end

-- How much a villager whose ledger view is `view` cares to hear the entry. `known`
-- (wanted_and_had of what it has heard), if given, makes a trade it completes count.
function M.interest(view, entry, now, known)
	local weight = 1
	if view then
		if entry.kind == "has" and view.needs[entry.item] then weight = INTEREST_MATCH end
		if entry.kind == "needs" then
			for item in pairs(items_of(entry)) do
				if view.surplus[item] then weight = INTEREST_MATCH break end
			end
		end
	end
	if known then
		if entry.kind == "has" and known.needs[entry.item] then weight = INTEREST_MATCH end
		if entry.kind == "needs" then
			for item in pairs(items_of(entry)) do
				if known.has[item] then weight = INTEREST_MATCH break end
			end
		end
	end
	local freshness = math.max(1 - (now - entry.heard) / lifetime(), MIN_FRESHNESS)
	return weight * freshness / (1 + entry.hops)
end

-- The best price asked for each item among `heard` (M.heard): what someone needs it at.
function M.asking(heard)
	local best = {}
	for _, entry in ipairs(heard) do
		if entry.kind == "needs" and entry.price then
			if entry.group and goods.units(entry.group, entry.item) then
				-- A category's need, priced per unit, asks every member at its units' worth.
				local per = entry.price / goods.units(entry.group, entry.item)
				for item, units in pairs(goods.CATEGORIES[entry.group]) do
					if per * units > (best[item] or 0) then best[item] = per * units end
				end
			elseif entry.price > (best[entry.item] or 0) then
				best[entry.item] = entry.price
			end
		end
	end
	return best
end

-- What it has heard, with stale news and news about itself dropped.
function M.heard(self, now)
	local list = self._villages_market_news
	if not list then return {} end
	local kept = {}
	local oldest = (now or core.get_gametime()) - lifetime()
	for _, entry in ipairs(list) do
		if entry.heard >= oldest and entry.who ~= self._id then kept[#kept + 1] = entry end
	end
	self._villages_market_news = #kept > 0 and kept or nil
	return kept
end

-- The inputs of the recipes it makes (recipes.lua), as a set: none for the keeper or a
-- Builder, which make nothing of their trade's.
-- A recipe's fuel counts, as coal, and a category's input (fuel, logs, planks) stands for
-- its category: its need is told under the member cheapest per unit, as M.own does.
function M.recipe_inputs(self)
	local out = {}
	if self._villages_keeper or self._villages_builder then return out end
	for _, recipe in ipairs(recipes[self._villages_alchemist and "alchemist" or self._profession] or {}) do
		for _, input in ipairs(recipe.from) do out[input[1]] = true end
		if recipe.fuel then out[COAL] = true end
	end
	-- A labourer's plan (ticket 23a, possessions.labour_plan).
	local plan = possessions.labour_plan(self)
	for _, input in ipairs(plan and plan.from or {}) do out[input[1]] = true end
	return out
end

-- Its own news, from its ledger view: its top OWN_ITEMS needs and surpluses, its fuel and
-- top OWN_ITEMS other needs among its recipes' inputs, and any other surplus it has heard
-- someone needs. A single hoe a farmer is after is worth
-- telling, though the tool smith's spare shovels outrank it (run 47).
function M.own(self, view, now)
	local entries = {}
	local home = self._bed and vector.new(self._bed) or nil
	local asked = M.wanted_and_had(M.heard(self, now)).needs
	-- A category's need (ticket 15) is told once, under the member cheapest per unit.
	local needs, cheapest = {}, {}
	for item, count in pairs(view.needs) do
		local group = view.group and view.group[item]
		if group then
			local per = (view.value(item) or math.huge) / goods.units(group, item)
			local best = cheapest[group]
			if not best or per < best.per or (per == best.per and item < best.item) then
				cheapest[group] = {item = item, per = per}
			end
		else
			needs[item] = count
		end
	end
	for _, best in pairs(cheapest) do needs[best.item] = view.needs[best.item] end
	for kind, list in pairs({needs = needs, has = view.surplus}) do
		local told = {}
		-- `converted` (goods.lua): a product told at its ask capped by its sources'.
		local function add(item, count, price, converted)
			told[item] = true
			-- What it has is told at its ask (asks.lua), what a buyer would pay it; what it
			-- needs at its bid, its value capped at its emeralds (ticket 21b: others' reference
			-- prices learn from both, prices.hear).
			if kind == "has" then
				if converted then price = asks.converted(self, converted, view) or price
				else price = asks.ask(self, item, view) or price end
			end
			price = price or view.value(item)
			if kind == "needs" and price then price = math.min(price, math.max(possessions.emeralds(self), 1)) end
			-- Its own price signal, for others' reference prices to learn from (prices.hear):
			-- what it has at its reference price times its ask factor, what it needs at its
			-- reference price, with no urgency or money factor in either.
			local ref = prices.price(self._villages_prices, item)
			if ref and kind == "has" then ref = ref * asks.factor(self, item) end
			entries[#entries + 1] = {
				item = item, who = self._id, kind = kind, count = count,
				price = price, ref = ref, home = home, heard = now, hops = 0,
				group = kind == "needs" and view.group and view.group[item] or nil,
				-- What it has to pay with, so a need counts only as far as it can pay (prices.lua).
				budget = kind == "needs" and possessions.emeralds(self) or nil,
				-- A product it makes on sale (goods.lua): what from, so a trip buys it from
				-- the sources in person and in its stash (ticket 29: an armorer's 20 trips
				-- for the alchemist's ingots all failed, its stash holding only nuggets).
				from = converted and converted.from or nil, ratio = converted and converted.ratio or nil,
				takes = converted and converted.takes or nil, reserve = converted and converted.reserve or nil,
			}
		end
		for _, top in ipairs(ledger.top(list, view.value, OWN_ITEMS)) do add(top.item, top.count) end
		if kind == "needs" then
			-- What its recipes take (recipes.lua) is told too: the butcher's top needs were
			-- vanilla trade wants nobody here makes (sweet berries, chicken, kelp blocks), so
			-- it never told of the beef it cooks, never heard of the leatherworker's 29, and
			-- laboured instead (ColonyFood, 2026-11-14).
			-- Fuel, which every smelting recipe burns, is told whatever its rank: among the
			-- butcher's seven inputs it came fourth.
			local inputs, fuel = {}, nil
			for item in pairs(M.recipe_inputs(self)) do
				local category = goods.target_category(item)
				local key = category and cheapest[category] and cheapest[category].item or item
				if list[key] and not told[key] then
					if category == "fuel" then fuel = key else inputs[key] = list[key] end
				end
			end
			if fuel then add(fuel, list[fuel]) end
			for _, top in ipairs(ledger.top(inputs, view.value, OWN_ITEMS)) do add(top.item, top.count) end
			-- A keeper's dishes (ticket 40c), whatever their rank: the pantry's shortfall, under
			-- its cheapest dish, and the few of each it keeps. Capped at what a plate earns, they
			-- ranked under a bow, an allium and a carpet, so nobody heard the tavern wanted food.
			if self._villages_keeper then
				local dish = cheapest.dish
				if dish and not told[dish.item] then add(dish.item, list[dish.item]) end
				local wanted = {}
				for item in pairs(self._villages_dish_wants or {}) do
					if list[item] and not told[item] then wanted[item] = list[item] end
				end
				for _, top in ipairs(ledger.top(wanted, view.value, OWN_ITEMS)) do add(top.item, top.count) end
			end
		end
		if kind == "has" then
			-- What its trade makes (ledger.outputs) is told too, the most a buyer would pay at
			-- its ask first: a seller values its own spare at next to nothing, so by its value
			-- a fisherman's 16 cod ranked under the iron armour it was born with, and the
			-- butcher never heard of them (ColonyFood, 2026-11-13).
			-- An alchemist is a cleric to vanilla and sells none of the cleric's goods (ticket 20).
			local trade = self._villages_alchemist and "alchemist" or self._profession
			local outputs = trade and ledger.outputs(trade, self._max_trade_tier) or {}
			local made = {}
			for item, count in pairs(list) do
				if outputs[item] and not told[item] then made[item] = count end
			end
			for _, top in ipairs(ledger.top(made, function(item) return asks.ask(self, item, view) or view.value(item) end,
				OWN_ITEMS)) do
				add(top.item, top.count)
			end
			for item, count in pairs(list) do
				if asked[item] and not told[item] then add(item, count) end
			end
			-- What its job turns its spare into when it sells (goods.lua), where asked.
			for _, conversion in ipairs(goods.conversions(self)) do
				local spare = list[conversion.from]
				if spare and conversion.reserve then
					spare = math.min(spare, possessions.count(self, conversion.from) - conversion.reserve)
				end
				local value = view.value(conversion.from)
				local makes = spare and spare > 0 and goods.yield(conversion, spare) or 0
				if makes >= 1 and value and asked[conversion.to] and not told[conversion.to] then
					add(conversion.to, makes, value / conversion.ratio, conversion)
				end
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.kind ~= b.kind then return a.kind < b.kind end
		return a.item < b.item
	end)
	return entries
end

local function copy(entry)
	local out = {}
	for k, v in pairs(entry) do out[k] = v end
	if entry.home then out.home = vector.new(entry.home) end
	return out
end

-- Takes in one entry it was told. Returns whether it kept it.
local function receive(listener, entry)
	if entry.who == listener._id then return false end
	-- A keeper notes every dish it hears offered (ticket 35, keeper.lua's known dishes),
	-- kept or not.
	if listener._villages_keeper and entry.kind == "has" and not entry.group and food.is_prepared(entry.item)
		and core.get_day_count then
		listener._villages_known_dishes = listener._villages_known_dishes or {}
		listener._villages_known_dishes[entry.item] = core.get_day_count()
	end
	if entry.kind == "has" and not entry.group and core.get_day_count and not ledger.supplied(entry.item) then
		listener._villages_heard_offered = listener._villages_heard_offered or {}
		listener._villages_heard_offered[entry.item] = core.get_day_count()
	end
	local list = listener._villages_market_news or {}
	listener._villages_market_news = list
	for i, known in ipairs(list) do
		if same(known, entry) then
			if known.heard >= entry.heard then return false end
			list[i] = entry
			return true
		end
	end
	list[#list + 1] = entry
	return true
end

-- What a cook's trade takes and makes (ticket 40b): its demand recipes' (recipes.lua)
-- inputs and outputs, as {takes = set, makes = set}; nil for a villager with none (all but
-- the butcher). Never the keeper, which cooks nothing (ticket 45).
local trades = {}
function M.trade_goods(self)
	if self._villages_keeper or self._villages_builder or self._villages_alchemist or not self._profession then return nil end
	local profession = self._profession
	if trades[profession] == nil then
		local takes, makes = {}, {}
		for _, recipe in ipairs(recipes[profession] or {}) do
			if recipe.demand then
				makes[recipe.makes] = true
				for _, input in ipairs(recipe.from) do takes[input[1]] = true end
			end
		end
		trades[profession] = next(makes) and {takes = takes, makes = makes} or false
	end
	return trades[profession] or nil
end

-- Drops the least interesting entries past NEWS_ENTRIES (`limit`, if given).
local function trim(listener, view, now, limit)
	limit = limit or ((listener._villages_alchemist or M.trade_goods(listener)) and OVERHEAR_ENTRIES) or NEWS_ENTRIES
	local list = listener._villages_market_news
	if not list or #list <= limit then return end
	local known = M.wanted_and_had(list)
	table.sort(list, function(a, b) return M.interest(view, a, now, known) > M.interest(view, b, now, known) end)
	for i = #list, limit + 1, -1 do list[i] = nil end
end

-- A speaker tells `listener` up to NEWS_SHARE of what it knows (`known`: its own news
-- and hearsay), given the listener's ledger view. Returns how many the listener kept.
function M.tell(known, listener, view, now)
	local candidates, total = {}, 0
	local heard = M.wanted_and_had(listener._villages_market_news)
	for _, entry in ipairs(known) do
		if entry.who ~= listener._id then
			local weight = M.interest(view, entry, now, heard)
			candidates[#candidates + 1] = {entry = entry, weight = weight}
			total = total + weight
		end
	end
	local kept = 0
	for _ = 1, NEWS_SHARE do
		if #candidates == 0 then break end
		local roll, chosen = math.random() * total, #candidates
		for i, candidate in ipairs(candidates) do
			roll = roll - candidate.weight
			if roll <= 0 then chosen = i break end
		end
		local picked = table.remove(candidates, chosen)
		total = total - picked.weight
		local told = copy(picked.entry)
		told.hops = told.hops + 1
		if receive(listener, told) then kept = kept + 1 end
	end
	trim(listener, view, now)
	return kept
end

-- Its prices' move for the day (prices.lua), once a day, before it talks.
local function price_day(member, now)
	local day = core.get_day_count and core.get_day_count()
	if not day or member._villages_prices_day == day then return end
	prices.daily(member, M.heard(member, now), possessions.assess(member), day,
		{budget = possessions.emeralds(member), stock = stock.food_for_sale(member)})
	core.log("action", string.format("[living_villages] prices: villager %s, day %d: %s",
		short_id(member._id), day, prices.describe(member._villages_prices, 4)))
	-- Its asks over their floors (asks.describe, ticket 43d), so a stuck price can be read.
	core.log("action", string.format("[living_villages] asks: villager %s, day %d: %s",
		short_id(member._id), day, asks.describe(member, possessions.assess(member), 4)))
end

-- Everyone in a finished conversation tells everyone else, both ways. What each knows
-- is fixed before anyone speaks, so news crosses one hop per conversation. First, each
-- makes its prices' move for the day, and their prices move toward each other's
-- (prices.share).
function M.exchange(members)
	if not clock.enabled() then return 0 end
	local now = core.get_gametime()
	local beliefs = {}
	for i, member in ipairs(members) do
		price_day(member, now)
		beliefs[i] = member._villages_prices
	end
	for i, shared in ipairs(prices.share(beliefs, #members)) do members[i]._villages_prices = shared end
	local views, known = {}, {}
	for i, member in ipairs(members) do
		views[i] = possessions.assess(member)
		local all = M.own(member, views[i], now)
		for _, entry in ipairs(M.heard(member, now)) do all[#all + 1] = entry end
		known[i] = all
	end
	local kept = 0
	for i = 1, #members do
		for j, listener in ipairs(members) do
			if i ~= j then kept = kept + M.tell(known[i], listener, views[j], now) end
		end
	end
	if kept > 0 then
		local ids = {}
		for _, member in ipairs(members) do ids[#ids + 1] = short_id(member._id) end
		core.log("action", string.format("[living_villages] market news: villagers %s passed on %d entries",
			table.concat(ids, " "), kept))
	end
	return kept
end

-- The alchemist hears everything (ticket 24). It goes to neither the tavern nor the church
-- and talked once in 70 minutes (ColonyFood, 2026-11-15), so it never heard who wanted
-- its nuggets or who had stone and logs to spare: `heard=0` at day 416. It takes in the
-- own news (M.own) of every loaded adult villager in `villagers`, one hop away, as if told
-- face to face, and makes its prices' move for the day first, which a villager otherwise
-- makes in its first conversation. It is overheard alike (ticket 26a): each of them takes in
-- its own news, a hop away, so its nuggets, glass and flint have buyers. It opens no stall
-- and goes nowhere news is told, so nobody heard of the 63 nuggets it held at 0.29 while
-- labourers planned 880 lanterns, and broke, it bought no stone or logs again (ColonyFood,
-- day 694). Returns how many entries it kept, and how many the others kept of its news.
function M.overhear(listener, villagers, now)
	if not clock.enabled() then return 0, 0 end
	now = now or core.get_gametime()
	price_day(listener, now)
	local kept, others = 0, {}
	for _, villager in ipairs(villagers) do
		if villager ~= listener and villager._id and villager._id ~= listener._id and not villager.child then
			others[#others + 1] = villager
			for _, entry in ipairs(M.own(villager, possessions.assess(villager), now)) do
				local told = copy(entry)
				told.hops = (told.hops or 0) + 1
				if receive(listener, told) then kept = kept + 1 end
			end
		end
	end
	local view = possessions.assess(listener)
	trim(listener, view, now, OVERHEAR_ENTRIES)
	local own, told_kept = M.own(listener, view, now), 0
	for _, villager in ipairs(others) do
		local took = false
		for _, entry in ipairs(own) do
			local told = copy(entry)
			told.hops = (told.hops or 0) + 1
			if receive(villager, told) then
				told_kept = told_kept + 1
				took = true
			end
		end
		if took then trim(villager, possessions.assess(villager), now) end
	end
	return kept, told_kept
end

-- Whether a news entry is about a cook's trade (M.trade_goods): an offer of what it takes,
-- or a want of what it makes, a category's (the keeper's dishes) if a member is one.
local function about(trade, entry)
	if entry.kind == "has" then return trade.takes[entry.item] == true end
	if trade.makes[entry.item] then return true end
	for item in pairs(entry.group and goods.CATEGORIES[entry.group] or {}) do
		if trade.makes[item] then return true end
	end
	return false
end

-- A cook knows its trade partners (ticket 40b), as the alchemist hears everyone (above):
-- the butcher takes in, a hop away, the own news (M.own) of every loaded adult villager in
-- `villagers` that is about its trade, the leatherworker's beef, the fishermen's catch, the
-- farmers' potatoes on offer and the keeper's dishes wanted; and each of them takes in the
-- butcher's offers of dishes it needs and wants of what it has spare. Gossip never brought
-- them together: every villager's 24 entries were full of wood, sticks and cobble, so for
-- 8 days the butcher heard of no beef while the leatherworker held 95, and of no dish wanted
-- (ColonyFood, 2026-11-21). What they trade at is their asks and bids as ever (asks.lua,
-- prices.lua): this only carries the news. Returns how many entries it kept, and how many
-- the others kept of its news.
function M.partners(cook, villagers, now)
	local trade = M.trade_goods(cook)
	if not trade or not clock.enabled() then return 0, 0 end
	now = now or core.get_gametime()
	price_day(cook, now)
	local cook_view = possessions.assess(cook)
	local own = {}
	for _, entry in ipairs(M.own(cook, cook_view, now)) do
		if (entry.kind == "has" and trade.makes[entry.item]) or (entry.kind == "needs" and trade.takes[entry.item]) then
			own[#own + 1] = entry
		end
	end
	local kept, told_kept = 0, 0
	for _, villager in ipairs(villagers) do
		if villager ~= cook and villager._id and villager._id ~= cook._id and not villager.child then
			local view = possessions.assess(villager)
			for _, entry in ipairs(M.own(villager, view, now)) do
				if about(trade, entry) then
					local told = copy(entry)
					told.hops = (told.hops or 0) + 1
					if receive(cook, told) then kept = kept + 1 end
				end
			end
			local took = false
			for _, entry in ipairs(own) do
				if (entry.kind == "has" and view.needs[entry.item]) or (entry.kind == "needs" and view.surplus[entry.item]) then
					local told = copy(entry)
					told.hops = (told.hops or 0) + 1
					if receive(villager, told) then
						told_kept = told_kept + 1
						took = true
					end
				end
			end
			if took then trim(villager, view, now) end
		end
	end
	trim(cook, cook_view, now)
	return kept, told_kept
end

-- The loaded adult villagers: every active villager entity.
local function loaded_villagers()
	local out = {}
	for _, entity in pairs(core.luaentities or {}) do
		if entity.name == VILLAGER and entity._id and not entity.child then out[#out + 1] = entity end
	end
	return out
end

-- Wraps do_custom: an alchemist overhears every OVERHEAR_SECONDS, and a cook hears its
-- trade partners as often (M.partners).
local next_overhear = setmetatable({}, {__mode = "k"})
function M.install(def)
	if not clock.enabled() then return end
	local original = def.do_custom
	def.do_custom = function(self, dtime)
		local result = original(self, dtime)
		if not self._villages_alchemist and not self.child and self._id and M.trade_goods(self) then
			local now = core.get_gametime()
			if now >= (next_overhear[self] or 0) then
				next_overhear[self] = now + OVERHEAR_SECONDS
				local kept, told = M.partners(self, loaded_villagers(), now)
				if kept > 0 or told > 0 then
					core.log("action", string.format(
						"[living_villages] market news: cook %s heard %d entries from its trade partners, told them %d",
						short_id(self._id), kept, told))
				end
			end
		elseif self._villages_alchemist and not self.child and self._id then
			local now = core.get_gametime()
			if now >= (next_overhear[self] or 0) then
				next_overhear[self] = now + OVERHEAR_SECONDS
				local kept, told = M.overhear(self, loaded_villagers(), now)
				if kept > 0 or told > 0 then
					core.log("action", string.format(
						"[living_villages] market news: alchemist %s overheard %d entries, was overheard %d times",
						short_id(self._id), kept, told))
				end
			end
		end
		return result
	end
end

-- One line for the Lookup Tool inspector (diagnostic.lua): how much it has heard, and
-- the freshest few.
function M.status(self)
	local now = core.get_gametime()
	local list = M.heard(self, now)
	if #list == 0 then return "nothing heard" end
	local sorted = {}
	for i, entry in ipairs(list) do sorted[i] = entry end
	table.sort(sorted, function(a, b)
		if a.heard ~= b.heard then return a.heard > b.heard end
		return a.item < b.item
	end)
	local parts = {}
	for i = 1, math.min(3, #sorted) do
		local entry = sorted[i]
		parts[i] = string.format("%s %s %d %s", short_id(entry.who), entry.kind, entry.count, entry.item:gsub("^.*:", ""))
	end
	return #list .. " heard; " .. table.concat(parts, ", ")
end

return M
