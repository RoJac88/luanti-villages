-- The window a right-click on a Builder opens (builder.lua): what it is doing, and, while it
-- waits for materials, exactly what it lacks, with a Buy button on what it sells. It is a
-- snapshot, with a Refresh button. It works from what builder.lua reports, and has no state
-- of its own but which villager each player has open.
local core = minetest
local S = core.get_translator and core.get_translator("living_villages") or function(message) return message end

local M = {}

local FORM = "living_villages:builder_status"
local WIDTH, ROW = 12.5, 0.8

local open = {}

local STATE_TEXT = {
	no_bench = S("It has no bench to work from."),
	choosing = S("Deciding what the village needs next."),
	finding_site = S("Looking for a site."),
	no_site = S("There is no suitable site for this building."),
	requires_materials = S("Waiting for materials. Put them in a chest near its bench."),
	collecting = S("Fetching materials from the chests."),
	building = S("Building."),
	blocked = S("Something is in the way, so it has stopped."),
	returning = S("Finished. Putting back what was left over."),
}

local BUY_MESSAGES = {
	in_chest = S("Bought. It is in the chest by the bench."),
	in_inventory = S("Bought. The chests are full, so it is in your inventory."),
	no_emeralds = S("You do not have enough emeralds."),
	not_needed = S("The Builder does not need that any more."),
	not_for_sale = S("The Builder does not sell that."),
	too_far = S("You are too far away."),
}

local function pretty_building(name)
	local text = (name or ""):gsub("_", " ")
	return (text:gsub("^%l", string.upper))
end

local function item_label(item)
	local def = core.registered_items and core.registered_items[item]
	local description = def and def.description or item
	-- The first line only: the rest is a tooltip's.
	return (description:match("^[^\n]*"))
end

local function escape(text)
	return core.formspec_escape(text)
end

