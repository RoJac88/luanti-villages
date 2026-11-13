-- What a Builder's village needs built next, in its default mode (when no player's order is
-- in hand). Needs are tried in order, and the first one that has a building to answer it
-- wins:
--
--   1. bedless   Villagers have no bed and none is free: a house.
--   2. full      Every bed is taken. Births need a free bed (births.lua), so the village
--                cannot grow: a house, unless food is urgent, when more mouths would make
--                it worse: a greenhouse first.
--   3. food      Many villagers are hungry and no farmer's composter stands free: a
--                greenhouse (the farm with village_buildings.lua off).
--   4. tavern, bell, church
--                A group of beds out of reach of every tavern, bell or church (the radius
--                the visit looks within: tavern.lua, bell_hangout.lua, church.lua): that
--                building, near those beds. The largest group goes first.
--   5. goods     The worst gap (economy_report.lua): a building holding the jobsite of a
--                profession that makes what the village is short of, unless such a
--                jobsite already stands free, when it lacks people, not buildings.
--   6. jobs      More unemployed adults than free job blocks: a workplace.
--   7. mix       Nothing pressing: the mix the village generated with (village_census.lua),
--                the worst gap's buildings counting double, as before. A lamp only comes
--                this way, and goes up no nearer than SPREAD.lamp to another lamp, so they
--                spread over the village; with no such site it is left out a while.
--
-- Houses and workplaces are each picked as a proportional mix among themselves, by the
-- generator's own ratios (village_census.pick_among).
--
-- `decide` is pure, over a survey of the village; `survey` reads the world and is only
-- called in game.
local M = {}

