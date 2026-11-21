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
local prices = dofile(core.get_modpath("living_villages") .. "/prices.lua")

local BLOCK = "living_villages:alchemy_stand"
local PROFESSION = "cleric"
local FLAG = "_villages_alchemist"
-- The cleric's robe, recoloured, as keeper.lua recolours the butcher's apron.
local OVERLAY = "(living_villages_villager_profession_cleric.png^[multiply:#4fb3a0)"

-- Its trade (ticket 20c). It makes glass while it holds GLASS_KEEP or fewer, flint up to
-- FLINT_KEEP and nuggets up to NUGGET_KEEP (recipes.lua's `upto`), each burning half a lump
-- of fuel (ticket 28c), by rank, whether they pay or not. Since ticket 30 a day makes twice
-- what it did: 72 glass, 12 flint or 36 nuggets. It wants logs for the flint it is short
-- of, at most LOG_CAP at once, a day's STONE_WANT of stone or cobble and FUEL_WANT lumps'
-- worth of fuel always. Gold is sold only from the nuggets past GOLD_RESERVE (goods.lua's
-- conversions), so NUGGET_KEEP leaves room for a gold ingot's 162.
--
-- It breaks even (ticket 30). Its goods were priced at their inputs' base cost and its
-- bids lifted by a budget (ticket 28), so it bought stone at 0.18 and charcoal at 1 and
-- sold a nugget, 1.22's worth, for 1; its asks followed its own value, which its 2,600
-- emeralds raised to four times what it believed a nugget worth (ColonyFood, day 826).
-- * Its book (`_villages_input_cost`): the average it paid for a unit of stone, log and
--   fuel (a burn second), over what it holds (`bought`); a recipe's cost is its inputs and
--   fuel at those (`cost`), and what it holds of a good is at the average cost it was made
--   at (`_villages_made_cost`, `made`): a good made before the book at its reference price.
-- * Its asks (asks.reservation): no less than that cost times MARGIN, and no longer its own value,
--   so its wealth is in none of its prices.
-- * Its bids (`caps`): an input is worth no more to it than what the goods it would still
--   make (under `upto`) sell for pays: each recipe's sale price (`_villages_sold_at`, else
--   its reference price) over its cost at the book scales the book's unit costs, and the
--   best recipe's sets the cap. It applies after the money factor (ledger's `ceiling`).
-- * Its budget (ticket 28a, `floors`) still lifts its bids, above those caps too: each
--   day it means to spend what it holds over RESERVE_DINNERS dinners over SPEND_DAYS, on
--   the day's wants (a day's stock, so its targets bound it), shared by base price. What
--   it pays goes into its book, so its goods' asks rise with it and its savings become
--   stock that sells at cost, not a loss.
-- Sellers ask at least asks.BID_SHARE of a bid they heard for stone, logs, planks or fuel
-- (asks.bid_priced), so its bids raise their prices, not only what it buys.
local NUGGET, FLINT, GLASS = "mcl_core:iron_nugget", "mcl_core:flint", "mcl_core:glass"
local GLASS_KEEP, FLINT_KEEP, NUGGET_KEEP = 12, 32, 192
local LOGS_PER_FLINT, LOG_CAP = 4, 48
local STONE_WANT = 144
local GOLD_RESERVE = 24
local COAL = "mcl_core:coal_lump"
-- Fuel it keeps, in lumps: two hours of nuggets at half a lump each (ticket 28c), at
-- ticket 30's pace.
local FUEL_WANT = 16
local RESERVE_DINNERS = 8
local SPEND_DAYS = 30
-- Over its cost it asks this much (ticket 30).
local MARGIN = 1.05
local SMELTS_PER_LUMP = 8
local INPUT_CATEGORIES = {stone = true, log = true, fuel = true}
-- What it makes or sells, by conversion too (ledger.lua prices them at their inputs' cost,
-- the seed of every villager's reference price for them).
local GOODS = {
	[NUGGET] = true, ["mcl_core:iron_ingot"] = true, ["mcl_core:gold_nugget"] = true,
	["mcl_core:gold_ingot"] = true, [FLINT] = true, [GLASS] = true, ["xpanes:pane_natural_flat"] = true,
}

local M = {BLOCK = BLOCK, PROFESSION = PROFESSION, FLAG = FLAG, OVERLAY = OVERLAY, GOODS = GOODS,
	GLASS_KEEP = GLASS_KEEP, FLINT_KEEP = FLINT_KEEP, LOGS_PER_FLINT = LOGS_PER_FLINT, LOG_CAP = LOG_CAP,
	STONE_WANT = STONE_WANT, GOLD_RESERVE = GOLD_RESERVE, FUEL_WANT = FUEL_WANT, RESERVE_DINNERS = RESERVE_DINNERS,
	SPEND_DAYS = SPEND_DAYS, MARGIN = MARGIN, NUGGET_KEEP = NUGGET_KEEP}

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

-- What a unit of each input category costs at base prices, for sharing out its budget,
-- and the good each is reckoned by.
local BASE = {stone = "mcl_core:stone", log = "mcl_core:tree", fuel = COAL}
local function base_unit(category)
	return ledger.price(BASE[category]) / goods.units(category, BASE[category])
end

-- What it paid on average for a unit of the category (ticket 30): its book, else its
-- reference price for the category's base good.
function M.unit_cost(self, category)
	local book = self._villages_input_cost
	if book and book[category] then return book[category] end
	local base = BASE[category]
	local price = prices.price(self._villages_prices, base) or ledger.price(base)
	return price / goods.units(category, base)
end

-- Its book learns a purchase of `count` `item` for `paid` emeralds; `held` what it holds
-- now (possessions.held), the purchase in it.
function M.bought(self, held, item, count, paid)
	if not self[FLAG] or not paid or count <= 0 then return end
	for category in pairs(INPUT_CATEGORIES) do
		local units = goods.CATEGORIES[category][item]
		if units then
			local before = -count * units
			for member, per in pairs(goods.CATEGORIES[category]) do before = before + (held[member] or 0) * per end
			before = math.max(before, 0)
			local cost = M.unit_cost(self, category)
			self._villages_input_cost = self._villages_input_cost or {}
			self._villages_input_cost[category] = (before * cost + paid) / (before + count * units)
		end
	end
end

-- The input category a recipe input is reckoned in, and its units.
local function input_category(input)
	local category = input[3] or goods.target_category(input[1])
	if category and INPUT_CATEGORIES[category] then return category, goods.units(category, input[1]) end
	return nil
end

-- What one of the recipe's goods costs it at its book: inputs and fuel.
function M.cost(self, recipe)
	local cost = 0
	for _, input in ipairs(recipe.from) do
		local category, units = input_category(input)
		if category then cost = cost + input[2] * units * M.unit_cost(self, category) end
	end
	if recipe.fuel then
		cost = cost + recipe.fuel / SMELTS_PER_LUMP * goods.units("fuel", COAL) * M.unit_cost(self, "fuel")
	end
	return cost / recipe.count
end

local by_makes = {}
for _, recipe in ipairs(recipes.alchemist) do by_makes[recipe.makes] = recipe end

-- Its stock's cost learns a craft: `before` how many it held before, `cost` each.
function M.made(self, item, count, before)
	local recipe = by_makes[item]
	if not self[FLAG] or not recipe then return end
	local cost = M.cost(self, recipe)
	local old = M.stock_cost(self, item)
	before = math.max(before or 0, 0)
	self._villages_made_cost = self._villages_made_cost or {}
	self._villages_made_cost[item] = (before * old + count * cost) / (before + count)
end

-- What it reckons one of a good it holds cost it: the average it was made at, a product
-- made on sale its sources' over the ratio (goods.lua). A good with no entry yet (stock
-- from before the book) is entered at its reference price then, once: a seed that kept
-- following the reference would rise with every sale at its margin, and never let its
-- ask fall.
function M.stock_cost(self, item)
	local book = self._villages_made_cost
	if book and book[item] then return book[item] end
	for _, conversion in ipairs(goods.CONVERSIONS.alchemist) do
		if conversion.to == item then return M.stock_cost(self, conversion.from) / conversion.ratio end
	end
	local seed = prices.price(self._villages_prices, item) or ledger.price(item) or 0
	if self[FLAG] and by_makes[item] then
		self._villages_made_cost = book or {}
		self._villages_made_cost[item] = seed
	end
	return seed
