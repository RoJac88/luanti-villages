-- Run with: lua tests/pulpit_menu.lua
-- The parish register on the pulpit (ticket 48a): the report, the page and its right-click.
local day, time, economy = 10, 0.3, true
local objects, metas, shown, closed = {}, {}, {}, 0
local node_there, player_pos = true, {x = 0, y = 0, z = 3}
local overrides, receive, leave
local stored, serialized = {}, {}
local lbm, timers = nil, {}
minetest = {
	register_lbm = function(def) lbm = def end,
	get_node_timer = function(pos)
		local key = pos.x .. "," .. pos.y .. "," .. pos.z
		return {
			is_started = function() return timers[key] ~= nil end,
			start = function(_, seconds) timers[key] = seconds end,
		}
	end,
	get_mod_storage = function()
		return {
			get_string = function(_, k) return stored[k] or "" end,
			set_string = function(_, k, v) stored[k] = v end,
		}
	end,
	serialize = function(value)
		serialized[#serialized + 1] = value
		return "s" .. #serialized
	end,
	deserialize = function(text) return serialized[tonumber((text or ""):match("^s(%d+)$") or 0)] end,
	get_modpath = function() return "." end,
	get_gametime = function() return 0 end,
	get_day_count = function() return day end,
	get_timeofday = function() return time end,
	settings = {
		get = function() return nil end,
		get_bool = function(_, name, default)
			if name == "living_villages_economy" then return economy end
			return default
		end,
	},
	log = function() end,
	get_objects_inside_radius = function() return objects end,
	get_meta = function(pos)
		local key = pos.x .. "," .. pos.y .. "," .. pos.z
		metas[key] = metas[key] or {}
		local fields = metas[key]
		return {
			get_string = function(_, k) return fields[k] or "" end,
			set_string = function(_, k, v) fields[k] = v end,
		}
	end,
	formspec_escape = function(text) return (text:gsub("[,;%[%]\\]", "\\%0")) end,
	colorize = function(_, text) return text end,
	get_translator = function()
		return function(message, ...)
			local args = {...}
			return (message:gsub("@(%d)", function(i) return args[tonumber(i)] end))
		end
	end,
	registered_nodes = {["living_villages:pulpit"] = {}},
	get_node_or_nil = function() return node_there and {name = "living_villages:pulpit"} or nil end,
	show_formspec = function(name, form, text) shown[#shown + 1] = {name = name, form = form, text = text} end,
	close_formspec = function() closed = closed + 1 end,
	override_item = function(name, fields) overrides = {name = name, fields = fields} end,
	register_on_player_receive_fields = function(fn) receive = fn end,
	register_on_leaveplayer = function(fn) leave = fn end,
}
vector = {
	new = function(p) return {x = p.x, y = p.y, z = p.z} end,
	distance = function(a, b)
		local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end,
}

local parish = dofile("parish_report.lua")
local menu = dofile("pulpit_menu.lua")
local tally = dofile("economy_tally.lua")
local deaths = dofile("parish_deaths.lua")
local register = dofile("parish_register.lua")

local function villager(fields)
	fields.name = fields.name or "mobs_mc:villager"
	return fields
end
local function as_objects(list)
	local out = {}
	for i, entity in ipairs(list) do out[i] = {get_luaentity = function() return entity end} end
	return out
end

-- Counted for five stars: every profession but the fisherman.
do
	assert(#parish.COUNTED == 12)
	local counted = {}
	for _, name in ipairs(parish.COUNTED) do counted[name] = true end
	assert(not counted.fisherman and counted.tool_smith and counted.weapon_smith and counted.mason)
	local all = {}
	for _, name in ipairs(parish.COUNTED) do all[name] = 1 end
	assert(#parish.missing(all) == 0)
	all.mason = nil
	local missing = parish.missing(all)
	assert(#missing == 1 and missing[1] == "mason")
	assert(#parish.missing({fisherman = 3}) == 12, "the fisherman counts for nothing")
end

-- Trades in order: counted, the fisherman, the roles; no nitwits or unemployed.
do
	local list = parish.trades({keeper = 1, farmer = 2, fisherman = 1, nitwit = 3, unemployed = 1, cleric = 1})
	local names = {}
	for i, entry in ipairs(list) do names[i] = entry.name .. entry.count end
	assert(table.concat(names, " ") == "farmer2 cleric1 fisherman1 keeper1", table.concat(names, " "))
end

-- The report: roles by role (a Builder is no mason, an alchemist no cleric), idle hands,
-- food states.
do
	local adults = {
		villager({_id = "a", _profession = "farmer", _jobsite = {}}),
		villager({_id = "b", _profession = "mason", _villages_builder = true}),
		villager({_id = "c", _profession = "cleric", _villages_alchemist = true}),
		villager({_id = "d", _profession = "nitwit", _villages_labour = {day = 10, activity = "gather"}}),
		villager({_id = "e", _profession = "unemployed"}),
	}
	local states = {a = "full", b = "fed", c = "full", d = "hungry", e = "starving"}
	local report = parish.build(adults, {{}, {}}, {
		day = 10, weekday = 3, weekday_name = "Forgeday",
		state = function(v) return states[v._id] end, economy = true,
	})
	assert(report.adults == 5 and report.children == 2)
	assert(report.idle == 2 and report.labouring == 1)
	assert(report.food.full == 2 and report.food.fed == 1 and report.food.hungry == 1 and report.food.starving == 1)
	local missing = table.concat(report.missing, " ")
	assert(missing:find("mason") and missing:find("cleric") and not missing:find("farmer"), missing)
	assert(#report.missing == 11)
end

-- Trade volume (ticket 48b): what villagers paid one another, today and yesterday.
do
	local a, b = {}, {}
	tally.paid(a, 5, 9)
	tally.paid(a, 7, 10)
	tally.paid(b, 3, 10)
	tally.paid(b, 0, 10)
	tally.paid(b, nil, 10)
	tally.money(b, "premium_in", 100, 10)
	assert(parish.paid({a, b}, 10) == 10 and parish.paid({a, b}, 9) == 5, "only `paid` counts")
	local report = parish.build({a, b}, {}, {day = 10, weekday = 1, weekday_name = "Sunday",
		state = function() return "fed" end, economy = true})
	assert(report.paid_today == 10 and report.paid_yesterday == 5)
end

-- How a villager died, in words.
do
	local zombie = {get_luaentity = function() return {name = "mobs_mc:zombie"} end, is_player = function() return false end}
	local player = {is_player = function() return true end, get_player_name = function() return "sam" end}
	assert(deaths.cause({type = "punch", puncher = zombie}) == "was killed by a zombie")
	assert(deaths.cause({type = "punch", puncher = player}) == "was killed by sam")
	assert(deaths.cause({type = "fall"}) == "died in a fall")
	assert(deaths.cause({type = "environment", node = "mcl_core:water_source"}) == "drowned")
	assert(deaths.cause({type = "environment", node = "mcl_core:lava_flowing"}) == "burned to death")
	assert(deaths.cause({type = "environment", node = "mcl_core:acaciatree"}) == "suffocated in acaciatree")
	assert(deaths.cause({type = "fire"}) == "burned to death")
	assert(deaths.cause({type = "unknown"}) == "died")
	assert(deaths.cause({type = "unknown"}, true) == "starved")
	assert(deaths.cause({type = "fall"}, true) == "died in a fall, starving")
	assert(deaths.cause(nil) == "died")
	assert(parish.trade_of({child = true, _profession = "farmer"}) == "child")
	assert(parish.trade_of({_profession = "mason", _villages_builder = true}) == "builder")
	assert(parish.trade_of({_profession = "cleric"}) == "cleric")
end

-- The latest death within a radius; the list keeps KEEP, newest last.
do
	assert(deaths.latest({x = 0, y = 0, z = 0}, 128) == nil)
	deaths.note({pos = {x = 10.4, y = 0, z = 0}, day = 5, id = "farmer1234", trade = "farmer", cause = "drowned"})
	deaths.note({pos = {x = 500, y = 0, z = 0}, day = 6, id = "far", trade = "mason", cause = "died"})
	local latest = deaths.latest({x = 0, y = 0, z = 0}, 128)
	assert(latest.id == "farmer1234" and latest.pos.x == 10 and latest.day == 5, "the far one is another village's")
	assert(deaths.latest({x = 490, y = 0, z = 0}, 128).id == "far")
	deaths.note({pos = {x = 20, y = 0, z = 0}, day = 7, id = "kid", trade = "child", cause = "died in a fall"})
	assert(deaths.latest({x = 0, y = 0, z = 0}, 128).id == "kid", "the newest first")
	for i = 1, deaths.KEEP + 3 do deaths.note({pos = {x = 900, y = 0, z = 0}, day = 8, id = "n" .. i}) end
	assert(deaths.latest({x = 0, y = 0, z = 0}, 128) == nil, "the oldest are dropped past KEEP")
	stored[deaths.KEY] = nil
end

-- The register (ticket 48c): a day noted once, the last KEEP kept, averages over the days
-- noted, trends from four.
do
	local list = {}
	assert(register.due(list, 10))
	local report = {adults = 10, children = 2, food = {starving = 1, hungry = 2}, paid_yesterday = 40,
		diners = 6, church = {fund = 90}}
	list = register.push(list, register.entry(report, 10))
	assert(#list == 1 and list[1].day == 9 and list[1].paid == 40 and list[1].starving == 1 and list[1].fund == 90)
	assert(not register.due(list, 10), "noted for the day that ended")
	assert(register.due(list, 11))
	report.paid_yesterday = 44
	list = register.push(list, register.entry(report, 10))
	assert(#list == 1 and list[1].paid == 44, "a day noted again is replaced")
	for d = 11, 20 do
		report.paid_yesterday = d * 10
		list = register.push(list, register.entry(report, d))
	end
	assert(#list == register.KEEP and list[1].day == 13 and list[#list].day == 19)
	assert(register.average(list, "paid") == 170 and select(2, register.average(list, "paid")) == 7)
	assert(register.trend(list, "paid") == "rising")
	assert(register.trend({{paid = 50}, {paid = 50}, {paid = 30}, {paid = 30}}, "paid") == "falling")
	assert(register.trend({{paid = 50}, {paid = 52}, {paid = 49}, {paid = 51}}, "paid") == "steady")
	assert(register.trend({{paid = 0}, {paid = 0}, {paid = 0}, {paid = 0}}, "paid") == "steady")
	assert(register.trend({{paid = 1}, {paid = 2}, {paid = 3}}, "paid") == nil, "too few days")
	assert(register.average({}, "paid") == nil)
	-- Gaps: averages count the days noted.
	local gappy = {{day = 1, paid = 10, adults = 8, children = 0}, {day = 5, paid = 30, adults = 9, children = 1}}
	assert(register.average(gappy, "paid") == 20 and register.span(gappy) == 5)
	local growth, days = register.growth(gappy, 9, 2, 6)
	assert(growth == 3 and days == 5)
	assert(register.growth({}, 1, 1, 1) == nil)
	local summary = register.summary(gappy, {adults = 7, children = 0, day = 6})
	assert(summary.paid_avg == 20 and summary.paid_days == 2 and summary.growth == -1 and summary.last_day == 5)
end

-- The page.
local function page(report)
	return menu.formspec(report)
end
do
	local base = {
		day = 1093, weekday = 1, weekday_name = "Sunday", adults = 3, children = 1,
		trades = {{name = "farmer", count = 2}, {name = "tool_smith", count = 1}},
		missing = {"weapon_smith", "mason"}, idle = 1, labouring = 0,
		food = {full = 1, fed = 1, hungry = 0, starving = 1}, economy = true,
		church = {claimed = true, here = true, fund = 40, target = 120},
		paid_today = 34, paid_yesterday = 120,
		death = {id = "84ebb7aa", trade = "tool_smith", cause = "drowned", day = 1090},
		keepers = 1, diners = 12, dinner_price = 3,
		register = {paid_avg = 85.4, paid_days = 7, paid_trend = "rising", growth = 2, growth_days = 6},
	}
	local text = page(base)
	assert(text:find("Latest death: The tool smith 84ebb7 drowned\\, day 1090", 1, true), text)
	assert(text:find("Paid between villagers: 34 emeralds today\\, 120 yesterday", 1, true))
	assert(text:find("Average 85 a day over 7 days\\, rising", 1, true), text)
	assert(text:find("Over 6 days: +2", 1, true))
	assert(text:find("Tavern: 12 meals last evening\\, dinner 3 emeralds", 1, true))
	-- The stars and the sermon (ticket 48d): one starving caps at four, and the sermon says so.
	local _, lit = text:gsub("image%[[^%]]*mcl_mobitems_nether_star.png%]", "")
	local _, dark = text:gsub("nether_star%.png%^\\%[colorize", "")
	local stars = tonumber(text:match("(%d) of 5 stars"))
	assert(stars and stars <= 4 and lit == stars and dark == 5 - stars, text)
	assert(text:find("The cleric preaches: \"", 1, true) and text:find("one of ", 1, true), text)
	assert(text:find("One starving: at most four stars.", 1, true))
	assert(text:find("Fed: 67%", 1, true), "each part's score")
	assert(text:find("Sunday\\, day 1093", 1, true), text)
	assert(text:find("3 adults\\, 1 children", 1, true))
	assert(text:find("Farmer 2\\, Tool smith 1", 1, true))
	assert(text:find("Missing: Weapon smith\\, Mason", 1, true))
	assert(text:find("Without a trade: 1\\, 0 of them labouring today", 1, true))
	assert(text:find("starving 1", 1, true))
	assert(text:find("Alms fund: 40 of 120 emeralds", 1, true))
	assert(text:find("button%[.-refresh;Refresh%]"))
	base.missing = {}
	assert(page(base):find("Every trade is here.", 1, true))
	base.register = {paid_avg = 10, paid_days = 2, growth = -3, growth_days = 1}
	assert(page(base):find("Average 10 a day over 2 days\n", 1, true), "no trend from two days")
	assert(page(base):find("Over 1 days: -3", 1, true))
	base.register = {}
	assert(not page(base):find("Average", 1, true) and not page(base):find("Over ", 1, true), "nothing noted yet")
	base.keepers = 0
	assert(page(base):find("No keeper serves dinner here.", 1, true))
	base.death = {id = "k1", trade = "child", cause = "died in a fall", day = 3}
	assert(page(base):find("Latest death: A child k1 died in a fall", 1, true))
	base.death = nil
	assert(page(base):find("No death is recorded here.", 1, true))
	base.church = {claimed = false}
	assert(page(base):find("No cleric tends this church.", 1, true))
	assert(page(base):find("No one preaches here. A note on the pulpit reads: \"", 1, true))
	base.church = {claimed = true, here = false}
	assert(page(base):find("The cleric is away.", 1, true))
	base.church = {claimed = true, here = true, fund = 5}
	assert(page(base):find("Alms fund: 5 emeralds\\, no service held yet", 1, true))
	base.economy = false
	assert(page(base):find("economy is off", 1, true))
	assert(not page(base):find("Paid between villagers", 1, true), "no trade volume with the economy off")
	assert(not page(base):find("keeper", 1, true) and not page(base):find("Tavern", 1, true))
	base.trades = {}
	assert(page(base):find("No one here has a trade.", 1, true))
end

-- Gathering from the world: children apart, the pulpit's cleric found by its claim.
local PULPIT = {x = 0, y = 0, z = 0}
do
	mcl_moon = {get_moon_phase = function() return 2 end}
	local priest = villager({_id = "p1", _profession = "cleric", _villages_alms = 33.6, _villages_alms_need = 50})
	objects = as_objects({
		priest,
		villager({_id = "f1", _profession = "farmer", _villages_food = 12}),
		villager({_id = "k1", child = true}),
		villager({name = "mobs_mc:cow", _id = "cow"}),
		villager({_profession = "farmer"}),
	})
	minetest.get_meta(PULPIT):set_string("villager", "p1")
	local report = menu.gather(PULPIT)
	assert(report.adults == 2 and report.children == 1)
	-- Phase 2 in the morning reads 3: Hearthday.
	assert(report.weekday == 4 and report.weekday_name == "Hearthday")
	assert(report.church.claimed and report.church.here and report.church.fund == 33)
	assert(report.church.target and report.church.target > 50, "the target adds the flesh reserve")
	priest._villages_alms_need = nil
	assert(menu.gather(PULPIT).church.target == nil)
	economy = false
	local off = menu.gather(PULPIT)
	assert(off.church.here and off.church.fund == nil and not off.economy)
	economy = true
	minetest.get_meta(PULPIT):set_string("villager", "gone")
	local away = menu.gather(PULPIT)
	assert(away.church.claimed and not away.church.here)
	minetest.get_meta(PULPIT):set_string("villager", "")
	assert(not menu.gather(PULPIT).church.claimed)
end

-- The tavern from its keepers: last evening's meals, the posted price; the register noted
-- once a day by the timer and by opening the page.
do
	local JUKEBOX = {x = 5, y = 0, z = 5}
	minetest.get_meta(JUKEBOX):set_string("villages_dinner_price", "3")
	local keeper = villager({_id = "kp", _profession = "farmer", _villages_keeper = true, _jobsite = JUKEBOX,
		_villages_dinner = {day = 10, last_served = 9}})
	tally.paid(keeper, 20, 9)
	objects = as_objects({keeper, villager({_id = "f2", _profession = "farmer"})})
	local report = menu.gather(PULPIT)
	assert(report.keepers == 1 and report.diners == 9 and report.dinner_price == 3)
	economy = false
	assert(menu.gather(PULPIT).keepers == 0, "no tavern with the economy off")
	economy = true
	minetest.get_meta(PULPIT):set_string(register.META, "")
	day = 10
	local list = menu.note(PULPIT)
	assert(#list == 1 and list[1].day == 9 and list[1].paid == 20 and list[1].diners == 9 and list[1].adults == 2)
	tally.paid(keeper, 5, 9)
	assert(menu.note(PULPIT)[1].paid == 20, "not noted twice in a day")
	day = 11
	assert(#menu.note(PULPIT) == 2, "the next day")
	minetest.get_meta(PULPIT):set_string(register.META, "")
	day = 10
end

-- Install: the right-click opens the page, Refresh redraws it, walking away closes it.
do
	menu.install()
	assert(overrides.name == "living_villages:pulpit" and overrides.fields.on_rightclick)
	local player = {
		is_player = function() return true end,
		get_player_name = function() return "sam" end,
		get_pos = function() return player_pos end,
	}
	local stack = {}
	assert(overrides.fields.on_rightclick(PULPIT, nil, player, stack) == stack)
	assert(#shown == 1 and shown[1].form == menu.FORM and shown[1].name == "sam")
	assert(#register.load(PULPIT) == 1, "opening the page notes the day")
	-- The timer: started on placing, by the LBM on load, and noting on each run.
	assert(lbm and lbm.name == "living_villages:pulpit_register" and lbm.run_at_every_load
		and lbm.nodenames[1] == "living_villages:pulpit")
	local placed = {x = 50, y = 0, z = 0}
	overrides.fields.on_construct(placed)
	assert(timers["50,0,0"] == register.TIMER_SECONDS)
	local loaded = {x = 60, y = 0, z = 0}
	lbm.action(loaded)
	assert(timers["60,0,0"] == register.TIMER_SECONDS)
	timers["60,0,0"] = 99
	lbm.action(loaded)
	assert(timers["60,0,0"] == 99, "a running timer is left alone")
	assert(overrides.fields.on_timer(loaded) == true and #register.load(loaded) == 1, "the timer notes and repeats")
	assert(receive(player, "other:form", {}) == false)
	assert(receive(player, menu.FORM, {refresh = "Refresh"}) == true and #shown == 2)
	player_pos = {x = 0, y = 0, z = 40}
	receive(player, menu.FORM, {refresh = "Refresh"})
	assert(#shown == 2 and closed == 1, "too far: closed, not redrawn")
	receive(player, menu.FORM, {refresh = "Refresh"})
	assert(#shown == 2, "forgotten once closed")
	player_pos = {x = 0, y = 0, z = 3}
	overrides.fields.on_rightclick(PULPIT, nil, player, stack)
	node_there = false
	receive(player, menu.FORM, {refresh = "Refresh"})
	assert(closed == 2, "the pulpit is gone")
	node_there = true
	overrides.fields.on_rightclick(PULPIT, nil, player, stack)
	leave(player)
	local before = #shown
	receive(player, menu.FORM, {refresh = "Refresh"})
	assert(#shown == before, "forgotten on leaving")
	-- A mob or a dispenser right-clicking shows nothing.
	overrides.fields.on_rightclick(PULPIT, nil, nil, stack)
	assert(#shown == before)
end

print("pulpit_menu tests passed")
