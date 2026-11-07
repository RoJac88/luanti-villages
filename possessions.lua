-- What a villager owns (docs/villager-economy-design.md, ticket 2): its belongings, carried
-- with it, and its stash, a chest by its bed.
--
-- Belongings (`_villages_belongings`, item name to count) are kept apart from the work
-- pouch (`_villages_farm_pouch`, farm_stock.lua). The farmer, the Builder and the keeper
-- treat the pouch as goods for their job: they empty it into work chests, wait for it to
-- be empty, drop it when the job goes. A villager's emeralds and its own things must
-- survive all of that. Both drop where the villager dies.
--
-- Emeralds: 3 to 6 when a villager is first seen as an adult. A kit: the goods of its
-- profession (KITS), the first time it has one, once in its life, so taking a job away
-- and back cannot mint more.
--
-- The stash is the chest nearest its bed, within living_villages_stash_radius (8), that
-- no one else holds. A claim is written in the chest's meta: `villages_owner` (the
-- villager's _id) and `villages_owner_bed` (the bed it was claimed from). It belongs to
-- the bed, so a villager who takes a bed whose owner is gone (the bed names someone
-- else, or no one) takes the chest with what is in it. Work chests are never stashes:
-- the tavern's pantry (by a jukebox), a farm's chest (beside a composter), a Builder's
-- (by its bench). farm_stock.find_chests leaves stashes out, so farmers, Builders and
-- keepers never take from one.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")

local DEFAULT_STASH_RADIUS = 8
local STASH_HEIGHT = 3
local CLAIM_SECONDS = 60
local STACK = 64
local OWNER, OWNER_BED = "villages_owner", "villages_owner_bed"
local EMERALD = "mcl_core:emerald"
-- Work chests, and how near their node they are.
local PANTRY_RADIUS = 6
local WORKSHOP_RADIUS = 6
local JUKEBOX = "mcl_jukebox:jukebox"
local BENCH = "living_villages:builder_block"
local COMPOSTERS = {"mcl_composters:composter", "mcl_composters:composter_ready"}
for level = 1, 7 do COMPOSTERS[#COMPOSTERS + 1] = "mcl_composters:composter_" .. level end
local DOUBLE_HALVES = {["mcl_chests:chest_left"] = true, ["mcl_chests:chest_right"] = true}

-- What a profession starts with: a little of what it works with, from its trade table's
-- side of things. Professions not here start with emeralds only.
local KITS = {
	farmer = {{"mcl_farming:bread", 3}, {"mcl_farming:wheat_seeds", 8}},
	fisherman = {{"mcl_fishing:fish_raw", 4}},
	shepherd = {{"mcl_wool:white", 4}},
	fletcher = {{"mcl_core:stick", 16}, {"mcl_core:flint", 4}},
	librarian = {{"mcl_core:paper", 8}},
	cartographer = {{"mcl_core:paper", 8}},
	armorer = {{"mcl_core:iron_ingot", 3}, {"mcl_core:coal_lump", 4}},
	weapon_smith = {{"mcl_core:iron_ingot", 3}, {"mcl_core:coal_lump", 4}},
	tool_smith = {{"mcl_core:iron_ingot", 2}, {"mcl_core:coal_lump", 4}, {"mcl_core:stick", 4}},
	leatherworker = {{"mcl_mobitems:leather", 4}},
	butcher = {{"mcl_mobitems:porkchop", 4}, {"mcl_core:coal_lump", 4}},
	cleric = {{"mcl_potions:glass_bottle", 4}},
	mason = {{"mcl_core:clay_lump", 8}, {"mcl_core:stone", 8}},
}

local M = {KITS = KITS, EMERALD = EMERALD, OWNER = OWNER, OWNER_BED = OWNER_BED, CLAIM_SECONDS = CLAIM_SECONDS}

-- Belongings.

local function belongings(self)
	self._villages_belongings = self._villages_belongings or {}
	return self._villages_belongings
end

function M.count(self, name)
	local held = self._villages_belongings
	return held and held[name] or 0
end

function M.total(self)
	local total = 0
	for _, count in pairs(self._villages_belongings or {}) do total = total + count end
	return total
end

function M.add(self, name, count)
	local held = belongings(self)
	held[name] = (held[name] or 0) + (count or 1)
end

-- Takes up to count. Returns how many.
function M.take(self, name, count)
	local held = self._villages_belongings
	local have = held and held[name] or 0
	local taken = math.min(have, count or 1)
	if taken <= 0 then return 0 end
	held[name] = have - taken > 0 and have - taken or nil
	if not next(held) then self._villages_belongings = nil end
	return taken
end

function M.emeralds(self)
	return M.count(self, EMERALD)
end

function M.drop_all(self, pos)
	local held = self._villages_belongings
	if not held or not pos then return end
	self._villages_belongings = nil
	for name, count in pairs(held) do
		while count > 0 do
			local stack = math.min(count, STACK)
			core.add_item(pos, name .. " " .. stack)
			count = count - stack
		end
	end
end

-- A number from 0 to n - 1 that is always the same for this villager.
local function roll(self, n)
	local sum = 0
	for i = 1, #tostring(self._id) do sum = sum + tostring(self._id):byte(i) * i end
	return sum % n
end

-- Emeralds when first seen as an adult; a kit the first time it has a profession that has one.
function M.endow(self)
	if self.child or not self._id then return false end
	local given = false
	if not self._villages_endowed then
		M.add(self, EMERALD, 3 + roll(self, 4))
		self._villages_endowed = true
		given = true
	end
	local kit = KITS[self._profession]
	if kit and not self._villages_kit then
		for _, entry in ipairs(kit) do M.add(self, entry[1], entry[2]) end
		self._villages_kit = self._profession
		given = true
	end
	if given then
		core.log("action", string.format("[living_villages] villager %s (%s) now owns %s",
			tostring(self._id), tostring(self._profession), M.status(self)))
	end
	return given
end

-- The stash.

local function stash_radius()
	local value = core.settings and tonumber(core.settings:get("living_villages_stash_radius"))
	return value or DEFAULT_STASH_RADIUS
end

local function near(pos, radius, names)
	return #core.find_nodes_in_area(
		{x = pos.x - radius, y = pos.y - radius, z = pos.z - radius},
		{x = pos.x + radius, y = pos.y + radius, z = pos.z + radius}, names) > 0
