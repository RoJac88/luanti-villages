-- A testing aid: `/giveme build_project_materials` hands the player what the nearest Builder
-- waiting for materials still lacks. Anything else typed after /giveme goes to the engine's
-- command as usual, so it needs the same `give` privilege.
local core = minetest

local M = {}

local KEYWORD = "build_project_materials"
local STATE = "requires_materials"
-- Further off than this, vanilla has suspended the villager anyway.
local RADIUS = 48

-- The Builders near a position, nearest first, with what each one reports.
local function builders_near(pos, builder)
	local found = {}
	for _, object in ipairs(core.get_objects_inside_radius(pos, RADIUS)) do
		local entity = object.get_luaentity and object:get_luaentity()
		local at = object:get_pos()
		if entity and entity._villages_builder and at then
			found[#found + 1] = {report = builder.report(entity), distance = vector.distance(pos, at)}
		end
	end
	table.sort(found, function(a, b) return a.distance < b.distance end)
	return found
end

local function held(inv, item)
	local count = 0
	for _, stack in ipairs(inv:get_list("main")) do
		if stack:get_name() == item then count = count + stack:get_count() end
	end
	return count
end

-- Tops the player's inventory up to what is missing, so running it twice gives nothing more.
-- Returns whether it did, and a line for the chat.
function M.give(player, builder)
	local near = builders_near(player:get_pos(), builder)
	if #near == 0 then
		return false, ("No Builder within %d nodes. Nothing given."):format(RADIUS)
	end
	local chosen
	for _, entry in ipairs(near) do
		if entry.report.state == STATE then
			chosen = entry.report
			break
		end
	end
	if not chosen then
		return false, ("The nearest Builder is not waiting for materials (state: %s). Nothing given."):format(
			near[1].report.state)
	end

	local inv = player:get_inventory()
	local given, left_out = 0, {}
	for _, row in ipairs(chosen.rows or {}) do
		local count = row.missing - held(inv, row.item)
		if count > 0 then
			local left = inv:add_item("main", row.item .. " " .. count):get_count()
			given = given + count - left
			if left > 0 then left_out[#left_out + 1] = row.item .. " " .. left end
		end
	end
	core.log("action", string.format("[living_villages] %s took %d items for a builder's %s by command",
		player:get_player_name(), given, tostring(chosen.building)))
	local message
	if given == 0 and #left_out == 0 then
		message = ("You already hold what the Builder's %s is missing. It counts only once it is in a chest near "
			.. "its bench."):format(tostring(chosen.building))
	else
		message = ("Added %d %s to your inventory for the Builder's %s. They count only once they are in a chest "
			.. "near its bench."):format(given, given == 1 and "item" or "items", tostring(chosen.building))
	end
	if #left_out > 0 then
		message = message .. " Your inventory is full, so these are left: " .. table.concat(left_out, ", ")
			.. ". Make room and run it again."
	end
	return true, message
end

function M.install(builder)
	if not core.override_chatcommand or not core.registered_chatcommands then return end
	local original = core.registered_chatcommands.giveme
	if not original then return end
	local original_func = original.func
	core.override_chatcommand("giveme", {
		params = original.params .. " | " .. KEYWORD,
		func = function(name, param)
			if param:match("^%s*(.-)%s*$") ~= KEYWORD then return original_func(name, param) end
			local player = core.get_player_by_name(name)
			if not player then return false, "You must be in the game to use this." end
			return M.give(player, builder)
		end,
	})
end

return M
