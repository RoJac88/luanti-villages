-- Keeps the tavern's pantry (tavern_pantry.lua) stocked (docs/villager-economy-design.md,
-- ticket 1). Every generated tavern has a pantry: the stock schematic's chest stands 3
-- behind the jukebox, filled with ordinary village loot. So that its dinners go on, the
-- keeper supplies it:
--
-- * In its free hours, while the pantry holds fewer than TARGET_MEALS, it walks to the
--   nearest farmer's work chest with food within SUPPLY_RADIUS of the jukebox (the chest
--   nearest a claimed composter, the one farmer.lua stores its surplus in). It takes up
--   to CARRY of bread, potatoes and then carrots and carries them back to its jukebox, from where it
--   fills the pantry (a pantry chest behind the bar may have nowhere to stand by it).
--   Only the farmer bakes bread, and only the butcher cooks meat and fish (recipes.lua):
--   the keeper buys those ready made.
-- * It buys what it takes (ticket 4): setting out, it takes up to PURSE emeralds from
--   the pantry, and leaves in the work chest what the food will sell for as dinners, for
--   its farmer or fisherman to collect: DINNER (meal.lua's VILLAGER_PRICE) for each meal
--   the food makes (MEALS: a loaf or a potato is one). The tavern
--   keeps no margin, so dinner money, a player's too, passes through the pantry to the
--   food producers (ticket 11b; at vanilla's prices, rounded, 8 wheat paid nothing while
--   its dinners took 1 emerald each, and money piled up in the pantry). What it cannot
--   pay in whole emeralds, a fraction or an empty purse, it owes in the chest's
--   `villages_keeper_tab` and pays first next time, up to TAB_CAP; past that it is
--   forgiven (the keeper's household eats free, so more goes out than comes in). It takes
--   the food anyway, so the tavern keeps feeding the village. What it did not spend goes
--   back in the pantry.
-- * Over its shift at the jukebox it cooks the pantry's raw food into its menu, one dish
--   every COOK_SECONDS: a potato baked.
-- * Dishes it bought in conversation or on a trade trip (ticket 11e: cooked beef and
--   cooked fish from the butcher, bread from a farmer, keeper inputs in ledger.lua) go
--   from its belongings into the pantry on
--   its shift, before it cooks. It pays for them with the tavern's money: on shift it
--   tops its own emeralds up to FLOAT from the pantry, where dinner money goes, so it
--   does not run out of its starting money.
-- * A newly generated tavern's chest gets STARTING_STOCK on top of its loot, through
--   settlements.fill_chest, which the village generator calls for every chest it places.
--
-- What it carries goes in the pouch (farm_stock.lua). Nothing is saved but the pouch and
-- the times of the next check and dish; the trip itself is a planned walk like any other.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local SCALE = ledger.SCALE
local pantry = dofile(core.get_modpath("living_villages") .. "/tavern_pantry.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local keeper = dofile(core.get_modpath("living_villages") .. "/keeper.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")

local SUPPLY_RADIUS = 48
local COMPOSTER_HEIGHT = 8
local CARRY = 24
local TARGET_MEALS = 12
local CHECK_SECONDS = 30
local RETRY_SECONDS = 120
-- A source it could not walk to is passed over this long, so the next nearest gets a
-- turn rather than the keeper trying the nearest, and nothing else, for ever.
local SKIP_SECONDS = 600
local COOK_SECONDS = 10
-- In emeralds at ledger.SCALE (ticket 11h).
local PURSE = 8 * SCALE
local DINNER = ledger.DINNER
local TAB_CAP = 8 * SCALE
-- What it keeps on it from the pantry, for the dishes it buys: the whole purse, so a
-- dish dear in a short week is still within its reach (run of 2026-11-13: eight dinners'
-- 144 could not buy one cooked salmon while the pantry held 530).
local FLOAT = PURSE
local TAB = "villages_keeper_tab"
-- The tab is kept to 4 places: a third and two thirds written down must still make one.
local EPSILON = 1e-3
local EMERALD = "mcl_core:emerald"
-- How near the chest a walk must end for the keeper to reach into it.
local REACH = 3

local BREAD = "mcl_farming:bread"
local POTATO = "mcl_farming:potato_item"
-- Carrots are a last resort (meal.lua serves a plate of them only with no dish in the
-- pantry), fetched after the rest, and they count toward no meal the pantry holds.
local CARROT = "mcl_farming:carrot_item"
local CARROTS_PER_MEAL = 4
-- What it fetches, most wanted first.
local SUPPLIES = {BREAD, POTATO, CARROT}
local RECIPES = {
	{from = POTATO, count = 1, to = "mcl_farming:potato_item_baked"},
}
local STARTING_STOCK = {{BREAD, 9}, {POTATO, 6}}
-- Dinners each supply makes.
local MEALS = {[BREAD] = 1, [POTATO] = 1, [CARROT] = 1 / CARROTS_PER_MEAL}

local COMPOSTERS = {"mcl_composters:composter", "mcl_composters:composter_ready"}
for level = 1, 7 do COMPOSTERS[#COMPOSTERS + 1] = "mcl_composters:composter_" .. level end

local M = {
	SUPPLY_RADIUS = SUPPLY_RADIUS, CARRY = CARRY, TARGET_MEALS = TARGET_MEALS,
	CHECK_SECONDS = CHECK_SECONDS, RETRY_SECONDS = RETRY_SECONDS, SKIP_SECONDS = SKIP_SECONDS, COOK_SECONDS = COOK_SECONDS,
	STARTING_STOCK = STARTING_STOCK, PURSE = PURSE, DINNER = DINNER, TAB_CAP = TAB_CAP, TAB = TAB, FLOAT = FLOAT,
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

-- The nearest farmer's work chest with something to fetch, never a pantry chest, nor
-- one `skip(pos)` passes over.
function M.source(jukebox, chests, skip)
	local r = SUPPLY_RADIUS
	local minp = {x = jukebox.x - r, y = jukebox.y - COMPOSTER_HEIGHT, z = jukebox.z - r}
	local maxp = {x = jukebox.x + r, y = jukebox.y + COMPOSTER_HEIGHT, z = jukebox.z + r}
	local best, best_distance
	local function consider(pos)
		if pos and not is_pantry(chests, pos) and not (skip and skip(pos)) and supplies_in(pos) then
			local distance = vector.distance(pos, jukebox)
			if not best or distance < best_distance then best, best_distance = pos, distance end
		end
	end
	for _, composter in ipairs(core.find_nodes_in_area(minp, maxp, COMPOSTERS)) do
		if core.get_meta(composter):get_string("villager") ~= "" then consider(stock.find_chests(composter)[1]) end
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

-- Sources each keeper could not reach, by position, until when. Not saved.
local unreachable = setmetatable({}, {__mode = "k"})

local function spot(pos)
	return string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
end

local function skipped(self, now)
	return function(pos)
		local list = unreachable[self]
		return list ~= nil and (list[spot(pos)] or 0) > now
	end
end

local function pass_over(self, target, now)
	if not target then return end
	unreachable[self] = unreachable[self] or {}
	unreachable[self][spot(target)] = now + SKIP_SECONDS
end

local function go(self, target, now, arrive)
	self._villages_supply_target = vector.new(target)
	local started = self:gopath(target, function(entity)
		entity._villages_supply_target = nil
		local pos = entity.object:get_pos()
		if pos and vector.distance(pos, target) <= REACH then
			arrive(entity)
		else
			pass_over(entity, target, core.get_gametime())
			core.log("action", string.format("[living_villages] keeper %s stopped %s short of %s",
				tostring(entity._id):sub(1, 6), pos and string.format("%.1f", vector.distance(pos, target)) or "?",
				core.pos_to_string(target)))
		end
	end, true)
	if started == false then
		self._villages_supply_target = nil
		self._villages_supply_next = now + RETRY_SECONDS
		pass_over(self, target, now)
		core.log("action", string.format("[living_villages] keeper %s found no way to %s, passing it over for %d s",
			tostring(self._id):sub(1, 6), core.pos_to_string(target), SKIP_SECONDS))
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
		pass_over(self, self._villages_supply_target, now)
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
	local source = M.source(jukebox, chests, skipped(self, now))
	if not source then
		self._villages_supply_next = now + RETRY_SECONDS
		return
	end
	take_purse(self, chests)
	go(self, source, now, function(entity) fetch(entity, source) end)
end

-- Moves the menu's dishes from its belongings into the pantry. Returns how many.
function M.shelve(self, chests)
	local moved = 0
	for _, item in ipairs(menu_items()) do
		local count = possessions.count(self, item)
		while count > 0 and pantry.has_room(chests, item, 1) do
			possessions.take(self, item, 1)
			pantry.put(chests, item, 1)
			count, moved = count - 1, moved + 1
		end
	end
	if moved > 0 then
		core.log("action", string.format("[living_villages] keeper %s put %d bought dishes in the pantry",
			tostring(self._id):sub(1, 6), moved))
	end
	return moved
end

-- Tops its emeralds up to FLOAT from the pantry. Returns how many it took.
function M.float(self, chests)
	local short = FLOAT - possessions.emeralds(self)
	local taken = 0
	while taken < short and pantry.take(chests, EMERALD) do taken = taken + 1 end
	if taken > 0 then possessions.add(self, EMERALD, taken) end
	return taken
end

local function cook_tick(self, jukebox, now)
	if self.order ~= "work" or now < (self._villages_cook_next or 0) then return end
	self._villages_cook_next = now + COOK_SECONDS
	local chests = pantry.chests(jukebox)
	if chests then
		M.float(self, chests)
		M.shelve(self, chests)
		M.cook(chests)
	end
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