end

-- A chest that does a job: the tavern's pantry, a farm's chest, a Builder's.
function M.is_work_chest(pos)
	return near(pos, PANTRY_RADIUS, {JUKEBOX}) or near(pos, 1, COMPOSTERS) or near(pos, WORKSHOP_RADIUS, {BENCH})
end

-- Whether the villager the chest names still holds the bed it was claimed from.
local function holder_present(meta)
	local owner = meta:get_string(OWNER)
	if owner == "" then return false end
	local bed = core.string_to_pos(meta:get_string(OWNER_BED))
	return bed ~= nil and core.get_meta(bed):get_string("villager") == owner
end

-- The chest and, if it is half of a double chest, its other half.
local function halves(pos)
	local found = {pos}
	local node = core.get_node_or_nil(pos)
	if node and DOUBLE_HALVES[node.name] then
		for _, other in ipairs(core.find_nodes_in_area(vector.subtract(pos, 1), vector.add(pos, 1), stock.CHEST_NODES)) do
			if vector.distance(other, pos) == 1 then
				local other_node = core.get_node_or_nil(other)
				if other_node and DOUBLE_HALVES[other_node.name] then table.insert(found, other) end
			end
		end
	end
	return found
end

local function set_owner(pos, id, bed)
	for _, half in ipairs(halves(pos)) do
		local meta = core.get_meta(half)
		meta:set_string(OWNER, id or "")
		meta:set_string(OWNER_BED, bed and core.pos_to_string(bed) or "")
	end
end

local function owned_by(pos, self)
	local node = core.get_node_or_nil(pos)
	if not node then return false end
	local is_chest = false
	for _, name in ipairs(stock.CHEST_NODES) do
		if node.name == name then is_chest = true end
	end
	return is_chest and core.get_meta(pos):get_string(OWNER) == self._id
end

-- The villager's stash, claiming one if it has none or its bed moved. Nil without a bed.
function M.claim_stash(self)
	local bed = self._bed
	if self.child or not self._id or not bed then return nil end
	local radius = stash_radius()
	local current = self._villages_stash
	if current and owned_by(current, self) and vector.distance(current, bed) <= radius * 2 then
		local claimed_from = core.string_to_pos(core.get_meta(current):get_string(OWNER_BED))
		if claimed_from and vector.equals(claimed_from, bed) then return current end
	end
	if current and owned_by(current, self) then set_owner(current, nil, nil) end
	self._villages_stash = nil
	local chests = core.find_nodes_in_area(
		{x = bed.x - radius, y = bed.y - STASH_HEIGHT, z = bed.z - radius},
		{x = bed.x + radius, y = bed.y + STASH_HEIGHT, z = bed.z + radius}, stock.CHEST_NODES)
	table.sort(chests, function(a, b) return vector.distance(a, bed) < vector.distance(b, bed) end)
	for _, pos in ipairs(chests) do
		local meta = core.get_meta(pos)
		local owner = meta:get_string(OWNER)
		if not core.is_protected(pos, "") and meta:get_inventory():get_size("main") > 0
			and not M.is_work_chest(pos)
			and (owner == "" or owner == self._id or not holder_present(meta)) then
			if owner ~= "" and owner ~= self._id then
				core.log("action", string.format("[living_villages] villager %s inherits the stash at %s from %s",
					tostring(self._id), core.pos_to_string(pos), owner))
			elseif owner == "" then
				core.log("action", string.format("[living_villages] villager %s claims the stash at %s",
					tostring(self._id), core.pos_to_string(pos)))
			end
			set_owner(pos, self._id, bed)
			self._villages_stash = vector.new(pos)
			return pos
		end
	end
	return nil
end

local next_check = setmetatable({}, {__mode = "k"})

function M.step(self, now)
	if self.child or not self._id or now < (next_check[self] or 0) then return end
	next_check[self] = now + CLAIM_SECONDS
	M.endow(self)
	M.claim_stash(self)
end

function M.install(def)
	if not clock.enabled() then return end
	local original_custom = def.do_custom
	def.do_custom = function(self, dtime)
		M.step(self, core.get_gametime())
		return original_custom(self, dtime)
	end
	local original_die = def.on_die
	def.on_die = function(self, pos, cause)
		M.drop_all(self, pos or self.object:get_pos())
		if original_die then return original_die(self, pos, cause) end
	end
end

-- One line each for the Lookup Tool inspector (diagnostic.lua).
function M.status(self)
	local parts = {}
	for name, count in pairs(self._villages_belongings or {}) do
		table.insert(parts, count .. " " .. name:gsub("^.*:", ""))
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "none"
end

function M.stash_status(self)
	local stash = self._villages_stash
	if not stash then return "none" end
	return core.pos_to_string(stash) .. (owned_by(stash, self) and "" or " (claim lost)")
end

return M