local function summary_lines(report)
	local lines = {STATE_TEXT[report.state] or report.state}
	if report.no_projects then
		lines[#lines + 1] = S("Its bench is set to schematics it cannot use, or has none.")
	end
	if report.building then
		lines[#lines + 1] = S("Building: @1", pretty_building(report.building))
		if report.reason then lines[#lines + 1] = S("Because @1.", report.reason) end
	end
	if report.scaffold then
		lines[#lines + 1] = S("Working from the scaffolding.")
	end
	if report.state == "no_site" and report.size then
		lines[#lines + 1] = S("It needs near-level ground @1 by @2, clear to @3 high, with 2 clear cells round it,",
			tostring(report.size.x), tostring(report.size.z), tostring(report.size.y))
		lines[#lines + 1] = S("close to the village and within @1 nodes of its bench.", tostring(report.range or 0))
		lines[#lines + 1] = S("Clear a spot and it will find it.")
	end
	if report.site then
		lines[#lines + 1] = S("Site: @1", core.pos_to_string(report.site))
	end
	if report.earthwork and report.earthwork > 0 then
		lines[#lines + 1] = S("It will level @1 blocks of dirt there first, at no cost.", tostring(report.earthwork))
	end
	if report.blocked then
		lines[#lines + 1] = S("Something is in the way at @1.", core.pos_to_string(report.blocked))
	end
	if report.away_built then
		lines[#lines + 1] = S("While no one was near, it placed @1 blocks.", tostring(report.away_built))
	end
	if report.left and report.total and report.total > 0 and report.state ~= "requires_materials" then
		lines[#lines + 1] = S("Done: @1 of @2 steps.", tostring(report.total - report.left), tostring(report.total))
	end
	if report.stuck == "chest" then
		lines[#lines + 1] = S("It cannot get to the chest that has what it needs.")
	elseif report.stuck == "occupied" then
		lines[#lines + 1] = S("Someone is standing where it needs to build.")
	elseif report.stuck == "site" then
		lines[#lines + 1] = S("It cannot get to the site. Keep the ground around the site clear.")
	end
	if report.state ~= "no_bench" and report.at_work == false then
		lines[#lines + 1] = S("It is off work now.")
	end
	return lines
end

-- The form, and the items its Buy buttons stand for.
function M.formspec(report, notice)
	local lines = summary_lines(report)
	local parts = {}
	local y = 0.8
	for _, line in ipairs(lines) do
		parts[#parts + 1] = ("label[0.4,%.2f;%s]"):format(y, escape(line))
		y = y + 0.45
	end

	local buttons = {}
	local rows = report.rows or {}
	local show_rows = report.state == "requires_materials" and #rows > 0
	local list_top = y + 0.1
	local list_height = 0
	if show_rows then
		local columns = {{4.9, S("Needed")}, {6.0, S("In chests")}, {7.2, S("Carried")}, {8.2, S("Missing")}}
		for _, row in ipairs(rows) do
			if row.price then
				columns[#columns + 1] = {9.2, S("Price each")}
				break
			end
		end
		for _, column in ipairs(columns) do
			parts[#parts + 1] = ("label[%.1f,%.2f;%s]"):format(column[1], list_top, escape(column[2]))
		end
		list_top = list_top + 0.3
		list_height = math.min(5.2, #rows * ROW)
		parts[#parts + 1] = ("scroll_container[0.4,%.2f;%.1f,%.2f;builder_rows;vertical;0.1]"):format(
			list_top, WIDTH - 1.2, list_height)
		for i, row in ipairs(rows) do
			local top = (i - 1) * ROW
			parts[#parts + 1] = ("item_image[0,%.2f;0.7,0.7;%s]"):format(top, escape(row.item))
			parts[#parts + 1] = ("label[0.85,%.2f;%s]"):format(top + 0.35, escape(item_label(row.item)))
			parts[#parts + 1] = ("label[4.6,%.2f;%d]"):format(top + 0.35, row.need)
			parts[#parts + 1] = ("label[5.7,%.2f;%d]"):format(top + 0.35, row.in_chests)
			parts[#parts + 1] = ("label[6.9,%.2f;%d]"):format(top + 0.35, row.carried)
			local missing = row.missing > 0 and core.colorize("#ff8a80", tostring(row.missing)) or tostring(row.missing)
			parts[#parts + 1] = ("label[7.9,%.2f;%s]"):format(top + 0.35, escape(missing))
			if row.price then
				local field = "buy_" .. i
				buttons[field] = row.item
				parts[#parts + 1] = ("label[8.9,%.2f;%s]"):format(top + 0.35,
					escape(core.colorize("#7fe08a", tostring(row.price))))
				parts[#parts + 1] = ("item_image[9.35,%.2f;0.5,0.5;%s]"):format(top + 0.1, escape(report.currency))
				parts[#parts + 1] = ("button[10.0,%.2f;1.3,0.7;%s;%s]"):format(top, field, escape(S("Buy 1")))
				parts[#parts + 1] = ("tooltip[%s;%s]"):format(field, escape(row.price == 1
					and S("One costs 1 emerald. It goes in the chest by the bench.")
					or S("One costs @1 emeralds. It goes in the chest by the bench.", tostring(row.price))))
			end
		end
		parts[#parts + 1] = "scroll_container_end[]"
		if #rows * ROW > list_height then
			parts[#parts + 1] = ("scrollbaroptions[max=%d]"):format(math.ceil((#rows * ROW - list_height) * 10))
			parts[#parts + 1] = ("scrollbar[%.1f,%.2f;0.3,%.2f;vertical;builder_rows;0]"):format(
				WIDTH - 0.6, list_top, list_height)
		end
		y = list_top + list_height + 0.2
	end

	if notice then
		parts[#parts + 1] = ("label[0.4,%.2f;%s]"):format(y + 0.2, escape(notice))
		y = y + 0.5
	end
	local height = y + 1.2
	parts[#parts + 1] = ("button[%.1f,%.2f;2.2,0.7;refresh;%s]"):format(WIDTH - 2.6, height - 0.9, escape(S("Refresh")))
	local head = ("formspec_version[4]size[%.1f,%.2f]label[0.4,0.35;%s]"):format(WIDTH, height, escape(S("Builder")))
	return head .. table.concat(parts), buttons
end

function M.show(player_name, villager, builder, notice)
	local report = builder.report(villager)
	local form, buttons = M.formspec(report, notice)
	open[player_name] = {villager = villager, builder = builder, buttons = buttons}
	core.show_formspec(player_name, FORM, form)
end

if core.register_on_player_receive_fields then
	core.register_on_player_receive_fields(function(player, formname, fields)
		if formname ~= FORM then return false end
		local name = player:get_player_name()
		local context = open[name]
		if not context then return true end
		if fields.quit then
			open[name] = nil
			return true
		end
		local villager = context.villager
		-- It may have died or unloaded with the window open.
		if not villager.object or not villager.object:get_pos() then
			open[name] = nil
			core.close_formspec(name, FORM)
			return true
		end
		local notice
		for field, item in pairs(context.buttons) do
			if fields[field] then
				local _, message = context.builder.buy(villager, player, item)
				notice = BUY_MESSAGES[message] or message
				break
			end
		end
		if notice or fields.refresh then M.show(name, villager, context.builder, notice) end
		return true
	end)
end
if core.register_on_leaveplayer then
	core.register_on_leaveplayer(function(player) open[player:get_player_name()] = nil end)
end

return M
