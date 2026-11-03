-- What a farmer carries. VoxeLibre's villagers have no inventory, so the pouch is
-- a plain table of item name to count on the villager, which mcl_mobs saves with
-- the rest of its fields.
local core = minetest

local POUCH_CAPACITY = 128
-- The most one harvest can yield, so a harvest always fits when it starts.
local HARVEST_ROOM = 8
local STACK = 64

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

return M
