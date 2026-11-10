-- Jobsite census (#217): after a village is built, let the villagers live a
-- working morning, then record every villager's profession and jobsite and
-- every workstation node's claim. Only runs when lv_probe_census is set.
--
-- lv_probe_news = 1 (economy ticket 5) lets the day run instead of holding the work
-- stage, so villagers meet at the well, the bell and the tavern, and records how far
-- each villager's market news has spread: every 60 s, for each villager, how many of
-- the others have heard something from it (`_villages_market_news`). The record gains
-- `news`: the village's size, the timeline of the best and median reach, and the final
-- reach per villager.
--
-- lv_probe_seed_goods = "<item> <count>" (with lv_probe_news; economy ticket 6) puts that
-- many of the item in every other adult's belongings at the first step, so a new village
-- has something to trade before it has made anything; trades show as `trade:` log lines.
--
-- lv_probe_skip_days = N (with lv_probe_news) starts at least N days later, and then
-- skips on while the day is a holiday with no work stage (living_villages' common.lua;
-- holidays follow the moon, and the probe's first day often is one). Each skip sets the
-- time to night, then back to the morning: a new day (get_day_count) whose work stage no
-- villager saw the start of from the wrong side.
--
-- lv_probe_skip_nights = true (with lv_probe_news) skips the night once every villager is
-- asleep (the keeper last, at 19000): from NIGHT_FROM it sets the time to MORNING, just
-- before the putter stage, a new day as midnight would be. Game time (get_gametime) runs
-- on, so the economic clock, hunger and crop growth count no skipped hours: a run sees
-- more days per real minute, and less eaten and grown per day.
--
-- lv_probe_nitwits = N (with lv_probe_news; economy ticket 7) makes N unemployed adults
-- nitwits at the first step. A new village's unemployed soon all find jobsites, and
-- nitwits never do, so labour.lua has someone to drive.
--
-- With lv_probe_news (economy ticket 11b), at the first step of each game day the census
-- logs where the village's emeralds sit (`[lv_probe] emeralds day N: ...`) and keeps it in
-- the record's `emeralds` list: each adult's own (profession and count), what villagers
-- carry in their work pouches (a keeper's purse on its way to buy food), and the chests'
-- by kind: stashes (claimed by a villager), the pantry (within 6 of a jukebox), farms' (beside
-- a composter, where the keeper pays farmers), the Builder's (within 32 of a bench),
-- fishermen's barrels and any other.
local core = minetest

local census = {}
-- lv_probe_skip_nights: the sleep stage, keeper included, and the morning it skips to.
local NIGHT_FROM, NIGHT_TO, MORNING = 19200 / 24000, 5300 / 24000, 5400 / 24000
local wells = dofile(core.get_modpath("lv_probe") .. "/wells.lua")

local STATIONS = {
	"mcl_composters:composter", "mcl_barrels:barrel_closed", "mcl_fletching_table:fletching_table",
	"mcl_loom:loom", "mcl_lectern:lectern", "mcl_cartography_table:cartography_table",
	"mcl_blast_furnace:blast_furnace", "mcl_blast_furnace:blast_furnace_active",
	"mcl_smoker:smoker", "mcl_smoker:smoker_active", "mcl_grindstone:grindstone",
	"mcl_smithing_table:table", "mcl_brewing:stand_000", "mcl_stonecutter:stonecutter",
	"living_villages:pulpit", "group:cauldron",
}

local function news_mode()
	return core.settings:get_bool("lv_probe_news", false)
end

-- For each villager id, how many other villagers have heard news from it.
local function news_reach(entities)
	local reach = {}
	for _, e in ipairs(entities) do reach[e._id] = 0 end
	for _, e in ipairs(entities) do
		local from = {}
		for _, entry in ipairs(e._villages_market_news or {}) do from[entry.who] = true end
		for who in pairs(from) do
			if reach[who] then reach[who] = reach[who] + 1 end
		end
	end
	return reach
end

local function reach_summary(reach)
	local values = {}
	for _, n in pairs(reach) do values[#values + 1] = n end
	table.sort(values)
	if #values == 0 then return 0, 0 end
	return values[#values], values[math.floor((#values + 1) / 2)]
end

local EMERALD = "mcl_core:emerald"
local CHESTS = {"mcl_chests:chest", "mcl_chests:chest_small", "mcl_chests:chest_left", "mcl_chests:chest_right"}
local BARRELS = {"mcl_barrels:barrel_closed", "mcl_barrels:barrel_open"}

local function emeralds_in(pos)
	local total = 0
	for _, stack in ipairs(core.get_meta(pos):get_inventory():get_list("main") or {}) do
		if stack:get_name() == EMERALD then total = total + stack:get_count() end
	end
	return total
end

-- Where the village's emeralds are: adults' belongings, and chests by kind.
local function emerald_snapshot(entities, minp, maxp)
	local villagers, held, pouches = {}, 0, 0
	for _, e in ipairs(entities) do
		local n = e._villages_belongings and e._villages_belongings[EMERALD] or 0
		villagers[#villagers + 1] = {id = e._id:sub(1, 6), profession = e._profession, emeralds = n}
		held = held + n
		pouches = pouches + (e._villages_farm_pouch and e._villages_farm_pouch[EMERALD] or 0)
	end
	table.sort(villagers, function(a, b) return a.emeralds > b.emeralds or (a.emeralds == b.emeralds and a.id < b.id) end)
	local jukeboxes = core.find_nodes_in_area(minp, maxp, {"mcl_jukebox:jukebox"})
	local benches = core.find_nodes_in_area(minp, maxp, {"living_villages:builder_block"})
	local composter_names = {"mcl_composters:composter", "mcl_composters:composter_ready"}
	for level = 1, 7 do composter_names[#composter_names + 1] = "mcl_composters:composter_" .. level end
	local composters = core.find_nodes_in_area(minp, maxp, composter_names)
	local function near(p, list, r)
		for _, q in ipairs(list) do
			if math.abs(p.x - q.x) <= r and math.abs(p.z - q.z) <= r and math.abs(p.y - q.y) <= 4 then return true end
		end
		return false
	end
	local chests = {stash = 0, pantry = 0, farm = 0, bench = 0, barrel = 0, other = 0}
	for _, p in ipairs(core.find_nodes_in_area(minp, maxp, BARRELS)) do chests.barrel = chests.barrel + emeralds_in(p) end
	for _, p in ipairs(core.find_nodes_in_area(minp, maxp, CHESTS)) do
		local n = emeralds_in(p)
		if n > 0 then
			local kind = core.get_meta(p):get_string("villages_owner") ~= "" and "stash"
				or near(p, jukeboxes, 6) and "pantry" or near(p, composters, 1) and "farm"
				or near(p, benches, 32) and "bench" or "other"
			chests[kind] = chests[kind] + n
		end
	end
	return {day = core.get_day_count(), held = held, pouches = pouches, villagers = villagers, chests = chests}
end

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end
local function vec(p) return {x = round1(p.x), y = round1(p.y), z = round1(p.z)} end

function census.enabled()
	return (tonumber(core.settings:get("lv_probe_census")) or 0) > 0
end

core.register_on_mods_loaded(function()
	if not census.enabled() then return end
	local class = mcl_mobs.mob_class
	local original = class.player_in_active_range
	class.player_in_active_range = function(self, ...)
		if self.name == "mobs_mc:villager" then return true end
		return original(self, ...)
	end
end)

local cells
local function load_cells()
	if not cells and core.get_modpath("living_villages") then
		cells = dofile(core.get_modpath("living_villages") .. "/cells.lua")
	end
	return cells
end

-- Whether a position lies inside the village's area (the query below is a sphere).
local function inside(p, minp, maxp)
	return p.x >= minp.x and p.x <= maxp.x and p.y >= minp.y and p.y <= maxp.y and p.z >= minp.z and p.z <= maxp.z
end

-- Steps every 10 s (so a timeline time is a multiple of 10). Writes one record through emit after the census seconds, then calls done().
function census.run(area, emit, done)
	local seconds = tonumber(core.settings:get("lv_probe_census")) or 0
	local minp = {x = area.x1, y = area.y1, z = area.z1}
	local maxp = {x = area.x2, y = area.y2, z = area.z2}
	local center = {x = (minp.x + maxp.x) / 2, y = (minp.y + maxp.y) / 2, z = (minp.z + maxp.z) / 2}
	local radius = math.max(maxp.x - minp.x, maxp.z - minp.z, maxp.y - minp.y)
	load_cells()
	-- lv_probe_census_putter (#11): hold the morning Putter stage this many seconds, then work time.
	local putter = tonumber(core.settings:get("lv_probe_census_putter")) or 0
	local finish_watch = putter > 0 and wells.available() and wells.watch(minp, maxp) or nil
	local waited = 0
	local timeline, last = {}, {}
	local news_timeline = {}
	local money, money_day = {}, nil
	local skipping, skipped = nil, 0
	local nights = 0
	local schedule = core.get_modpath("living_villages")
		and dofile(core.get_modpath("living_villages") .. "/common.lua") or nil
	local function adults()
		local found = {}
		for _, object in ipairs(core.get_objects_inside_radius(center, radius)) do
			local e = object:get_luaentity()
			if e and e.name == "mobs_mc:villager" and e._id and not e.child and inside(object:get_pos(), minp, maxp) then
				found[#found + 1] = e
			end
		end
		return found
	end
	local function tick()
		-- Setting the time back counts as a new day (get_day_count), which would give every
		-- villager a fresh roll each tick, so a putter census stops the clock instead.
		local wanted = waited < putter and (tonumber(core.settings:get("lv_probe_tod")) or 0.24) or 0.33
		if news_mode() then
			local skip = tonumber(core.settings:get("lv_probe_skip_days")) or 0
			if skipping == nil then skipping = skip > 0 end
			if skipping then
				local workday = schedule and schedule.schedule_stage(0.4) == "work"
				if skipped >= skip and (workday or skipped >= 8) then
					skipping = false
					core.log("action", "[lv_probe] census starts on day " .. core.get_day_count()
						.. " after skipping " .. skipped)
				else
					skipped = skipped + 1
					core.set_timeofday(0.9)
					core.after(1, function() core.set_timeofday(0.24) end)
				end
			end
			if waited == 0 and skip == 0 then core.set_timeofday(0.24) end
			if not skipping and core.settings:get_bool("lv_probe_skip_nights", false) then
				local tod = core.get_timeofday()
				if tod >= NIGHT_FROM or tod < NIGHT_TO then
					core.set_timeofday(MORNING)
					nights = nights + 1
					core.log("action", string.format("[lv_probe] skipped the night to day %d (%d skipped)",
						core.get_day_count(), nights))
				end
			end
		elseif putter > 0 then
			core.settings:set("time_speed", "0")
			if waited == 0 or waited == putter then core.set_timeofday(wanted) end
		else
			core.set_timeofday(wanted)
		end
		waited = waited + 10
		local seed = core.settings:get("lv_probe_seed_goods") or ""
		local nitwits = tonumber(core.settings:get("lv_probe_nitwits")) or 0
		if news_mode() and waited == 10 and nitwits > 0 then
			for _, e in ipairs(adults()) do
				if nitwits > 0 and e._profession == "unemployed" then
					e._profession = "nitwit"
					nitwits = nitwits - 1
					core.log("action", "[lv_probe] made villager " .. e._id:sub(1, 6) .. " a nitwit")
				end
			end
		end
		if news_mode() and waited == 10 and seed ~= "" then
			local item, count = seed:match("^(%S+)%s+(%d+)$")
			for i, e in ipairs(adults()) do
				if item and i % 2 == 1 then
					e._villages_belongings = e._villages_belongings or {}
					e._villages_belongings[item] = (e._villages_belongings[item] or 0) + tonumber(count)
					core.log("action", "[lv_probe] seeded " .. seed .. " on villager " .. e._id:sub(1, 6))
				end
			end
		end
		if news_mode() and waited % 60 == 0 then
			local best, median = reach_summary(news_reach(adults()))
			news_timeline[#news_timeline + 1] = {t = waited, day = core.get_day_count(),
				tod = math.floor(core.get_timeofday() * 100 + 0.5) / 100, best = best, median = median}
		end
		if news_mode() and not skipping and core.get_day_count() ~= money_day then
			money_day = core.get_day_count()
			local snap = emerald_snapshot(adults(), minp, maxp)
			money[#money + 1] = snap
			local top = {}
			for i = 1, math.min(#snap.villagers, 5) do
				local v = snap.villagers[i]
				top[#top + 1] = string.format("%s %s=%d", tostring(v.profession), v.id, v.emeralds)
			end
			core.log("action", string.format("[lv_probe] emeralds day %d: villagers %d (%s), pouches %d, stashes %d, pantry %d, farms %d, bench %d, barrels %d, other %d",
				snap.day, snap.held, table.concat(top, ", "), snap.pouches, snap.chests.stash, snap.chests.pantry,
				snap.chests.farm, snap.chests.bench, snap.chests.barrel, snap.chests.other))
		end
		-- What each villager held at each step, so a change shows when it happened.
		for _, object in ipairs(core.get_objects_inside_radius(center, radius)) do
			local e = object:get_luaentity()
			if e and e.name == "mobs_mc:villager" and e._id and inside(object:get_pos(), minp, maxp) then
				local key = tostring(e._profession) .. "@" .. (e._jobsite and core.pos_to_string(e._jobsite) or "-")
				if last[e._id] ~= key then
					last[e._id] = key
					timeline[#timeline + 1] = {t = waited, id = e._id:sub(1, 6), what = key,
						pos = core.pos_to_string(vector.round(object:get_pos())),
						bed = e._bed and core.pos_to_string(e._bed) or "-"}
				end
			end
		end
		if waited < seconds then return core.after(10, tick) end
		local villagers, by_id = {}, {}
		for _, object in ipairs(core.get_objects_inside_radius(center, radius)) do
			local e = object:get_luaentity()
			if e and e.name == "mobs_mc:villager" and e._id and inside(object:get_pos(), minp, maxp) then
				local route = e._villages_job_search_route
				local v = {
					id = e._id, profession = e._profession, child = e.child or nil,
					jobsite = e._jobsite and vec(e._jobsite) or nil, bed = e._bed and vec(e._bed) or nil,
					pos = vec(object:get_pos()), state = e.state, order = e.order,
					job_route = route and (tostring(route.status) .. "/" .. tostring(route.reason)) or nil,
				}
				villagers[#villagers + 1] = v
				by_id[e._id] = v
			end
		end
		local stations = {}
		for _, p in ipairs(core.find_nodes_in_area(minp, maxp, STATIONS)) do
			local claim = core.get_meta(p):get_string("villager")
			-- navigation.lua's cardinal approach cells (approaches(site, true)).
			local approach, standable = 0, 0
			if cells then
				for _, o in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
					local c = {x = p.x + o[1], y = p.y, z = p.z + o[2]}
					if cells.is_open(c, {thin = true}) and cells.is_open({x = c.x, y = c.y + 1, z = c.z})
						and cells.has_floor(c) then
						approach = approach + 1
						if cells.can_stand(c) then standable = standable + 1 end
					end
				end
			end
			stations[#stations + 1] = {
				name = core.get_node(p).name, pos = vec(p), approach = approach, standable = standable, claim = claim ~= "" and claim or nil,
				claimant = claim ~= "" and by_id[claim] and by_id[claim].profession or nil,
			}
		end
		local news
		if news_mode() then
			local everyone = adults()
			local reach = news_reach(everyone)
			local final = {}
			for id, n in pairs(reach) do final[id:sub(1, 6)] = n end
			news = {adults = #everyone, timeline = news_timeline, reach = final}
			money[#money + 1] = emerald_snapshot(everyone, minp, maxp)
		end
		emit({type = "census", seconds = seconds, villagers = villagers, stations = stations, timeline = timeline,
			wells = finish_watch and finish_watch() or nil, news = news, emeralds = news and money or nil})
		done()
	end
	core.after(10, tick)
end

return census
