-- Keeps the tavern's pantry (tavern_pantry.lua) stocked (docs/villager-economy-design.md,
-- ticket 1). Every generated tavern has a pantry: the stock schematic's chest stands 3
-- behind the jukebox, filled with ordinary village loot. So that its dinners go on, the
-- keeper supplies it:
--
-- * In its free hours, while the pantry holds fewer than its target, it walks to the
--   nearest farmer's work chest with food within SUPPLY_RADIUS of the jukebox (the chest
--   nearest a claimed composter, the one farmer.lua stores its surplus in). It takes up
--   to its carry of bread, potatoes and then carrots and carries them back to its jukebox, from where it
--   fills the pantry (a pantry chest behind the bar may have nowhere to stand by it).
--   Stocked to demand (ticket 22c): the target is the last evening's demand (dinner.demand:
--   meals served and guests it ran out on) and a quarter more (STOCK_MARGIN), at least TARGET_MEALS,
--   and it carries that many, at least CARRY and at most CARRY_MAX. A dish served as
--   seconds (meal.lua) counts as a meal. The margin (2026-11-16): stocked to exactly the
--   last evening's 21, the pantry was down to 5 after dinner, and one day the keeper
--   could not reach a farm chest left 16 without. ColonyRich, 2026-11-15: at a fixed 12
--   and 24, the tavern ran out most evenings, dinner rose to 13 and 352 potatoes sat in the
--   farm chest. Now a dinner in demand draws more food out, and its price falls back.
--   Only the farmer bakes bread, and only the butcher cooks meat and fish (recipes.lua):
--   the keeper buys those ready made.
-- * It buys what it takes (ticket 4): setting out, it takes up to PURSE emeralds from
--   the pantry (and, short there, from its own float, below), and leaves in the work
--   chest what the food is worth, for its farmer or
--   fisherman to collect: a meal's food cost (dinner.food_cost, its reference price for a
--   loaf, ticket 21e; DINNER until then) for each meal the food makes (MEALS: a loaf or a
--   potato is one). The tavern
--   keeps no margin, so dinner money, a player's too, passes through the pantry to the
--   food producers (ticket 11b; at vanilla's prices, rounded, 8 wheat paid nothing while
--   its dinners took 1 emerald each, and money piled up in the pantry). It takes only
--   the food its purse pays for (ticket 27): what is left of a whole emerald, a fraction,
--   it owes in the chest's `villages_keeper_tab` and pays first next time, up to TAB_CAP
--   (1). It used to take the food anyway and owe the rest, up to a cap that grew with
--   the tavern; in ColonyFood (2026-11-20) it owed the two farms 1,950, a quarter of the
--   village's money, as dinner sold at 1 for food it paid 1.2 for. A larger tab, from
--   then, is written off when it next fetches there. Food dearer than dinners pay for (it
--   could not pay for all it wanted, or paid from its float) moves the dinner price up
--   the next day, as running out does (dinner.dear). What it did not spend goes back in
--   the pantry.
-- * Over its shift at the jukebox it cooks the pantry's raw food into its menu, one dish
--   every COOK_SECONDS: a potato baked.
-- * Dishes it bought in conversation or on a trade trip (ticket 11e: cooked beef and
--   cooked fish from the butcher, bread from a farmer, keeper inputs in ledger.lua) go
--   from its belongings into the pantry on
--   its shift, before it cooks. It pays for them with the tavern's money: on shift it
--   tops its own emeralds up to FLOAT from the pantry, where dinner money goes, so it
--   does not run out of its starting money.
-- * A few of every dish (ticket 35): each dish it heard offered in the last week
--   (keeper.known_dishes), but its fixed inputs and the baked potato, it wants up to
--   keeper.MIN_DISHES of in the pantry (M.dish_wants, `_villages_dish_wants`, set on its
--   shift), at no more than its dinner price for one (possessions.assess), so the menu has
--   something new for a guest tired of the rest (ticket 34) and never at a loss. Every
--   prepared food is on the menu (keeper.dishes), and shelving takes from its stash too.
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
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local dinner = dofile(core.get_modpath("living_villages") .. "/dinner.lua")

