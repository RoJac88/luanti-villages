-- The window a right-click on a Builder's bench opens, in three tabs:
--
-- * Default: what the Builder builds by itself, for what the village needs (builder_needs.lua),
--   with the village's mix, what is next and why.
-- * Select schematic: the schematics of <world>/schems (builder_catalog.lua), each with a
--   picture if a PNG or JPEG of the same name is beside it (builder_preview.lua) or else what
--   it is mostly made of, and its price for this player, by its size and the Builder's opinion
--   of them (builder.lua). Ordering one pays the bench; the Builder takes it up in place of
--   whatever it has not started. If it finds no site, it goes back to what it was doing and
--   the player who paid may take the emeralds back here.
-- * Economy (docs/villager-economy-design.md, Visibility; ticket 10): the bench's economy
--   report (builder.economy, economy_report.lua) in two halves, each labelled with how it is
--   known: what the bench's Builder has heard in market news (shortages, gluts, and the worst
--   gaps: professions missing that would make what the village is short of), and what is seen
--   of the villagers loaded around the bench (professions present, nitwits and the unemployed
--   with their labour, and goods made and used today and yesterday). It only looks.
--
-- An order takes what building takes: the bench must not be protected from the player.
-- Everything a client sends is checked against what the server showed it: names never come
-- from a field.
local core = minetest
local S = core.get_translator and core.get_translator("living_villages") or function(message) return message end
local preview = dofile(core.get_modpath("living_villages") .. "/builder_preview.lua")

local M = {}

M.FORM = "living_villages:builder_bench"
M.DEFAULT, M.SELECT, M.ECONOMY = "default", "select", "economy"
local BENCH = "living_villages:builder_block"
-- A little past a player's reach, for one who stepped back with the window open.
local MAX_DISTANCE = 12
local WIDTH, HEIGHT = 15, 10
local MATERIALS_SHOWN = 4
local PICTURE_WIDTH, PICTURE_HEIGHT = 5, 2.7
local ROW_COLOR, HEADER_COLOR, PROBLEM_COLOR, GOOD_COLOR = "#ffffff", "#c8c8c8", "#ff8a80", "#7fe08a"

local TABS = {
	{view = M.DEFAULT, title = S("Default")},
	{view = M.SELECT, title = S("Select schematic")},
	{view = M.ECONOMY, title = S("Economy")},
}
local ECONOMY_ROWS = 5
local GOODS_SHOWN = 4

-- player name -> {bench, builder, view, options, selected name}
local open = {}

local function escape(text)
	return core.formspec_escape(text)
end

local function problem_text(problem)
	local code = problem.code
	if code == "unknown_nodes" then
		return S("Uses blocks this world does not have: @1", table.concat(problem.nodes, ", "))
	elseif code == "no_item" then
		return S("Uses blocks a player cannot supply: @1", table.concat(problem.nodes, ", "))
	elseif code == "empty" then
		return S("There is nothing in it to build.")
	elseif code == "too_big" then
		return S("Too big: at most @1 cells.", tostring(problem.limit))
	elseif code == "too_tall" then
		return S("Too tall: at most @1 high.", tostring(problem.limit))
	elseif code == "out_of_reach" then
		return S("Too wide for a Builder: it reaches @1, and this needs @2.",
			tostring(problem.reach), tostring(problem.needs))
	elseif code == "file_too_big" then
		return S("The file is too large to read.")
	end
	return S("The file cannot be read as a schematic.")
end

local function percent(share)
	if not share or share <= 0 then return "-" end
	if share < 0.01 then return "<1%" end
	return ("%d%%"):format(math.floor(share * 100 + 0.5))
end

local function pretty(name)
	local text = name:gsub("_", " ")
	return (text:gsub("^%l", string.upper))
end

local function item_label(item)
	local def = core.registered_items and core.registered_items[item]
	local description = def and def.description or item
	return (description:match("^[^\n]*"))
end

local function tab_index(view)
	for i, tab in ipairs(TABS) do
		if tab.view == view then return i end
	end
	return 1
end

local function row_of(options, name)
	for i, row in ipairs(options.rows) do
		if row.name == name then return row, i end
	end
end

