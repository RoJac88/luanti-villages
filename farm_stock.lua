-- What a farmer carries and stores. VoxeLibre's villagers have no inventory, so the
-- pouch is a plain table of item name to count on the villager, which mcl_mobs saves
-- with the rest of its fields.
--
-- Storage is whatever chests are already near the farm, generated or a player's. A
-- farmer never places one. Trapped chests would set off whatever they are wired to,
-- and an ender chest belongs to a player.
local core = minetest

local POUCH_CAPACITY = 128
-- The most one harvest can yield, so a harvest always fits when it starts.
local HARVEST_ROOM = 8
local STACK = 64
local DEFAULT_CHEST_RADIUS = 32
local CHEST_HEIGHT = 8
-- mcl_chests:chest is what a village schematic holds until an LBM renames it.
local CHEST_NODES = {
	"mcl_chests:chest", "mcl_chests:chest_small", "mcl_chests:chest_left", "mcl_chests:chest_right",
}

local M = {CAPACITY = POUCH_CAPACITY}

local function pouch_of(self)
	self._villages_farm_pouch = self._villages_farm_pouch or {}
	return self._villages_farm_pouch
end

function M.count(self, name)
	local pouch = self._villages_farm_pouch
	return pouch and pouch[name] or 0
end

function M.total(self)
	local total = 0
	for _, count in pairs(self._villages_farm_pouch or {}) do total = total + count end
	return total
end

function M.add(self, name, count)
	local pouch = pouch_of(self)
	pouch[name] = (pouch[name] or 0) + (count or 1)
end

-- An item string as core.get_node_drops gives it: "name" or "name count".
function M.add_itemstring(self, itemstring)
	local name, count = itemstring:match("^(%S+)%s*(%d*)")
	if not name then return end
	M.add(self, name, tonumber(count) or 1)
end

-- Takes up to count and returns how many it got.
function M.take(self, name, count)
	local pouch = self._villages_farm_pouch
	local held = pouch and pouch[name] or 0
	local taken = math.min(held, count or 1)
	if taken <= 0 then return 0 end
	pouch[name] = held > taken and held - taken or nil
	return taken
end

function M.has_harvest_room(self)
	return M.total(self) + HARVEST_ROOM <= POUCH_CAPACITY
end

-- A farmer's goods go with it: these are real items now, not a stand-in.
function M.drop_all(self, pos)
	local pouch = self._villages_farm_pouch
	if not pouch or not pos then return end
	self._villages_farm_pouch = nil
	for name, count in pairs(pouch) do
		while count > 0 do
			local stack = math.min(count, STACK)
			core.add_item(pos, name .. " " .. stack)
			count = count - stack
		end
	end
end

local function chest_radius()
	return tonumber(core.settings and core.settings:get("living_villages_farmer_chest_radius")) or DEFAULT_CHEST_RADIUS
end

function M.may_withdraw()
	return not core.settings or core.settings:get_bool("living_villages_farmer_chest_withdraw", true)
end

local function chest_inventory(pos)
	local inv = core.get_meta(pos):get_inventory()
	if inv:get_size("main") == 0 then return nil end
	return inv
end

local function is_chest(pos)
	local node = core.get_node_or_nil(pos)
	if not node then return false end
	for _, name in ipairs(CHEST_NODES) do
		if node.name == name then return true end
	end
	return false
end

-- The chests a farm can use, nearest the composter first.
function M.find_chests(job)
	local radius = chest_radius()
	if radius <= 0 then return {} end
	local minp = {x = job.x - radius, y = job.y - CHEST_HEIGHT, z = job.z - radius}
	local maxp = {x = job.x + radius, y = job.y + CHEST_HEIGHT, z = job.z + radius}
	local chests = {}
	for _, pos in ipairs(core.find_nodes_in_area(minp, maxp, CHEST_NODES)) do
		if not core.is_protected(pos, "") and chest_inventory(pos) then table.insert(chests, pos) end
	end
	table.sort(chests, function(a, b) return vector.distance(a, job) < vector.distance(b, job) end)
	return chests
end

-- Moves up to count of the item from the pouch to the chest, keeping what does not
-- fit. Returns how many moved, and whether it all fitted.
function M.put_in_chest(self, pos, name, count)
	if not is_chest(pos) or core.is_protected(pos, "") then return 0, false end
	local inv = chest_inventory(pos)
	if not inv then return 0, false end
	local taken = M.take(self, name, count)
	if taken == 0 then return 0, true end
	local left = inv:add_item("main", name .. " " .. taken):get_count()
	if left > 0 then M.add(self, name, left) end
	return taken - left, left == 0
end

-- Moves up to count of the item from the chest to the pouch. Returns how many.
function M.take_from_chest(self, pos, name, count)
	if not is_chest(pos) or core.is_protected(pos, "") then return 0 end
	local inv = chest_inventory(pos)
	if not inv then return 0 end
	local moved = inv:remove_item("main", name .. " " .. count):get_count()
	if moved > 0 then M.add(self, name, moved) end
	return moved
end

-- How many of the item are in the chest.
function M.chest_count(pos, name)
	local inv = chest_inventory(pos)
	local total = 0
	for _, stack in ipairs(inv and inv:get_list("main") or {}) do
		if stack:get_name() == name then total = total + stack:get_count() end
	end
	return total
end

return M
