-- Keeps the tavern's pantry (tavern_pantry.lua) stocked (docs/villager-economy-design.md,
-- ticket 1). Every generated tavern has a pantry: the stock schematic's chest stands 3
-- behind the jukebox, filled with ordinary village loot. So that its dinners go on, the
-- keeper supplies it:
--
-- * In its free hours, while the pantry holds fewer than TARGET_MEALS, it walks to the
--   nearest work chest with food within SUPPLY_RADIUS of the jukebox: a farmer's (the
--   chest nearest a claimed composter, the one farmer.lua stores its surplus in) or a
--   fisherman's claimed barrel, where fisherman.lua puts its cod. It takes up to CARRY of
--   bread, potatoes, cod and wheat and carries them back to its jukebox, from where it fills
--   the pantry (a pantry chest behind the bar may have nowhere to stand by it).
-- * It buys what it takes (ticket 4): setting out, it takes up to PURSE emeralds from
--   the pantry, and leaves in the work chest what the food will sell for as dinners, for
--   its farmer or fisherman to collect: DINNER (meal.lua's VILLAGER_PRICE) for each meal
--   the food makes (MEALS: a loaf, a potato or a cod is one, wheat a third). The tavern
--   keeps no margin, so dinner money, a player's too, passes through the pantry to the
--   food producers (ticket 11b; at vanilla's prices, rounded, 8 wheat paid nothing while
--   its dinners took 1 emerald each, and money piled up in the pantry). What it cannot
--   pay in whole emeralds, a fraction or an empty purse, it owes in the chest's
--   `villages_keeper_tab` and pays first next time, up to TAB_CAP; past that it is
--   forgiven (the keeper's household eats free, so more goes out than comes in). It takes
--   the food anyway, so the tavern keeps feeding the village. What it did not spend goes
--   back in the pantry.
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
local PURSE = 8
local DINNER = 1
local TAB_CAP = 8
local TAB = "villages_keeper_tab"
-- The tab is kept to 4 places: a third and two thirds written down must still make one.
local EPSILON = 1e-3
local EMERALD = "mcl_core:emerald"
-- How near the chest a walk must end for the keeper to reach into it.
local REACH = 3

local BREAD = "mcl_farming:bread"
local WHEAT = "mcl_farming:wheat_item"
local POTATO = "mcl_farming:potato_item"
local COD = "mcl_fishing:fish_raw"
-- What it fetches, most wanted first.
local SUPPLIES = {BREAD, POTATO, COD, WHEAT}
local RECIPES = {
	{from = WHEAT, count = 3, to = BREAD},
	{from = POTATO, count = 1, to = "mcl_farming:potato_item_baked"},
	{from = COD, count = 1, to = "mcl_fishing:fish_cooked"},
}
local STARTING_STOCK = {{BREAD, 6}, {WHEAT, 9}, {POTATO, 6}}
-- Dinners each supply makes.
local MEALS = {[BREAD] = 1, [POTATO] = 1, [COD] = 1, [WHEAT] = 1 / 3}

local COMPOSTERS = {"mcl_composters:composter", "mcl_composters:composter_ready"}
for level = 1, 7 do COMPOSTERS[#COMPOSTERS + 1] = "mcl_composters:composter_" .. level end

local M = {
	SUPPLY_RADIUS = SUPPLY_RADIUS, CARRY = CARRY, TARGET_MEALS = TARGET_MEALS,
	CHECK_SECONDS = CHECK_SECONDS, RETRY_SECONDS = RETRY_SECONDS, COOK_SECONDS = COOK_SECONDS,
	STARTING_STOCK = STARTING_STOCK, PURSE = PURSE, DINNER = DINNER, TAB_CAP = TAB_CAP, TAB = TAB,
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

-- The nearest work chest with something to fetch, a farmer's or a fisherman's barrel,
-- never a pantry chest.
function M.source(jukebox, chests)
	local r = SUPPLY_RADIUS
	local minp = {x = jukebox.x - r, y = jukebox.y - COMPOSTER_HEIGHT, z = jukebox.z - r}
	local maxp = {x = jukebox.x + r, y = jukebox.y + COMPOSTER_HEIGHT, z = jukebox.z + r}
	local best, best_distance
	local function consider(pos)
		if pos and not is_pantry(chests, pos) and supplies_in(pos) then
			local distance = vector.distance(pos, jukebox)
			if not best or distance < best_distance then best, best_distance = pos, distance end
		end
	end
	for _, composter in ipairs(core.find_nodes_in_area(minp, maxp, COMPOSTERS)) do
		if core.get_meta(composter):get_string("villager") ~= "" then consider(stock.find_chests(composter)[1]) end
	end
	for _, barrel in ipairs(core.find_nodes_in_area(minp, maxp, stock.BARREL_NODES)) do
		if core.get_meta(barrel):get_string("villager") ~= "" then consider(barrel) end
	end
	return best
end

local function carried(self)
	local total = 0
	for _, item in ipairs(SUPPLIES) do total = total + stock.count(self, item) end
	return total
end

-- What goods will sell for as dinners, in emeralds, fractions kept.
function M.worth(goods)
	local value = 0
	for item, count in pairs(goods) do value = value + count * (MEALS[item] or 0) * DINNER end
	return value
end

-- What the keeper owes this chest from before.
function M.tab(pos)
	return tonumber(core.get_meta(pos):get_string(TAB)) or 0
end

local function take_purse(self, chests)
	for _, chest in ipairs(chests) do
		local want = PURSE - stock.count(self, EMERALD)
		if want <= 0 then break end
		stock.take_from_chest(self, chest, EMERALD, want)
	end
end

-- Pays for what it took from the chest, and what it owed there, from its purse.
-- Returns what it paid and what it still owes.
function M.pay(self, chest, taken)
	local due = M.tab(chest) + M.worth(taken)
	local paid = stock.put_in_chest(self, chest, EMERALD, math.min(math.floor(due + EPSILON), stock.count(self, EMERALD)))
	local owed = due - paid
	if owed > TAB_CAP then
		core.log("action", string.format("[living_villages] keeper %s forgave %.2f emerald(s) owed at %s",
			tostring(self._id), owed - TAB_CAP, core.pos_to_string(chest)))
		owed = TAB_CAP
	end
	if owed < EPSILON then owed = 0 end
	core.get_meta(chest):set_string(TAB, owed > 0 and string.format("%.4f", owed) or "")
	return paid, owed
end

local function fetch(self, chest)
	local room = CARRY - carried(self)
	local taken = {}
	for _, item in ipairs(SUPPLIES) do
		if room <= 0 then break end
		local moved = stock.take_from_chest(self, chest, item, room)
		if moved > 0 then taken[item] = moved end
		room = room - moved
	end
	local paid, owed = M.pay(self, chest, taken)
	core.log("action", string.format("[living_villages] keeper %s fetched %d food for the pantry, paying %d emerald(s), owing %.2f",
		tostring(self._id), carried(self), paid, owed))
end

local function deliver(self, jukebox)
	local chests = pantry.chests(jukebox)
	if not chests then return end
	local delivered = 0
	local goods = {EMERALD}
	for _, item in ipairs(SUPPLIES) do goods[#goods + 1] = item end
	for _, item in ipairs(goods) do
		for _, chest in ipairs(chests) do
			local count = stock.count(self, item)
			if count == 0 then break end
			local moved = stock.put_in_chest(self, chest, item, count)
			if item ~= EMERALD then delivered = delivered + moved end
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
		if pos and vector.distance(pos, target) <= REACH then
			arrive(entity)
		else
			core.log("action", string.format("[living_villages] keeper %s stopped %s short of %s",
				tostring(entity._id):sub(1, 6), pos and string.format("%.1f", vector.distance(pos, target)) or "?",
				core.pos_to_string(target)))
		end
	end, true)
	if started == false then
		self._villages_supply_target = nil
		self._villages_supply_next = now + RETRY_SECONDS
		core.log("action", string.format("[living_villages] keeper %s found no way to %s",
			tostring(self._id):sub(1, 6), core.pos_to_string(target)))
	end
end

local function supply(self, jukebox, now)
	if self._villages_supply_target then
		-- The walk ended without arriving: try again later.
		local route, pos = self._villages_goto_route, self.object:get_pos()
		core.log("action", string.format("[living_villages] keeper %s gave up walking to %s (%s away, state %s, route %s)",
			tostring(self._id):sub(1, 6), core.pos_to_string(self._villages_supply_target),
			pos and string.format("%.1f", vector.distance(pos, self._villages_supply_target)) or "?", tostring(self.state),
			route and (tostring(route.status) .. "/" .. tostring(route.reason)) or "none"))
		self._villages_supply_target = nil
		self._villages_supply_next = now + RETRY_SECONDS
		return
	end
	if now < (self._villages_supply_next or 0) then return end
	self._villages_supply_next = now + CHECK_SECONDS
	local chests = pantry.chests(jukebox)
	if not chests then return end
	-- Delivered from beside the jukebox, its own post, which it reaches every shift: a
	-- pantry chest behind the bar may have nowhere to stand by it (seed 2007's tavern).
	if carried(self) > 0 then
		return go(self, jukebox, now, function(entity) deliver(entity, jukebox) end)
	end
	if M.meals(chests) >= TARGET_MEALS then return end
	local source = M.source(jukebox, chests)
	if not source then
		self._villages_supply_next = now + RETRY_SECONDS
		return
	end
	take_purse(self, chests)
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
