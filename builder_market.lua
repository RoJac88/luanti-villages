-- The Builder in the market (docs/villager-economy-design.md, Exchange between villagers;
-- ticket 11). While its project waits in requires_materials, builder.lua hands each
-- materials report here:
--
-- * Wants. What its chests and pouch are short of, of the priced items (ledger.price),
--   goes in `_villages_builder_wants` (item -> count). possessions.assess adds it to its
--   ledger as `extra`, so its market news posts the shortage and it values the goods
--   urgently (ledger.lua), and trade trips (trade_trips.lua) take it to sellers, in its
--   work stage too. An unpriced material it cannot buy: a player must bring it.
-- * Stowing. What it bought sits in its belongings; the materials report counts its pouch
--   (farm_stock.lua), so bought materials move there.
-- * Purse. Its own emeralds, topped up to PURSE from emeralds left in its bench chests:
--   whoever leaves emeralds there is paying for materials.
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

local PURSE = 8
local EMERALD = "mcl_core:emerald"

local M = {PURSE = PURSE}

-- Takes in a materials report (builder.materials_report) that is short.
function M.update(self, report)
	if not clock.enabled() then return M.clear(self) end
	for _, row in ipairs(report.rows) do
		local bought = possessions.count(self, row.item)
		if bought > 0 then
			possessions.take(self, row.item, bought)
			stock.add(self, row.item, bought)
			row.carried, row.missing = row.carried + bought, math.max(row.missing - bought, 0)
		end
	end
	local wants
	for _, row in ipairs(report.rows) do
		if row.missing > 0 and ledger.price(row.item) then
			wants = wants or {}
			wants[row.item] = row.missing
		end
	end
	self._villages_builder_wants = wants
	self._villages_builder_drop = report.chests[1] and vector.new(report.chests[1]) or nil
	local have = possessions.emeralds(self)
	if wants and have < PURSE then
		for _, chest in ipairs(report.chests) do
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
	self._villages_builder_drop = nil
end

-- One line for the inspector.
function M.status(self)
	local parts = {}
	for item, count in pairs(self._villages_builder_wants or {}) do parts[#parts + 1] = count .. " " .. item:gsub("^.*:", "") end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

return M
