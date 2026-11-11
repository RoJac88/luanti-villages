-- Market news (docs/villager-economy-design.md, ticket 5): who needs what and who has
-- what to spare, passed from villager to villager when a conversation runs its time
-- (conversation.lua), as gossip about players is (gossip.lua). There is no village-wide
-- market: each villager knows only what it has heard, and a villager who talks a lot
-- hears of trades sooner.
--
-- A villager's own news is its ledger's (possessions.assess, ledger.lua) top OWN_ITEMS
-- needs and surpluses, and any other surplus it has heard someone needs, worked out fresh
-- when it talks, with hops 0. What it has heard is
-- `_villages_market_news`, a list of at most NEWS_ENTRIES entries:
--
--   {item, who = <villager _id>, kind = "has" | "needs", count, price = <its value to
--    who, in emeralds>, home = <who's bed>, heard = <game time it was first told>, hops}
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
-- Hearsay ages by game time, since it describes the world rather than the villager.
-- With the economy off nothing is told or kept.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local prices = dofile(core.get_modpath("living_villages") .. "/prices.lua")
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")

local NEWS_ENTRIES = 24
local NEWS_SHARE = 6
local NEWS_DAYS = 2
local OWN_ITEMS = 3
local INTEREST_MATCH = 4
-- Freshness never falls below this share, so old news can still be told.
local MIN_FRESHNESS = 0.1
local DEFAULT_TIME_SPEED = 72

local M = {
	NEWS_ENTRIES = NEWS_ENTRIES, NEWS_SHARE = NEWS_SHARE, NEWS_DAYS = NEWS_DAYS, OWN_ITEMS = OWN_ITEMS,
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

-- Its own news, from its ledger view: its top OWN_ITEMS needs and surpluses, and any
-- other surplus it has heard someone needs. A single hoe a farmer is after is worth
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
		local function add(item, count, price)
			told[item] = true
			entries[#entries + 1] = {
				item = item, who = self._id, kind = kind, count = count,
				price = price or view.value(item), home = home, heard = now, hops = 0,
				group = kind == "needs" and view.group and view.group[item] or nil,
			}
		end
		for _, top in ipairs(ledger.top(list, view.value, OWN_ITEMS)) do add(top.item, top.count) end
		if kind == "has" then
			for item, count in pairs(list) do
				if asked[item] and not told[item] then add(item, count) end
			end
			-- What its job turns its spare into when it sells (goods.lua), where asked.
			for _, conversion in ipairs(goods.conversions(self)) do
				local spare = list[conversion.from]
				local value = view.value(conversion.from)
				if spare and value and asked[conversion.to] and not told[conversion.to] then
					add(conversion.to, spare * conversion.ratio, value / conversion.ratio)
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

-- Drops the least interesting entries past NEWS_ENTRIES.
local function trim(listener, view, now)
	local list = listener._villages_market_news
	if not list or #list <= NEWS_ENTRIES then return end
	local known = M.wanted_and_had(list)
	table.sort(list, function(a, b) return M.interest(view, a, now, known) > M.interest(view, b, now, known) end)
	for i = #list, NEWS_ENTRIES + 1, -1 do list[i] = nil end
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
	prices.daily(member, M.heard(member, now), possessions.assess(member), day)
	core.log("action", string.format("[living_villages] prices: villager %s, day %d: %s",
		short_id(member._id), day, prices.describe(member._villages_prices, 4)))
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
