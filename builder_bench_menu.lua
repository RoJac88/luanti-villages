-- The window a right-click on a Builder's bench opens: which schematics the bench builds from
-- (the stock buildings, schemedit's directory or the project folder), what each source holds
-- with its share of what gets built, each building's weight, and a picture of it if it has one
-- (builder_preview.lua) or else what it is mostly made of. A tab only looks; a button
-- puts that source to use, so a player can see what is in one first.
--
-- Weights belong to a directory, so they change every bench using it, and need the server
-- privilege. The source belongs to one bench, and takes what building there takes. Everything
-- a client sends is checked against what the server showed it: names and paths never come
-- from a field.
local core = minetest
local S = core.get_translator and core.get_translator("living_villages") or function(message) return message end
local catalog = dofile(core.get_modpath("living_villages") .. "/builder_catalog.lua")
local preview = dofile(core.get_modpath("living_villages") .. "/builder_preview.lua")

local M = {}

M.FORM = "living_villages:builder_bench"
M.STOCK = "stock"
local BENCH = "living_villages:builder_block"
-- A little past a player's reach, for one who stepped back with the window open.
local MAX_DISTANCE = 12
local WIDTH, HEIGHT = 15, 10
local MATERIALS_SHOWN = 4
local PICTURE_WIDTH, PICTURE_HEIGHT = 5, 2.7
local ROW_COLOR, HEADER_COLOR, PROBLEM_COLOR = "#ffffff", "#c8c8c8", "#ff8a80"

local TABS = {
	{source = M.STOCK, title = S("Default")},
	{source = catalog.SCHEMEDIT, title = S("Schemedit")},
	{source = catalog.FOLDER, title = S("Project folder")},
}

-- player name -> {bench, builder, source being viewed, options, selected name, notice}
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
		return S("A Builder reaches @1, and this needs @2.", tostring(problem.reach), tostring(problem.needs))
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

local function tab_index(source)
	for i, tab in ipairs(TABS) do
		if tab.source == source then return i end
	end
	return 1
end

local function row_of(options, name)
	for i, row in ipairs(options.rows) do
		if row.name == name then return row, i end
	end
end

-- Where a source's files go, as a player would find it, and what else to know.
local function where_text(view)
	if view.source == M.STOCK then return S("The buildings a village generates with, in the mix it generated with.") end
	local place = view.place or ""
	if view.source == catalog.SCHEMEDIT and not view.schemedit_installed then
		return S("Files from @1. The schemedit mod is not on, but what is there can still be built.", place)
	end
	return S("Files from @1. Put a .mts file there and press Refresh.", place)
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
	line(S("Share: @1", percent(row.share)))
	line(S("Built here: @1", tostring(row.built or 0)))
	if row.is_next then line(core.colorize("#7fe08a", S("Next to be built"))) end
	if row.problem then
		y = y + 0.05
		parts[#parts + 1] = ("textarea[%.2f,%.2f;%.2f,%.1f;;;%s]"):format(x, y, w, view.preview and 1.2 or 1.6,
			escape(core.colorize(PROBLEM_COLOR, problem_text(row.problem))))
		y = y + 1.7
	end
	-- The picture takes their place: there is no room for both above the weight.
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
	if view.source ~= M.STOCK then
		local top = HEIGHT - 1.75
		if view.can_edit and not view.options.manifest_problem then
			parts[#parts + 1] = ("field[%.2f,%.2f;1.6,0.7;weight;%s;%s]"):format(x, top, escape(S("Weight")),
				escape(("%g"):format(row.weight or catalog.DEFAULT_WEIGHT)))
			parts[#parts + 1] = "field_close_on_enter[weight;false]"
			parts[#parts + 1] = ("button[%.2f,%.2f;1.6,0.7;set_weight;%s]"):format(x + 1.75, top, escape(S("Set")))
			parts[#parts + 1] = ("tooltip[set_weight;%s]"):format(
				escape(S("For every bench using this directory. 0 means never.")))
		else
			parts[#parts + 1] = ("label[%.2f,%.2f;%s]"):format(x, top + 0.35,
				escape(S("Weight: @1", ("%g"):format(row.weight or catalog.DEFAULT_WEIGHT))))
		end
	end
	return table.concat(parts)
end

-- The form, from what show() gathered. Pure, for the tests.
function M.formspec(view)
	local options = view.options
	local parts = {
		("formspec_version[4]size[%d,%d]"):format(WIDTH, HEIGHT),
	}
	local titles = {}
	for i, tab in ipairs(TABS) do titles[i] = escape(tab.title) end
	parts[#parts + 1] = ("tabheader[0,0;tabs;%s;%d;false;false]"):format(table.concat(titles, ","), tab_index(view.source))

	local in_use = view.source == view.in_use
	if in_use then
		parts[#parts + 1] = ("label[0.4,0.45;%s]"):format(escape(core.colorize("#7fe08a", S("This bench builds from these."))))
	elseif view.can_use then
		parts[#parts + 1] = ("button[0.4,0.15;4,0.65;use;%s]"):format(escape(S("Build from these")))
	else
		parts[#parts + 1] = ("label[0.4,0.45;%s]"):format(escape(S("This bench is protected, so you can only look.")))
	end
	parts[#parts + 1] = ("button[%.2f,0.15;2.2,0.65;refresh;%s]"):format(WIDTH - 2.6, escape(S("Refresh")))
	parts[#parts + 1] = ("label[0.4,1.05;%s]"):format(escape(where_text(view)))
	if view.project_text then
		parts[#parts + 1] = ("label[0.4,1.45;%s]"):format(escape(view.project_text))
	end

	if options.manifest_problem then
		parts[#parts + 1] = ("label[0.4,%.2f;%s]"):format(HEIGHT - 0.75, escape(core.colorize(PROBLEM_COLOR,
			S("@1 cannot be read. Using weight 1 for all until it is fixed.", catalog.MANIFEST))))
	elseif view.notice then
		parts[#parts + 1] = ("label[0.4,%.2f;%s]"):format(HEIGHT - 0.75, escape(view.notice))
	end

	-- A header in the table's own first row keeps it in line with its columns.
	local cells = {HEADER_COLOR, "", escape(S("Building")), escape(S("Weight")), escape(S("Share")), escape(S("Built"))}
	for _, row in ipairs(options.rows) do
		cells[#cells + 1] = row.problem and PROBLEM_COLOR or ROW_COLOR
		cells[#cells + 1] = row.problem and "x" or (row.is_next and ">" or "")
		cells[#cells + 1] = escape(pretty(row.name))
		cells[#cells + 1] = row.weight and ("%g"):format(row.weight) or "-"
		cells[#cells + 1] = percent(row.share)
		cells[#cells + 1] = tostring(row.built or 0)
	end
	local _, selected_index = nil, 0
	local selected = view.selected and row_of(options, view.selected)
	if selected then
		_, selected_index = row_of(options, view.selected)
	end
	parts[#parts + 1] = "tablecolumns[color;text,align=center,width=1;text,width=14;"
		.. "text,align=right,width=4;text,align=right,width=4;text,align=right,width=4]"
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

local function can_edit(name)
	return core.check_player_privs(name, {server = true}) == true
end

local function project_text(project)
	if not project then return nil end
	return S("Now: @1, @2", pretty(project.building), (project.state:gsub("_", " ")))
end

-- Reads the source afresh. Only here, not on a click in the table: it reads every file.
local function load_options(context)
	context.options = context.builder.options(context.bench, context.source)
	if not (context.selected and row_of(context.options, context.selected)) then
		local first = context.options.rows[1]
		context.selected = first and first.name or nil
	end
end

local show
show = function(name, context, notice)
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
	core.show_formspec(name, M.FORM, M.formspec({
		source = context.source,
		in_use = context.builder.source_of(context.bench) or M.STOCK,
		options = context.options,
		selected = context.selected,
		preview = picture,
		notice = notice,
		place = place,
		schemedit_installed = core.get_modpath("schemedit") ~= nil,
		can_use = can_use(name, context.bench),
		can_edit = can_edit(name),
		project_text = project_text(context.builder.load_project(context.bench)),
	}))
end

function M.open(name, bench, builder)
	local source = builder.source_of(bench) or M.STOCK
	local context = {bench = bench, builder = builder, source = source}
	load_options(context)
	open[name] = context
	show(name, context)
end

local WEIGHT_MESSAGES = {
	bad_weight = S("A weight is a number from 0 to @1.", tostring(catalog.MAX_WEIGHT)),
	no_file = S("That schematic has gone."),
	malformed = S("@1 cannot be read, so it was not changed.", catalog.MANIFEST),
	write_failed = S("The weight could not be saved."),
}

local function handle_weight(name, context, fields)
	if not can_edit(name) then return S("Changing a weight needs the server privilege.") end
	local directory = context.options.directory
	if not (directory and context.selected) then return nil end
	local ok, why = catalog.set_weight(directory, context.selected, fields.weight)
	load_options(context)
	if not ok then return WEIGHT_MESSAGES[why] or why end
	return S("Weight saved.")
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
	if fields.use then
		if can_use(name, context.bench) then
			context.builder.set_source(context.bench, context.source)
			notice = S("Saved. A building already started is finished first.")
		else
			notice = S("This bench is protected, so you can only look.")
		end
		load_options(context)
	elseif fields.set_weight or fields.key_enter_field == "weight" then
		notice = handle_weight(name, context, fields)
	elseif fields.refresh then
		load_options(context)
	elseif tab and TABS[tab] and TABS[tab].source ~= context.source then
		context.source, context.selected = TABS[tab].source, nil
		if context.source == catalog.FOLDER then core.mkdir(catalog.directory(catalog.FOLDER)) end
		load_options(context)
	elseif fields.projects then
		local event = core.explode_table_event(fields.projects)
		-- Row 1 is the header.
		local row = (event.type == "CHG" or event.type == "DCL") and context.options.rows[event.row - 1]
		if row then context.selected = row.name end
	else
		return
	end
	show(name, context, notice)
end

-- `builder`: options(bench, source), source_of(bench), set_source(bench, source), load_project(bench).
function M.install(builder)
	core.override_item(BENCH, {
		_doc_items_usagehelp = S("Rightclick to choose what a Builder builds from it. Sneak to place a block against it."),
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
