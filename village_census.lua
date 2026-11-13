-- Which building a Builder puts up next, so that a village keeps the mix it was
-- generated with. A village's record (village_index.lua) lists what generated in
-- `buildings` and counts what Builders added in `built`. One generated before records
-- existed has neither list to go by, so it takes the generator's own ratios (max_num
-- in settlements.schematic_table) and counts only what is built from then on.
--
-- The pick is the largest deficit: with one more building, which type falls furthest
-- short of its share. A Builder's own house is no part of the mix, either way.
--
-- An economic weight (docs/villager-economy-design.md, Visibility; ticket 10): a stock
-- building that holds the jobsite of the village's worst gap (economy_report.lua,
-- `favoured`) counts double, its share doubled in the deficit, so a village short of what
-- a missing profession makes gets that profession's building sooner without losing its
-- mix. The bench menu's choice of a schematic source overrides this as it overrides the
-- stock mix: pick_custom has no weight.
local M = {FAVOURED_WEIGHT = 2}

M.BUILDER_HOUSE = "builder_house"

local function counted(name)
	return name ~= M.BUILDER_HOUSE
end

-- Buildings the generator's list now holds under another name, so a village recorded with
-- the old one wants the new in its place (village_buildings.lua's greenhouse for the farm).
M.RENAMED = {farm = "greenhouse"}

-- The name a recorded building goes by in `schematic_table`, or nil if the list no longer
-- has it, so it is never picked. Without a list, the name as recorded.
local function listed(name, schematic_table)
	if not schematic_table then return name end
	local renamed
	for _, entry in ipairs(schematic_table) do
		if entry.name == name then return name end
		if entry.name == M.RENAMED[name] then renamed = entry.name end
	end
	return renamed
end

-- How many of each type a record lists as generated, and the total. `schematic_table`
-- (optional) renames and drops as `listed` does.
function M.generated(record, schematic_table)
	local counts, total = {}, 0
	for _, building in ipairs(record and record.buildings or {}) do
		local name = listed(building.name, schematic_table)
		if name and counted(name) then
			counts[name] = (counts[name] or 0) + 1
			total = total + 1
		end
	end
	return counts, total
end

-- Each type's share of the village, summing to 1, or nil if there is nothing to go by.
function M.shares(record, schematic_table)
	local shares = {}
	local counts, total = M.generated(record, schematic_table)
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

-- The village as it stands: what generated and what Builders added. `schematic_table`: see
-- M.generated.
function M.current(record, schematic_table)
	local counts, total = M.generated(record, schematic_table)
	for recorded, count in pairs(record and record.built or {}) do
		local name = listed(recorded, schematic_table)
		if name and counted(name) then
			counts[name] = (counts[name] or 0) + count
			total = total + count
		end
	end
	return counts, total
end

-- The name furthest short of its share with one more building, or nil. `block_totals`
-- (optional, name -> blocks) breaks a tie toward the smaller building, then the name settles
-- it, so the pick does not depend on table order and a reload picks the same. `favoured`
-- (optional, a set of names) counts double.
local FAVOURED_WEIGHT = M.FAVOURED_WEIGHT
local function largest_deficit(shares, counts, total, block_totals, favoured, exclude)
	local best, best_deficit
	local EPSILON = 1e-9
	for name, share in pairs(shares) do
		if not (exclude and exclude[name]) then
			if favoured and favoured[name] then share = share * FAVOURED_WEIGHT end
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
	end
	return best
end

-- The stock type to build next, or nil. `favoured`: see largest_deficit. `exclude` (optional,
-- a set of names) are passed over.
function M.pick(record, schematic_table, block_totals, favoured, exclude)
	local shares = M.shares(record, schematic_table)
	if not shares then return nil end
	local counts, total = M.current(record, schematic_table)
	return largest_deficit(shares, counts, total, block_totals, favoured, exclude)
end

-- The one of `names` (a set) furthest short of its share, the shares being the generator's
-- own ratios (max_num) among just those names, so a kind the village never generated with
-- (a duplex in an old village) still gets its turn. Counts are the village as it stands.
-- nil when none of them is listed with a share. `favoured`: see largest_deficit.
function M.pick_among(record, schematic_table, names, block_totals, favoured)
	local shares, sum = {}, 0
	for _, entry in ipairs(schematic_table or {}) do
		if names[entry.name] and counted(entry.name) and (entry.max_num or 0) > 0 then
			shares[entry.name] = entry.max_num
			sum = sum + entry.max_num
		end
	end
	if sum <= 0 then return nil end
	for name, share in pairs(shares) do shares[name] = share / sum end
	local all = M.current(record, schematic_table)
	local counts, total = {}, 0
	for name in pairs(shares) do
		counts[name] = all[name] or 0
		total = total + counts[name]
	end
	return largest_deficit(shares, counts, total, block_totals, favoured)
end

-- What a village has built from a source of schematics, name -> count.
function M.custom_counts(record, source)
	return record and record.built_custom and record.built_custom[source] or {}
end

-- The schematic to build next from `weights` (name -> weight above 0), or nil. Only what was
-- built from these counts: against a whole village, with its stock buildings, the mix would
-- come out right only after dozens of the heaviest in a row.
function M.pick_custom(weights, counts, block_totals)
	local sum, total, shares = 0, 0, {}
	for _, weight in pairs(weights) do sum = sum + weight end
	if sum <= 0 then return nil end
	for name, weight in pairs(weights) do
		shares[name] = weight / sum
		total = total + (counts[name] or 0)
	end
	return largest_deficit(shares, counts, total, block_totals)
end

-- Kept apart from `built`, so that the stock mix is the same whatever a bench has done, and a
-- schematic may share a stock building's name.
function M.add_built_custom(record, source, name)
	record.built_custom = record.built_custom or {}
	local counts = record.built_custom[source] or {}
	record.built_custom[source] = counts
	counts[name] = (counts[name] or 0) + 1
end

-- A finished building counts from now on.
function M.add_built(record, name)
	record.built = record.built or {}
	record.built[name] = (record.built[name] or 0) + 1
end

return M
