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
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local wants = dofile(core.get_modpath("living_villages") .. "/wants.lua")
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")

local M = {}

-- What the village makes that a villager may want for its own sake, and how many game
-- days each lasts: the foragers' flowers and apples, the shepherd's carpets (two wool make
-- three, at sale; any colour, ticket 24), the cartographer's banners and item frames, the
-- librarian's bookshelves, what labourers make from stone and wood (ticket 23a), and
-- (ticket 24) the leatherworker's clothes and the fletcher's bows and arrows: both sat on
-- their goods with no money (ColonyFood, day 416), and the fletcher could not buy flint;
-- (ticket 29) the armorer's cauldron, so iron has a use beyond the smiths' wares, and
-- the cleric's clock, so gold has one.
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

-- How many of `slots` each of its tastes gets, going round them: {[i] = count}.
local function per_taste(tastes, slots)
	local out = {}
	for i = 1, #tastes do out[i] = 0 end
	for slot = 1, slots do
		local i = (slot - 1) % #tastes + 1
		out[i] = out[i] + 1
	end
	return out
end

-- Which of its tastes a comfort in use is, or nil (a comfort from a taste it no longer has).
local function taste_of(tastes, item)
	local def = by_item[item]
	for i, taste in ipairs(tastes) do
		if taste == def then return i end
	end
	return nil
end

-- Never an alchemist's, which wants nothing for itself (ticket 20).
local function wanted(self)
	return not self.child and self._id ~= nil and not self._villages_alchemist
end

-- Drops the comforts used up by `now`, and fills free slots from what it holds, through
-- take(self, item, count) (possessions.take). Returns nothing.
function M.update(self, emeralds, take, now)
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
	-- Each taste fills its own slots, so one held in plenty fills no other taste's
	-- (ColonyFood, 2026-11-15: an armorer holding lilies filled all nine of its slots
	-- with them). A comfort in use counts against its taste's slots and all of them.
	local tastes = M.tastes(self._id)
	local free = per_taste(tastes, M.slots(emeralds))
	local total = M.slots(emeralds) - #kept
	for _, comfort in ipairs(kept) do
		local i = taste_of(tastes, comfort.item)
		if i then free[i] = free[i] - 1 end
	end
	for i, taste in ipairs(tastes) do
		while free[i] > 0 and total > 0 do
			local item = take_one(self, taste, take)
			if not item then break end
			table.insert(kept, {item = item, ["until"] = now + taste.days * wants.DAY_SECONDS})
			core.log("action", string.format("[living_villages] villager %s enjoys a %s", id, item))
			free[i], total = free[i] - 1, total - 1
		end
	end
	self._villages_comforts = #kept > 0 and kept or nil
end

-- For the ledger: {item = count} it should get, {item = worth} for each of its tastes (a
-- flower's for every flower), and {category = count} for the comforts any member of a
-- category fills: a flower, and the flowers its pots want.
function M.targets(self, emeralds, now)
	local targets, worth, categories = {}, {}, {}
	if not wanted(self) then return targets, worth, categories end
	-- Over the money factor (ledger.lambda, ticket 21a): the richer, the more it pays.
	local lambda = ledger.lambda(emeralds)
	local function value(item) worth[item] = M.WORTH * (ledger.price(item) or 0) / lambda end
	local tastes = M.tastes(self._id)
	local function want(comfort)
		if comfort.category then
			categories[comfort.category] = (categories[comfort.category] or 0) + 1
			for _, member in ipairs(members(comfort.category)) do value(member) end
		else
			targets[comfort.item] = (targets[comfort.item] or 0) + 1
		end
	end
	for _, taste in ipairs(tastes) do
		if taste.category then
			for _, member in ipairs(members(taste.category)) do value(member) end
		else
			value(taste.item)
		end
	end
	-- A slot in use and not nearly done needs nothing, its taste's or any; a pot with no
	-- flower, or one nearly wilted, wants one.
	local free = per_taste(tastes, M.slots(emeralds))
	local total = M.slots(emeralds)
	for _, comfort in ipairs(in_use(self)) do
		local def = by_item[comfort.item] or {days = 1}
		if comfort["until"] - now > def.days * wants.DAY_SECONDS * wants.NEARLY_WORN then
			total = total - 1
			local i = taste_of(tastes, comfort.item)
			if i then free[i] = free[i] - 1 end
		end
		if def.holds and comfort["until"] > now and (not comfort.flower
			or (comfort.flower_until or 0) - now <= M.FLOWER_DAYS * wants.DAY_SECONDS * wants.NEARLY_WORN) then
			want({category = def.holds})
		end
	end
	for i, taste in ipairs(tastes) do
		for _ = 1, math.max(math.min(free[i], total), 0) do
			want(taste)
			total = total - 1
		end
	end
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
