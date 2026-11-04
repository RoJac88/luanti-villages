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

print("village_census: ok")
