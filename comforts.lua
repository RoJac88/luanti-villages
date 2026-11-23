-- Comforts (docs/villager-economy-design.md, ticket 19): goods a villager with savings
-- buys for its own sake and uses up, so that money held by whoever sells food finds its
-- way back to the professions that make other things. Data as wants.lua is, and the few
-- functions that read it; it touches no engine state but the villager it is handed.
--
-- Tastes. Each villager has TASTES of COMFORTS, picked by its _id, always the same.
--
-- Slots. It has a slot for a comfort for every STEP emeralds it holds over SAVINGS, up to
-- BASE_SLOTS: none below SAVINGS, so a villager short of money spends nothing on them.
-- Past BASE_SLOTS each slot needs twice the span of the one before (2, 4, 8 ... STEPs), up
-- to MAX_SLOTS (ticket 23c): a farmer with 1,163 filled the same six slots as one with
-- 576, so a hoard bought nothing more; now the richest spend more, by less for each slot.
-- The slots go round its tastes in turn, so the second slot is its second taste, and one
-- with more slots than tastes wants some twice.
--
-- Use. A comfort it holds in its belongings fills a free slot (`_villages_comforts`, a
-- list of {item, until}), and is used up `days` game days later: gone, never back to its
-- belongings or stash (ticket 23b: every comfort perishes, at most MAX_DAYS, so money
-- keeps going round). The ledger wants one for each slot that is free or nearly done
-- (wants.NEARLY_WORN of its days left), worth at most WORTH times its base price over the
-- money factor (ledger.lambda, ticket 21a), so it never pays more than that, and the
-- richer it is the more that is. A villager that grew poorer keeps what it is using until
-- it is used up, and wants no more.
--
-- Flowers (ticket 23b). One comfort, a flower, is any of goods.lua's `flower` category,
-- wanted as the category, so the foragers' lilies of the valley sell too. A flower pot in
-- use holds a flower (`flower`, `flower_until` on its entry): while one is in use its
-- owner wants a flower for it every FLOWER_DAYS, and a flower it holds goes in the pot,
-- before any loose flower fills a slot. The pot keeps its slot with or without one; a
-- flower in it wilts after FLOWER_DAYS and is gone.
--
-- Replaces the ledger's fixed preferences, two of which (cake, cookie) no village makes.
--
-- Following supply (experiment E9). Tastes are fixed, but what a village makes is not: in
-- lv_pair e8b (37 days) no bookshelf, frame, lantern, cauldron or clock was ever made, so a
-- villager with one of those tastes kept its slot empty and the money for it idle (a
-- leatherworker with 1,970 wanted a frame, a butcher with 1,832 a cauldron), while a farmer
-- with chestplates for a taste bought three in an hour, its later slots going round the
-- same four tastes. Now:
-- * A taste is about when its good is on offer (a `has` entry in its market news heard
--   within OFFER_DAYS, from another villager), held, in use, or made by its own trade at
--   its tier (a cartographer's banner); else dormant.
-- * Its slots go to the tastes about, then to the other comforts on offer, cheapest
--   first, one each, before any second of one: so savings always have something real to
--   buy, and the richest buy more kinds rather than more of one.
-- * A dormant taste still wants one (a probe) while the villager has a slot, at its usual
--   worth: its want is told in market news, so a crafter that could make it hears of it,
--   and a commission (commission.lua) can still be paid for it, and a new good can come
--   into the village. Bought or heard offered, the taste is about again and takes its slots.
-- * A taste it holds comes first, so buying one (and so holding less money, so fewer
--   slots) never leaves it spare to sell on (e9: a helmet passed back and forth between a
--   weapon smith and the keeper). A taste takes at most its share of the slots
--   (slots / TASTES, rounded up), another comfort one: slots past that stay empty (e9: a
--   keeper wanted four helmets, the one comfort on offer).
-- * Worth is capped at MAX_MARKUP times the base price: the richer still pay more, but
--   a cauldron is no longer worth 11,285 to a butcher.
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local wants = dofile(core.get_modpath("living_villages") .. "/wants.lua")
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local recipes = dofile(core.get_modpath("living_villages") .. "/recipes.lua")

local M = {}

-- What the village makes that a villager may want for its own sake, and how many game
-- days each lasts: the foragers' flowers and apples, the shepherd's carpets (two wool make
-- three, at sale; any colour, ticket 24), the cartographer's banners and item frames, the
-- librarian's bookshelves, what labourers make from stone and wood (ticket 23a), and
-- (ticket 24) the leatherworker's clothes and the fletcher's bows and arrows: both sat on
-- their goods with no money (ColonyFood, day 416), and the fletcher could not buy flint;
-- (ticket 29) the armorer's cauldron, so iron has a use beyond the smiths' wares, and
-- the cleric's clock, so gold has one; (ticket 32) the librarian's book and quill, so the
-- butcher's feathers have one beyond arrows.
-- VoxeLibre 0.92 has no bundle or harness.
M.FLOWER = "flower"
M.CARPET = "carpet"
M.COMFORTS = {
	{item = "mcl_flowers:poppy", category = M.FLOWER, days = 2},
	{item = "mcl_core:apple", days = 2},
	{item = "mcl_wool:white_carpet", category = M.CARPET, days = 4},
	{item = "mcl_bows:arrow", days = 2},
	{item = "mcl_banners:banner_item_white", days = 6},
	{item = "mcl_paintings:painting", days = 6},
	{item = "mcl_barrels:barrel_closed", days = 6},
	{item = "mcl_flowerpots:flower_pot", days = 8, holds = M.FLOWER},
	{item = "mcl_armor_stand:armor_stand", days = 8},
	{item = "mcl_books:bookshelf", days = 8},
	{item = "mcl_itemframes:frame", days = 8},
	{item = "mcl_lanterns:lantern_floor", days = 10},
	-- The armorer's, from seven of the alchemist's ingots (ticket 29).
	{item = "mcl_cauldrons:cauldron", days = 12},
	-- The cleric's, from a gold ingot and an iron one (ticket 29): a use for gold. A player's
	-- held clock turns into one of VoxeLibre's 64 frames (mcl_clock:clock_N), which is no
	-- comfort; villagers' and chests' clocks stay mcl_clock:clock.
	{item = "mcl_clock:clock", days = 12},
	{item = "mcl_armor:helmet_leather", days = 10},
	{item = "mcl_armor:boots_leather", days = 10},
	{item = "mcl_armor:chestplate_leather", days = 12},
	{item = "mcl_armor:leggings_leather", days = 12},
	{item = "mcl_bows:bow", days = 12},
	-- The librarian's book and quill (ticket 32), a use for the butcher's feathers.
	{item = "mcl_books:writable_book", days = 8},
}
M.FLOWER_DAYS = 2
M.MAX_DAYS = 12
M.TASTES = 4
-- alms.lua's SAVINGS: what a villager keeps before it gives, or buys comforts.
M.SAVINGS = 8 * ledger.DINNER
M.STEP = 4 * ledger.DINNER
M.BASE_SLOTS = 6
M.MAX_SLOTS = 12
M.WORTH = 2
-- Experiment E9: the most a comfort is worth to anyone, in base prices; how long a
-- comfort heard offered counts as on offer.
M.MAX_MARKUP = 4
M.OFFER_DAYS = 2

-- A category's members, in a fixed order.
local function members(category)
	local list = {}
	for item in pairs(goods.CATEGORIES[category] or {}) do list[#list + 1] = item end
	table.sort(list)
	return list
end

-- Every item a comfort is held as: a flower comfort under each flower.
local by_item = {}
for _, comfort in ipairs(M.COMFORTS) do
	by_item[comfort.item] = comfort
	if comfort.category then
		for _, member in ipairs(members(comfort.category)) do by_item[member] = comfort end
	end
end
M.by_item = by_item

-- Takes one of the comfort (any member of its category) through take; the item taken, or nil.
local function take_one(self, comfort, take)
	if not comfort.category then return take(self, comfort.item, 1) > 0 and comfort.item or nil end
	for _, member in ipairs(members(comfort.category)) do
		if take(self, member, 1) > 0 then return member end
	end
	return nil
end

local function roll(id, salt, n)
	local text = tostring(id) .. salt
	local sum = 0
	for i = 1, #text do sum = sum + text:byte(i) * i end
	return sum % n
end

-- Its tastes, in order: TASTES distinct comforts, always the same for one _id.
function M.tastes(id)
	local pool = {}
	for i, comfort in ipairs(M.COMFORTS) do pool[i] = comfort end
	local chosen = {}
	for i = 1, math.min(M.TASTES, #pool) do
		local pick = table.remove(pool, roll(id, "taste" .. i, #pool) + 1)
		chosen[i] = pick
	end
	return chosen
end

-- How many comforts a villager with `emeralds` has room for.
function M.slots(emeralds)
	if emeralds <= M.SAVINGS then return 0 end
	local steps = (emeralds - M.SAVINGS) / M.STEP
	if steps < M.BASE_SLOTS then return math.floor(steps) end
	local slots, needed, span = M.BASE_SLOTS, M.BASE_SLOTS, 2
	while slots < M.MAX_SLOTS and steps >= needed + span do
		slots, needed, span = slots + 1, needed + span, span * 2
	end
	return slots
end

local function in_use(self)
	return self._villages_comforts or {}
end

-- The items a comfort is held as: its item, or every member of its category.
local function items_of(comfort)
	if comfort.category then return members(comfort.category) end
	return {comfort.item}
end

-- Its base price: the cheapest member's for a category.
local function price_of(comfort)
	local best
	for _, item in ipairs(items_of(comfort)) do
		local price = ledger.price(item)
		if price and (not best or price < best) then best = price end
	end
	return best or 0
end

-- What other villagers were heard to have within OFFER_DAYS: a set of items.
local function offered(self, now)
	local set, oldest = {}, now - M.OFFER_DAYS * wants.DAY_SECONDS
	for _, entry in ipairs(self._villages_market_news or {}) do
		if entry.kind == "has" and entry.who ~= self._id and (entry.heard or 0) >= oldest then set[entry.item] = true end
	end
	return set
end

-- Whether its own trade makes the item at its tier (recipes.lua; not a keeper or Builder).
local function makes(self, item)
	if self._villages_keeper or self._villages_builder then return false end
	local tier = self._max_trade_tier or 1
	for _, recipe in ipairs(recipes[self._profession] or {}) do
		if recipe.makes == item and (recipe.tier or 1) <= tier then return true end
	end
	return false
end

-- Its slots' plan (experiment E9): {[comfort] = slots}, the comforts in the order they
-- fill, its dormant tastes, and its slots. `count(self, item)` (possessions.count, may be
-- nil) tells what it holds: a taste held or made by its own trade is about; another comfort
-- only on offer or in use, so a crafter's stock of one is not its own comfort.
function M.plan(self, emeralds, now, count)
	local tastes = M.tastes(self._id)
	local slots = M.slots(emeralds)
	local heard, using = offered(self, now), {}
	for _, comfort in ipairs(in_use(self)) do
		if by_item[comfort.item] then using[by_item[comfort.item]] = true end
	end
	local function about(comfort, own)
		if using[comfort] then return true end
		for _, item in ipairs(items_of(comfort)) do
			if heard[item] or (own and (makes(self, item) or (count and count(self, item) > 0))) then return true end
		end
		return false
	end
	local function held(comfort)
		if not count then return false end
		for _, item in ipairs(items_of(comfort)) do
			if count(self, item) > 0 then return true end
		end
		return false
	end
	-- Held tastes first (E9b): a comfort it bought keeps a slot when paying for it left it
	-- fewer, rather than turning spare and sold on.
	local order, dormant, mine, later = {}, {}, {}, {}
	for _, taste in ipairs(tastes) do
		mine[taste] = true
		if not about(taste, true) then
			dormant[#dormant + 1] = taste
		elseif held(taste) then
			order[#order + 1] = taste
		else
			later[#later + 1] = taste
		end
	end
	for _, taste in ipairs(later) do order[#order + 1] = taste end
	local others = {}
	for _, comfort in ipairs(M.COMFORTS) do
		if not mine[comfort] and about(comfort, false) then others[#others + 1] = comfort end
	end
	table.sort(others, function(a, b)
		local pa, pb = price_of(a), price_of(b)
		if pa ~= pb then return pa < pb end
		return a.item < b.item
	end)
	for _, comfort in ipairs(others) do order[#order + 1] = comfort end
	-- Round the order, a taste up to its share of the slots (as if all its tastes were
	-- about), another comfort one (E9b): the richest buy more kinds, not four of one.
	local per, share = {}, math.max(math.ceil(slots / M.TASTES), 1)
	local left = slots
	while left > 0 do
		local placed = false
		for _, comfort in ipairs(order) do
			if left == 0 then break end
			if (per[comfort] or 0) < (mine[comfort] and share or 1) then
				per[comfort], left, placed = (per[comfort] or 0) + 1, left - 1, true
			end
		end
		if not placed then break end
	end
	return per, order, slots > 0 and dormant or {}, slots
end

-- Never an alchemist's, which wants nothing for itself (ticket 20).
local function wanted(self)
	return not self.child and self._id ~= nil and not self._villages_alchemist
end

-- Drops the comforts used up by `now`, and fills free slots from what it holds, through
-- take(self, item, count) (possessions.take); `count` as M.plan's. Returns nothing.
function M.update(self, emeralds, take, now, count)
	if not wanted(self) then return end
	local id = tostring(self._id):sub(1, 6)
	local list, kept = in_use(self), {}
	for _, comfort in ipairs(list) do
		if now < comfort["until"] then
			table.insert(kept, comfort)
		else
			core.log("action", string.format("[living_villages] villager %s used up its %s", id, comfort.item))
		end
	end
	-- A pot's flower wilts, and a flower it holds takes its place.
	for _, comfort in ipairs(kept) do
		local def = by_item[comfort.item]
		if def and def.holds then
			if comfort.flower and now >= (comfort.flower_until or 0) then
				core.log("action", string.format("[living_villages] villager %s's %s wilted", id, comfort.flower))
				comfort.flower, comfort.flower_until = nil, nil
			end
			if not comfort.flower then
				local flower = take_one(self, {category = def.holds}, take)
				if flower then
					comfort.flower, comfort.flower_until = flower, now + M.FLOWER_DAYS * wants.DAY_SECONDS
					core.log("action", string.format("[living_villages] villager %s puts a %s in its %s", id, flower,
						comfort.item))
				end
			end
		end
	end
	self._villages_comforts = #kept > 0 and kept or nil
	-- Each comfort fills its own slots, so one held in plenty fills no other's (ColonyFood,
	-- 2026-11-15: an armorer holding lilies filled all nine of its slots with them). A
	-- comfort in use counts against its own slots and all of them.
	local per, order, _, slots = M.plan(self, emeralds, now, count)
	local free, total = {}, slots - #kept
	for comfort, n in pairs(per) do free[comfort] = n end
	for _, comfort in ipairs(kept) do
		local def = by_item[comfort.item]
		if def and free[def] then free[def] = free[def] - 1 end
	end
	for _, comfort in ipairs(order) do
		while (free[comfort] or 0) > 0 and total > 0 do
			local item = take_one(self, comfort, take)
			if not item then break end
			table.insert(kept, {item = item, ["until"] = now + comfort.days * wants.DAY_SECONDS})
			core.log("action", string.format("[living_villages] villager %s enjoys a %s", id, item))
			free[comfort], total = free[comfort] - 1, total - 1
		end
	end
	self._villages_comforts = #kept > 0 and kept or nil
end

-- For the ledger: {item = count} it should get, {item = worth} for each of its tastes and
-- the comforts its slots go to (a flower's for every flower), and {category = count} for
-- the comforts any member of a category fills: a flower, and the flowers its pots want.
-- `count` as M.plan's.
function M.targets(self, emeralds, now, count)
	local targets, worth, categories = {}, {}, {}
	if not wanted(self) then return targets, worth, categories end
	-- Over the money factor (ledger.lambda, ticket 21a): the richer, the more it pays, up to
	-- MAX_MARKUP times the base price (E9).
	local lambda = ledger.lambda(emeralds)
	local function value_of(comfort)
		for _, item in ipairs(items_of(comfort)) do
			local price = ledger.price(item) or 0
			worth[item] = math.min(M.WORTH * price / lambda, M.MAX_MARKUP * price)
		end
	end
	local function want(comfort, n)
		if comfort.category then
			categories[comfort.category] = (categories[comfort.category] or 0) + (n or 1)
		else
			targets[comfort.item] = (targets[comfort.item] or 0) + (n or 1)
		end
	end
	local per, order, dormant, slots = M.plan(self, emeralds, now, count)
	for _, taste in ipairs(M.tastes(self._id)) do value_of(taste) end
	for _, comfort in ipairs(order) do value_of(comfort) end
	-- A slot in use and not nearly done needs nothing, its comfort's or any; a pot with no
	-- flower, or one nearly wilted, wants one.
	local free, total = {}, slots
	for comfort, n in pairs(per) do free[comfort] = n end
	for _, comfort in ipairs(in_use(self)) do
		local def = by_item[comfort.item] or {days = 1}
		if comfort["until"] - now > def.days * wants.DAY_SECONDS * wants.NEARLY_WORN then
			total = total - 1
			if free[def] then free[def] = free[def] - 1 end
		end
		if def.holds and comfort["until"] > now and (not comfort.flower
			or (comfort.flower_until or 0) - now <= M.FLOWER_DAYS * wants.DAY_SECONDS * wants.NEARLY_WORN) then
			want({category = def.holds})
		end
	end
	for _, comfort in ipairs(order) do
		local n = math.max(math.min(free[comfort] or 0, total), 0)
		if n > 0 then
			want(comfort, n)
			total = total - n
		end
	end
	-- A dormant taste's probe (E9): one, so a crafter hears of it.
	for _, taste in ipairs(dormant) do want(taste, 1) end
	return targets, worth, categories
end

-- One line for the inspector.
function M.status(self)
	local parts = {}
	for _, comfort in ipairs(in_use(self)) do
		local flower = comfort.flower and (" with a " .. comfort.flower:gsub("^.*:", "")) or ""
		table.insert(parts, string.format("%s%s, %d s left", comfort.item, flower,
			math.max(math.floor(comfort["until"] - core.get_gametime()), 0)))
	end
	return #parts > 0 and table.concat(parts, "; ") or "none"
end

return M
