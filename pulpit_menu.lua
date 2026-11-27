-- The window a right-click on a church's pulpit opens (ticket 48, the parish register): the
-- day of the week and the state of the village within VILLAGE_RADIUS of the pulpit
-- (parish_report.lua), and the latest death there (parish_deaths.lua). It only looks.
--
-- The register (ticket 48c, parish_register.lua) notes a day's snapshot in the pulpit's
-- meta once the day turns: the pulpit's node timer runs every few seconds while its block
-- is loaded (started on placing it, and by an LBM for pulpits a schematic placed or that
-- were there before), and opening the page notes one too. The page shows the last week's
-- trade and the change in population from it.
--
-- Under the day stand the stars and the sermon (ticket 48d, parish_rating.lua), and each
-- part's score is listed beside the food. Under the trades stand the village's needs (ticket
-- 48e): its shortages and the professions that would make them, from the cleric's news. It shows with or without a cleric: the church part
-- says when no cleric holds the pulpit, and the alms fund needs the economy on.
--
-- The lectern the pulpit copies has no right-click of its own (mcl_lectern), so nothing is
-- lost; a player sneaking still places a block against it.
local core = minetest
local S = core.get_translator and core.get_translator("living_villages") or function(message) return message end
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local parish = dofile(core.get_modpath("living_villages") .. "/parish_report.lua")
local deaths = dofile(core.get_modpath("living_villages") .. "/parish_deaths.lua")
local register = dofile(core.get_modpath("living_villages") .. "/parish_register.lua")
local rating = dofile(core.get_modpath("living_villages") .. "/parish_rating.lua")

local M = {}

M.FORM = "living_villages:pulpit"
local PULPIT = "living_villages:pulpit"
local VILLAGER = "mobs_mc:villager"
-- church.lua's and rent.lua's village.
local VILLAGE_RADIUS = 128
-- A little past a player's reach, for one who stepped back with the window open.
local MAX_DISTANCE = 12
local WIDTH, HEIGHT = 13, 10.5
local STAR = "mcl_mobitems_nether_star.png"
local NO_STAR = STAR .. "^[colorize:#000000:190"
local STAR_SIZE = 0.55
local TITLE_COLOR, HEADER_COLOR, PROBLEM_COLOR, GOOD_COLOR = "#ffff80", "#c8c8c8", "#ff8a80", "#7fe08a"

local NAMES = {
	tool_smith = S("Tool smith"), weapon_smith = S("Weapon smith"),
}

local TRENDS = {rising = S("rising"), falling = S("falling"), steady = S("steady")}

-- player name -> pulpit position
local open = {}

local function escape(text)
	return core.formspec_escape(text)
end

function M.pretty(name)
	if NAMES[name] then return NAMES[name] end
	local text = name:gsub("_", " ")
	return (text:gsub("^%l", string.upper))
end

local function header(text)
	return core.colorize(HEADER_COLOR, text)
end

local NEEDS_SHOWN, GAPS_SHOWN = 4, 3

local function item_label(item)
	local def = core.registered_items and core.registered_items[item]
	local description = def and def.description or item
	return (description:match("^[^\n]*"))
end

