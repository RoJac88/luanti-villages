-- Run with: lua tests/builder_needs.lua
-- What a Builder in its default mode builds next: the needs in order, and the mix within
-- houses and workplaces.
local census = dofile("village_census.lua")
local needs = dofile("builder_needs.lua")

local TABLE = {
	{name = "small_house", max_num = 0.7}, {name = "medium_house", max_num = 0.08},
	{name = "large_house", max_num = 0.08}, {name = "duplex", max_num = 0.08},
	{name = "greenhouse", max_num = 0.08}, {name = "blacksmith", max_num = 0.055},
	{name = "library", max_num = 0.04}, {name = "butcher", max_num = 0.03},
	{name = "fisherman_hut", max_num = 0.05},
	{name = "tavern", max_num = 0.05}, {name = "church", max_num = 0.04},
	{name = "belltower", max_num = 0}, {name = "lamp", max_num = 0.1},
}

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

local RECORD = village({small_house = 6, greenhouse = 1, tavern = 1, church = 1, blacksmith = 1, lamp = 2})

-- Beds around the origin, all served by a tavern, bell and church at the origin.
local function beds(n, free, at)
	local list = {}
	at = at or {x = 0, y = 0, z = 0}
	for i = 1, n do list[#list + 1] = {pos = {x = at.x + i, y = at.y, z = at.z}, free = i <= (free or 0)} end
	return list
end

local ORIGIN = {x = 0, y = 0, z = 0}
local function survey(fields)
	local s = {
		beds = beds(8, 2), bedless = 0, idle = 0, free_jobs = 0, free_by_profession = {},
		civic = {tavern = {ORIGIN}, bell = {ORIGIN}, church = {ORIGIN}},
	}
	for k, v in pairs(fields or {}) do s[k] = v end
	return s
end

local function decide(s, record)
	return needs.decide(s, record or RECORD, TABLE, nil, census)
end

local HOUSES = needs.HOUSES

-- Villagers with no bed and none free: a house, even when hungry.
do
	local found = decide(survey({beds = beds(8, 0), bedless = 2, food = {adults = 8, hungry = 6, starving = 0}}))
	assert(found.need == "bedless" and HOUSES[found.building], found.need)
	assert(found.reason == "2 villagers have no bed", found.reason)
end

-- Every bed taken: a house, unless food is urgent, then a greenhouse.
do
	local found = decide(survey({beds = beds(8, 0)}))
	assert(found.need == "full" and HOUSES[found.building])
	found = decide(survey({beds = beds(8, 0), food = {adults = 8, hungry = 1, starving = 1}}))
	assert(found.need == "food" and found.building == "greenhouse", found.need)
	-- A free composter: the food is short of a farmer, not a field.
	found = decide(survey({beds = beds(8, 0), food = {adults = 8, hungry = 4, starving = 0},
		free_by_profession = {farmer = 1}}))
	assert(found.need == "full", found.need)
end

-- Food urgency needs both a count and a share.
do
	assert(not needs.food_urgent({adults = 20, hungry = 4, starving = 0}))
	assert(needs.food_urgent({adults = 20, hungry = 3, starving = 2}))
	assert(not needs.food_urgent({adults = 3, hungry = 1, starving = 0}))
	assert(not needs.food_urgent(nil))
end

-- Free beds and hungry: a greenhouse; with the farm in its place, the farm.
do
	local found = decide(survey({food = {adults = 8, hungry = 3, starving = 0}}))
	assert(found.need == "food" and found.building == "greenhouse")
	local farm_table = {{name = "small_house", max_num = 1}, {name = "farm", max_num = 0.1}}
	found = needs.decide(survey({food = {adults = 8, hungry = 3, starving = 0}}), RECORD, farm_table, nil, census)
	assert(found.building == "farm")
end

-- Beds out of reach of the tavern: a tavern near them, the search held within half the reach.
do
	local far = beds(5, 1, {x = 70, y = 0, z = 0})
	local all = beds(8, 2)
	for _, bed in ipairs(far) do all[#all + 1] = bed end
	local found = decide(survey({beds = all, civic = {tavern = {ORIGIN}, bell = {ORIGIN, {x = 72, y = 0, z = 0}},
		church = {ORIGIN, {x = 74, y = 0, z = 0}}}}))
	assert(found.need == "tavern" and found.building == "tavern", found.need)
	assert(found.near.x == 73 and found.near.z == 0, found.near.x)
	assert(found.within == 24)
	assert(found.reason == "5 beds are out of reach of a tavern", found.reason)
	-- Two stray beds are not a part of the village.
	local few = beds(8, 2)
	few[#few + 1] = {pos = {x = 70, y = 0, z = 0}, free = false}
	few[#few + 1] = {pos = {x = 71, y = 0, z = 0}, free = false}
	assert(decide(survey({beds = few})).need ~= "tavern")
	-- Given up on for now: the next need.
	found = decide(survey({beds = all, civic = {tavern = {ORIGIN}, bell = {ORIGIN, {x = 72, y = 0, z = 0}},
		church = {ORIGIN, {x = 74, y = 0, z = 0}}}, skip = {tavern = true}}))
	assert(found.need ~= "tavern")
end

-- The largest group out of reach goes first; a village with no church at all gets one.
do
	local found = decide(survey({civic = {tavern = {ORIGIN}, bell = {ORIGIN}, church = {}}}))
	assert(found.need == "church" and found.building == "church", found.need)
	assert(found.near.x == 5, found.near.x) -- the middle of beds 1 to 8
end

-- A civic need only counts the beds in the Builder's range, when given.
do
	local found = decide(survey({civic = {tavern = {ORIGIN}, bell = {ORIGIN}, church = {}}, civic_beds = {}}))
	assert(found.need ~= "church")
end

-- The worst gap: its building, unless its jobsite already stands free.
do
	local gap = {profession = "librarian", items = {"mcl_books:book"}, buildings = {library = true}}
	local found = decide(survey({gap = gap}))
	assert(found.need == "goods" and found.building == "library", found.need)
	assert(found.reason == "no librarian for mcl_books:book", found.reason)
	found = decide(survey({gap = gap, free_by_profession = {librarian = 1}}))
	assert(found.need ~= "goods")
	-- Two buildings hold a fisherman's jobsite: the mix between them decides.
	gap = {profession = "fisherman", items = {"mcl_fishing:fish_raw"}, buildings = {fisherman_hut = true, medium_house = true}}
	found = decide(survey({gap = gap}))
	assert(found.building == "fisherman_hut" or found.building == "medium_house")
end

-- More unemployed than free job blocks: a workplace.
do
	local found = decide(survey({idle = 2, free_jobs = 1}))
	assert(found.need == "jobs" and needs.WORKPLACES[found.building], found.need)
	found = decide(survey({idle = 1, free_jobs = 1}))
	assert(found.need == "mix", found.need)
end

-- Nothing pressing: the village's mix.
do
	local found = decide(survey())
	assert(found.need == "mix" and found.building == census.pick(RECORD, TABLE))
end

-- A lamp comes from the mix, kept away from the lamps there are; left out a while, the mix
-- picks something else.
do
	local lamp_table = {{name = "small_house", max_num = 0.5}, {name = "lamp", max_num = 0.5}}
	local record = village({small_house = 1, lamp = 1}) -- level: the tie goes to the name
	local lamps = {{x = 5, y = 1, z = 5}}
	local found = needs.decide(survey({spread = {lamp = lamps}}), record, lamp_table, nil, census)
	assert(found.need == "mix" and found.building == "lamp", found.building)
	assert(found.keep_away.spots == lamps and found.keep_away.distance == needs.SPREAD.lamp.distance)
	found = needs.decide(survey({skip = {lamp = true}}), record, lamp_table, nil, census)
	assert(found.building == "small_house" and not found.keep_away, found.building)
end

-- Houses keep the generator's proportions among themselves, a duplex included though the
-- village never had one.
do
	local record = village({small_house = 2, tavern = 1})
	local built = {}
	for _ = 1, 47 do
		local found = decide(survey({beds = beds(4, 0)}), record)
		assert(found.need == "full")
		built[found.building] = (built[found.building] or 0) + 1
		census.add_built(record, found.building)
	end
	-- 49 houses at 0.7 : 0.08 : 0.08 : 0.08 of 0.94.
	assert(built.duplex >= 3 and built.medium_house >= 3 and built.large_house >= 3, tostring(built.duplex))
	assert(built.small_house + 2 >= 34 and built.small_house + 2 <= 38, tostring(built.small_house))
end

-- No house in the list: the next need answers (here, the mix).
do
	local found = needs.decide(survey({beds = beds(4, 0)}), RECORD, {{name = "hut", max_num = 1}}, nil, census)
	assert(found.need == "mix" and found.building == "hut")
end

print("builder_needs: ok")
