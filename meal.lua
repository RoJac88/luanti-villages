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
-- to sell): VILLAGER_PRICE emeralds from its belongings (possessions.lua) into the
-- pantry, unless it is the keeper or of the keeper's household (possessions.same_house),
-- who eat free. At a pantry it is served only when it has room for a meal, at or below
-- possessions.EAT_AT points. Served, it has had its dinner for the day
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
local ENTITY = "living_villages:meal"
local PLATE = "mcl_itemframes:plate"
-- A guest waits this long after sitting down before it is served.
local WAIT_SECONDS = 3
-- A keeper serves one plate at a time, this often.
local SERVE_SECONDS = 3
-- How long a meal lasts, and how often the guest takes a bite.
local EAT_SECONDS = 12
local BITE_SECONDS = 0.8
-- A plate hold lapses unless renewed, so one left by a guest that unloaded
-- frees itself.
local HOLD_SECONDS = 5
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
-- What a villager pays for dinner: a bundle of bread at the farmer's costs the same.
-- A dinner's price (ledger.DINNER).
local VILLAGER_PRICE = ledger.DINNER

local plates = {}
local served = {}

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function now()
	return core.get_gametime()
end

local function menu()
	local items = {}
	for _, entry in ipairs(keeper.MENU) do
		if not core.registered_items or core.registered_items[entry.offered] then
			table.insert(items, entry.offered)
		end
	end
	return items
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

-- What the diner pays, and how: a player's terms come with its diner table
-- (player_meals.lua); a villager's are worked out here.
local function terms(self, jukebox)
	if not is_villager(self) then return self._villages_price or 0, self._villages_can_pay, self._villages_pay end
	local keeper = keeper_state(jukebox)
	if keeper and (keeper == self or possessions.same_house(keeper._bed, self._bed)) then return 0 end
	return VILLAGER_PRICE,
		function() return possessions.emeralds(self) >= VILLAGER_PRICE end,
		function() possessions.take(self, possessions.EMERALD, VILLAGER_PRICE) end
end

-- A villager at a pantry orders only when it has room for a meal.
local function has_room(self)
	return not is_villager(self) or food.points(self) <= possessions.EAT_AT
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
		if #pantry.available(chests, menu()) == 0 then return "the pantry is empty" end
		if not has_room(self) then return "the diner is not hungry" end
		local price, can_pay = terms(self, jukebox)
		if price > 0 and not can_pay() then return "the diner cannot pay " .. price .. " emerald(s)" end
		if price > 0 and not pantry.has_room(chests, pantry.EMERALD, price) then return "the pantry has no room for the payment" end
	end
	return "ready to serve"
end

-- Takes the meal out of the pantry and the payment into it. False if either fails,
-- having changed nothing.
local function settle(self, jukebox, chests, item)
	local price, can_pay, pay = terms(self, jukebox)
	if price > 0 and (not can_pay() or not pantry.has_room(chests, pantry.EMERALD, price)) then
		return false
	end
	if not pantry.take(chests, item) then return false end
	if price > 0 then
		pay()
		pantry.put(chests, pantry.EMERALD, price)
		if is_villager(self) then
			core.log("action", string.format("[living_villages] villager %s paid %d emerald(s) for dinner at the tavern at %s",
				tostring(self._id):sub(1, 6), price, core.pos_to_string(jukebox)))
		end
	end
	return true
end

local function serve(self, jukebox)
	local pos, node = plate_for(self)
	if not pos or not plate_empty(pos) or held_by_other(pos, self._id) then return end
	local last = served[key(jukebox)]
	if last and now() - last < SERVE_SECONDS then return end
	if not keeper_on_duty(jukebox) then return end
	local chests = pantry.chests(jukebox)
	if chests and not has_room(self) then return end
	local items = chests and pantry.available(chests, menu()) or menu()
	if #items == 0 then return end
	local item = items[math.random(#items)]
	clear_orphans(pos)
	hold(self, pos)
	local object = show(self, pos, node, item)
	if not object then
		plates[key(pos)] = nil
		return
	end
	if chests and not settle(self, jukebox, chests, item) then
		object:remove()
		plates[key(pos)] = nil
		return
	end
	served[key(jukebox)] = now()
	-- Counted from the moment it is served, so a meal cut short by standing
	-- up, a reload or a player's item still spends the evening's meal.
	self._villages_meal_day = core.get_day_count()
	self._villages_meal = {plate = pos, item = item, served_at = now(), object = object, bite_in = 0}
	-- A villager guest is fed when served; a player diner (no luaentity of its own)
	-- by its bites.
	if chests and not self._villages_on_bite then
		food.receive(self, item)
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