local function needs_lines(report)
	if not report.economy then return {} end
	local lines = {header(S("Village needs"))}
	local needs = report.needs
	if not needs then
		lines[#lines + 1] = S("With no cleric to hear the village's news, no one knows what it lacks.")
		return lines
	end
	if #needs.shortages == 0 then
		lines[#lines + 1] = S("No shortage is heard of.")
	else
		local parts = {}
		for i = 1, math.min(NEEDS_SHOWN, #needs.shortages) do
			local row = needs.shortages[i]
			parts[i] = row.count .. " " .. item_label(row.item)
		end
		lines[#lines + 1] = S("Short of: @1", table.concat(parts, ", "))
	end
	if #needs.gaps > 0 then
		local parts = {}
		for i = 1, math.min(GAPS_SHOWN, #needs.gaps) do
			local gap = needs.gaps[i]
			parts[i] = S("@1 (@2)", M.pretty(gap.profession), item_label(gap.items[1]))
		end
		lines[#lines + 1] = S("No one here makes it: @1", table.concat(parts, ", "))
	end
	return lines
end

local function people_lines(report)
	local lines = {
		header(S("People")),
		S("@1 adults, @2 children", tostring(report.adults), tostring(report.children)),
	}
	local summary = report.register
	if summary and summary.growth and summary.growth_days > 0 then
		local change = summary.growth > 0 and ("+" .. summary.growth) or tostring(summary.growth)
		lines[#lines + 1] = S("Over @1 days: @2", tostring(summary.growth_days), change)
	end
	local death = report.death
	if death then
		local who = death.trade == "child" and S("A child") or S("The @1", M.pretty(death.trade or "villager"):lower())
		lines[#lines + 1] = S("Latest death: @1 @2 @3, day @4", who, tostring(death.id or ""):sub(1, 6), death.cause or S("died"),
			tostring(death.day or "?"))
	else
		lines[#lines + 1] = S("No death is recorded here.")
	end
	return lines
end

local function trade_lines(report)
	local lines = {header(S("Trades"))}
	if #report.trades == 0 then
		lines[#lines + 1] = S("No one here has a trade.")
	else
		local parts = {}
		for i, entry in ipairs(report.trades) do parts[i] = M.pretty(entry.name) .. " " .. entry.count end
		lines[#lines + 1] = table.concat(parts, ", ")
	end
	if #report.missing == 0 then
		lines[#lines + 1] = core.colorize(GOOD_COLOR, S("Every trade is here."))
	else
		local parts = {}
		for i, name in ipairs(report.missing) do parts[i] = M.pretty(name) end
		lines[#lines + 1] = core.colorize(PROBLEM_COLOR, S("Missing: @1", table.concat(parts, ", ")))
	end
	if report.idle > 0 then
		lines[#lines + 1] = S("Without a trade: @1, @2 of them labouring today", tostring(report.idle),
			tostring(report.labouring))
	end
	return lines
end

local function food_lines(report)
	local f = report.food
	local starving = S("starving @1", tostring(f.starving))
	if f.starving > 0 then starving = core.colorize(PROBLEM_COLOR, starving) end
	local lines = {
		header(S("Food")),
		S("Full @1, fed @2, hungry @3, @4", tostring(f.full), tostring(f.fed), tostring(f.hungry), starving),
	}
	if report.economy then
		if (report.keepers or 0) == 0 then
			lines[#lines + 1] = S("No keeper serves dinner here.")
		elseif report.dinner_price then
			lines[#lines + 1] = S("Tavern: @1 meals last evening, dinner @2 emeralds", tostring(report.diners),
				tostring(report.dinner_price))
		else
			lines[#lines + 1] = S("Tavern: @1 meals last evening", tostring(report.diners))
		end
	end
	return lines
end

local function trade_volume_lines(report)
	if not report.economy then return {} end
	local lines = {
		header(S("Trade")),
		S("Paid between villagers: @1 emeralds today, @2 yesterday", tostring(report.paid_today),
			tostring(report.paid_yesterday)),
	}
	local summary = report.register
	if summary and summary.paid_avg then
		local trend = summary.paid_trend and TRENDS[summary.paid_trend]
		local line = S("Average @1 a day over @2 days", tostring(math.floor(summary.paid_avg + 0.5)),
			tostring(summary.paid_days))
		lines[#lines + 1] = trend and S("@1, @2", line, trend) or line
	end
	return lines
end

local function church_lines(report)
	local church = report.church
	local lines = {header(S("Church"))}
	if not church.claimed then
		lines[#lines + 1] = S("No cleric tends this church.")
	elseif not church.here then
		lines[#lines + 1] = S("The cleric is away.")
	elseif not report.economy then
		lines[#lines + 1] = S("The village economy is off on this server.")
	elseif church.target then
		lines[#lines + 1] = S("Alms fund: @1 of @2 emeralds", tostring(church.fund or 0), tostring(church.target))
	else
		lines[#lines + 1] = S("Alms fund: @1 emeralds, no service held yet", tostring(church.fund or 0))
	end
	return lines
end

local PART_NAMES = {
	fed = S("Fed"), trades = S("Trades"), employed = S("Employed"), trade = S("Trade"),
	safety = S("Alms"), growth = S("Growth"),
}

local CAP_TEXT = {
	starving1 = S("One starving: at most four stars."),
	starving2 = S("Two or more starving: at most three stars."),
	missing = S("Five stars needs every trade."),
}

local function rating_lines(rated)
	local lines = {header(S("Rating"))}
	for _, part in ipairs(rating.PARTS) do
		local score = rated.scores[part.name]
		if score then
			local text = S("@1: @2%", PART_NAMES[part.name], tostring(math.floor(score * 100 + 0.5)))
			if score < 0.5 then text = core.colorize(PROBLEM_COLOR, text) end
			lines[#lines + 1] = text
		end
	end
	if rated.cap_reason then lines[#lines + 1] = CAP_TEXT[rated.cap_reason] end
	return lines
end

local function join(...)
	local lines = {}
	for _, list in ipairs({...}) do
		if #lines > 0 and #list > 0 then lines[#lines + 1] = "" end
		for _, line in ipairs(list) do lines[#lines + 1] = line end
	end
	return table.concat(lines, "\n")
end

-- The form, from a parish report. Pure, for the tests.
-- The sermon as the page gives it: the cleric's words, or a note on a pulpit with none.
function M.sermon_text(report, rated)
	local line = rating.sermon(rated, report, report.day)
	if report.church and report.church.claimed then return S("The cleric preaches: \"@1\"", line) end
	return S("No one preaches here. A note on the pulpit reads: \"@1\"", line)
end

function M.formspec(report)
	local rated = rating.rate(report)
	local parts = {
		("formspec_version[4]size[%.2f,%.2f]"):format(WIDTH, HEIGHT),
		("label[0.4,0.6;%s]"):format(escape(core.colorize(TITLE_COLOR,
			S("@1, day @2", report.weekday_name, tostring(report.day))))),
		("button[%.2f,0.25;2.2,0.65;refresh;%s]"):format(WIDTH - 2.6, escape(S("Refresh"))),
	}
	for i = 1, 5 do
		parts[#parts + 1] = ("image[%.2f,1.0;%.2f,%.2f;%s]"):format(0.4 + (i - 1) * (STAR_SIZE + 0.1), STAR_SIZE,
			STAR_SIZE, escape(i <= rated.stars and STAR or NO_STAR))
	end
	parts[#parts + 1] = ("label[%.2f,1.28;%s]"):format(0.6 + 5 * (STAR_SIZE + 0.1),
		escape(S("@1 of 5 stars", tostring(rated.stars))))
	parts[#parts + 1] = ("textarea[0.4,1.8;%.2f,1.0;;;%s]"):format(WIDTH - 0.8, escape(M.sermon_text(report, rated)))
	local half = (WIDTH - 1.2) / 2
	local top = 3.0
	parts[#parts + 1] = ("textarea[0.4,%.2f;%.2f,%.2f;;;%s]"):format(top, half, HEIGHT - top - 0.4,
		escape(join(people_lines(report), trade_lines(report), needs_lines(report))))
	parts[#parts + 1] = ("textarea[%.2f,%.2f;%.2f,%.2f;;;%s]"):format(0.8 + half, top, half, HEIGHT - top - 0.4,
		escape(join(rating_lines(rated), food_lines(report), trade_volume_lines(report), church_lines(report))))
	return table.concat(parts)
end

-- alms.lua, dinner.lua, market_news.lua and possessions.lua, loaded the first time they are
-- wanted: they load the economy's modules.
local alms, dinner, news, possessions
local function alms_module()
	alms = alms or dofile(core.get_modpath("living_villages") .. "/alms.lua")
	return alms
end
local function dinner_module()
	dinner = dinner or dofile(core.get_modpath("living_villages") .. "/dinner.lua")
	return dinner
end

-- The cleric's market news, own and hearsay, as builder.lua reads its Builder's.
local function cleric_news(cleric)
	news = news or dofile(core.get_modpath("living_villages") .. "/market_news.lua")
	possessions = possessions or dofile(core.get_modpath("living_villages") .. "/possessions.lua")
	local now = core.get_gametime()
	local known = news.own(cleric, possessions.assess(cleric), now)
	for _, entry in ipairs(news.heard(cleric, now)) do known[#known + 1] = entry end
	return known
end

-- The keepers among `adults`: how many, the meals they served last evening, and the dinner
-- price posted at the first one's jukebox (its jobsite).
local function tavern_of(adults)
	local tavern = {keepers = 0, diners = 0}
	for _, villager in ipairs(adults) do
		if villager._villages_keeper then
			local d = dinner_module()
			tavern.keepers = tavern.keepers + 1
			tavern.diners = tavern.diners + d.last_served(villager)
			local jukebox = villager._jobsite
			local price = jukebox and tonumber(core.get_meta(jukebox):get_string(d.POSTED))
			if price and not tavern.price then tavern.price = math.floor(price) end
		end
	end
	return tavern
end

-- The adults and children within the radius, and the loaded cleric with id `cleric_id`.
local function villagers_around(pos, cleric_id)
	local adults, children, cleric = {}, {}, nil
	for _, object in ipairs(core.get_objects_inside_radius(pos, VILLAGE_RADIUS)) do
		local entity = object:get_luaentity()
		if entity and entity.name == VILLAGER and entity._id then
			if entity.child then
				children[#children + 1] = entity
			else
				adults[#adults + 1] = entity
				if cleric_id and entity._id == cleric_id then cleric = entity end
			end
		end
	end
	return adults, children, cleric
end

-- The villagers' mean reference price for a dinner (dinner.reference), the rating's
-- measure of trade when no keeper posts one; nil with no adults.
local function dinner_reference(adults)
	if #adults == 0 then return nil end
	local d, sum = dinner_module(), 0
	for _, villager in ipairs(adults) do sum = sum + d.reference(villager) end
	return sum / #adults
end

-- The report for the pulpit at pos, from the world as it is loaded now.
function M.gather(pos)
	local claim = core.get_meta(pos):get_string("villager")
	local cleric_id = claim ~= "" and claim or nil
	local adults, children, cleric = villagers_around(pos, cleric_id)
	local economy = clock.enabled()
	local church = {claimed = cleric_id ~= nil, here = cleric ~= nil}
	if cleric and economy then
		church.fund = math.floor(cleric._villages_alms or 0)
		local need = cleric._villages_alms_need
		if need then church.target = math.ceil(need + alms_module().flesh_reserve(cleric)) end
	end
	local weekday, weekday_name = common.day_of_week()
	return parish.build(adults, children, {
		day = core.get_day_count(), weekday = weekday, weekday_name = S(weekday_name),
		state = food.state, economy = economy, church = church,
		death = deaths.latest(pos, VILLAGE_RADIUS),
		tavern = economy and tavern_of(adults) or nil,
		dinner_ref = economy and dinner_reference(adults) or nil,
		heard = economy and cleric and cleric_news(cleric) or nil,
	})
end

local function pulpit_is_there(pos)
	local node = core.get_node_or_nil(pos)
	return node and node.name == PULPIT
end

-- Notes the day that ended in the register, once it has turned; `report` saves a second
-- gathering. Returns the register.
function M.note(pos, report)
	local list = register.load(pos)
	local day = core.get_day_count()
	if register.due(list, day) then
		list = register.push(list, register.entry(report or M.gather(pos), day))
		register.save(pos, list)
	end
	return list
end

local function show(name, pos)
	local report = M.gather(pos)
	report.register = register.summary(M.note(pos, report), report)
	core.show_formspec(name, M.FORM, M.formspec(report))
end

local function start_timer(pos)
	local timer = core.get_node_timer(pos)
	if not timer:is_started() then timer:start(register.TIMER_SECONDS) end
end

function M.open(name, pos)
	open[name] = vector.new(pos)
	show(name, pos)
end

local function handle_fields(player, fields)
	local name = player:get_player_name()
	local pos = open[name]
	if not pos then return end
	if fields.quit then
		open[name] = nil
		return
	end
	local at = player:get_pos()
	if not pulpit_is_there(pos) or not at or vector.distance(at, pos) > MAX_DISTANCE then
		open[name] = nil
		core.close_formspec(name, M.FORM)
		return
	end
	if fields.refresh then show(name, pos) end
end

function M.install()
	if not core.registered_nodes[PULPIT] or not core.override_item then return end
	core.override_item(PULPIT, {
		_doc_items_usagehelp = S("Rightclick to read the parish register: the day of the week and how the village is doing."),
		on_rightclick = function(pos, _, clicker, itemstack)
			if clicker and clicker.is_player and clicker:is_player() then
				M.open(clicker:get_player_name(), pos)
			end
			return itemstack
		end,
		on_construct = start_timer,
		on_timer = function(pos)
			M.note(pos)
			return true
		end,
	})
	-- A schematic's pulpit, and one placed before the register, get their timer on load.
	core.register_lbm({
		label = "Start the parish register's timer",
		name = "living_villages:pulpit_register",
		nodenames = {PULPIT},
		run_at_every_load = true,
		action = start_timer,
	})
	core.register_on_player_receive_fields(function(player, formname, fields)
		if formname ~= M.FORM then return false end
		handle_fields(player, fields)
		return true
	end)
	core.register_on_leaveplayer(function(player)
		open[player:get_player_name()] = nil
	end)
end

return M