local SUPPLY_RADIUS = 48
local COMPOSTER_HEIGHT = 8
local CARRY = 24
local CARRY_MAX = 64
local TARGET_MEALS = 12
local STOCK_MARGIN = 1.25
local CHECK_SECONDS = 30
local RETRY_SECONDS = 120
-- A source it could not walk to is passed over this long, so the next nearest gets a
-- turn rather than the keeper trying the nearest, and nothing else, for ever.
local SKIP_SECONDS = 600
local COOK_SECONDS = 10
-- In emeralds at ledger.SCALE (ticket 11h).
local PURSE = 8 * SCALE
local DINNER = ledger.DINNER
-- What it may owe a chest: a fraction of an emerald (ticket 27).
local TAB_CAP = 1
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
-- Carrots and beetroot are a last resort (meal.lua serves a raw plate of them with no
-- dish in the pantry, or to a guest who cannot pay a dinner), fetched after the rest, and
-- they count toward no meal the pantry holds.
local CARROT = "mcl_farming:carrot_item"
local CARROTS_PER_MEAL = 4
-- What it fetches, most wanted first.
local BEETROOT = "mcl_farming:beetroot_item"
local SUPPLIES = {BREAD, POTATO, CARROT, BEETROOT}
local RECIPES = {
	{from = POTATO, count = 1, to = "mcl_farming:potato_item_baked"},
}
-- Raw potatoes it never bakes, for RESERVE_PLATES raw plates (meal.lua, ticket 39h): a
-- starving guest always eats. They count toward no meal the pantry holds, so its fetches
-- bring them on top of its dinners.
local RESERVE_PLATES = 4
local RAW_RESERVE = {[POTATO] = RESERVE_PLATES * food.raw_portion(POTATO)}
local STARTING_STOCK = {{BREAD, 9}, {POTATO, 6}}
-- Dinners each supply makes.
local MEALS = {[BREAD] = 1, [POTATO] = 1, [CARROT] = 1 / CARROTS_PER_MEAL, [BEETROOT] = 1 / CARROTS_PER_MEAL}

