-- The alchemist (docs/villager-economy-design.md, ticket 20): a villager who claims an
-- alchemist's stand (alchemy_stand.lua) and turns stone and logs, which few buy, into
-- iron, flint, glass and gold, which no village makes. It neither eats nor wants
-- comforts, and works through the hours the others spend at the tavern and the church.
--
-- VoxeLibre cannot be given a new profession (keeper.lua says why), so the alchemist is a
-- role layered on the cleric, whose vanilla jobsite is the brewing stand:
--
-- - The stand is claimed through the node meta `villager`, as vanilla claims a
--   workstation. Vanilla's validate_jobsite checks only that meta, never the node, so
--   vanilla keeps the jobsite and commutes to it like any other.
-- - `_villages_alchemist` marks the role (saved), recovered on activation for a cleric
--   whose claimed jobsite is a stand. An alchemist whose stand is gone, or no longer
--   names it, goes back to being unemployed, so it looks for work again. An unloaded
--   stand is not taken for a gone one.
-- - Every module that treats a cleric specially asks the flag first: its timetables
--   (common.lua), food that never falls (food.lua), no comforts or wants, no donations or
--   alms (alms.lua), its ledger by role (possessions.trade_key), and its robe (init.lua).
--
-- job_blocks.lua hands stands out to a villager out of work (job_seek.lua); a new village
-- is never staffed with one (village_staffing.lua), since none is ever generated.
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local recipes = dofile(core.get_modpath("living_villages") .. "/recipes.lua")

local BLOCK = "living_villages:alchemy_stand"
local PROFESSION = "cleric"
local FLAG = "_villages_alchemist"
-- The cleric's robe, recoloured, as keeper.lua recolours the butcher's apron.
local OVERLAY = "(living_villages_villager_profession_cleric.png^[multiply:#4fb3a0)"