-- What the bench's order says, for the Select schematic tab, or nil with none.
local function order_text(order)
	if not order then return nil end
	local name, by = pretty(order.name), order.player
	if order.state == "waiting" then
		return S("Ordered by @1: @2, to be started when the Builder is free.", by, name)
	elseif order.state == "started" then
		return S("Ordered by @1: @2. The Builder is looking for a site.", by, name)
	elseif order.state == "accepted" then
		return S("Ordered by @1: @2, under way.", by, name)
	end
	return S("No site was found for @1's @2. @3 emeralds can be refunded to them.", by, name, tostring(order.price))
end

local function detail_parts(view, row)
	local parts = {}
	local x, w = 9.6, WIDTH - 9.6 - 0.4
	local y = 2.15
	local function line(text)
		parts[#parts + 1] = ("label[%.2f,%.2f;%s]"):format(x, y, escape(text))
		y = y + 0.42
	end
	line(core.colorize("#ffff80", pretty(row.name)))
	if view.preview then
		local width, height = preview.fit(view.preview.width, view.preview.height, PICTURE_WIDTH, PICTURE_HEIGHT)
		parts[#parts + 1] = ("image[%.2f,%.2f;%.2f,%.2f;%s]"):format(x, y - 0.15, width, height, escape(view.preview.texture))
		y = y + PICTURE_HEIGHT
	end
	if row.size then
		line(S("Size: @1 by @2, @3 high", tostring(row.size.x), tostring(row.size.z), tostring(row.size.y)))
	end
	if row.blocks then line(S("Blocks: @1", tostring(row.blocks))) end
	if view.view == M.DEFAULT then line(S("Share: @1", percent(row.share))) end
	line(S("Built here: @1", tostring(row.built or 0)))
	if row.is_next then line(core.colorize(GOOD_COLOR, S("Next to be built"))) end
	if row.problem then
		y = y + 0.05
		parts[#parts + 1] = ("textarea[%.2f,%.2f;%.2f,%.1f;;;%s]"):format(x, y, w, view.preview and 1.2 or 1.6,
			escape(core.colorize(PROBLEM_COLOR, problem_text(row.problem))))
		y = y + 1.7
	end
	-- The picture takes their place: there is no room for both.
	if not view.preview and row.materials and #row.materials > 0 then
		y = y + 0.1
		for i = 1, math.min(MATERIALS_SHOWN, #row.materials) do
			local material = row.materials[i]
			parts[#parts + 1] = ("item_image[%.2f,%.2f;0.6,0.6;%s]"):format(x, y, escape(material.item))
			parts[#parts + 1] = ("label[%.2f,%.2f;%s]"):format(x + 0.75, y + 0.3,
				escape(tostring(material.count) .. " " .. item_label(material.item)))
			y = y + 0.65
		end
	end
	-- One order at a time: while there is one, its line at the top says so.
	if view.view == M.SELECT and row.price and not view.order then
		local top = HEIGHT - 1.75
		if view.can_use then
			parts[#parts + 1] = ("button[%.2f,%.2f;%.2f,0.7;order;%s]"):format(x, top, w,
				escape(S("Order for @1 emeralds", tostring(row.price))))
			parts[#parts + 1] = ("tooltip[order;%s]"):format(escape(
				S("Paid now. The materials still have to be found. It can be refunded if no site can be found.")))
		else
			parts[#parts + 1] = ("label[%.2f,%.2f;%s]"):format(x, top + 0.35, escape(S("Price: @1 emeralds", tostring(row.price))))
		end
	end
	return table.concat(parts)
end

local function goods_text(rows)
	local parts = {}
	for i = 1, math.min(GOODS_SHOWN, #rows) do parts[i] = rows[i].count .. " " .. item_label(rows[i].item) end
	if #rows > GOODS_SHOWN then parts[#parts + 1] = S("@1 more", tostring(#rows - GOODS_SHOWN)) end
	return #parts > 0 and table.concat(parts, ", ") or S("nothing")
end

local function list_text(list, shown, describe)
	local parts = {}
	for i = 1, math.min(shown, #list) do parts[i] = describe(list[i]) end
	if #list > shown then parts[#parts + 1] = S("@1 more", tostring(#list - shown)) end
	return table.concat(parts, ", ")
end

-- The Economy tab's body, from builder.economy's report (nil with the economy off).
local function economy_parts(report)
	local parts = {}
	local function label(x, y, text)
		parts[#parts + 1] = ("label[%.2f,%.2f;%s]"):format(x, y, escape(text))
	end
	local function wrapped(x, y, w, h, text)
		parts[#parts + 1] = ("textarea[%.2f,%.2f;%.2f,%.2f;;;%s]"):format(x, y, w, h, escape(text))
	end
	if not report then
		label(0.4, 0.6, S("The village economy is off on this server."))
		return table.concat(parts)
	end
	parts[#parts + 1] = ("button[%.2f,0.15;2.2,0.65;refresh;%s]"):format(WIDTH - 2.6, escape(S("Refresh")))
	-- Heard, on the left.
	local x, y = 0.4, 0.6
	label(x, y, core.colorize("#ffff80", S("Heard by the Builder (market news)")))
	y = y + 0.5
	if not report.heard then
		wrapped(x, y - 0.2, 6.8, 1.2, S("The Builder is not here, so there is no news to tell."))
	else
		local function rows(title, list, empty)
			label(x, y, core.colorize(HEADER_COLOR, title))
			y = y + 0.45
			if #list == 0 then
				label(x + 0.2, y, empty)
				y = y + 0.5
			end
			for i = 1, math.min(ECONOMY_ROWS, #list) do
				local row = list[i]
				parts[#parts + 1] = ("item_image[%.2f,%.2f;0.5,0.5;%s]"):format(x + 0.2, y - 0.25, escape(row.item))
				label(x + 0.85, y, S("@1 @2, @3 villagers", tostring(row.count), item_label(row.item), tostring(row.villagers)))
				y = y + 0.52
			end
			y = y + 0.15
		end
		rows(S("Short of"), report.shortages, S("No shortage heard of."))
		rows(S("Spare"), report.gluts, S("No glut heard of."))
		label(x, y, core.colorize(HEADER_COLOR, S("Missing professions")))
		y = y + 0.2
		local text
		if #report.gaps == 0 then
			text = S("None: someone here makes everything the village is short of.")
		else
			text = list_text(report.gaps, 3, function(gap)
				return S("@1 (@2)", pretty(gap.profession), list_text(gap.items, 2, item_label))
			end)
			text = text .. "\n" .. S("A building for the first comes when nothing is more pressing.")
		end
		wrapped(x, y, 6.8, HEIGHT - y - 0.3, text)
	end
	-- Seen, on the right.
	x, y = 7.8, 0.6
	label(x, y, core.colorize("#ffff80", S("Seen around the bench")))
	local professions = {}
	for name, count in pairs(report.present) do professions[#professions + 1] = {name = name, count = count} end
	table.sort(professions, function(a, b) return a.name < b.name end)
	local lines = {
		core.colorize(HEADER_COLOR, S("Professions")),
		#professions > 0 and list_text(professions, #professions, function(entry)
			return pretty(entry.name) .. " " .. entry.count
		end) or S("No villagers loaded."),
		"",
		core.colorize(HEADER_COLOR, S("Idle hands")),
		#report.idle > 0 and list_text(report.idle, 6, function(entry)
			return S("@1 @2: @3", pretty(entry.profession), tostring(entry.id):sub(1, 6), entry.activity or S("nothing to do"))
		end) or S("None."),
		"",
		core.colorize(HEADER_COLOR, S("Today")),
		S("Made: @1", goods_text(report.today.made)),
		S("Used: @1", goods_text(report.today.used)),
		"",
		core.colorize(HEADER_COLOR, S("Yesterday")),
		S("Made: @1", goods_text(report.yesterday.made)),
		S("Used: @1", goods_text(report.yesterday.used)),
	}
	wrapped(x, y + 0.3, WIDTH - x - 0.4, HEIGHT - y - 0.6, table.concat(lines, "\n"))
	return table.concat(parts)
end

-- The form, from what show() gathered. Pure, for the tests.
--   view: {view, report (economy), options, selected, preview, notice, place, can_use,
--          project_text, order, can_refund}
function M.formspec(view)
	local options = view.options
	local parts = {
		("formspec_version[4]size[%d,%d]"):format(WIDTH, HEIGHT),
	}
	local titles = {}
	for i, tab in ipairs(TABS) do titles[i] = escape(tab.title) end
	parts[#parts + 1] = ("tabheader[0,0;tabs;%s;%d;false;false]"):format(table.concat(titles, ","), tab_index(view.view))
	if view.view == M.ECONOMY then
		parts[#parts + 1] = economy_parts(view.report)
		return table.concat(parts)
	end

	parts[#parts + 1] = ("button[%.2f,0.15;2.2,0.65;refresh;%s]"):format(WIDTH - 2.6, escape(S("Refresh")))
	local selecting = view.view == M.SELECT
	local intro
	if selecting then
		intro = S("Files from @1. Put a .mts file there, with a .png of the same name for a picture, and press Refresh.",
			view.place or "")
	else
		intro = S("The Builder builds what the village needs. To choose a building, order one on the next tab.")
	end
	parts[#parts + 1] = ("label[0.4,0.45;%s]"):format(escape(intro))
	local status = selecting and order_text(view.order) or view.project_text
	if status then parts[#parts + 1] = ("label[0.4,0.95;%s]"):format(escape(status)) end
	if selecting and view.can_refund then
		parts[#parts + 1] = ("button[0.4,1.25;3,0.6;refund;%s]"):format(escape(S("Take the refund")))
	elseif selecting and not view.can_use then
		parts[#parts + 1] = ("label[0.4,1.45;%s]"):format(escape(S("This bench is protected, so you can only look.")))
	end

	if view.notice then
		parts[#parts + 1] = ("label[0.4,%.2f;%s]"):format(HEIGHT - 0.75, escape(view.notice))
	elseif not selecting and options.reason then
		parts[#parts + 1] = ("label[0.4,%.2f;%s]"):format(HEIGHT - 0.75, escape(S("Next, because @1.", options.reason)))
	end

	-- A header in the table's own first row keeps it in line with its columns.
	local cells = {HEADER_COLOR, "", escape(S("Building")), escape(selecting and S("Price") or S("Share")), escape(S("Built"))}
	for _, row in ipairs(options.rows) do
		cells[#cells + 1] = row.problem and PROBLEM_COLOR or ROW_COLOR
		cells[#cells + 1] = row.problem and "x" or (row.is_next and ">" or "")
		cells[#cells + 1] = escape(pretty(row.name))
		if selecting then
			cells[#cells + 1] = row.price and tostring(row.price) or "-"
		else
			cells[#cells + 1] = percent(row.share)
		end
		cells[#cells + 1] = tostring(row.built or 0)
	end
	local _, selected_index = nil, 0
	local selected = view.selected and row_of(options, view.selected)
	if selected then
		_, selected_index = row_of(options, view.selected)
	end
	parts[#parts + 1] = "tablecolumns[color;text,align=center,width=1;text,width=16;"
		.. "text,align=right,width=5;text,align=right,width=4]"
	parts[#parts + 1] = ("table[0.4,2;8.9,%.2f;projects;%s;%d]"):format(HEIGHT - 3, table.concat(cells, ","), selected_index + 1)
	if selected then
		parts[#parts + 1] = detail_parts(view, selected)
	elseif #options.rows == 0 then
		parts[#parts + 1] = ("label[9.6,2.4;%s]"):format(escape(S("Nothing here yet.")))
	end
	return table.concat(parts)
end

local function bench_is_there(bench)
	local node = core.get_node_or_nil(bench)
	return node ~= nil and node.name == BENCH
end

local function can_use(name, bench)
	return not core.is_protected(bench, name)
end

local function project_text(project)
	if not project then return nil end
	return S("Now: @1, @2", pretty(project.building), (project.state:gsub("_", " ")))
end

-- Reads afresh. Only here, not on a click in the table: the Select tab reads every file.
local function load_options(name, context)
	if context.view == M.SELECT then
		context.options = context.builder.catalog_options(context.bench, name)
	elseif context.view == M.DEFAULT then
		context.options = context.builder.options(context.bench)
	else
		return
	end
	if not (context.selected and row_of(context.options, context.selected)) then
		local first = context.options.rows[1]
		context.selected = first and first.name or nil
	end
end

local show
show = function(name, context, notice)
	if context.view == M.ECONOMY then
		core.show_formspec(name, M.FORM, M.formspec({view = M.ECONOMY, report = context.builder.economy(context.bench)}))
		return
	end
	local directory = context.options.directory
	local selected = context.selected and row_of(context.options, context.selected)
	local picture
	if selected and selected.image and directory then
		local wanted = context.selected
		picture = preview.request(name, directory .. "/" .. selected.image, function()
			-- It may have moved on, or closed the window, while the picture was on its way.
			if open[name] == context and context.selected == wanted then show(name, context) end
		end)
	end
	local world = core.get_worldpath()
	local place = directory
	if directory and directory:sub(1, #world) == world then place = "<world>" .. directory:sub(#world + 1) end
	local order = context.builder.order_of(context.bench)
	core.show_formspec(name, M.FORM, M.formspec({
		view = context.view,
		options = context.options,
		selected = context.selected,
		preview = picture,
		notice = notice,
		place = place,
		can_use = can_use(name, context.bench),
		project_text = project_text(context.builder.load_project(context.bench)),
		order = order,
		can_refund = order ~= nil and order.state == "failed" and order.player == name,
	}))
end

function M.open(name, bench, builder)
	local context = {bench = bench, builder = builder, view = M.DEFAULT}
	load_options(name, context)
	open[name] = context
	show(name, context)
end

local ORDER_MESSAGES = {
	busy = S("This bench has an order already."),
	no_file = S("That schematic has gone."),
	cannot_build = S("A Builder cannot put that up."),
	no_emeralds = S("You do not have the emeralds."),
	copy_failed = S("The schematic could not be copied for the Builder."),
}

local function handle_order(player, name, context)
	if not can_use(name, context.bench) then return S("This bench is protected, so you can only look.") end
	if not context.selected then return nil end
	local ok, result = context.builder.place_order(context.bench, player, context.selected)
	load_options(name, context)
	if not ok then return ORDER_MESSAGES[result] or result end
	return S("Ordered for @1 emeralds.", tostring(result))
end

local function handle_fields(player, fields)
	local name = player:get_player_name()
	local context = open[name]
	if not context then return end
	if fields.quit then
		open[name] = nil
		return
	end
	local at = player:get_pos()
	if not bench_is_there(context.bench) or not at or vector.distance(at, context.bench) > MAX_DISTANCE then
		open[name] = nil
		core.close_formspec(name, M.FORM)
		return
	end

	local notice
	local tab = tonumber(fields.tabs)
	if fields.order and context.view == M.SELECT then
		notice = handle_order(player, name, context)
	elseif fields.refund and context.view == M.SELECT then
		local ok, amount = context.builder.refund(context.bench, player)
		notice = ok and S("@1 emeralds refunded.", tostring(amount)) or S("There is nothing to refund to you.")
	elseif fields.refresh then
		load_options(name, context)
	elseif tab and TABS[tab] and TABS[tab].view ~= context.view then
		context.view, context.selected = TABS[tab].view, nil
		load_options(name, context)
	elseif fields.projects then
		local event = core.explode_table_event(fields.projects)
		-- Row 1 is the header.
		local row = (event.type == "CHG" or event.type == "DCL") and context.options and context.options.rows[event.row - 1]
		if row then context.selected = row.name end
	else
		return
	end
	show(name, context, notice)
end

-- `builder`: options(bench), catalog_options(bench, player name), order_of(bench),
-- place_order(bench, player, name), refund(bench, player), load_project(bench), economy(bench).
function M.install(builder)
	core.override_item(BENCH, {
		_doc_items_usagehelp = S("Rightclick to see what a Builder will build from it, or to order a building. "
			.. "Sneak to place a block against it."),
		on_rightclick = function(pos, _, clicker, itemstack)
			if clicker and clicker.is_player and clicker:is_player() then
				M.open(clicker:get_player_name(), pos, builder)
			end
			return itemstack
		end,
	})
	core.register_on_player_receive_fields(function(player, formname, fields)
		if formname ~= M.FORM then return false end
		handle_fields(player, fields)
		return true
	end)
	core.register_on_leaveplayer(function(player)
		open[player:get_player_name()] = nil
		preview.forget(player:get_player_name())
	end)
end

return M
