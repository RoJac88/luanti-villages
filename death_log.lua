-- What a villager was doing when it died, for the death line in init.lua's on_die (#84).
-- The cause alone says how, not why: "environment node acaciatree" fits a villager that
-- walked into a trunk and one a sapling grew around while it stood there. So the line
-- also gives its trade, the stage of its day, its labour and where that was taking it,
-- its hunger, and whether it died on a spot of its own grove (labour.lua). It records,
-- and changes nothing: a villager dying in the world is not assumed to be a fault.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")

local M = {}

local function pos_text(pos)
	return pos and string.format("(%d,%d,%d)", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5),
		math.floor(pos.z + 0.5)) or "-"
end

-- The grove spot (labour.lua's _villages_grove) within one node of pos, or nil.
local function grove_spot(self, pos)
	if not pos then return nil end
	for _, at in ipairs(self._villages_grove or {}) do
		if math.abs(at.x - pos.x) <= 1.5 and math.abs(at.z - pos.z) <= 1.5
			and math.abs(at.y - pos.y) <= 2 then
			return at
		end
	end
	return nil
end
M.grove_spot = grove_spot

-- ", profession X, stage Y, ..." for the death line.
function M.context(self, died_at)
	local parts = {}
	parts[#parts + 1] = "profession " .. tostring(self._profession)
	if self._villages_keeper then parts[#parts + 1] = "keeper" end
	local ok, stage = pcall(common.schedule_stage, nil, self)
	parts[#parts + 1] = "stage " .. tostring(ok and stage or "?")
	local labour = self._villages_labour
	if labour and labour.day == core.get_day_count() and labour.activity then
		parts[#parts + 1] = "labour " .. labour.activity
	end
	if self._villages_labour_target then
		parts[#parts + 1] = "heading for " .. pos_text(self._villages_labour_target)
	end
	local route = self._villages_goto_route
	if route and route.goal then parts[#parts + 1] = "route to " .. pos_text(route.goal) end
	parts[#parts + 1] = "state " .. tostring(self.state)
	local points
	ok, points = pcall(food.points, self)
	if ok and points then parts[#parts + 1] = string.format("food %.1f", points) end
	local spot = grove_spot(self, died_at)
	if spot then parts[#parts + 1] = "on its grove spot " .. pos_text(spot) end
	return ", " .. table.concat(parts, ", ")
end

return M
