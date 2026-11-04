-- Which building a Builder puts up next, so that a village keeps the mix it was
-- generated with. A village's record (village_index.lua) lists what generated in
-- `buildings` and counts what Builders added in `built`. One generated before records
-- existed has neither list to go by, so it takes the generator's own ratios (max_num
-- in settlements.schematic_table) and counts only what is built from then on.
--
-- The pick is the largest deficit: with one more building, which type falls furthest
-- short of its share. A Builder's own house is no part of the mix, either way.
local M = {}

M.BUILDER_HOUSE = "builder_house"

local function counted(name)
	return name ~= M.BUILDER_HOUSE
end

-- How many of each type a record lists as generated, and the total.
function M.generated(record)
	local counts, total = {}, 0
	for _, building in ipairs(record and record.buildings or {}) do
		if counted(building.name) then
			counts[building.name] = (counts[building.name] or 0) + 1
			total = total + 1
		end
	end
	return counts, total
end

-- Each type's share of the village, summing to 1, or nil if there is nothing to go by.
function M.shares(record, schematic_table)
	local shares = {}
	local counts, total = M.generated(record)
	if total > 0 then
		for name, count in pairs(counts) do shares[name] = count / total end
		return shares
	end
	local sum = 0
	for _, entry in ipairs(schematic_table or {}) do
		if counted(entry.name) then sum = sum + (entry.max_num or 0) end
	end
	if sum <= 0 then return nil end
	for _, entry in ipairs(schematic_table) do
		if counted(entry.name) and (entry.max_num or 0) > 0 then shares[entry.name] = entry.max_num / sum end
	end
	return shares
end

-- The village as it stands: what generated and what Builders added.
function M.current(record)
	local counts, total = M.generated(record)
	for name, count in pairs(record and record.built or {}) do
		if counted(name) then
			counts[name] = (counts[name] or 0) + count
			total = total + count
		end
	end
	return counts, total
end

-- The type to build next, or nil. `block_totals` (optional, name -> blocks) breaks a tie
-- toward the smaller building, then the name settles it, so the pick does not depend on
-- table order and a reload picks the same.
function M.pick(record, schematic_table, block_totals)
	local shares = M.shares(record, schematic_table)
	if not shares then return nil end
	local counts, total = M.current(record)
	local best, best_deficit
	local EPSILON = 1e-9
	for name, share in pairs(shares) do
		local deficit = share * (total + 1) - (counts[name] or 0)
		local better
		if not best or deficit > best_deficit + EPSILON then
			better = true
		elseif deficit > best_deficit - EPSILON then
			local size, best_size = block_totals and block_totals[name], block_totals and block_totals[best]
			if size and best_size and size ~= best_size then
				better = size < best_size
			else
				better = name < best
			end
		end
		if better then best, best_deficit = name, deficit end
	end
	return best
end

-- A finished building counts from now on.
function M.add_built(record, name)
	record.built = record.built or {}
	record.built[name] = (record.built[name] or 0) + 1
end

return M
