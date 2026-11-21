-- Dinner (#100): a seated guest (seat.lua, #99) is served a meal on the plate
-- in front of it by the keeper staffing its tavern, eats it, and the plate
-- empties. At most one meal per guest per evening.
--
-- The meal is a display only. It is this mod's own entity, never saved
-- (static_save = false), shown where the plate would show an item; the
-- plate's inventory is never written. There is no stack to take, a player's
-- item on a plate is never touched, and a plate a player puts something on
-- mid-meal simply clears the meal. The frame's own code looks only for its
-- mcl_itemframes:item entity, so it never mistakes the meal for its item.
--
-- A player at a tavern table (#19) is served by the same loop: player_meals.lua
-- passes a diner table that stands in for a villager (_id, _villages_seat.table,
-- object, _villages_meal_day, and optionally _villages_mouth_at
-- (a function giving the mouth position) and _villages_on_bite, called on each bite).
--
-- Where the tavern has a pantry (tavern_pantry.lua), the meal is real: only what the
-- pantry holds is served, the plate's item comes out of it, a villager guest gets its
-- food points (food.lua) when served, and a diner with a price (a player,
-- player_meals.lua) pays into the pantry first. Without one, the meal is a display, as
-- it always was.
--
-- A villager guest pays too (ticket 8, once crafting gives every profession something
-- to sell): the keeper's posted dinner price (dinner.lua, ticket 21e; ledger.DINNER where
-- none was ever posted) from its belongings (possessions.lua) into the pantry, unless it
-- is the keeper or of the keeper's household (possessions.same_house), who eat free, or
-- the cleric (ticket 24) with no more than CLERIC_SAVINGS. A cleric over that pays, and
-- always dines (ticket 27). It
-- dines only when the price is no more than a meal is worth to it (dinner.wants);
-- otherwise it eats its own food, or buys some. A guest who would not pay while dishes
-- were left, and one who would have paid but found none, move the keeper's price for the
-- next day. At a pantry it is served only when it has room for a meal, at or below
-- possessions.EAT_AT points. A villager guest served a dish is served more, one after
-- another and each at the same price, while it is still at or below EAT_AT, up to
-- MAX_DISHES in all (seconds, below). Served, it has had its dinner for the day
-- (`_villages_dined_day`); one that was not eats its own food at home afterwards
-- (possessions.lua). One that cannot pay is not served. Each payment is
-- logged (ticket 11b), so a probe run shows where the money goes.
--
-- News at the tavern: once an evening, a villager seated at a tavern whose keeper is on
-- duty swaps market news with the keeper (market_news.exchange), served or not. The
-- keeper hears every diner, so it carries what one needs to another that has it: in
-- run 50 a farmer had four conversations in three hours and never heard of the tool
-- smith's hoe. `_villages_tavern_news` holds the day.
--
-- Variety (ticket 34, variety.lua): a villager guest is served the dish it is least tired
-- of, values a dinner by the best of the dishes on offer (dinner.wants), and each dish
-- served is noted on the keeper, whose buying follows what its guests ate.
--
-- Load this once, at top-level load time (init.lua): it registers the entity,
-- which Luanti allows only then, and the plate holds are its own in-memory
-- table.
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local keeper = dofile(core.get_modpath("living_villages") .. "/keeper.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local pantry = dofile(core.get_modpath("living_villages") .. "/tavern_pantry.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local news = dofile(core.get_modpath("living_villages") .. "/market_news.lua")
local dinner = dofile(core.get_modpath("living_villages") .. "/dinner.lua")
local variety = dofile(core.get_modpath("living_villages") .. "/variety.lua")
local ENTITY = "living_villages:meal"
local PLATE = "mcl_itemframes:plate"
-- A guest waits this long after sitting down before it is served.
local WAIT_SECONDS = 2
-- A keeper serves one plate at a time, this often.
local SERVE_SECONDS = 2
-- How long a meal lasts, and how often the guest takes a bite.
local EAT_SECONDS = 6
local BITE_SECONDS = 0.4
-- A plate hold lapses unless renewed, so one left by a guest that unloaded
-- frees itself.
local HOLD_SECONDS = 5
-- A raw plate (2026-11-13): raw food, as much as makes about a dish's points
-- (food.raw_portion: 4 potatoes, carrots or beetroot, 4 raw fish). A villager guest who can
-- pay a dinner gets one at dinner's price when the pantry holds no dish; one who cannot, or
-- a starving one that will not, gets only this, for BROKE_PRICE, and a starving one with no
-- emerald at all gets it free (ticket 39h). Before 39h only carrots and beetroot made one,
-- 4 of either, and the pantry held 2 carrots all run, so a starving guest went without
-- (ColonyFood, 2026-11-21). The keeper keeps raw potatoes for it (keeper_supply.lua's
-- RAW_RESERVE). Carrots and beetroot first: they make no dish.
local RAW_PLATES = {"mcl_farming:carrot_item", "mcl_farming:beetroot_item", "mcl_farming:potato_item",
	"mcl_fishing:fish_raw", "mcl_fishing:salmon_raw"}
local BROKE_PRICE = 1
-- Up to this, in dinners at its own price for one (dinner.scale), the cleric eats free:
-- alms.lua's SAVINGS.
local CLERIC_SAVINGS = 8 * ledger.DINNER
-- Dishes a villager guest may have in one evening: enough to take it from starving (0)
-- to above EAT_AT (4 + 4 + 4 points).
local MAX_DISHES = 3
-- How far from the jukebox its keeper is looked for: keeper.lua's staffing
-- distance, with room to spare.
local KEEPER_RADIUS = 4
-- The frame item entity's size and placement (mcl_itemframes base_props and
-- set_item).
local VISUAL_SIZE = 0.3
local FRAME_OFFSET = 0.42
-- A seated guest's mouth, above its origin (seat.lua sets the origin in the
-- chair; the model's head is about 1.3 above it seated).
local MOUTH_HEIGHT = 1.3
-- What a villager pays for dinner where no keeper ever posted a price (dinner.lua).
local VILLAGER_PRICE = ledger.DINNER

local plates = {}
local served = {}

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function now()
	return core.get_gametime()
end

-- Every dish it serves: MENU's, then any other prepared food (keeper.dishes, ticket 35).
local function menu()
	return keeper.dishes()
end

-- The plate on the guest's table, if it is free for a meal: a plate with
-- nothing of a player's on it, and no other guest's meal.
local function plate_for(self)
	local seat = self._villages_seat
	if not seat or not seat.table then return end
	local pos = {x = seat.table.x, y = seat.table.y + 1, z = seat.table.z}
	local node = core.get_node_or_nil(pos)
	if not node or node.name ~= PLATE then return end
	return pos, node
end

local function plate_empty(pos)
	local stack = core.get_meta(pos):get_inventory():get_stack("main", 1)
	return not stack or stack:is_empty()
end

local function held_by_other(pos, id)
	local hold = plates[key(pos)]
	return hold and hold.id ~= id and hold.until_time >= now()
end

local function hold(self, pos)
	plates[key(pos)] = {id = self._id, until_time = now() + HOLD_SECONDS}
end

-- The keeper on duty at the guest's tavern: the villager that claimed the
-- jukebox, close by and staffing it.
local function keeper_state(jukebox)
	local id = core.get_meta(jukebox):get_string("villager")
	if id == "" then return nil, "the jukebox has no keeper claimed" end
	local status
	for _, object in ipairs(core.get_objects_inside_radius(jukebox, KEEPER_RADIUS)) do
		local entity = object:get_luaentity()
		if entity and entity._id == id and entity._villages_keeper then
			status = keeper.status(entity)
			if status == "staffing the tavern" then return entity end
		end
	end
	return nil, status and ("the keeper is " .. status:gsub(" %(.*%)", "")) or "the keeper is not loaded within reach of the jukebox"
end

local function keeper_on_duty(jukebox)
	return (keeper_state(jukebox))
end

local function is_villager(self)
	return not self._villages_on_bite and self._villages_price == nil
end

-- The dish a guest is served (ticket 34): a villager the one it is least tired of
-- (variety.best, at random among equals), a player any.
local function pick_dish(self, dishes)
	if not is_villager(self) then return dishes[math.random(#dishes)] end
	return variety.best(self._villages_meals, dishes, core.get_day_count(), math.random)
end

-- A dish served at the keeper's tavern, in its record of what its guests ate (ticket 34):
-- what it buys follows it (possessions.variety_of).
local function note_dish(jukebox, item)
	local keeper_entity = keeper_on_duty(jukebox)
	if keeper_entity then
		keeper_entity._villages_served_dishes = variety.note(keeper_entity._villages_served_dishes, item,
			core.get_day_count())
	end
end

-- What the diner pays, and how: a player's terms come with its diner table
-- (player_meals.lua); a villager's are worked out here.
local function terms(self, jukebox)
	if not is_villager(self) then return self._villages_price or 0, self._villages_can_pay, self._villages_pay end
	local keeper = keeper_state(jukebox)
	if keeper and (keeper == self or possessions.same_house(keeper._bed, self._bed)) then return 0 end
	-- The cleric eats free (ticket 24): it lives on alms and sells nothing a village wants,
	-- and starved at 15 emeralds while dinner cost 1 (ColonyFood, 2026-11-16). Not the
	-- alchemist, a cleric underneath, which never eats. Over its savings it pays, and
	-- always dines, never weighing the price as it starved doing (ticket 27): one with
	-- 2,700 emeralds ate free while the keeper owed the farms 1,950 (ColonyFood, 2026-11-20).
	local cleric = self._profession == "cleric" and not self._villages_alchemist
	if cleric and possessions.emeralds(self) <= CLERIC_SAVINGS * dinner.scale(self) then return 0 end
	local price = dinner.posted(jukebox, keeper, core.get_day_count()) or VILLAGER_PRICE
	return price,
		function() return possessions.emeralds(self) >= price end,
		function()
			possessions.take(self, possessions.EMERALD, price)
			dinner.paid(self, price)
		end,
		cleric
end

-- A villager at a pantry orders only when it has room for a meal.
local function has_room(self)
	return not is_villager(self) or food.points(self) <= possessions.EAT_AT
end

-- A raw plate the pantry holds: the item and how many make it; or nil.
local function raw_plate(chests)
	for _, item in ipairs(RAW_PLATES) do
		local portion = food.raw_portion(item)
		if portion and pantry.count(chests, item) >= portion then return item, portion end
	end
	return nil
end

-- What a guest at a tavern with a pantry would be served: the item, how many, the price
-- and how it pays (nil for free); or nil and why not. `choose` picks the dish at random,
-- as serving does; without it the first will do, to ask whether there is one.
local function order(self, jukebox, chests, choose)
	local price, can_pay, pay, always = terms(self, jukebox)
	local dishes = pantry.available(chests, menu())
	local villager = is_villager(self)
	local day = core.get_day_count()
	-- A villager pays only what a meal is worth to it (dinner.lua, ticket 21e).
	local willing = price == 0
		or (can_pay() and (not villager or always or dinner.wants(self, price, day, possessions.assess, dishes,
			news.heard(self, core.get_gametime()))))
	local keeper = villager and price > 0 and keeper_state(jukebox) or nil
	if #dishes == 0 and willing then dinner.ran_out(keeper, day, self._id) end
	if #dishes == 0 and not (villager and raw_plate(chests)) then return nil, "the pantry is empty" end
	if willing then
		if #dishes > 0 then return choose and pick_dish(self, dishes) or dishes[1], 1, price, pay end
		if villager then
			local raw, portion = raw_plate(chests)
			if raw then return raw, portion, price, pay end
		end
		return nil, "the pantry is empty"
	end
	if #dishes > 0 then dinner.turned(keeper, self._id, day) end
	-- A starving guest that will not pay still gets the raw plate, as one that cannot does
	-- (ticket 22b).
	local starving = villager and food.state(self) == "starving"
	if villager and can_pay() and not starving then
		return nil, "a dinner is not worth " .. price .. " emerald(s) to the diner"
	end
	local broke = villager and possessions.emeralds(self) < BROKE_PRICE
	if not villager or (broke and not starving) then
		return nil, "the diner cannot pay " .. price .. " emerald(s)"
	end
	local raw, portion = raw_plate(chests)
	if not raw then return nil, "the diner cannot pay " .. price .. " emerald(s), and there is no raw plate" end
	-- A starving guest always eats (ticket 39h): with no emerald, free.
	if broke then return raw, portion, 0, nil end
	return raw, portion, BROKE_PRICE, function() possessions.take(self, possessions.EMERALD, BROKE_PRICE) end
end

-- Whether a guest should take a seat at this tavern: it would be served there tonight
-- (2026-11-13: guests who could not pay sat at full tables while others went without).
-- With no pantry the meal is a display, served to anyone.
local function would_serve(self, jukebox)
	if not jukebox then return false end
	local chests = pantry.chests(jukebox)
	if not chests then return true end
	if not has_room(self) then return false end
	local item = order(self, jukebox, chests)
	return item ~= nil
end

-- A display whose guest no longer holds its plate: the guest unloaded, or
-- was removed, while the plate stayed loaded, and nothing will finish it.
local function orphaned(entity)
	local hold_here = entity._plate and plates[entity._plate]
	return not hold_here or hold_here.id ~= entity._guest or hold_here.until_time < now()
end

-- Clear any display left on this plate before serving another.
local function clear_orphans(pos)
	for _, object in ipairs(core.get_objects_inside_radius(pos, 0.5)) do
		local entity = object:get_luaentity()
		if entity and entity.name == ENTITY and orphaned(entity) then object:remove() end
	end
end

local function show(self, pos, node, item)
	local dir = core.wallmounted_to_dir(node.param2)
	local at = {x = pos.x + dir.x * FRAME_OFFSET, y = pos.y + dir.y * FRAME_OFFSET, z = pos.z + dir.z * FRAME_OFFSET}
	local object = core.add_entity(at, ENTITY)
	if not object then return end
	local entity = object:get_luaentity()
	if entity then entity._plate, entity._guest = key(pos), self._id end
	local definition = core.registered_items[item] or {}
	local scale = definition.wield_scale or {x = 1, y = 1}
	object:set_rotation(vector.dir_to_rotation(dir))
	object:set_properties({
		wield_item = item,
		visual_size = {x = VISUAL_SIZE / scale.x, y = VISUAL_SIZE / scale.y},
	})
	return object
end

-- A bite: food particles from the guest's mouth and the eating sound, as a
-- player eating (mcl_hunger eat_effects).
local function bite(self, item)
	local pos = self.object:get_pos()
	if not pos then return end
	local definition = core.registered_items[item] or {}
	local texture = definition.inventory_image
	if not texture or texture == "" then texture = definition.wield_image end
	local mouth = self._villages_mouth_at and self._villages_mouth_at(self)
		or {x = pos.x, y = pos.y + MOUTH_HEIGHT, z = pos.z}
	if texture and texture ~= "" and definition._food_particles ~= false then
		for i = 0, 8 do
			core.add_particle({
				pos = mouth,
				velocity = {x = math.random(-1, 1), y = math.random(1, 2), z = math.random(-1, 1)},
				acceleration = {x = 0, y = math.random(-9, -5), z = 0},
				expirationtime = 1,
				size = math.random(1, 2),
				collisiondetection = true,
				texture = "[combine:3x3:" .. -i .. "," .. -i .. "=" .. texture,
			})
		end
	end
	core.sound_play("mcl_hunger_bite", {
		max_hear_distance = 12, gain = 0.33, pitch = 1 + math.random(-10, 10) * 0.005, object = self.object,
	}, true)
	-- A player diner (player_meals.lua, #19) is fed by its bites.
	if self._villages_on_bite then self._villages_on_bite(self) end
end

local M = {}
M.would_serve = would_serve

-- Clear the meal and let the plate go. Safe to call on a guest with none.
function M.finish(self)
	local meal = self._villages_meal
	self._villages_meal = nil
	if not meal then return end
	if meal.object then meal.object:remove() end
	local hold_here = plates[key(meal.plate)]
	if hold_here and hold_here.id == self._id then plates[key(meal.plate)] = nil end
end

-- Why a diner would not be served now, for the log and /living_villages_meal (#19).
function M.explain(self, jukebox)
	if not jukebox then return "no jukebox near the chair" end
	if self._villages_meal then return "eating" end
	if self._villages_meal_day == core.get_day_count() then return "already served here today" end
	local pos = plate_for(self)
	if not pos then return "no plate on the table in front of the chair" end
	if not plate_empty(pos) then return "the plate holds an item" end
	if held_by_other(pos, self._id) then return "the plate is held by " .. plates[key(pos)].id end
	local _, reason = keeper_state(jukebox)
	if reason then return reason end
	local last = served[key(jukebox)]
	if last and now() - last < SERVE_SECONDS then return "the keeper is serving another plate" end
	if #menu() == 0 then return "the menu is empty" end
	local chests = pantry.chests(jukebox)
	if chests then
		if not has_room(self) then return "the diner is not hungry" end
		local item, price = order(self, jukebox, chests)
		if not item then return price end
		if price > 0 and not pantry.has_room(chests, pantry.EMERALD, price) then return "the pantry has no room for the payment" end
	end
	return "ready to serve"
end

-- Takes the meal out of the pantry and the payment into it. False if either fails,
-- having changed nothing.
local function settle(self, jukebox, chests, item, portion, price, pay, what)
	if price > 0 and not pantry.has_room(chests, pantry.EMERALD, price) then return false end
	if pantry.count(chests, item) < portion then return false end
	for _ = 1, portion do pantry.take(chests, item) end
	if price > 0 then
		pay()
		pantry.put(chests, pantry.EMERALD, price)
		if is_villager(self) then
			core.log("action", string.format("[living_villages] villager %s paid %d emerald(s) for %s at the tavern at %s",
				tostring(self._id):sub(1, 6), price, what or "dinner", core.pos_to_string(jukebox)))
		end
	end
	return true
end

-- Seconds (2026-11-16): a dish is 4 points, a day's hunger, so one dinner a day only
-- held a guest where it was. One that missed a dinner stayed 4 points down for good
-- (ColonyFood day 428: the keeper could not reach a farm chest, 16 went without, and sat
-- hungry at 1.5 points each morning after, while about 480 potatoes sat in the farm
-- chests). Served its dinner, a villager guest is served dish after dish, each at the
-- price it paid for the first, while it is at or below EAT_AT, up to MAX_DISHES in all.
-- Only dishes: a raw plate is a last resort, never a second. A pantry with no dish left
-- counts as running out, as for a guest that found none (dinner.ran_out). Each dish counts
-- toward the evening's demand, which the keeper stocks the pantry to. Returns how many
-- more it had.
local function seconds(self, jukebox, chests)
	local price, can_pay, pay = terms(self, jukebox)
	local day = core.get_day_count()
	local keeper = price > 0 and keeper_state(jukebox) or nil
	local more = 0
	for _ = 2, MAX_DISHES do
		if food.points(self) > possessions.EAT_AT then break end
		if price > 0 and not can_pay() then break end
		local dishes = pantry.available(chests, menu())
		if #dishes == 0 then
			dinner.ran_out(keeper, day, self._id)
			break
		end
		local item = pick_dish(self, dishes)
		if not settle(self, jukebox, chests, item, 1, price, pay, "another dish") then break end
		dinner.served(keeper_on_duty(jukebox), day)
		note_dish(jukebox, item)
		food.receive(self, item)
		more = more + 1
	end
	if more > 0 then
		core.log("action", string.format("[living_villages] villager %s had %d more dish(es) at the tavern at %s",
			tostring(self._id):sub(1, 6), more, core.pos_to_string(jukebox)))
	end
	return more
end

local function serve(self, jukebox)
	local pos, node = plate_for(self)
	if not pos or not plate_empty(pos) or held_by_other(pos, self._id) then return end
	local last = served[key(jukebox)]
	if last and now() - last < SERVE_SECONDS then return end
	if not keeper_on_duty(jukebox) then return end
	local chests = pantry.chests(jukebox)
	if chests and not has_room(self) then return end
	local item, portion, price, pay
	if chests then
		item, portion, price, pay = order(self, jukebox, chests, true)
		if not item then return end
	else
		local items = menu()
		if #items == 0 then return end
		item, portion = items[math.random(#items)], 1
	end
	clear_orphans(pos)
	hold(self, pos)
	local object = show(self, pos, node, item)
	if not object then
		plates[key(pos)] = nil
		return
	end
	if chests and not settle(self, jukebox, chests, item, portion, price, pay) then
		object:remove()
		plates[key(pos)] = nil
		return
	end
	served[key(jukebox)] = now()
	-- The evening's demand, which the keeper stocks the pantry to (ticket 22c).
	if chests then
		dinner.served(keeper_on_duty(jukebox), core.get_day_count())
		if not food.raw_portion(item) then note_dish(jukebox, item) end
	end
	-- Counted from the moment it is served, so a meal cut short by standing
	-- up, a reload or a player's item still spends the evening's meal.
	self._villages_meal_day = core.get_day_count()
	self._villages_meal = {plate = pos, item = item, served_at = now(), object = object, bite_in = 0}
	-- A villager guest is fed when served; a player diner (no luaentity of its own)
	-- by its bites.
	if chests and not self._villages_on_bite then
		for _ = 1, portion do food.receive(self, item) end
		-- A dish, not a raw plate: more while it is still hungry.
		if not food.raw_portion(item) then seconds(self, jukebox, chests) end
		-- Its dinner for the day: it eats nothing of its own tonight (possessions.lua).
		self._villages_dined_day = core.get_day_count()
	end
end

-- Swaps market news with the keeper on duty, once a day. Returns whether it did.
function M.tavern_news(self, jukebox)
	local today = core.get_day_count()
	if not is_villager(self) or self._villages_keeper or self._villages_tavern_news == today then return false end
	local keeper_entity = keeper_on_duty(jukebox)
	if not keeper_entity then return false end
	self._villages_tavern_news = today
	news.exchange({self, keeper_entity})
	return true
end

-- Each tick while seated at dinner, after the seat has been held.
function M.tick(self, dtime, jukebox)
	local meal = self._villages_meal
	if not meal then
		if not jukebox then return end
		self._villages_seated_at = self._villages_seated_at or now()
		if now() - self._villages_seated_at < WAIT_SECONDS then return end
		M.tavern_news(self, jukebox)
		if self._villages_meal_day == core.get_day_count() then return end
		serve(self, jukebox)
		return
	end
	-- The plate went, or a player put something on it: the meal is over.
	-- The keeper leaving is no reason: a served meal is finished.
	local node = core.get_node_or_nil(meal.plate)
	if not node or node.name ~= PLATE or not plate_empty(meal.plate)
		or not meal.object:get_pos() or now() - meal.served_at >= EAT_SECONDS then
		M.finish(self)
		return
	end
	hold(self, meal.plate)
	meal.bite_in = meal.bite_in - (dtime or 0)
	if meal.bite_in <= 0 then
		meal.bite_in = BITE_SECONDS
		bite(self, meal.item)
	end
end

-- Getting up ends the meal.
function M.stand(self)
	self._villages_seated_at = nil
	M.finish(self)
end

if core.register_entity then
	core.register_entity(ENTITY, {
		initial_properties = {
			visual = "wielditem",
			visual_size = {x = VISUAL_SIZE, y = VISUAL_SIZE},
			physical = false,
			pointable = false,
			static_save = false,
			textures = {"blank.png"},
		},
		-- Never saved; one that outlives its guest's hold on the plate
		-- clears itself, before the plate can be served again.
		on_step = function(entity)
			if orphaned(entity) then entity.object:remove() end
		end,
	})
end

M.plates = plates
M.served = served
return M