local COMPOSTERS = {"mcl_composters:composter", "mcl_composters:composter_ready"}
for level = 1, 7 do COMPOSTERS[#COMPOSTERS + 1] = "mcl_composters:composter_" .. level end

local M = {
	SUPPLY_RADIUS = SUPPLY_RADIUS, CARRY = CARRY, CARRY_MAX = CARRY_MAX, TARGET_MEALS = TARGET_MEALS, STOCK_MARGIN = STOCK_MARGIN,
	CHECK_SECONDS = CHECK_SECONDS, RETRY_SECONDS = RETRY_SECONDS, SKIP_SECONDS = SKIP_SECONDS, COOK_SECONDS = COOK_SECONDS,
	STARTING_STOCK = STARTING_STOCK, PURSE = PURSE, DINNER = DINNER, TAB_CAP = TAB_CAP, TAB = TAB, FLOAT = FLOAT,
	RAW_RESERVE = RAW_RESERVE,
}

-- Every dish it serves (keeper.dishes, ticket 35: MENU's and any other prepared food).
local function menu_items()
	return keeper.dishes()
end

-- Ticket 35: for each dish it heard offered lately (keeper.known_dishes), how many short
-- of keeper.MIN_DISHES the pantry is, 0 for none. None for its fixed inputs (ledger.lua's keeper role,
-- wanted already) nor what it cooks itself (RECIPES).
function M.dish_wants(self, chests, day)
	local wants = {}
	local fixed = ledger.inputs("keeper")
	local cooked = {}
	for _, recipe in ipairs(RECIPES) do cooked[recipe.to] = true end
	for _, item in ipairs(keeper.known_dishes(self, day)) do
		if not fixed[item] and not cooked[item] then
			-- 0 for one it has enough of: still its own, so one it carries is never spare.
			wants[item] = math.max(keeper.MIN_DISHES - pantry.count(chests, item), 0)
		end
	end
	return wants
end

-- How much of a raw food the pantry holds past its raw plates' reserve (RAW_RESERVE).
function M.cookable(chests, item)
	return math.max(pantry.count(chests, item) - (RAW_RESERVE[item] or 0), 0)
end

-- How many dinners the pantry holds, counting what it can cook.
function M.meals(chests)
	local total = 0
	for _, item in ipairs(menu_items()) do total = total + pantry.count(chests, item) end
	for _, recipe in ipairs(RECIPES) do
		total = total + math.floor(M.cookable(chests, recipe.from) / recipe.count)
	end
	return total
end

local function is_pantry(chests, pos)
	for _, chest in ipairs(chests) do
		if vector.equals(chest, pos) then return true end
	end
	return false
end

-- Dinners' worth of supplies in a chest (MEALS).
local function meals_in(pos)
	local total = 0
	for _, item in ipairs(SUPPLIES) do total = total + stock.chest_count(pos, item) * MEALS[item] end
	return total
end

-- The farmer's work chest with the most meals to fetch, the nearest of equals, never a
-- pantry chest, nor one `skip(pos)` passes over. The nearest one always had all the
-- tavern's money: one farmer held 1169 emeralds while the other's chest held 345 potatoes
-- nobody fetched (ColonyFood, 2026-11-14). Taking from the fullest pays each farm for
-- what it grows.
function M.source(jukebox, chests, skip)
	local r = SUPPLY_RADIUS
	local minp = {x = jukebox.x - r, y = jukebox.y - COMPOSTER_HEIGHT, z = jukebox.z - r}
	local maxp = {x = jukebox.x + r, y = jukebox.y + COMPOSTER_HEIGHT, z = jukebox.z + r}
	local best, best_meals, best_distance
	local function consider(pos)
		if not pos or is_pantry(chests, pos) or (skip and skip(pos)) then return end
		local meals = meals_in(pos)
		if meals > 0 then
			local distance = vector.distance(pos, jukebox)
			if not best or meals > best_meals or (meals == best_meals and distance < best_distance) then
				best, best_meals, best_distance = pos, meals, distance
			end
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

-- The meals it stocks the pantry to, and carries a trip (ticket 22c).
function M.target(self)
	return math.max(TARGET_MEALS, math.ceil(dinner.demand(self) * STOCK_MARGIN))
end

function M.carry(self)
	return math.min(math.max(CARRY, M.target(self)), CARRY_MAX)
end

-- What it may owe a chest: a fraction (ticket 27; it grew with the tavern before).
function M.tab_cap()
	return TAB_CAP
end

-- What the keeper pays for goods, in emeralds, fractions kept: a meal's food cost at its
-- reference prices (dinner.food_cost) for each meal they make.
function M.worth(goods, keeper_self)
	local value = 0
	local cost = dinner.food_cost(keeper_self)
	for item, count in pairs(goods) do value = value + count * (MEALS[item] or 0) * cost end
	return value
end

-- What the keeper owes this chest from before.
function M.tab(pos)
	return tonumber(core.get_meta(pos):get_string(TAB)) or 0
end

-- What of its purse came from its own float, and the meals the pantry lacked when it
-- set out, per keeper (not saved).
local from_float = setmetatable({}, {__mode = "k"})
local lacking = setmetatable({}, {__mode = "k"})

-- Its purse: up to PURSE from the pantry, and, short there, from its own emeralds (the
-- float, refilled from the pantry on shift), so a pantry with no money left still buys
-- the food the next dinners pay for.
local function take_purse(self, chests)
	for _, chest in ipairs(chests) do
		local want = PURSE - stock.count(self, EMERALD)
		if want <= 0 then break end
		stock.take_from_chest(self, chest, EMERALD, want)
	end
	local short = math.min(PURSE - stock.count(self, EMERALD), possessions.emeralds(self))
	from_float[self] = nil
	if short > 0 then
		possessions.take(self, EMERALD, short)
		stock.add(self, EMERALD, short)
		from_float[self] = short
	end
end

-- Writes off a tab over TAB_CAP, from when it took food it could not pay for.
local function write_off(self, chest)
	local tab = M.tab(chest)
	if tab <= TAB_CAP then return end
	core.get_meta(chest):set_string(TAB, "")
	core.log("action", string.format("[living_villages] keeper %s wrote off %.2f emerald(s) it owed at %s",
		tostring(self._id), tab, core.pos_to_string(chest)))
end

-- Pays for what it took from the chest, and what it owed there, from its purse.
-- Returns what it paid and what it still owes.
function M.pay(self, chest, taken)
	local due = M.tab(chest) + M.worth(taken, self)
	local paid = stock.put_in_chest(self, chest, EMERALD, math.min(math.floor(due + EPSILON), stock.count(self, EMERALD)))
	local owed = due - paid
	local cap = M.tab_cap()
	if owed > cap then
		core.log("action", string.format("[living_villages] keeper %s forgave %.2f emerald(s) owed at %s",
			tostring(self._id), owed - cap, core.pos_to_string(chest)))
		owed = cap
	end
	if owed < EPSILON then owed = 0 end
	core.get_meta(chest):set_string(TAB, owed > 0 and string.format("%.4f", owed) or "")
	return paid, owed
end

local function fetch(self, chest)
	write_off(self, chest)
	local room = M.carry(self) - carried(self)
	local cost = dinner.food_cost(self)
	local purse = stock.count(self, EMERALD)
	local budget = purse - M.tab(chest)
	local taken, short, got = {}, 0, 0
	for _, item in ipairs(SUPPLIES) do
		if room <= 0 then break end
		local unit = MEALS[item] * cost
		local want = math.min(room, stock.chest_count(chest, item))
		local afford = unit > 0 and math.max(math.floor((budget + EPSILON) / unit), 0) or want
		local moved = stock.take_from_chest(self, chest, item, math.min(want, afford))
		if moved > 0 then taken[item] = moved end
		short = short + want - moved
		got = got + moved * MEALS[item]
		budget, room = budget - moved * unit, room - moved
	end
	local paid, owed = M.pay(self, chest, taken)
	core.log("action", string.format("[living_villages] keeper %s fetched %d food for the pantry, paying %d emerald(s), owing %.2f",
		tostring(self._id), carried(self), paid, owed))
	-- Dinners did not pay for the food: it went without some the pantry lacked, or paid
	-- from its float.
	local float = from_float[self] or 0
	if (short > 0 and got < (lacking[self] or 0)) or paid > purse - float + EPSILON then
		dinner.dear(self, core.get_day_count())
		core.log("action", string.format("[living_villages] keeper %s: food dearer than dinners pay (left %d it could not pay for, %d from its float)",
			tostring(self._id), short, math.max(math.min(paid - (purse - float), float), 0)))
	end
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
		if M.cookable(chests, recipe.from) >= recipe.count and pantry.has_room(chests, recipe.to, 1) then
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
	if M.meals(chests) >= M.target(self) then return end
	local source = M.source(jukebox, chests, skipped(self, now))
	if not source then
		self._villages_supply_next = now + RETRY_SECONDS
		return
	end
	take_purse(self, chests)
	lacking[self] = M.target(self) - M.meals(chests)
	go(self, source, now, function(entity) fetch(entity, source) end)
end

-- Moves the menu's dishes from its belongings, and its stash, where a porter leaves what
-- it bought (ticket 35), into the pantry. Returns how many.
function M.shelve(self, chests)
	local moved = 0
	local held = possessions.held(self)
	for _, item in ipairs(menu_items()) do
		local count = held[item] or 0
		while count > 0 and pantry.has_room(chests, item, 1) and possessions.take_held(self, item, 1) == 1 do
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

-- The keeper eats from its own pantry, free (2026-11-13: behind the bar, it never sat
-- down to dinner and starved all run). Once a day, at or below possessions.EAT_AT, the
-- dishes first, until above it; a starving keeper takes raw food too if there is no dish.
function M.feed_keeper(self, chests)
	local today = core.get_day_count()
	if self._villages_dined_day == today or food.points(self) > possessions.EAT_AT then return {} end
	local eaten = {}
	local function eat_from(items)
		for _, item in ipairs(items) do
			while food.points(self) <= possessions.EAT_AT and pantry.take(chests, item) do
				food.receive(self, item)
				eaten[#eaten + 1] = item
			end
		end
	end
	eat_from(menu_items())
	if food.points(self) <= 0 then eat_from({CARROT, BEETROOT, POTATO}) end
	if #eaten > 0 then
		self._villages_dined_day = today
		core.log("action", string.format("[living_villages] keeper %s ate %d from its pantry",
			tostring(self._id):sub(1, 6), #eaten))
	end
	return eaten
end

local function cook_tick(self, jukebox, now)
	if self.order ~= "work" or now < (self._villages_cook_next or 0) then return end
	self._villages_cook_next = now + COOK_SECONDS
	local chests = pantry.chests(jukebox)
	if chests then
		M.float(self, chests)
		M.shelve(self, chests)
		M.cook(chests)
		M.feed_keeper(self, chests)
		-- What it buys to keep a few of each dish it knows (possessions.assess).
		self._villages_dish_wants = M.dish_wants(self, chests, core.get_day_count())
	end
end

-- Each tick of a keeper's do_custom.
function M.step(self, now)
	if not self._villages_keeper or self.child or busy(self) then return end
	local jukebox = keeper.claimed_jukebox(self)
	if not jukebox then return end
	-- Its dinner price for the day, posted at the jukebox (dinner.lua, ticket 21e).
	dinner.settle(self, jukebox, core.get_day_count())
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
