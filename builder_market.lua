-- The Builder in the market (docs/villager-economy-design.md, Exchange between villagers;
-- ticket 11). While its project waits in requires_materials, builder.lua hands each
-- materials report here:
--
-- * Wants. What its chests and pouch are short of, of the priced items (ledger.price),
--   goes in `_villages_builder_wants` (item -> count). possessions.assess adds it to its
--   ledger as `extra`, so its market news posts the shortage and it values the goods
--   urgently (ledger.lua), and trade trips (trade_trips.lua) take it to sellers, in its
--   work stage too. An unpriced material it cannot buy: a player must bring it.
-- * Logs for planks. Planks it is short of, where any wood will do (builder_families.lua),
--   it buys as logs of any species (`_villages_builder_logs`, in logs, a quarter of the
--   planks: ledger.assess's `extra_categories`), and splits what it gets four planks a log
--   as it stows them, and a porter delivering logs to it hands over the planks
--   (trade_trips.lua). Logs a player leaves in its chests are not split: those are for a
--   building that wants logs, and a player can make planks.
-- * Red beds (19i). Nobody makes beds, so it makes the red beds it is short of, and any bed
--   where any colour will do (a stock building): three wool of any colour, three planks and
--   a red dye each, a mod-side craft (VoxeLibre beds take wool of their own colour, or
--   recolour a white bed). It wants the wool as any colour (`_villages_builder_wool`, the
--   ledger's `extra_categories`), the planks with its other planks as logs, and the dye
--   among its wants, which anyone sells from a poppy or a red tulip (goods.lua). It makes
--   them from what its pouch and its chests hold past the building's own wool and planks.
-- * Stowing. What it bought sits in its belongings; the materials report counts its pouch
--   (farm_stock.lua), so bought materials move there, any of an item's family with it.
-- * Purse. Its own emeralds, topped up to PURSE from emeralds left in its bench chests:
--   whoever leaves emeralds there is paying for materials, rent included (rent.lua).
--   Never from a farm's chest or the pantry in its reach (possessions.is_food_chest):
--   a probe run caught it taking the pay the keeper had just left a farmer.
-- * Delivery. A porter it hires (trade_trips.lua) delivers to its nearest bench chest,
--   kept in `_villages_builder_drop`.
--
-- Not short, or past requires_materials, the wants are cleared. With the economy off
-- nothing is wanted.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local families = dofile(core.get_modpath("living_villages") .. "/builder_families.lua")

-- In emeralds at ledger.SCALE (ticket 11h).
local PURSE = 8 * ledger.SCALE
local EMERALD = "mcl_core:emerald"

local PLANKS_PER_LOG = 4
local RED_BED, RED_DYE = "mcl_beds:bed_red_bottom", "mcl_dye:red"
local BED_WOOL, BED_PLANKS = 3, 3

local M = {PURSE = PURSE, PLANKS_PER_LOG = PLANKS_PER_LOG, RED_BED = RED_BED, RED_DYE = RED_DYE,
	BED_WOOL = BED_WOOL, BED_PLANKS = BED_PLANKS}

local function sorted(set)
	local list = {}
	for item in pairs(set) do list[#list + 1] = item end
	table.sort(list)
	return list
end
local WOOL, PLANKS = sorted(goods.CATEGORIES.wool), sorted(goods.CATEGORIES.planks)

-- Whether a red bed it makes fills this row: a red bed, or any bed where any colour will do.
local function bed_row(row)
	if row.item == RED_BED then return true end
	return row.swaps and row.item:match("^mcl_beds:bed_.*_bottom$") ~= nil
end

-- How many of `items` its pouch and `chests` hold.
local function held(self, chests, items)
	local total = 0
	for _, item in ipairs(items) do
		total = total + stock.count(self, item)
		for _, chest in ipairs(chests) do total = total + stock.chest_count(chest, item) end
	end
	return total
end

-- Uses up `count` of `items`, its pouch first, then its chests.
local function use(self, chests, items, count)
	for _, item in ipairs(items) do
		for _, chest in ipairs(chests) do
			local short = count - stock.count(self, item)
			if short <= 0 then break end
			stock.take_from_chest(self, chest, item, short)
		end
		local taken = math.min(count, stock.count(self, item))
		if taken > 0 then stock.take(self, item, taken) end
		count = count - taken
		if count <= 0 then return end
	end
end

-- What the building itself needs of `category`'s members, so that beds take only the rest.
local function building_need(rows, category)
	local total = 0
	for _, row in ipairs(rows) do
		if goods.CATEGORIES[category][row.item] then total = total + row.need end
	end
	return total
end

-- Planks a log splits into, or nil for anything else (goods.lua's species).
function M.split(item)
	return goods.SPECIES[item]
end

-- Moves `count` of `item` from its belongings to its pouch, as planks if it is a log.
-- Returns what landed in the pouch and how many.
local function stow(self, item, count)
	possessions.take(self, item, count)
	local planks = M.split(item)
	if planks then item, count = planks, count * PLANKS_PER_LOG end
	stock.add(self, item, count)
	return item, count
end

-- Takes in a materials report (builder.materials_report) that is short.
function M.update(self, report)
	if not clock.enabled() then return M.clear(self) end
	local by_item = {}
	for _, row in ipairs(report.rows) do by_item[row.item] = row end
	-- What it bought: each row's item, or any of its family where it may be swapped, and logs.
	local stowed = {}
	for _, row in ipairs(report.rows) do
		for _, item in ipairs(row.swaps and families.members(row.item) or {row.item}) do
			local bought = not stowed[item] and possessions.count(self, item) or 0
			stowed[item] = true
			if bought > 0 then stow(self, item, bought) end
		end
	end
	for log in pairs(goods.SPECIES) do
		local bought = possessions.count(self, log)
		if bought > 0 then
			local planks, count = stow(self, log, bought)
			core.log("action", string.format("[living_villages] builder %s split %d %s into %d %s",
				tostring(self._id):sub(1, 6), bought, log, count, planks))
		end
	end
	-- Wool and red dye bought for beds.
	for _, item in ipairs(WOOL) do
		local bought = possessions.count(self, item)
		if bought > 0 then stow(self, item, bought) end
	end
	local dye_bought = possessions.count(self, RED_DYE)
	if dye_bought > 0 then stow(self, RED_DYE, dye_bought) end
	-- Counted again by family: one bought birch plank covers an oak one.
	local carried = {}
	for _, row in ipairs(report.rows) do
		for _, item in ipairs(row.swaps and families.members(row.item) or {row.item}) do
			carried[item] = stock.count(self, item)
		end
	end
	local need, swappable = {}, {}
	for _, row in ipairs(report.rows) do
		need[row.item] = row.need - row.in_chests
		swappable[row.item] = row.swaps
	end
	local covered = families.cover(need, swappable, carried)
	for item, row in pairs(by_item) do
		row.carried = covered[item]
		row.missing = math.max(row.need - row.in_chests - row.carried, 0)
	end
	-- The red beds it is short of, made from what it holds past the building's needs.
	local chests = {}
	for _, chest in ipairs(report.chests or {}) do
		if not possessions.is_food_chest(chest) then chests[#chests + 1] = chest end
	end
	local beds_short = 0
	for _, row in ipairs(report.rows) do
		if bed_row(row) then beds_short = beds_short + row.missing end
	end
	local bed_wool, bed_planks, bed_dye = 0, 0, 0
	if beds_short > 0 then
		local wool = math.max(held(self, chests, WOOL) - building_need(report.rows, "wool"), 0)
		local planks = math.max(held(self, chests, PLANKS) - building_need(report.rows, "planks"), 0)
		local dye = held(self, chests, {RED_DYE})
		local made = math.min(beds_short, math.floor(wool / BED_WOOL), math.floor(planks / BED_PLANKS), dye)
		if made > 0 then
			use(self, chests, WOOL, made * BED_WOOL)
			use(self, chests, PLANKS, made * BED_PLANKS)
			use(self, chests, {RED_DYE}, made)
			stock.add(self, RED_BED, made)
			core.log("action", string.format("[living_villages] builder %s made %d red bed(s)",
				tostring(self._id):sub(1, 6), made))
			local placed = made
			for _, row in ipairs(report.rows) do
				if bed_row(row) and placed > 0 then
					local filled = math.min(row.missing, placed)
					row.carried, row.missing, placed = row.carried + filled, row.missing - filled, placed - filled
				end
			end
		end
		local left = beds_short - made
		bed_wool = math.max(left * BED_WOOL - (wool - made * BED_WOOL), 0)
		bed_planks = math.max(left * BED_PLANKS - (planks - made * BED_PLANKS), 0)
		bed_dye = math.max(left - (dye - made), 0)
	end
	local wants, planks
	if bed_planks > 0 then planks = bed_planks end
	if bed_dye > 0 then wants = {[RED_DYE] = bed_dye} end
	for _, row in ipairs(report.rows) do
		if row.missing > 0 and row.swaps and goods.CATEGORIES.planks[row.item] then
			planks = (planks or 0) + row.missing
		elseif row.missing > 0 and bed_row(row) then
			-- Made, not bought: its wool, planks and dye are wanted above.
		elseif row.missing > 0 and ledger.price(row.item) then
			wants = wants or {}
			wants[row.item] = row.missing
		end
	end
	self._villages_builder_wants = wants
	self._villages_builder_logs = planks and math.ceil(planks / PLANKS_PER_LOG) or nil
	self._villages_builder_wool = bed_wool > 0 and bed_wool or nil
	-- Its own chests: within its reach a farm's chest or the pantry may stand, whose
	-- emeralds are the farmer's or the keeper's.
	local own = {}
	for _, chest in ipairs(report.chests) do
		if not possessions.is_food_chest(chest) then own[#own + 1] = chest end
	end
	self._villages_builder_drop = own[1] and vector.new(own[1]) or nil
	local have = possessions.emeralds(self)
	if (wants or planks or bed_wool > 0) and have < PURSE then
		for _, chest in ipairs(own) do
			local moved = stock.take_from_chest(self, chest, EMERALD, PURSE - have)
			if moved > 0 then
				stock.take(self, EMERALD, moved)
				possessions.add(self, EMERALD, moved)
				have = have + moved
				core.log("action", string.format("[living_villages] builder %s took %d emerald(s) from %s to buy materials",
					tostring(self._id):sub(1, 6), moved, core.pos_to_string(chest)))
			end
			if have >= PURSE then break end
		end
	end
	return wants
end

function M.clear(self)
	self._villages_builder_wants = nil
	self._villages_builder_logs = nil
	self._villages_builder_wool = nil
	self._villages_builder_drop = nil
end

-- Whether it wants anything from the market.
function M.wanting(self)
	return self._villages_builder_wants ~= nil or self._villages_builder_logs ~= nil
		or self._villages_builder_wool ~= nil
end

-- One line for the inspector.
function M.status(self)
	local parts = {}
	for item, count in pairs(self._villages_builder_wants or {}) do parts[#parts + 1] = count .. " " .. item:gsub("^.*:", "") end
	if self._villages_builder_logs then parts[#parts + 1] = self._villages_builder_logs .. " logs (any)" end
	if self._villages_builder_wool then parts[#parts + 1] = self._villages_builder_wool .. " wool (any)" end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

return M
