-- Comforts (docs/villager-economy-design.md, ticket 19): goods a villager with savings
-- buys for its own sake and uses up, so that money held by whoever sells food finds its
-- way back to the professions that make other things. Data as wants.lua is, and the few
-- functions that read it; it touches no engine state but the villager it is handed.
--
-- Tastes. Each villager has TASTES of COMFORTS, picked by its _id, always the same.
--
-- Slots. It has a slot for a comfort for every STEP emeralds it holds over SAVINGS, up to
-- MAX_SLOTS: none below SAVINGS, so a villager short of money spends nothing on them. The
-- slots go round its tastes in turn, so the second slot is its second taste.
--
-- Use. A comfort it holds in its belongings fills a free slot (`_villages_comforts`, a
-- list of {item, until}), and is used up `days` game days later. The ledger wants one for
-- each slot that is free or nearly done (wants.NEARLY_WORN of its days left), worth at
-- most WORTH times its base price over the money factor (ledger.lambda, ticket 21a), so it
-- never pays more than that, and the richer it is the more that is. A villager that grew
-- poorer keeps what it is using until it is used up, and wants no more.
--
-- Replaces the ledger's fixed preferences, two of which (cake, cookie) no village makes.
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local wants = dofile(core.get_modpath("living_villages") .. "/wants.lua")

local M = {}

-- What the village makes that a villager may want for its own sake, and how many game
-- days each lasts: the foragers' blooms, the shepherd's carpets (two wool make three, at
-- sale) and the cartographer's item frames (ticket 19c), dear, for the richest.
M.COMFORTS = {
	{item = "mcl_banners:banner_item_white", days = 6},
	{item = "mcl_books:bookshelf", days = 8},
	{item = "mcl_core:apple", days = 2},
	{item = "mcl_flowers:poppy", days = 2},
	{item = "mcl_flowers:dandelion", days = 2},
	{item = "mcl_wool:white_carpet", days = 4},
	{item = "mcl_itemframes:frame", days = 8},
}
M.TASTES = 3
-- alms.lua's SAVINGS: what a villager keeps before it gives, or buys comforts.
M.SAVINGS = 8 * ledger.DINNER
M.STEP = 4 * ledger.DINNER
M.MAX_SLOTS = 6
M.WORTH = 2

local by_item = {}
for _, comfort in ipairs(M.COMFORTS) do by_item[comfort.item] = comfort end

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
	return math.min(math.floor((emeralds - M.SAVINGS) / M.STEP), M.MAX_SLOTS)
end

local function in_use(self)
	return self._villages_comforts or {}
end

-- Never an alchemist's, which wants nothing for itself (ticket 20).
local function wanted(self)
	return not self.child and self._id ~= nil and not self._villages_alchemist
end

-- Drops the comforts used up by `now`, and fills free slots from what it holds, through
-- take(self, item, count) (possessions.take). Returns nothing.
function M.update(self, emeralds, take, now)
	if not wanted(self) then return end
	local list, kept = in_use(self), {}
	for _, comfort in ipairs(list) do
		if now < comfort["until"] then
			table.insert(kept, comfort)
		else
			core.log("action", string.format("[living_villages] villager %s used up its %s",
				tostring(self._id):sub(1, 6), comfort.item))
		end
	end
	local slots, tastes = M.slots(emeralds), M.tastes(self._id)
	for slot = #kept + 1, slots do
		local taste = tastes[(slot - 1) % #tastes + 1]
		if take(self, taste.item, 1) > 0 then
			table.insert(kept, {item = taste.item, ["until"] = now + taste.days * wants.DAY_SECONDS})
			core.log("action", string.format("[living_villages] villager %s enjoys a %s",
				tostring(self._id):sub(1, 6), taste.item))
		end
	end
	self._villages_comforts = #kept > 0 and kept or nil
end

-- For the ledger: {item = count} it should get, and {item = worth} for each of its tastes.
function M.targets(self, emeralds, now)
	local targets, worth = {}, {}
	if not wanted(self) then return targets, worth end
	local tastes = M.tastes(self._id)
	for _, taste in ipairs(tastes) do
		-- Over the money factor (ledger.lambda, ticket 21a): the richer, the more it pays.
		worth[taste.item] = M.WORTH * (ledger.price(taste.item) or 0) / ledger.lambda(emeralds)
	end
	-- A slot in use and not nearly done needs nothing.
	local busy = 0
	for _, comfort in ipairs(in_use(self)) do
		local days = (by_item[comfort.item] or {days = 1}).days
		if comfort["until"] - now > days * wants.DAY_SECONDS * wants.NEARLY_WORN then busy = busy + 1 end
	end
	for slot = busy + 1, M.slots(emeralds) do
		local item = tastes[(slot - 1) % #tastes + 1].item
		targets[item] = (targets[item] or 0) + 1
	end
	return targets, worth
end

-- One line for the inspector.
function M.status(self)
	local parts = {}
	for _, comfort in ipairs(in_use(self)) do
		table.insert(parts, string.format("%s, %d s left", comfort.item,
			math.max(math.floor(comfort["until"] - core.get_gametime()), 0)))
	end
	return #parts > 0 and table.concat(parts, "; ") or "none"
end

return M