end

-- The most an input is worth to it ({item = emeralds}, ticket 30): for each recipe it
-- would still make (`held` under its `upto`), what the good sells for over its cost at the
-- book scales the book's unit costs; the best recipe's sets each category's cap, and a
-- member's is that times its units. A category no such recipe takes is capped at 0: at
-- its stops it buys nothing over its budget's floors, however rich.
function M.caps(self, held)
	local per_unit = {}
	for category in pairs(INPUT_CATEGORIES) do per_unit[category] = 0 end
	local sold_at = self._villages_sold_at or {}
	for _, recipe in ipairs(recipes.alchemist) do
		if not recipe.upto or (held[recipe.makes] or 0) < recipe.upto then
			local sale = sold_at[recipe.makes] or prices.price(self._villages_prices, recipe.makes)
				or ledger.price(recipe.makes)
			local cost = M.cost(self, recipe)
			if sale and cost > 0 then
				local scale = sale / cost
				local used = {}
				for _, input in ipairs(recipe.from) do
					local category = input_category(input)
					if category then used[category] = true end
				end
				if recipe.fuel then used.fuel = true end
				for category in pairs(used) do
					per_unit[category] = math.max(per_unit[category] or 0, M.unit_cost(self, category) * scale)
				end
			end
		end
	end
	local caps = {}
	for category, per in pairs(per_unit) do
		for item, units in pairs(goods.CATEGORIES[category]) do caps[item] = math.max(caps[item] or 0, per * units) end
	end
	return caps
end

-- Its least value for each input ({item = emeralds}, ticket 28a): `wanted` its categories
-- (M.targets), `emeralds` what it holds, `scale` its dinner scale (dinner.scale). Its
-- budget, shared by base price over the day's wants. Above its caps too (ticket 30): it
-- turns its savings into a day's stock of inputs, which its targets bound, and what it
-- pays goes into its book, so its goods' asks cover it.
function M.floors(wanted, emeralds, scale)
	local floors = {}
	local budget = math.max((emeralds or 0) - RESERVE_DINNERS * ledger.DINNER * (scale or 1), 0) / SPEND_DAYS
	local total = 0
	for category, amount in pairs(wanted or {}) do
		if BASE[category] then total = total + amount * base_unit(category) end
	end
	if budget <= 0 or total <= 0 then return floors end
	for category, amount in pairs(wanted) do
		if BASE[category] and amount > 0 then
			local per = budget * base_unit(category) / total
			for item, units in pairs(goods.CATEGORIES[category]) do
				if per * units > (floors[item] or 0) then floors[item] = per * units end
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
