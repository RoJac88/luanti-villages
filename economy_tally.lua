-- What a villager made and used, today and yesterday (docs/villager-economy-design.md,
-- What the player sees, Visibility; ticket 10), for the Builder's bench Economy tab
-- (economy_report.lua). It lives on the villager, in `_villages_tally`:
--
--   {day, made = {item = count}, used = {item = count}, last = {day, made, used}}
--
-- `last` is the day before `day`, kept when the day turns; anything older is dropped.
-- production.lua notes crafts (output made, inputs and fuel used), labour.lua gathering
-- and charcoal, possessions.lua meals. No state is kept here, so every dofile of it is
-- the same.
local core = minetest

local M = {}

local function add(list, item, count)
	list[item] = (list[item] or 0) + count
end

-- Notes what it made and used: {item = count} each, either may be nil.
function M.note(self, made, used, day)
	day = day or (core.get_day_count and core.get_day_count()) or 0
	local tally = self._villages_tally
	if not tally or tally.day ~= day then
		local last
		if tally and tally.day == day - 1 then last = {day = tally.day, made = tally.made, used = tally.used} end
		tally = {day = day, made = {}, used = {}, last = last}
		self._villages_tally = tally
	end
	for item, count in pairs(made or {}) do add(tally.made, item, count) end
	for item, count in pairs(used or {}) do add(tally.used, item, count) end
end

-- What it made and used on `day`, or nil for each.
function M.on(self, day)
	local tally = self._villages_tally
	if not tally then return nil, nil end
	if tally.day == day then return tally.made, tally.used end
	if tally.last and tally.last.day == day then return tally.last.made, tally.last.used end
	return nil, nil
end

local function list_text(list)
	local parts = {}
	for item, count in pairs(list or {}) do parts[#parts + 1] = count .. " " .. item:gsub("^.*:", "") end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

-- Today's made and used, for the inspector.
function M.status(self, day)
	local made, used = M.on(self, day or (core.get_day_count and core.get_day_count()) or 0)
	return "made " .. list_text(made) .. "; used " .. list_text(used)
end

return M