-- Its trade (ticket 20c). It makes glass while it holds GLASS_KEEP or fewer and flint up
-- to FLINT_KEEP (recipes.lua's `upto`), and nuggets without end, each burning half a lump
-- of fuel (ticket 28c), and makes them whether they pay or not (production.choose: it
-- works its stand). It wants logs for the flint it is short of, at most LOG_CAP at once,
-- a day's STONE_WANT of stone or cobble and FUEL_WANT lumps' worth of fuel always. Gold is
-- sold only from the nuggets past GOLD_RESERVE (goods.lua's conversions).
--
-- What it pays for them (ticket 28, `floors`). Its goods were priced at their inputs' cost
-- and its bids at what its goods returned, so a glut of stone and logs drove its prices
-- and its bids down together: it bid 0.01 for cobble, sold flint for 8.5 and held 2,745
-- emeralds, a third of the village's (ColonyFood, 2026-11-20, day 820). Now its value for
-- each input is at least the greater of:
-- * its budget's (28a): each day it means to spend what it holds over RESERVE_DINNERS
--   dinners (at its own price for one) over SPEND_DAYS, on the day's wants, shared by
--   their base prices, so it spends its savings and its takings back on stone and wood;
-- * its takings' (28b): SALE_SHARE of what it last sold the good made from it for
--   (`_villages_sold_at`, asks.sold), per input.
-- Sellers ask at least asks.BID_SHARE of a bid they heard for stone, logs, planks or fuel
-- (asks.bid_priced), so its bids raise their prices, not only what it buys.
local NUGGET, FLINT, GLASS = "mcl_core:iron_nugget", "mcl_core:flint", "mcl_core:glass"
local GLASS_KEEP, FLINT_KEEP = 12, 32
local LOGS_PER_FLINT, LOG_CAP = 4, 32
local STONE_WANT = 72
local GOLD_RESERVE = 12 * 9
local COAL = "mcl_core:coal_lump"
-- Fuel it keeps, in lumps: two hours of nuggets at half a lump each (ticket 28c).
local FUEL_WANT = 8
local RESERVE_DINNERS = 8
local SPEND_DAYS = 30
local SALE_SHARE = 0.5
-- What it makes or sells, by conversion too (ledger.lua prices them at their inputs' cost,
-- the seed of every villager's reference price for them).
local GOODS = {
	[NUGGET] = true, ["mcl_core:iron_ingot"] = true, ["mcl_core:gold_nugget"] = true,
	["mcl_core:gold_ingot"] = true, [FLINT] = true, [GLASS] = true, ["xpanes:pane_natural_flat"] = true,
}

local M = {BLOCK = BLOCK, PROFESSION = PROFESSION, FLAG = FLAG, OVERLAY = OVERLAY, GOODS = GOODS,
	GLASS_KEEP = GLASS_KEEP, FLINT_KEEP = FLINT_KEEP, LOGS_PER_FLINT = LOGS_PER_FLINT, LOG_CAP = LOG_CAP,
	STONE_WANT = STONE_WANT, GOLD_RESERVE = GOLD_RESERVE, FUEL_WANT = FUEL_WANT, RESERVE_DINNERS = RESERVE_DINNERS,
	SPEND_DAYS = SPEND_DAYS, SALE_SHARE = SALE_SHARE}

-- For its ledger (possessions.assess), from what it holds (possessions.held): the
-- categories it wants ({stone = n, log = n, fuel = burn seconds}). Stone and fuel always,
-- logs for the flint it is short of: whether they pay or not, since it works its stand
-- and spends its budget on them (ticket 28). Its goods have no floor (ticket 21b).
function M.targets(held)
	local wanted = {stone = STONE_WANT, fuel = FUEL_WANT * goods.units("fuel", COAL)}
	local logs = math.min(LOGS_PER_FLINT * math.max(FLINT_KEEP - (held[FLINT] or 0), 0), LOG_CAP)
	if logs > 0 then wanted.log = logs end
	return wanted
end

-- What a category unit of each wanted category costs at base prices, for sharing out its
-- budget.
local UNIT_PRICES = {
	stone = function() return ledger.price("mcl_core:stone") end,
	log = function() return ledger.price("mcl_core:tree") end,
	fuel = function() return ledger.price(COAL) / goods.units("fuel", COAL) end,
}

-- The members a recipe input takes: its category's, or itself.
local function members(input)
	local category = input[3] or goods.target_category(input[1])
	return category and goods.CATEGORIES[category] or {[input[1]] = 1}
end

-- Its least value for each input ({item = emeralds}, ticket 28): `wanted` its categories
-- (M.targets), `emeralds` what it holds, `scale` its dinner scale (dinner.scale), `sold_at`
-- what it last sold each good for ({item = emeralds each}, asks.sold).
function M.floors(wanted, emeralds, scale, sold_at)
	local floors = {}
	local function lift(item, value)
		if value > (floors[item] or 0) then floors[item] = value end
	end
	-- Its budget (28a), shared by base price over the day's wants.
	local budget = math.max((emeralds or 0) - RESERVE_DINNERS * ledger.DINNER * (scale or 1), 0) / SPEND_DAYS
	local total = 0
	for category, amount in pairs(wanted or {}) do
		if UNIT_PRICES[category] then total = total + amount * UNIT_PRICES[category]() end
	end
	if budget > 0 and total > 0 then
		for category, amount in pairs(wanted) do
			if UNIT_PRICES[category] and amount > 0 then
				local per = budget * UNIT_PRICES[category]() / total
				for item, units in pairs(goods.CATEGORIES[category]) do lift(item, per * units) end
			end
		end
	end
	-- Its takings (28b): a share of what the good made from an input last sold for.
	for _, recipe in ipairs(recipes.alchemist) do
		local sold = sold_at and sold_at[recipe.makes]
		if sold and sold > 0 then
			for _, input in ipairs(recipe.from) do
				for item in pairs(members(input)) do lift(item, SALE_SHARE * sold * recipe.count / input[2]) end
			end
		end
	end
	return floors
end

local function pos_string(pos)
	if not pos then return "?" end
	return string.format("(%d,%d,%d)", pos.x, pos.y, pos.z)
end

local function is_block(pos)
	local node = pos and core.get_node_or_nil(pos)
	return node ~= nil and node.name == BLOCK
end

-- Its stand, if it holds one: the jobsite, a stand naming it.
function M.claimed_block(self)
	local pos = self._jobsite
	return is_block(pos) and core.get_meta(pos):get_string("villager") == self._id and pos or nil
end

-- Whether it works as an alchemist now.
function M.is_alchemist(self)
	return self[FLAG] == true and not self.child and self._profession == PROFESSION and M.claimed_block(self) ~= nil
end

-- Whether it has lost its stand: the stand's node is loaded and is no stand naming it, or
-- it no longer has the profession or a jobsite.
local function lost(self)
	if self.child or self._profession ~= PROFESSION or not self._jobsite then return true end
	if not core.get_node_or_nil(self._jobsite) then return false end
	return M.claimed_block(self) == nil
end

-- Who may take one: an adult out of work, as for any job block (job_blocks.eligible).
local function eligible(self)
	return not self.child and self._id ~= nil and not self._jobsite and self._profession == "unemployed"
		and not self._villages_left_unemployed
end

-- Claims the stand at pos. Returns whether it did.
function M.employ(self, pos)
	if not is_block(pos) or core.get_meta(pos):get_string("villager") ~= "" or not eligible(self) then return false end
	core.get_meta(pos):set_string("villager", self._id)
	self._jobsite = {x = pos.x, y = pos.y, z = pos.z}
	self._profession = PROFESSION
	self[FLAG] = true
	-- Whatever it did as a labourer is over; what it carries stays its own. It is fed for good.
	self._villages_labour, self._villages_peddle, self._villages_farm_seek = nil, nil, nil
	self._villages_starving = nil
	core.log("action", string.format("[living_villages] villager %s became alchemist at the stand at %s",
		tostring(self._id), pos_string(pos)))
	return true
end

-- Its stand gone or taken: unemployed again, to look for work.
function M.release(self)
	self[FLAG] = nil
	if self._profession == PROFESSION then
		self._profession = "unemployed"
		self._jobsite = nil
	end
	core.log("action", string.format("[living_villages] villager %s is no longer an alchemist", tostring(self._id)))
end

function M.install(def)
	local original_activate = def.on_activate
	local original_custom = def.do_custom
	def.on_activate = function(self, staticdata, dtime)
		local result = original_activate(self, staticdata, dtime)
		if not self.child and self._profession == PROFESSION and self._id and M.claimed_block(self) then
			self[FLAG] = true
		end
		return result
	end
	def.do_custom = function(self, dtime)
		local result = original_custom(self, dtime)
		if self[FLAG] and lost(self) then M.release(self) end
		return result
	end
end

-- One line for the inspector.
function M.status(self)
	if not self[FLAG] then return "not an alchemist" end
	local block = M.claimed_block(self)
	return block and string.format("alchemist at the stand at %s", pos_string(block)) or "alchemist, stand not loaded"
end

return M
