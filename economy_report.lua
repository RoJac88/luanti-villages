-- What a Builder's bench says about its village's economy (docs/villager-economy-design.md,
-- What the player sees, Visibility; ticket 10): the Economy tab (builder_bench_menu.lua)
-- and the census weight (village_census.lua, through builder.lua).
--
-- Two kinds of knowledge, kept apart and labelled so in the tab:
-- * Heard: the bench Builder's market news (market_news.lua), its own and what it was
--   told. Shortages are its "needs" entries and gluts its "has" entries, summed by item:
--   how many villagers, how many items, and their worth (count times price) to them.
-- * Seen: the loaded adult villagers within a radius of the bench: the professions
--   present (the keeper and the Builder, a mason by vanilla's reckoning, by their roles), nitwits and the unemployed with their labour activity today (labour.lua),
--   and what they made and used today and yesterday (economy_tally.lua).
--
-- A gap is a profession that would make what the village is short of, with none of
-- that item's producers (ledger.producers) present. Its score is the shortages' worth
-- it would answer, and the worst gap scores most. Only vanilla professions count: a
-- labour activity or the keeper needs no building. BUILDINGS lists the stock buildings
-- holding each profession's jobsite (VoxeLibre 0.92.3's mcl_villages schematics, the
-- lectern library_schematic.lua adds, and village_buildings.lua's own); no stock building holds a weapon smith's, tool
-- smith's or mason's. The census counts a building holding the worst gap's jobsite
-- double.
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local tally = dofile(core.get_modpath("living_villages") .. "/economy_tally.lua")

local VILLAGER = "mobs_mc:villager"
local IDLE = {nitwit = true, unemployed = true}
local NOT_PROFESSIONS = {keeper = true, builder = true, nitwit = true, unemployed = true}

local BUILDINGS = {
	farm = {"farmer"},
	-- village_buildings.lua's greenhouse takes the farm's place. Its tavern has no
	-- fisherman's barrel; with it off, the stock tavern's barrel is behind a fence no
	-- villager gets past (tests/support/stock_buildings_known.lua), so neither counts.
	greenhouse = {"farmer"},
	fisherman_hut = {"fisherman"},
	medium_house = {"fisherman", "fletcher"},
	small_house = {"shepherd"},
	large_house = {"cartographer"},
	blacksmith = {"armorer"},
	library = {"librarian", "leatherworker"},
	butcher = {"butcher"},
	church = {"cleric"},
}

local M = {BUILDINGS = BUILDINGS}

local function sorted_by_worth(list)
	table.sort(list, function(a, b)
		if a.worth ~= b.worth then return a.worth > b.worth end
		return a.item < b.item
	end)
	return list
end

-- Heard entries of one kind, summed by item: {item, count, villagers, worth}, worthiest first.
local function summed(heard, kind)
	local by_item, list = {}, {}
	for _, entry in ipairs(heard) do
		if entry.kind == kind then
			local row = by_item[entry.item]
			if not row then
				row = {item = entry.item, count = 0, villagers = 0, worth = 0, seen = {}}
				by_item[entry.item] = row
				list[#list + 1] = row
			end
			row.count = row.count + (entry.count or 0)
			row.worth = row.worth + (entry.count or 0) * (entry.price or 0)
			if not row.seen[entry.who] then
				row.seen[entry.who] = true
				row.villagers = row.villagers + 1
			end
		end
	end
	for _, row in ipairs(list) do row.seen = nil end
	return sorted_by_worth(list)
end

function M.shortages(heard) return summed(heard, "needs") end
function M.gluts(heard) return summed(heard, "has") end

-- Professions present: name -> count.
function M.present(villagers)
	local present = {}
	for _, villager in ipairs(villagers) do
		local name = (villager._villages_keeper and "keeper") or (villager._villages_builder and "builder")
			or villager._profession
		if name then present[name] = (present[name] or 0) + 1 end
	end
	return present
end

-- {profession, score, items = {item...}}, worst first.
function M.gaps(shortages, present)
	local by_name, list = {}, {}
	for _, row in ipairs(shortages) do
		local producers = ledger.producers(row.item)
		local supplied = false
		for _, name in ipairs(producers) do
			if present[name] then supplied = true end
		end
		if not supplied then
			for _, name in ipairs(producers) do
				if not NOT_PROFESSIONS[name] then
					local gap = by_name[name]
					if not gap then
						gap = {profession = name, score = 0, items = {}}
						by_name[name] = gap
						list[#list + 1] = gap
					end
					gap.score = gap.score + row.worth
					gap.items[#gap.items + 1] = row.item
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.profession < b.profession
	end)
	return list
end

-- The stock buildings that hold a profession's jobsite, as a set, or nil.
function M.buildings_for(profession)
	local found
	for building, professions in pairs(BUILDINGS) do
		for _, name in ipairs(professions) do
			if name == profession then
				found = found or {}
				found[building] = true
			end
		end
	end
	return found
end

-- The buildings the census counts double for these gaps: those holding the worst gap's
-- jobsite, or nil.
function M.favoured(gaps)
	return gaps[1] and M.buildings_for(gaps[1].profession) or nil
end

-- Loaded adult villagers within radius of pos.
function M.around(pos, radius)
	local found = {}
	for _, object in ipairs(core.get_objects_inside_radius(pos, radius)) do
		local entity = object:get_luaentity()
		if entity and entity.name == VILLAGER and not entity.child and entity._id then found[#found + 1] = entity end
	end
	return found
end

local function add_into(into, list)
	for item, count in pairs(list or {}) do into[item] = (into[item] or 0) + count end
end

local function as_rows(counts)
	local rows = {}
	for item, count in pairs(counts) do rows[#rows + 1] = {item = item, count = count} end
	table.sort(rows, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.item < b.item
	end)
	return rows
end

-- What the villagers made and used on `day`: {made = rows, used = rows}, each row
-- {item, count}, most first.
function M.goods(villagers, day)
	local made, used = {}, {}
	for _, villager in ipairs(villagers) do
		local m, u = tally.on(villager, day)
		add_into(made, m)
		add_into(used, u)
	end
	return {made = as_rows(made), used = as_rows(used)}
end

-- Nitwits and the unemployed: {id, profession, activity}; activity is today's labour, or
-- nil when it has none.
function M.idle(villagers, day)
	local list = {}
	for _, villager in ipairs(villagers) do
		if IDLE[villager._profession] and not villager._jobsite and not villager._villages_keeper then
			local labour = villager._villages_labour
			list[#list + 1] = {
				id = villager._id, profession = villager._profession,
				activity = labour and labour.day == day and labour.activity or nil,
			}
		end
	end
	table.sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
	return list
end

-- The whole report. `heard` is the bench Builder's news (own and hearsay), or nil when
-- no Builder is near; `villagers` those around the bench.
function M.build(heard, villagers, day)
	local present = M.present(villagers)
	local report = {
		heard = heard ~= nil,
		present = present,
		idle = M.idle(villagers, day),
		today = M.goods(villagers, day),
		yesterday = M.goods(villagers, day - 1),
	}
	if heard then
		report.shortages = M.shortages(heard)
		report.gluts = M.gluts(heard)
		report.gaps = M.gaps(report.shortages, present)
	end
	return report
end

return M
