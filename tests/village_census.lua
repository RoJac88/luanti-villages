-- Run with: lua tests/village_census.lua
local census = dofile("village_census.lua")

local function village(counts)
	local buildings = {}
	local names = {}
	for name in pairs(counts) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		for _ = 1, counts[name] do buildings[#buildings + 1] = {name = name} end
	end
	return {buildings = buildings}
end

-- A Builder's house is no part of the mix, in shares or in the count.
do
	local record = village({small_house = 3, tavern = 1, builder_house = 1})
	local shares = census.shares(record)
	assert(shares.builder_house == nil)
	assert(math.abs(shares.small_house - 0.75) < 1e-9 and math.abs(shares.tavern - 0.25) < 1e-9)
	local _, total = census.current(record)
	assert(total == 4)
end

-- Building on keeps the original mix: after each whole multiple of the village's size
-- every type stands at exactly that multiple of what it generated with.
do
	local counts = {small_house = 10, medium_house = 2, large_house = 1, farm = 2, lamp = 2, tavern = 1, church = 1, belltower = 1}
	local record = village(counts)
	local _, size = census.generated(record)
	for round = 1, 3 do
		for _ = 1, size do
			local name = census.pick(record)
			assert(name)
			census.add_built(record, name)
		end
		local current = census.current(record)
		for name, count in pairs(counts) do
			assert(current[name] == count * (round + 1), name .. " at round " .. round .. ": " .. tostring(current[name]))
		end
	end
end

-- At no point does a type run a whole building or more behind its share.
do
	local record = village({small_house = 13, farm = 2, church = 1})
	local shares = census.shares(record)
	for _ = 1, 200 do
		census.add_built(record, census.pick(record))
		local current, total = census.current(record)
		for name, share in pairs(shares) do
			assert(math.abs((current[name] or 0) - share * total) < 1, name)
		end
	end
end

-- The first pick makes up the type furthest behind.
do
	local record = village({small_house = 8, tavern = 2})
	record.built = {tavern = 2}
	assert(census.pick(record) == "small_house", "the taverns are ahead")
end

-- A tie goes to the smaller building, then the name, whatever the order of the table.
do
	local record = village({well = 1, lamp = 1})
	assert(census.pick(record, nil, {well = 64, lamp = 9}) == "lamp")
	assert(census.pick(record, nil, {well = 9, lamp = 64}) == "well")
	assert(census.pick(record) == "lamp", "by name")
end

-- The worst gap's building counts double: a village of 8 houses and a farm, with
-- one more building, is short 0.89 of a house (8/9 * 10 - 8) against 0.11 of a farm;
-- doubled, the farm's 2 * 0.11 * 10 - 1 = 1.2 wins. Without the weight the house does.
do
	local record = village({small_house = 8, farm = 1})
	assert(census.pick(record) == "small_house")
	assert(census.pick(record, nil, nil, {farm = true}) == "farm")
	assert(census.pick(record, nil, nil, {church = true}) == "small_house", "a building it lacks is no part of the mix")
end

-- A village with no record goes by the generator's ratios and counts what is built.
do
	local stock = {
		{name = "belltower", max_num = 0},
		{name = "small_house", max_num = 0.7},
		{name = "farm", max_num = 0.1},
		{name = "lamp", max_num = 0.2},
		{name = "builder_house", max_num = 0},
	}
	local record = {}
	local shares = census.shares(record, stock)
	assert(shares.belltower == nil and shares.builder_house == nil, "a max_num of 0 is never picked")
	assert(math.abs(shares.small_house - 0.7) < 1e-9)
	assert(census.pick(record, stock) == "small_house")
	for _ = 1, 10 do census.add_built(record, census.pick(record, stock)) end
	local current = census.current(record)
	assert(current.small_house == 7 and current.lamp == 2 and current.farm == 1)
	assert(record.buildings == nil, "what generated is not invented")
end

-- Nothing to go by, nothing to pick.
assert(census.pick({}, {}) == nil)
assert(census.pick({}) == nil)
assert(census.pick({buildings = {{name = "builder_house"}}}) == nil)

-- A player's schematics: the mix of the weights, on what was built from them alone.
do
	local weights = {cottage = 3, shed = 1}
	local counts, order = {}, {}
	for _ = 1, 8 do
		local name = census.pick_custom(weights, counts)
		order[#order + 1] = name
		counts[name] = (counts[name] or 0) + 1
	end
	assert(counts.cottage == 6 and counts.shed == 2, "the shares hold")
	local run, longest = 0, 0
	for _, name in ipairs(order) do
		run = name == "cottage" and run + 1 or 0
		longest = math.max(longest, run)
	end
	assert(longest <= 3, "no long streak of the heaviest")

	-- A tie goes to the smaller, then the name, whatever the order.
	assert(census.pick_custom({a = 1, b = 1}, {}, {a = 20, b = 10}) == "b")
	assert(census.pick_custom({a = 1, b = 1}, {}) == "a")

	-- A count of something no longer offered does not skew the rest.
	assert(census.pick_custom({a = 1, b = 3}, {gone = 50, a = 1, b = 1}) == "b")

	assert(census.pick_custom({}, {}) == nil)

	-- Each source counts apart, and leaves the stock mix alone.
	local record = {buildings = {{name = "small_house"}}}
	census.add_built_custom(record, "schemedit", "small_house")
	census.add_built_custom(record, "schemedit", "small_house")
	census.add_built_custom(record, "folder", "tower")
	assert(census.custom_counts(record, "schemedit").small_house == 2)
	assert(census.custom_counts(record, "folder").small_house == nil)
	assert(next(census.custom_counts(nil, "folder")) == nil)
	local _, total = census.current(record)
	assert(total == 1 and record.built == nil)
end

-- A village recorded with a farm, from before village_buildings.lua swapped it for the
-- greenhouse, wants a greenhouse; a recorded building the list no longer has is never picked.
do
	local list = {
		{name = "belltower", max_num = 0}, {name = "small_house", max_num = 0.7},
		{name = "greenhouse", max_num = 0.08},
	}
	local record = {buildings = {
		{name = "belltower"}, {name = "farm"}, {name = "farm"}, {name = "small_house"}, {name = "lighthouse"},
	}, built = {farm = 1}}
	local shares = census.shares(record, list)
	assert(shares.farm == nil and shares.lighthouse == nil and math.abs(shares.greenhouse - 0.5) < 1e-9)
	local counts, total = census.current(record, list)
	assert(counts.greenhouse == 3 and counts.farm == nil and total == 5)
	assert(census.pick(record, list) ~= "farm" and census.pick(record, list) ~= "lighthouse")
	-- Nothing renamed where the list still has the old name.
	local old_list = {{name = "belltower", max_num = 0}, {name = "farm", max_num = 0.1}}
	assert(census.shares({buildings = {{name = "farm"}}}, old_list).farm == 1)
end

-- Within a set, the generator's ratios among just those names, counting what stands.
do
	local list = {
		{name = "small_house", max_num = 0.6}, {name = "duplex", max_num = 0.2}, {name = "large_house", max_num = 0.2},
		{name = "tavern", max_num = 0.05}, {name = "lamp", max_num = 0},
	}
	local houses = {small_house = true, duplex = true, large_house = true, lamp = true}
	local record = {buildings = {{name = "small_house"}, {name = "small_house"}, {name = "tavern"}}}
	-- With one more, 4 houses at 0.6/0.2/0.2: the duplex and large house are each 0.8 short.
	local first = census.pick_among(record, list, houses)
	assert(first == "duplex", first)
	census.add_built(record, first)
	assert(census.pick_among(record, list, houses) == "large_house")
	assert(census.pick_among(record, list, {lamp = true}) == nil, "no share, no pick")
	assert(census.pick_among(record, list, {church = true}) == nil)
end

print("village_census: ok")
