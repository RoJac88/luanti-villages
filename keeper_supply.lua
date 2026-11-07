-- Keeps the tavern's pantry (tavern_pantry.lua) stocked (docs/villager-economy-design.md,
-- ticket 1). Every generated tavern has a pantry: the stock schematic's chest stands 3
-- behind the jukebox, filled with ordinary village loot. So that its dinners go on, the
-- keeper supplies it:
--
-- * In its free hours, while the pantry holds fewer than TARGET_MEALS, it walks to the
--   work chest of a farmer near the tavern (the chest nearest a claimed composter, the one
--   farmer.lua stores its surplus in, within SUPPLY_RADIUS of the jukebox), takes up to
--   CARRY of bread, potatoes and wheat, and carries them back. Ticket 4 turns this into
--   buying.
-- * Over its shift at the jukebox it cooks the pantry's raw food into its menu, one dish
--   every COOK_SECONDS: three wheat to a loaf, a potato baked, a raw cod cooked.
-- * A newly generated tavern's chest gets STARTING_STOCK on top of its loot, through
--   settlements.fill_chest, which the village generator calls for every chest it places.
--
-- What it carries goes in the pouch (farm_stock.lua). Nothing is saved but the pouch and
-- the times of the next check and dish; the trip itself is a planned walk like any other.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local pantry = dofile(core.get_modpath("living_villages") .. "/tavern_pantry.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local keeper = dofile(core.get_modpath("living_villages") .. "/keeper.lua")

local SUPPLY_RADIUS = 48
local COMPOSTER_HEIGHT = 8
local CARRY = 24
local TARGET_MEALS = 12
local CHECK_SECONDS = 30
local RETRY_SECONDS = 120
local COOK_SECONDS = 10
-- How near the chest a walk must end for the keeper to reach into it.
local REACH = 3

local BREAD = "mcl_farming:bread"
local WHEAT = "mcl_farming:wheat_item"
local POTATO = "mcl_farming:potato_item"
local COD = "mcl_fishing:fish_raw"
-- What it fetches, most wanted first.
local SUPPLIES = {BREAD, POTATO, WHEAT}
local RECIPES = {
	{from = WHEAT, count = 3, to = BREAD},
	{from = POTATO, count = 1, to = "mcl_farming:potato_item_baked"},
	{from = COD, count = 1, to = "mcl_fishing:fish_cooked"},
}
local STARTING_STOCK = {{BREAD, 6}, {WHEAT, 9}, {POTATO, 6}}

local COMPOSTERS = {"mcl_composters:composter", "mcl_composters:composter_ready"}
for level = 1, 7 do COMPOSTERS[#COMPOSTERS + 1] = "mcl_composters:composter_" .. level end

local M = {
	SUPPLY_RADIUS = SUPPLY_RADIUS, CARRY = CARRY, TARGET_MEALS = TARGET_MEALS,
	CHECK_SECONDS = CHECK_SECONDS, RETRY_SECONDS = RETRY_SECONDS, COOK_SECONDS = COOK_SECONDS,
	STARTING_STOCK = STARTING_STOCK,
}

local function menu_items()
	local items = {}
	for _, entry in ipairs(keeper.MENU) do items[#items + 1] = entry.offered end
	return items
end

-- How many dinners the pantry holds, counting what it can cook.
function M.meals(chests)
	local total = 0
	for _, item in ipairs(menu_items()) do total = total + pantry.count(chests, item) end
	for _, recipe in ipairs(RECIPES) do
		total = total + math.floor(pantry.count(chests, recipe.from) / recipe.count)
	end
	return total
end

local function is_pantry(chests, pos)
	for _, chest in ipairs(chests) do
		if vector.equals(chest, pos) then return true end
	end
	return false
end

local function supplies_in(pos)
	for _, item in ipairs(SUPPLIES) do
		if stock.chest_count(pos, item) > 0 then return true end
	end
	return false
end

-- The nearest farmer's work chest with something to fetch, never a pantry chest.
function M.source(jukebox, chests)
	local r = SUPPLY_RADIUS
	local best, best_distance
	for _, composter in ipairs(core.find_nodes_in_area(
		{x = jukebox.x - r, y = jukebox.y - COMPOSTER_HEIGHT, z = jukebox.z - r},
		{x = jukebox.x + r, y = jukebox.y + COMPOSTER_HEIGHT, z = jukebox.z + r}, COMPOSTERS)) do
		if core.get_meta(composter):get_string("villager") ~= "" then
			local own = stock.find_chests(composter)[1]
			if own and not is_pantry(chests, own) and supplies_in(own) then
				local distance = vector.distance(own, jukebox)
				if not best or distance < best_distance then best, best_distance = own, distance end
			end
		end
	end
	return best
end

local function carried(self)
	local total = 0
	for _, item in ipairs(SUPPLIES) do total = total + stock.count(self, item) end
	return total
end

local function fetch(self, chest)
	local room = CARRY - carried(self)
	for _, item in ipairs(SUPPLIES) do
		if room <= 0 then break end
		room = room - stock.take_from_chest(self, chest, item, room)
	end
	core.log("action", string.format("[living_villages] keeper %s fetched %d food for the pantry",
		tostring(self._id), carried(self)))
end

local function deliver(self, jukebox)
	local chests = pantry.chests(jukebox)
	if not chests then return end
	local delivered = 0
	for _, item in ipairs(SUPPLIES) do
		for _, chest in ipairs(chests) do
			local count = stock.count(self, item)
			if count == 0 then break end
			delivered = delivered + stock.put_in_chest(self, chest, item, count)
		end
	end
	core.log("action", string.format("[living_villages] keeper %s stocked the pantry with %d food",
		tostring(self._id), delivered))
end

-- One dish, if the pantry holds what it takes and there is room for it.
function M.cook(chests)
	for _, recipe in ipairs(RECIPES) do
		if pantry.count(chests, recipe.from) >= recipe.count and pantry.has_room(chests, recipe.to, 1) then
			for _ = 1, recipe.count do pantry.take(chests, recipe.from) end
			pantry.put(chests, recipe.to, 1)
			return recipe.to
		end
	end
end

local function busy(self)
	local walk = self._villages_goto_route
	return self.state == "gowp" or self.following ~= nil or (walk ~= nil and walk.status == "planning")
end

local function go(self, target, now, arrive)
	self._villages_supply_target = vector.new(target)
	local started = self:gopath(target, function(entity)
		entity._villages_supply_target = nil
		local pos = entity.object:get_pos()
		if pos and vector.distance(pos, target) <= REACH then arrive(entity) end
	end, true)
	if started == false then
		self._villages_supply_target = nil
		self._villages_supply_next = now + RETRY_SECONDS
	end
end

local function supply(self, jukebox, now)
	if self._villages_supply_target then
		-- The walk ended without arriving: try again later.
		self._villages_supply_target = nil
		self._villages_supply_next = now + RETRY_SECONDS
		return
	end
	if now < (self._villages_supply_next or 0) then return end
	self._villages_supply_next = now + CHECK_SECONDS
	local chests = pantry.chests(jukebox)
	if not chests then return end
	if carried(self) > 0 then
		return go(self, chests[1], now, function(entity) deliver(entity, jukebox) end)
	end
	if M.meals(chests) >= TARGET_MEALS then return end
	local source = M.source(jukebox, chests)
	if not source then
		self._villages_supply_next = now + RETRY_SECONDS
		return
	end
	go(self, source, now, function(entity) fetch(entity, source) end)
end

local function cook_tick(self, jukebox, now)
	if self.order ~= "work" or now < (self._villages_cook_next or 0) then return end
	self._villages_cook_next = now + COOK_SECONDS
	local chests = pantry.chests(jukebox)
	if chests then M.cook(chests) end
end

-- Each tick of a keeper's do_custom.
function M.step(self, now)
	if not self._villages_keeper or self.child or busy(self) then return end
	local jukebox = keeper.claimed_jukebox(self)
	if not jukebox then return end
	local stage = common.schedule_stage(nil, self)
	if stage == "staff" then
		cook_tick(self, jukebox, now)
	elseif stage == "free" then
		supply(self, jukebox, now)
	else
		self._villages_supply_target = nil
	end
end

-- Adds the starting stock to a chest the village generator fills, if it is a pantry.
function M.stock_new_pantry(pos)
	local r = pantry.RADIUS
	if #core.find_nodes_in_area({x = pos.x - r, y = pos.y - r, z = pos.z - r},
		{x = pos.x + r, y = pos.y + r, z = pos.z + r}, {"mcl_jukebox:jukebox"}) == 0 then
		return false
	end
	local chests = {pos}
	for _, entry in ipairs(STARTING_STOCK) do pantry.put(chests, entry[1], entry[2]) end
	core.log("action", "[living_villages] stocked a new tavern pantry at " .. core.pos_to_string(pos))
	return true
end

function M.install(def)
	if not clock.enabled() then return end
	local original = def.do_custom
	def.do_custom = function(self, dtime)
		local result = original(self, dtime)
		if result ~= false then M.step(self, core.get_gametime()) end
		return result
	end
	if settlements and settlements.fill_chest then
		local original_fill = settlements.fill_chest
		settlements.fill_chest = function(pos, ...)
			local result = original_fill(pos, ...)
			M.stock_new_pantry(pos)
			return result
		end
	end
end

return M
