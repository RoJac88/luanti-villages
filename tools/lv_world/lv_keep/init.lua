-- Keeps a persistent test world's village alive with no player on, skips nights, and
-- logs a daily line per villager. Not in the repo: kept in ~/.cache/lv_probe_keep/lv_world.
--
-- Settings (the server's conf):
-- lv_keep_center = x,y,z  the village's middle (default the Markets world's)
-- lv_keep_radius = 72     forceloaded around it
-- lv_keep_skip_nights = true
-- A file named lv_keep.stop in the world folder shuts the server down cleanly (lvw.sh stop).
local core = minetest
local function center()
	local x, y, z = (core.settings:get("lv_keep_center") or ""):match("^%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)")
	if x then return {x = tonumber(x), y = tonumber(y), z = tonumber(z)} end
	return {x = -360, y = 10, z = -305}
end
local CENTER = center()
local RADIUS = tonumber(core.settings:get("lv_keep_radius")) or 72
local LOW, HIGH = 24, 40
local STOP_FILE = core.get_worldpath() .. "/lv_keep.stop"
local RUN_FILE = core.get_worldpath() .. "/lv_keep.run.lua"
local NIGHT_FROM, MORNING = 19200 / 24000, 5400 / 24000

core.register_on_mods_loaded(function()
	local class = mcl_mobs.mob_class
	local original = class.player_in_active_range
	class.player_in_active_range = function(self, ...)
		if self.name == "mobs_mc:villager" then return true end
		return original(self, ...)
	end
end)

core.after(2, function()
	local n = 0
	for bx = math.floor((CENTER.x - RADIUS) / 16), math.floor((CENTER.x + RADIUS) / 16) do
		for by = math.floor((CENTER.y - LOW) / 16), math.floor((CENTER.y + HIGH) / 16) do
			for bz = math.floor((CENTER.z - RADIUS) / 16), math.floor((CENTER.z + RADIUS) / 16) do
				core.forceload_block({x = bx * 16, y = by * 16, z = bz * 16}, true)
				n = n + 1
			end
		end
	end
	core.log("action", "[lv_keep] forceloaded " .. n .. " blocks")
end)

-- Following (2026-11-18): the fixed area above lost two crafters that walked out of it and
-- froze holding their job blocks. Every FOLLOW_SECONDS each loaded villager's mapblock and
-- its neighbours are forceloaded too, and freed once no villager has been near for
-- FOLLOW_KEEP seconds. Each villager's last position is kept in mod storage, so after a
-- restart one that was far away is loaded where it stood.
local storage = core.get_mod_storage()
local FOLLOW_SECONDS, FOLLOW_KEEP, SAVE_SECONDS = 1, 60, 30
local base, followed = {}, {}
local function block_key(bx, by, bz) return bx .. "," .. by .. "," .. bz end
for bx = math.floor((CENTER.x - RADIUS) / 16), math.floor((CENTER.x + RADIUS) / 16) do
	for by = math.floor((CENTER.y - LOW) / 16), math.floor((CENTER.y + HIGH) / 16) do
		for bz = math.floor((CENTER.z - RADIUS) / 16), math.floor((CENTER.z + RADIUS) / 16) do
			base[block_key(bx, by, bz)] = true
		end
	end
end
local function follow_around(pos, now)
	local cx, cy, cz = math.floor(pos.x / 16), math.floor(pos.y / 16), math.floor(pos.z / 16)
	for bx = cx - 1, cx + 1 do
		for by = cy - 1, cy + 1 do
			for bz = cz - 1, cz + 1 do
				local k = block_key(bx, by, bz)
				if not base[k] then
					if not followed[k] then
						core.forceload_block({x = bx * 16, y = by * 16, z = bz * 16}, true)
						followed[k] = {x = bx * 16, y = by * 16, z = bz * 16}
					end
					followed[k].seen = math.max(followed[k].seen or 0, now)
				end
			end
		end
	end
