-- What a villager's own state does to the prices it shows players (docs/villager-economy-
-- design.md, What the player sees; ticket 9): Java's demand term, which gossip.lua
-- left out while there was no demand to read, and a hunger term. gossip.lua applies
-- it to the first ingredient of the trade in the player's wanted list, before its
-- reputation term, so the two combine in one place and other players see their own.
--
-- The urgency is the ledger's (ledger.lua): the trader's value for the item over its
-- base price, 1 with no need, up to 3 when it holds none of what it wants, down toward
-- 0.5 for a glut. Its square root moves the price, so a full need is about 1.7 times:
-- * a trade where it buys (offers an emerald): it asks for the base count divided by
--   it, so a smith out of coal takes fewer lumps for its emerald, and one with plenty
--   asks more;
-- * a trade where it sells (asks emeralds or goods): the base times it, so a glut of
--   what it sells comes cheaper, and times HUNGRY or STARVING when it is hungry or
--   starving (food.lua's states): it works slower, so what it makes is scarcer.
-- Counts are rounded, at least 1, at most the item's stack. With the economy off the
-- base count stands.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")

local EMERALD = "mcl_core:emerald"
local HUNGER = {hungry = 1.25, starving = 1.5}

local M = {HUNGER = HUNGER}

M.enabled = clock.enabled

-- The trader's urgency for the item, from its view (possessions.assess), or 1.
function M.urgency(view, item)
	local price, value = ledger.price(item), view.value(item)
	if not price or price <= 0 or not value then return 1 end
	return value / price
end

-- The first ingredient's count for this trader, from vanilla's `base` count.
-- `wanted` and `offered` are item names; `view` and `state` default to the trader's own.
function M.count(trader, wanted, base, offered, stack_max, view, state)
	if not M.enabled() or trader.child then return base end
	view = view or possessions.assess(trader)
	local factor
	if offered == EMERALD then
		factor = 1 / math.sqrt(M.urgency(view, wanted))
	else
		factor = math.sqrt(M.urgency(view, offered)) * (HUNGER[state or food.state(trader)] or 1)
	end
	local count = math.floor(base * factor + 0.5)
	return math.min(math.max(count, 1), stack_max or count)
end

return M