M.HOUSES = {small_house = true, medium_house = true, large_house = true, duplex = true, tower_house = true}
-- Buildings whose point is a jobsite. Some of the mod's have a bed too, and a stock house
-- may hold a workstation, but a house is built for its beds.
M.WORKPLACES = {
	greenhouse = true, farm = true, fisherman_hut = true, blacksmith = true, library = true,
	butcher = true, woodcutter_shed = true,
}
M.FOOD = {"greenhouse", "farm"}
-- reach: how far from a bed a villager looks for one (tavern.lua, bell_hangout.lua, church.lua).
M.CIVIC = {
	{need = "tavern", building = "tavern", reach = 48},
	{need = "bell", building = "belltower", reach = 42},
	{need = "church", building = "church", reach = 48},
}
-- Buildings kept apart from others of their kind: name -> {node that marks one, least distance
-- from the new one's middle, horizontally}. A lamp's light is a sea lantern, which no other
-- village building has.
M.SPREAD = {lamp = {node = "mcl_ocean:sea_lantern", distance = 20}}

-- Fewer beds than this out of reach are a stray house, not a part of the village.
M.MIN_UNSERVED = 3
-- Food is urgent when at least this many adults, and this share of them, are hungry.
M.FOOD_MIN = 2
M.FOOD_SHARE = 0.25

local function listed(schematic_table, name)
	for _, entry in ipairs(schematic_table or {}) do
		if entry.name == name then return true end
	end
	return false
end

local function distance(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

local function centroid(list)
	local x, y, z = 0, 0, 0
	for _, pos in ipairs(list) do x, y, z = x + pos.x, y + pos.y, z + pos.z end
	local n = #list
	return {x = math.floor(x / n + 0.5), y = math.floor(y / n + 0.5), z = math.floor(z / n + 0.5)}
end

local function nearest(pos, spots)
	local best
	for _, spot in ipairs(spots) do
		local d = distance(pos, spot)
		if not best or d < best then best = d end
	end
	return best
end

-- The beds out of reach of every spot of one kind, and the group a new one should serve:
-- the bed furthest from any spot and the unserved beds within reach of it (with no spot at
-- all, every unserved bed). {unserved = n, group = n, near = pos}, or nil.
function M.civic_gap(beds, spots, reach)
	local unserved = {}
	for _, bed in ipairs(beds) do
		local d = nearest(bed.pos, spots)
		if not d or d > reach then unserved[#unserved + 1] = {pos = bed.pos, d = d or math.huge} end
	end
	if #unserved < M.MIN_UNSERVED then return nil end
	local group = {}
	if #spots == 0 then
		for _, bed in ipairs(unserved) do group[#group + 1] = bed.pos end
	else
		local seed = unserved[1]
		for _, bed in ipairs(unserved) do
			if bed.d > seed.d then seed = bed end
		end
		for _, bed in ipairs(unserved) do
			if distance(bed.pos, seed.pos) <= reach then group[#group + 1] = bed.pos end
		end
	end
	if #group < M.MIN_UNSERVED then return nil end
	return {unserved = #unserved, group = #group, near = centroid(group)}
end

local function count_free(beds)
	local free = 0
	for _, bed in ipairs(beds) do
		if bed.free then free = free + 1 end
	end
	return free
end

function M.food_urgent(food)
	if not food or (food.adults or 0) == 0 then return false end
	local hungry = (food.hungry or 0) + (food.starving or 0)
	return hungry >= M.FOOD_MIN and hungry >= food.adults * M.FOOD_SHARE
end

local function plural(n, one, many)
	return n .. " " .. (n == 1 and one or many)
end

-- What to build next: {building, need, reason, near, within, keep_away} or nil. near and
-- within are for a building that must serve a part of the village: the site search starts
-- from near and takes nothing further than within from it. keep_away {spots, distance} is for
-- one of SPREAD: the search takes nothing whose middle is nearer than distance to a spot.
--   survey: {beds = {{pos, free}}, bedless, food = {adults, hungry, starving} or nil,
--            civic = {tavern = {pos}, bell = {pos}, church = {pos}}, civic_beds = {{pos}},
--            gap = {profession, items, buildings = set} or nil, idle, free_jobs,
--            free_by_profession = {profession = n}, spread = {building = {pos}},
--            skip = {need or building = true}}
--   record, schematic_table, block_totals: as village_census.pick takes them.
function M.decide(survey, record, schematic_table, block_totals, census)
	local skip = survey.skip or {}
	local free_jobs = survey.free_by_profession or {}
	local favoured = survey.gap and survey.gap.buildings
	local function house()
		return census.pick_among(record, schematic_table, M.HOUSES, block_totals)
	end
	local function food()
		if (free_jobs.farmer or 0) > 0 then return nil end
		for _, name in ipairs(M.FOOD) do
			if listed(schematic_table, name) then return name end
		end
		return nil
	end
	local function answer(building, need, reason, extra)
		if not building then return nil end
		local result = {building = building, need = need, reason = reason}
		for k, v in pairs(extra or {}) do result[k] = v end
		return result
	end

	local beds = survey.beds or {}
	local free = count_free(beds)
	local hungry = M.food_urgent(survey.food)
	local hungry_text = hungry and string.format("%d of %d villagers are hungry",
		survey.food.hungry + survey.food.starving, survey.food.adults)

	if free == 0 and (survey.bedless or 0) > 0 then
		local found = answer(house(), "bedless", plural(survey.bedless, "villager has", "villagers have") .. " no bed")
		if found then return found end
	end
	if free == 0 then
		if hungry then
			local found = answer(food(), "food", hungry_text .. ", and every bed is taken")
			if found then return found end
		end
		local found = answer(house(), "full", "every bed is taken (" .. #beds .. ")")
		if found then return found end
	end
	if hungry then
		local found = answer(food(), "food", hungry_text)
		if found then return found end
	end

	local best
	for _, kind in ipairs(M.CIVIC) do
		if not skip[kind.need] and listed(schematic_table, kind.building) then
			local gap = M.civic_gap(survey.civic_beds or beds, (survey.civic or {})[kind.need] or {}, kind.reach)
			if gap and (not best or gap.group > best.gap.group) then best = {kind = kind, gap = gap} end
		end
	end
	if best then
		return answer(best.kind.building, best.kind.need,
			plural(best.gap.group, "bed is", "beds are") .. " out of reach of a " .. best.kind.need,
			{near = best.gap.near, within = math.floor(best.kind.reach / 2)})
	end

	local gap = survey.gap
	if gap and gap.buildings and (free_jobs[gap.profession] or 0) == 0 then
		local found = answer(census.pick_among(record, schematic_table, gap.buildings, block_totals), "goods",
			"no " .. gap.profession .. " for " .. table.concat(gap.items or {}, ", "))
		if found then return found end
	end

	local idle, open = survey.idle or 0, survey.free_jobs or 0
	if idle > open then
		local found = answer(census.pick_among(record, schematic_table, M.WORKPLACES, block_totals, favoured), "jobs",
			plural(idle, "villager has", "villagers have") .. " no job")
		if found then return found end
	end

	local building = census.pick(record, schematic_table, block_totals, favoured, skip)
	local spread = building and M.SPREAD[building]
	return answer(building, "mix", "the village's mix", spread and {
		keep_away = {spots = (survey.spread or {})[building] or {}, distance = spread.distance},
	})
end

-- Reading the world, in game only. --------------------------------------------------------

local BED_GROUP = "group:bed"
local JUKEBOX = "mcl_jukebox:jukebox"
local PULPIT = "living_villages:pulpit"
local BELL = "mcl_bells:bell"
-- find_nodes_in_area refuses an area over 4096000 nodes; slices along x stay well under.
local SLICE = 32

local function find(core, minp, maxp, names)
	local found = {}
	for x0 = minp.x, maxp.x, SLICE do
		local x1 = math.min(x0 + SLICE - 1, maxp.x)
		for _, pos in ipairs(core.find_nodes_in_area({x = x0, y = minp.y, z = minp.z}, {x = x1, y = maxp.y, z = maxp.z}, names)) do
			found[#found + 1] = pos
		end
	end
	return found
end

local function horizontal(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.z - b.z))
end

-- The survey `decide` takes, from what is loaded around the bench. Beds and spots within
-- `radius` (horizontally) and `height`; only beds within `range` (the Builder's site range)
-- count for the civic needs, since a building can only go up that near.
--   opts: {radius, height, range, villagers, food (module or nil with the economy off),
--          common, gap, skip}
function M.survey(core, bench, opts)
	local minp = {x = bench.x - opts.radius, y = bench.y - opts.height, z = bench.z - opts.radius}
	local maxp = {x = bench.x + opts.radius, y = bench.y + opts.height, z = bench.z + opts.radius}
	local common = opts.common
	local names = {BED_GROUP, JUKEBOX, PULPIT, BELL}
	local spread_of = {}
	for building, spread in pairs(M.SPREAD) do
		names[#names + 1] = spread.node
		spread_of[spread.node] = building
	end
	for _, name in ipairs(common.workstation_search_nodes()) do names[#names + 1] = name end
	for level = 1, 7 do names[#names + 1] = "mcl_composters:composter_" .. level end
	names[#names + 1] = "mcl_composters:composter_ready"

	local survey = {
		beds = {}, civic_beds = {}, civic = {tavern = {}, bell = {}, church = {}},
		free_jobs = 0, free_by_profession = {}, spread = {}, bedless = 0, idle = 0, gap = opts.gap, skip = opts.skip,
	}
	for _, pos in ipairs(find(core, minp, maxp, names)) do
		local node = core.get_node_or_nil(pos)
		local name = node and node.name or ""
		if spread_of[name] then
			local list = survey.spread[spread_of[name]] or {}
			survey.spread[spread_of[name]] = list
			list[#list + 1] = pos
		elseif name == JUKEBOX then
			table.insert(survey.civic.tavern, pos)
		elseif name == PULPIT then
			table.insert(survey.civic.church, pos)
		elseif name == BELL then
			table.insert(survey.civic.bell, pos)
		elseif core.get_item_group(name, "bed") > 0 then
			local meta = core.get_meta(pos)
			-- A player's bed is no villager's.
			if name:find("_bottom", 1, true) and meta:get_string("player") == "" then
				local bed = {pos = pos, free = meta:get_string("villager") == ""}
				table.insert(survey.beds, bed)
				if horizontal(pos, bench) <= opts.range then table.insert(survey.civic_beds, bed) end
			end
		elseif name ~= "" then
			local profession = common.workstation_profession(name)
				or (name:find("^mcl_composters:composter") and "farmer")
			if profession and core.get_meta(pos):get_string("villager") == "" then
				survey.free_jobs = survey.free_jobs + 1
				survey.free_by_profession[profession] = (survey.free_by_profession[profession] or 0) + 1
			end
		end
	end

	local food = opts.food
	if food then survey.food = {adults = 0, hungry = 0, starving = 0} end
	for _, villager in ipairs(opts.villagers or {}) do
		if not villager._bed then survey.bedless = survey.bedless + 1 end
		if villager._profession == "unemployed" and not villager._jobsite
			and not villager._villages_keeper and not villager._villages_builder then
			survey.idle = survey.idle + 1
		end
		if food then
			survey.food.adults = survey.food.adults + 1
			local state = food.state(villager)
			if state == "hungry" then survey.food.hungry = survey.food.hungry + 1 end
			if state == "starving" then survey.food.starving = survey.food.starving + 1 end
		end
	end
	return survey
end

return M