end
local last_save = 0
local function follow_tick()
	local now = core.get_us_time() / 1e6
	local where = {}
	for _, ent in pairs(core.luaentities) do
		if ent.name == "mobs_mc:villager" and ent._id and ent.object then
			local pos = ent.object:get_pos()
			if pos then
				follow_around(pos, now)
				where[ent._id] = vector.round(pos)
			end
		end
	end
	local held = 0
	for k, block in pairs(followed) do
		if now - block.seen > FOLLOW_KEEP then
			core.forceload_free_block({x = block.x, y = block.y, z = block.z}, true)
			followed[k] = nil
		else
			held = held + 1
		end
	end
	if now - last_save >= SAVE_SECONDS then
		last_save = now
		local saved = core.deserialize(storage:get_string("where")) or {}
		for id, pos in pairs(where) do saved[id] = pos end
		storage:set_string("where", core.serialize(saved))
		if held > 0 then core.log("action", "[lv_keep] following: " .. held .. " blocks outside the area") end
	end
	core.after(FOLLOW_SECONDS, follow_tick)
end
core.after(3, function()
	-- Saved positions and seek places stay loaded for 10 minutes, long enough for a villager
	-- there to wake and be followed.
	local now = core.get_us_time() / 1e6 + 600
	local saved = core.deserialize(storage:get_string("where")) or {}
	-- lv_keep_seek = x,y,z;x,y,z  places to load once, to find villagers lost before following.
	for x, y, z in (core.settings:get("lv_keep_seek") or ""):gmatch("(-?%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)") do
		saved["seek " .. x .. "," .. y .. "," .. z] = {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
	end
	local n = 0
	for _, pos in pairs(saved) do
		follow_around(pos, now)
		n = n + 1
	end
	core.log("action", "[lv_keep] following from " .. n .. " saved positions")
	follow_tick()
end)

local lv = core.get_modpath("living_villages")
local possessions = dofile(lv .. "/possessions.lua")
local ledger = dofile(lv .. "/ledger.lua")
local news = dofile(lv .. "/market_news.lua")
local labour = dofile(lv .. "/labour.lua")
local common = dofile(lv .. "/common.lua")
local food = dofile(lv .. "/food.lua")
local stock = dofile(lv .. "/farm_stock.lua")
local pantry = dofile(lv .. "/tavern_pantry.lua")

-- Food flow (2026-11-13): what farmers hold and store, what the pantry holds, and the
-- food anyone else carries, so a day's summary shows where the village's food sits.
local FOODISH = {"farming", "fishing", "mobitems:cooked", "mobitems:beef", "mobitems:porkchop",
	"mobitems:chicken", "mobitems:mutton", "mobitems:rabbit", "bone_meal", "mushroom_stew", "core:apple", "emerald"}
local function foodish(name)
	for _, part in ipairs(FOODISH) do
		if name:find(part, 1, true) then return true end
	end
	return false
end
local function listing(counts)
	local names = {}
	for name, count in pairs(counts) do
		if count > 0 and foodish(name) then names[#names + 1] = name end
	end
	table.sort(names)
	local out = {}
	for _, name in ipairs(names) do out[#out + 1] = counts[name] .. " " .. name:gsub("^[^:]*:", "") end
	return table.concat(out, ", ")
end
local function chest_counts(positions)
	local counts = {}
	for _, pos in ipairs(positions) do
		local inv = core.get_meta(pos):get_inventory()
		for _, stack in ipairs(inv:get_list("main") or {}) do
			if not stack:is_empty() then counts[stack:get_name()] = (counts[stack:get_name()] or 0) + stack:get_count() end
		end
	end
	return counts
end
local function food_flow(list)
	for _, e in ipairs(list) do
		local id = e._id:sub(1, 6)
		local site = e._jobsite
		if e._profession == "farmer" then
			local chest = site and stock.find_chests(site)[1]
			core.log("action", string.format("[lv_keep] food %s farmer pouch[%s] belongings[%s] chest%s[%s]", id,
				listing(e._villages_farm_pouch or {}), listing(e._villages_belongings or {}),
				chest and core.pos_to_string(chest) or "(none)", chest and listing(chest_counts({chest})) or ""))
		elseif e._villages_keeper then
			local chests = site and pantry.chests(site)
			core.log("action", string.format("[lv_keep] food %s keeper pouch[%s] belongings[%s] pantry[%s]", id,
				listing(e._villages_farm_pouch or {}), listing(e._villages_belongings or {}),
				chests and listing(chest_counts(chests)) or "none"))
			local rec = e._villages_dinner
			if rec then
				local turned = 0
				for _ in pairs(rec.turned or {}) do turned = turned + 1 end
				local posted = site and core.get_meta(site):get_string("villages_dinner_price") or ""
				local short = 0
				for _ in pairs(rec.short or {}) do short = short + 1 end
				local costs = {}
				for item, cost in pairs(e._villages_input_cost or e._villages_dish_cost or {}) do
					if type(item) == "string" and item:find(":") then
					costs[#costs + 1] = string.format("%s@%.2f", item:gsub("^.*:", ""), cost)
					end
				end
				table.sort(costs)
				core.log("action", string.format("[lv_keep] dinner %s posted=%s factor=%.2f plate=%s turned=%d out=%s served=%d short=%d demand=%d costs[%s]", id,
					posted, rec.factor or 1, e._villages_plate_cost and string.format("%.2f", e._villages_plate_cost) or "none",
					turned, tostring(rec.out or false), rec.served or 0, short, rec.demand or 0, table.concat(costs, ", ")))
			end
		else
			local held = {}
			for name, count in pairs(e._villages_belongings or {}) do
				if name ~= "mcl_core:emerald" and food.POINTS[name] or name:find("_raw", 1, true) or name:find("mobitems:", 1, true) then
					held[name] = count
				end
			end
			local text = listing(held)
			if text ~= "" then core.log("action", string.format("[lv_keep] food %s %s holds[%s]", id, tostring(e._profession), text)) end
		end
	end
end

local function short(item) return (item:gsub("^[^:]*:", "")) end

local function summary(why)
	local list = {}
	for _, e in pairs(core.luaentities) do
		if e.name == "mobs_mc:villager" and e._id and not e.child then list[#list + 1] = e end
	end
	table.sort(list, function(a, b) return a._id < b._id end)
	local states = {full = 0, fed = 0, hungry = 0, starving = 0}
	for _, e in ipairs(list) do
		local state = food.state(e)
		states[state] = (states[state] or 0) + 1
	end
	core.log("action", string.format("[lv_keep] %s day %d (holiday %s): %d adults; hunger full=%d fed=%d hungry=%d starving=%d",
		why, core.get_day_count(), tostring(common.is_holiday()), #list,
		states.full, states.fed, states.hungry, states.starving))
	if why == "work start" then food_flow(list) end
	-- Who holds the money (ticket 21a): the total, the richest three's share, and each
	-- adult's emeralds and money factor, richest first.
	local purses, total = {}, 0
	for _, e in ipairs(list) do
		local em = possessions.emeralds(e)
		total = total + em
		purses[#purses + 1] = {id = e._id:sub(1, 6), em = em, money = possessions.money and possessions.money(e)}
	end
	table.sort(purses, function(a, b) return a.em > b.em end)
	local top3, parts = 0, {}
	for i, p in ipairs(purses) do
		if i <= 3 then top3 = top3 + p.em end
		parts[#parts + 1] = string.format("%s=%d(l%.2f)", p.id, p.em, ledger.lambda and ledger.lambda(p.money) or 1)
	end
	core.log("action", string.format("[lv_keep] money total=%d top3=%.0f%% %s", total,
		total > 0 and 100 * top3 / total or 0, table.concat(parts, " ")))
	-- Reference prices (ticket 21b): per key, the median factor over the adults who hold
	-- one (the others are at 1), the furthest from 1 first.
	local by_key = {}
	for _, e in ipairs(list) do
		for key, factor in pairs(e._villages_prices or {}) do
			by_key[key] = by_key[key] or {}
			table.insert(by_key[key], factor)
		end
	end
	local rows = {}
	for key, factors in pairs(by_key) do
		while #factors < #list do factors[#factors + 1] = 1 end
		table.sort(factors)
		local median = factors[math.floor((#factors + 1) / 2)]
		rows[#rows + 1] = {key = key, median = median, low = factors[1], high = factors[#factors]}
	end
	table.sort(rows, function(a, b) return math.abs(math.log(a.median)) > math.abs(math.log(b.median)) end)
	local shown = {}
	for i = 1, math.min(16, #rows) do
		local r = rows[i]
		shown[i] = string.format("%s=x%.2f[%.2f-%.2f]", r.key:gsub("^.*:", ""), r.median, r.low, r.high)
	end
	core.log("action", "[lv_keep] prices " .. table.concat(shown, " "))
	for _, e in ipairs(list) do
		local view = possessions.assess(e)
		local spare = {}
		for _, top in ipairs(ledger.top(view.surplus, view.value, 3)) do
			spare[#spare + 1] = top.count .. " " .. short(top.item) .. "@" .. string.format("%.0f", view.value(top.item) or 0)
		end
		local needs = {}
		for _, top in ipairs(ledger.top(view.needs, view.value, 3)) do
			needs[#needs + 1] = top.count .. " " .. short(top.item) .. "@" .. string.format("%.0f", view.value(top.item) or 0)
		end
		local heard = news.heard(e)
		local deal = labour.deal(heard, possessions.emeralds(e))
		local dined = e._villages_dined_day
		core.log("action", string.format("[lv_keep]   %s %s%s food=%.1f(%s) dined=%s em=%d heard=%d spare[%s] needs[%s] labour=%s%s",
			e._id:sub(1, 6), tostring(e._profession), e._villages_keeper and "(keeper)" or "",
			food.points(e), food.state(e), dined and tostring(core.get_day_count() - dined) .. "d ago" or "never",
			possessions.emeralds(e), #heard, table.concat(spare, ", "), table.concat(needs, ", "),
			labour.status(e), deal and string.format(" deal=%d %s %.0f->%.0f", deal.count, short(deal.item), deal.bid, deal.sell_at) or ""))
	end
end

-- Each keeper's whereabouts once a minute (2026-11-13: one carried 20 food for a whole
-- day without stocking the pantry, its walk perhaps stuck).
local function keeper_status()
	for _, e in pairs(core.luaentities) do
		if e.name == "mobs_mc:villager" and e._villages_keeper and e._id then
			local pos = e.object:get_pos()
			local route = e._villages_goto_route
			local target = e._villages_supply_target
			local carried = 0
			for _, count in pairs(e._villages_farm_pouch or {}) do carried = carried + count end
			core.log("action", string.format("[lv_keep] keeper %s at %s stage=%s state=%s order=%s sleeping=%s route=%s target=%s carrying=%d",
				e._id:sub(1, 6), pos and core.pos_to_string(vector.round(pos)) or "?",
				tostring(common.schedule_stage(nil, e)), tostring(e.state), tostring(e.order), tostring(e._villages_sleeping ~= nil),
				route and tostring(route.status) or "none", target and core.pos_to_string(target) or "none", carried))
		end
	end
end
local keeper_timer = 0

-- Who is at the tavern mid-evening (2026-11-13: a pantry of 24 dishes fed 4 to 7 a night
-- while 13 starved), and why the rest are not.
local function tavern_census()
	local day = core.get_day_count()
	local counts = {seated = 0, standing = 0, walking = 0, skipped = 0, other = 0, dined = 0}
	local lines = {}
	for _, e in pairs(core.luaentities) do
		if e.name == "mobs_mc:villager" and e._id and not e.child then
			local where
			if e._villages_seat then where = "seated"
			elseif e._villages_tavern_arrived then where = "standing"
			elseif e._villages_tavern_target then where = "walking"
			elseif e._villages_skip_tavern == day then where = "skipped"
			else where = "other" end
			counts[where] = counts[where] + 1
			if e._villages_dined_day == day then counts.dined = counts.dined + 1 end
			local pos = e.object:get_pos()
			local target = e._villages_tavern_target
			lines[#lines + 1] = string.format("%s %s %s food=%.1f dined=%s stage=%s at=%s dist=%s", e._id:sub(1, 6),
				tostring(e._profession), where, food.points(e), tostring(e._villages_dined_day == day),
				tostring(common.schedule_stage(nil, e)), pos and core.pos_to_string(vector.round(pos)) or "?",
				(pos and target) and string.format("%.0f", vector.distance(pos, target)) or "-")
		end
	end
	core.log("action", string.format("[lv_keep] tavern day %d: seated=%d standing=%d walking=%d skipped=%d other=%d dined=%d",
		day, counts.seated, counts.standing, counts.walking, counts.skipped, counts.other, counts.dined))
	table.sort(lines)
	for _, line in ipairs(lines) do core.log("action", "[lv_keep]   tavern " .. line) end
end
local tavern_logged

-- Who is about the church in the holiday social stage, and at which pulpit (alms reach
-- only those within 12 of the cleric's).
local function church_census()
	local lines, clerics = {}, {}
	for _, e in pairs(core.luaentities) do
		if e.name == "mobs_mc:villager" and e._id and not e.child then
			local pos = e.object:get_pos()
			local social = e._villages_social and e._villages_social.pulpit
			local church = e._villages_church and e._villages_church.pulpit
			if e._profession == "cleric" and not e._villages_alchemist then clerics[#clerics + 1] = pos end
			lines[#lines + 1] = {e = e, pos = pos, social = social, church = church}
		end
	end
	local out = {}
	for _, l in ipairs(lines) do
		local near = "-"
		if l.pos and clerics[1] then near = string.format("%.0f", vector.distance(l.pos, clerics[1])) end
		out[#out + 1] = string.format("%s %s stage=%s at=%s social=%s church=%s to_cleric=%s em=%d", l.e._id:sub(1, 6),
			tostring(l.e._profession), tostring(common.schedule_stage(nil, l.e)),
			l.pos and core.pos_to_string(vector.round(l.pos)) or "?",
			l.social and core.pos_to_string(l.social) or "-", l.church and core.pos_to_string(l.church) or "-", near,
			(l.e._villages_belongings or {})["mcl_core:emerald"] or 0)
	end
	table.sort(out)
	core.log("action", "[lv_keep] church census day " .. core.get_day_count())
	for _, line in ipairs(out) do core.log("action", "[lv_keep]   church " .. line) end
end
local church_logged, church_tod

local last_day, bell_logged
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	keeper_timer = keeper_timer + dtime
	if keeper_timer >= 60 then
		keeper_timer = 0
		keeper_status()
	end
	if timer < 5 then return end
	timer = 0
	local stop = io.open(STOP_FILE, "r")
	if stop then
		stop:close()
		os.remove(STOP_FILE)
		core.log("action", "[lv_keep] stop file found: shutting down")
		core.request_shutdown("Test server stopping", false, 0)
		return
	end
	-- A file named lv_keep.run.lua in the world folder runs once, then is renamed .done.
	local run = io.open(RUN_FILE, "r")
	if run then
		local code = run:read("*a")
		run:close()
		-- Windows will not rename onto an existing file: the old .done goes first.
		os.remove(RUN_FILE .. ".done")
		if not os.rename(RUN_FILE, RUN_FILE .. ".done") then os.remove(RUN_FILE) end
		local fn, err = loadstring(code, "lv_keep.run.lua")
		local ok, result = false, err
		if fn then ok, result = pcall(fn) end
		core.log("action", "[lv_keep] run file: " .. (ok and "ok " or "error ") .. tostring(result))
	end
	local tod = core.get_timeofday()
	if tod >= NIGHT_FROM and core.settings:get_bool("lv_keep_skip_nights", true) then
		core.set_timeofday(MORNING + 0.0001)
		core.log("action", "[lv_keep] skipped the night")
		return
	end
	local day = core.get_day_count()
	if day ~= last_day and tod >= 7100 / 24000 then
		last_day = day
		summary("work start")
	end
	if tod >= 16600 / 24000 and tod < 17500 / 24000 and tavern_logged ~= day then
		tavern_logged = day
		tavern_census()
	end
	if common.is_holiday() and church_logged ~= day then
		for _, e in pairs(core.luaentities) do
			if e.name == "mobs_mc:villager" and e._profession == "cleric" and not e._villages_alchemist
				and common.schedule_stage(nil, e) == "social" then
				church_logged = day
				core.after(8, church_census)
				break
			end
		end
	end
	if common.is_holiday() and tod >= 10700 / 24000 and bell_logged ~= day then
		bell_logged = day
		summary("market")
	end
end)

-- Finds functions in data core.serialize is handed (it warns on them), by path.
local fn_seen = {}
local function fn_scan(value, path, depth, visited)
	if depth > 6 or visited[value] then return end
	visited[value] = true
	for k, v in pairs(value) do
		local p = path .. "." .. tostring(k)
		if type(v) == "function" then
			if not fn_seen[p] then
				fn_seen[p] = true
				core.log("action", "[lv_keep] function in save data: " .. p)
			end
		elseif type(v) == "table" then
			fn_scan(v, p, depth + 1, visited)
		end
	end
end
local original_serialize = core.serialize
core.serialize = function(value, ...)
	if type(value) == "table" then fn_scan(value, tostring(value.name or value._id or "?"):sub(1, 24), 0, {}) end
	return original_serialize(value, ...)
end

-- Beef: what the butcher needs and has heard, and what the leatherworker asks.
local lvmp = core.get_modpath("living_villages")
local lv_possessions = dofile(lvmp .. "/possessions.lua")
local lv_news = dofile(lvmp .. "/market_news.lua")
local lv_asks = dofile(lvmp .. "/asks.lua")
local BEEF = "mcl_mobitems:beef"
local function beef_tick()
	local now = core.get_gametime()
	for _, ent in pairs(core.luaentities) do
		if ent.name == "mobs_mc:villager" and ent._id and not ent.child then
			local id = ent._id:sub(1, 6)
			if ent._profession == "butcher" and not ent._villages_keeper then
				local view = lv_possessions.assess(ent)
				local heard = {}
				for _, e in ipairs(lv_news.heard(ent, now)) do
					if e.item == BEEF then heard[#heard + 1] = string.format("%s %s %d@%.2f", e.who:sub(1, 6), e.kind, e.count or 0, e.price or -1) end
				end
				core.log("action", string.format("[lv_keep] beef butcher %s need=%s value=%.2f urgency=%.2f belief=%.2f em=%d heard[%s]",
					id, tostring(view.needs[BEEF]), view.value(BEEF) or -1, view.urgency(BEEF),
					(ent._villages_prices or {})[BEEF] or 1, lv_possessions.emeralds(ent), table.concat(heard, "; ")))
			elseif ent._profession == "leatherworker" then
				local view = lv_possessions.assess(ent)
				core.log("action", string.format("[lv_keep] beef seller %s spare=%s ask=%.2f askfactor=%.2f belief=%.2f",
					id, tostring(view.surplus[BEEF]), lv_asks.ask(ent, BEEF) or -1, lv_asks.factor(ent, BEEF),
					(ent._villages_prices or {})[BEEF] or 1))
			end
		end
	end
	core.after(120, beef_tick)
end
core.after(30, beef_tick)

-- Flowers foragers pick, within the forced area: is there any lily of the valley?
core.after(60, function()
	local r = math.min(RADIUS, 80)
	for _, flower in ipairs({"mcl_flowers:lily_of_the_valley", "mcl_flowers:poppy", "mcl_flowers:dandelion"}) do
		local found = core.find_nodes_in_area(vector.subtract(CENTER, {x = r, y = 24, z = r}),
			vector.add(CENTER, {x = r, y = 24, z = r}), {flower})
		core.log("action", string.format("[lv_keep] flowers %s: %d within %d", flower, #found, r))
	end
end)
