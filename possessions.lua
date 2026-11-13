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
--
-- It eats what it owns (ticket 4), once a day: dinner is at the tavern (meal.lua, which
-- marks the day in `_villages_dined_day`), and one that did not dine there (no tavern in
-- reach, nothing in its pantry, no money) eats its own prepared food (food.is_prepared)
-- in the home stage that follows, at or below EAT_AT points, until above it. Between
-- dinners it eats only when starving: anything it has, raw food too, until hungry
-- (food.HUNGRY) instead of starving. It takes the best food in its belongings, then in
-- its stash if it stands within STASH_REACH of it. An adult never fed
-- (`_villages_food` unset, never 0 once set) starts at EAT_AT points: fed, not full.
-- Otherwise a new village starts out starving, crafting nothing and restocking nothing
-- (production.lua).
--
-- A starving villager walks slower (STARVING_SPEED of its speed, kept in
-- `_villages_slowed` until it eats) and stops work early (`_villages_starving`, which
-- common.lua's schedule reads).
--
-- Food it owns, in points (belongings and stash), is what makes a villager a parent
-- (births.lua): at least PARENT_FOOD each, a sign of a village that eats well. A birth
-- takes none of it.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local wants = dofile(core.get_modpath("living_villages") .. "/wants.lua")
local tally = dofile(core.get_modpath("living_villages") .. "/economy_tally.lua")
local asks = dofile(core.get_modpath("living_villages") .. "/asks.lua")

local DEFAULT_STASH_RADIUS = 8
local STASH_HEIGHT = 3
local CLAIM_SECONDS = 60
local STACK = 64
local OWNER, OWNER_BED = "villages_owner", "villages_owner_bed"
local EMERALD = "mcl_core:emerald"
-- herd.lua's HERD_WHEAT, held by a leatherworker for breeding (ticket 11e).
local HERD_WHEAT_ITEM, HERD_WHEAT = "mcl_farming:wheat_item", 4
-- market_stall.lua's banner and BANNER_DAYS (ticket 12): a stall keeper wants a banner.
local BANNER, BANNER_DAYS = "mcl_banners:banner_item_white", 3
-- Work chests, and how near their node they are.
local PANTRY_RADIUS = 6
local WORKSHOP_RADIUS = 6
local JUKEBOX = "mcl_jukebox:jukebox"
local BENCH = "living_villages:builder_block"
local COMPOSTERS = {"mcl_composters:composter", "mcl_composters:composter_ready"}
for level = 1, 7 do COMPOSTERS[#COMPOSTERS + 1] = "mcl_composters:composter_" .. level end
-- It eats at or below this many points, one item at a time, best first.
local EAT_AT = food.FULL - food.HUNGRY
local STASH_REACH = 4
-- How often it looks at its food: the home stage after dinner is a game hour, 50 s.
local EAT_CHECK_SECONDS = 10
local STARVING_SPEED = 0.7
-- Food points each parent must own: two days of food.
local PARENT_FOOD = 8
local DOUBLE_HALVES = {["mcl_chests:chest_left"] = true, ["mcl_chests:chest_right"] = true}

-- What a profession starts with: a little of what it works with, from its trade table's
-- side of things, enough for a crafting profession (recipes.lua) to make its first goods.
-- Professions not here start with emeralds only.
local KITS = {
	farmer = {{"mcl_farming:bread", 3}, {"mcl_farming:wheat_seeds", 8}},
	fisherman = {{"mcl_fishing:fish_raw", 4}},
	shepherd = {{"mcl_wool:white", 4}},
	fletcher = {{"mcl_core:stick", 16}, {"mcl_core:flint", 4}, {"mcl_mobitems:feather", 4}},
	librarian = {{"mcl_core:paper", 8}, {"mcl_mobitems:leather", 2}},
	cartographer = {{"mcl_core:paper", 8}},
	armorer = {{"mcl_core:iron_ingot", 4}, {"mcl_core:coal_lump", 4}},
	weapon_smith = {{"mcl_core:iron_ingot", 3}, {"mcl_core:coal_lump", 4}, {"mcl_core:stick", 2}},
	tool_smith = {{"mcl_core:iron_ingot", 2}, {"mcl_core:coal_lump", 4}, {"mcl_core:stick", 4}, {"mcl_core:cobble", 6}},
	leatherworker = {{"mcl_mobitems:leather", 4}},
	butcher = {{"mcl_mobitems:porkchop", 4}, {"mcl_core:coal_lump", 4}},
	cleric = {{"mcl_potions:glass_bottle", 4}},
	mason = {{"mcl_core:clay_lump", 8}, {"mcl_core:stone", 8}},
}

local M = {
	KITS = KITS, EMERALD = EMERALD, OWNER = OWNER, OWNER_BED = OWNER_BED, CLAIM_SECONDS = CLAIM_SECONDS, EAT_AT = EAT_AT,
	STARVING_SPEED = STARVING_SPEED, PARENT_FOOD = PARENT_FOOD,
}

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
-- One endowed before prices scaled (`_villages_emerald_scale` unset) has its emeralds
-- multiplied up to ledger.SCALE once.
function M.endow(self)
	if self.child or not self._id then return false end
	local given = false
	if not self._villages_endowed then
		M.add(self, EMERALD, (3 + roll(self, 4)) * ledger.SCALE)
		self._villages_endowed, self._villages_emerald_scale = true, ledger.SCALE
		given = true
	elseif self._villages_emerald_scale ~= ledger.SCALE then
		-- Endowed at vanilla's prices (before ticket 11h): its emeralds scale once.
		local held = M.emeralds(self)
		if held > 0 then M.add(self, EMERALD, held * (ledger.SCALE / (self._villages_emerald_scale or 1) - 1)) end
		self._villages_emerald_scale = ledger.SCALE
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

-- The tavern's pantry or a farm's chest: whatever emeralds are in it are its keeper's
-- or its farmer's (dinner money, pay for food), never a Builder's purse or a rent drop.
function M.is_food_chest(pos)
	return near(pos, PANTRY_RADIUS, {JUKEBOX}) or near(pos, 1, COMPOSTERS)
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

M.halves = halves

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

-- Foods, most points first.
local FOODS_BY_POINTS = {}
for item in pairs(food.POINTS) do FOODS_BY_POINTS[#FOODS_BY_POINTS + 1] = item end
table.sort(FOODS_BY_POINTS, function(a, b)
	if food.POINTS[a] ~= food.POINTS[b] then return food.POINTS[a] > food.POINTS[b] end
	return a < b
end)
-- The last resorts (food.LAST_RESORT) after every food: a starving villager eats them only
-- once it has nothing else.
local last_resorts = {}
for item in pairs(food.LAST_RESORT) do last_resorts[#last_resorts + 1] = item end
table.sort(last_resorts)
for _, item in ipairs(last_resorts) do FOODS_BY_POINTS[#FOODS_BY_POINTS + 1] = item end
M.FOODS_BY_POINTS = FOODS_BY_POINTS

-- Food points in its belongings.
function M.food_carried(self)
	local total = 0
	for item, points in pairs(food.POINTS) do total = total + M.count(self, item) * points end
	return total
end

local function stash_food(self, allowed)
	local stash = self._villages_stash
	local pos = self.object and self.object:get_pos()
	if not stash or not pos or vector.distance(pos, stash) > STASH_REACH or not owned_by(stash, self) then return nil end
	for _, item in ipairs(FOODS_BY_POINTS) do
		if allowed(item) then
			for _, half in ipairs(halves(stash)) do
				local inv = core.get_meta(half):get_inventory()
				if inv:remove_item("main", item .. " 1"):get_count() == 1 then return item end
			end
		end
	end
	return nil
end

-- The villager's stage of the day; common.lua's, loaded when first asked (a test may set it).
function M.stage_of(self)
	M.common = M.common or dofile(core.get_modpath("living_villages") .. "/common.lua")
	return M.common.schedule_stage(nil, self)
end

local function today()
	return core.get_day_count and core.get_day_count() or 0
end

-- Whether it may eat now: "starving" (anything, up to food.HUNGRY), "dinner" (its own
-- prepared food in the home stage after a dinner it did not have at the tavern, up to
-- above EAT_AT), or nil.
function M.meal_now(self)
	if self.child or self._villages_sleeping then return nil end
	local points = food.points(self)
	if points <= 0 then return "starving" end
	if points <= EAT_AT and self._villages_dined_day ~= today() and M.stage_of(self) == "home" then return "dinner" end
	return nil
end

-- Eats from its belongings, then its stash, as meal_now allows (or `meal`, the same
-- kinds). Returns what it ate.
function M.eat(self, meal)
	meal = meal or M.meal_now(self)
	if not meal or self.child or self._villages_sleeping then return {} end
	local allowed = meal == "dinner" and food.is_prepared
		or function(item) return food.POINTS[item] ~= nil or food.LAST_RESORT[item] ~= nil end
	local function more()
		if meal == "dinner" then return food.points(self) <= EAT_AT end
		return food.points(self) < food.HUNGRY
	end
	local eaten = {}
	while more() do
		local item
		for _, candidate in ipairs(FOODS_BY_POINTS) do
			if allowed(candidate) and M.take(self, candidate, 1) == 1 then item = candidate break end
		end
		item = item or stash_food(self, allowed)
		if not item then break end
		food.receive(self, item)
		eaten[#eaten + 1] = item
		tally.note(self, nil, {[item] = 1})
	end
	if meal == "dinner" and #eaten > 0 then self._villages_dined_day = today() end
	if #eaten > 0 and self.object and core.sound_play then
		core.sound_play("mcl_hunger_bite", {max_hear_distance = 12, gain = 0.33, object = self.object}, true)
	end
	return eaten
end

-- Food points it owns: belongings and stash.
function M.food_owned(self)
	local total = 0
	for item, count in pairs(M.held(self)) do total = total + (food.POINTS[item] or 0) * count end
	return total
end

-- Whether it owns food enough to become a parent (births.lua).
function M.can_parent(self)
	return not food.births_need_food() or M.food_owned(self) >= PARENT_FOOD
end

-- Slows a starving villager and marks it for common.lua's shorter working day; puts it
-- back once it is not.
function M.apply_hunger(self)
	local starving = not self.child and food.state(self) == "starving"
	self._villages_starving = starving or nil
	local slowed = self._villages_slowed
	if starving and not slowed then
		self._villages_slowed = {walk = self.walk_velocity, run = self.run_velocity}
		if self.walk_velocity then self.walk_velocity = self.walk_velocity * STARVING_SPEED end
		if self.run_velocity then self.run_velocity = self.run_velocity * STARVING_SPEED end
	elseif not starving and slowed then
		self.walk_velocity, self.run_velocity = slowed.walk, slowed.run
		self._villages_slowed = nil
	end
	return starving
end

local next_check = setmetatable({}, {__mode = "k"})
local next_meal = setmetatable({}, {__mode = "k"})

function M.step(self, now)
	if self.child or not self._id then return end
	if now >= (next_meal[self] or 0) then
		next_meal[self] = now + EAT_CHECK_SECONDS
		if self._villages_food == nil then self._villages_food = EAT_AT end
		M.eat(self)
		M.apply_hunger(self)
	end
	if now < (next_check[self] or 0) then return end
	next_check[self] = now + CLAIM_SECONDS
	M.endow(self)
	M.claim_stash(self)
	-- Its asks for what it did not sell yesterday come down (asks.lua).
	local day = today()
	if self._villages_asks_day ~= day then asks.daily(self, M.assess(self).surplus, day) end
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

-- What it holds: its belongings and its stash's contents.
function M.held(self)
	local held = {}
	for name, count in pairs(self._villages_belongings or {}) do held[name] = count end
	local stash = self._villages_stash
	if stash and owned_by(stash, self) then
		for _, pos in ipairs(halves(stash)) do
			for _, item in ipairs(core.get_meta(pos):get_inventory():get_list("main") or {}) do
				if not item:is_empty() then held[item:get_name()] = (held[item:get_name()] or 0) + item:get_count() end
			end
		end
	end
	return held
end

-- Takes up to count of the item from its belongings, then its stash wherever it stands
-- (a craftsman brings what it needs from home: production.lua). Returns how many.
function M.take_held(self, name, count)
	local taken = M.take(self, name, count)
	local stash = self._villages_stash
	if taken >= count or not stash or not owned_by(stash, self) then return taken end
	for _, half in ipairs(halves(stash)) do
		local inv = core.get_meta(half):get_inventory()
		taken = taken + inv:remove_item("main", name .. " " .. (count - taken)):get_count()
		if taken >= count then break end
	end
	return taken
end

-- Whether two beds are in one house: within 5 across and 4 up or down, as near as beds
-- tell (the farmer's household, the keeper's).
function M.same_house(a, b)
	return a ~= nil and b ~= nil and math.abs(a.x - b.x) <= 5 and math.abs(a.z - b.z) <= 5 and math.abs(a.y - b.y) <= 4
end

-- The ledger's view of this villager (ledger.lua): its targets, needs, surplus and values.
-- A keeper by its role; a Builder (a mason to vanilla, builder.lua) has no trade of its own.
function M.assess(self)
	local extra, worth = wants.targets(self)
	for item, count in pairs(self._villages_builder and self._villages_builder_wants or {}) do
		extra[item] = (extra[item] or 0) + count
	end
	-- A leatherworker breeds its herd on wheat (herd.lua's HERD_WHEAT).
	if self._profession == "leatherworker" and not self.child then
		extra[HERD_WHEAT_ITEM] = (extra[HERD_WHEAT_ITEM] or 0) + HERD_WHEAT
	end
	-- One that kept a stall lately and has no banner flying wants one, worth no more than
	-- its price (market_stall.lua).
	local stall_day, day = self._villages_stall_day, core.get_day_count and core.get_day_count()
	if stall_day and day and day - stall_day <= BANNER_DAYS and (self._villages_banner_left or 0) <= 0 then
		extra[BANNER] = (extra[BANNER] or 0) + 1
		worth[BANNER] = math.min(worth[BANNER] or math.huge, ledger.price(BANNER) or math.huge)
	end
	-- A peddler (labour.lua): buying, it wants its lot at its bid and no more; holding it,
	-- it takes no less than the bid, so it never sells at a loss.
	local least
	local peddle = self._villages_peddle
	if peddle then
		if peddle.buying then
			extra[peddle.item] = (extra[peddle.item] or 0) + peddle.count
			worth[peddle.item] = peddle.bid
		end
		least = {[peddle.item] = peddle.bid}
	end
	return ledger.assess({
		id = self._id,
		profession = (self._villages_keeper and "keeper") or (self._villages_builder and "builder") or self._profession,
		max_tier = self._max_trade_tier or 1,
		held = M.held(self),
		food_points = food.points(self),
		hunger_per_day = self.child and 0 or food.hunger_per_day(),
		foods = food.POINTS,
		-- What a Builder's chests are short of (builder_market.lua), and goods that wear out (wants.lua).
		extra = extra,
		worth = worth,
		least = least,
		-- What it believes things are worth (prices.lua).
		prices = self._villages_prices,
	})
end

local function list_status(list, value)
	local parts = {}
	for _, entry in ipairs(ledger.top(list, value, 5)) do
		table.insert(parts, entry.count .. " " .. entry.item:gsub("^.*:", ""))
	end
	return #parts > 0 and table.concat(parts, ", ") or "none"
end

-- Its five largest needs and surpluses, for the inspector.
function M.ledger_status(self)
	local view = M.assess(self)
	return list_status(view.needs, view.value), list_status(view.surplus, view.value)
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
