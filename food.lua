-- What food does for a villager. A farmer hands it over directly (farmer.lua), and
-- this is the receiving end. VoxeLibre's own feed_tame needs a player's hand and its
-- pickup treats food as breeding input, so neither serves here.
--
-- As in Java, an adult is short of food below 12 points, a loaf being worth 4 and a
-- crop 1. A villager needs 12 to become a parent, and spends them when it does, so
-- automatic births (births.lua) depend on a working farm. A child takes no points:
-- each feed, once a day, brings it closer to grown.
--
-- An adult's points fall by living_villages_hunger_per_day (4, a loaf) per game day
-- of its economic clock (economy_clock.lua), worked out when they are next read, so
-- a villager no player is near neither eats nor goes hungry. They never fall below
-- 0, and hunger never harms: it lowers what a villager does (state).
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")

local POINTS = {
	["mcl_farming:bread"] = 4,
	["mcl_farming:potato_item"] = 1,
	["mcl_farming:carrot_item"] = 1,
	["mcl_farming:beetroot_item"] = 1,
	-- What a forager gathers (labour.lua), at about three quarters of a player's.
	["mcl_core:apple"] = 3,
	["mcl_farming:sweet_berry"] = 1,
	-- The tavern's prepared foods (keeper.lua's menu), about four fifths of what
	-- they give a player, as bread's 4 is of its 5.
	["mcl_farming:potato_item_baked"] = 4,
	["mcl_fishing:fish_cooked"] = 4,
	["mcl_mushrooms:mushroom_stew"] = 5,
	["mcl_farming:pumpkin_pie"] = 6,
	-- What the butcher cooks (production.lua), on the same scale.
	["mcl_mobitems:cooked_porkchop"] = 6,
	["mcl_mobitems:cooked_chicken"] = 5,
	["mcl_mobitems:cooked_beef"] = 6,
}
local FULL = 12
-- Below this an adult is hungry; at 0, starving.
local HUNGRY = 4
local DEFAULT_HUNGER_PER_DAY = 4
local HEAL = 4
-- VoxeLibre's CHILD_GROW_TIME and the share of what is left that one feed takes off
-- (mcl_mobs/breeding.lua's feed_tame).
local CHILD_GROW_TIME = 60
local CHILD_FEED_SHARE = 0.1

local M = {FULL = FULL, HUNGRY = HUNGRY, POINTS = POINTS}

-- Best first.
M.FOODS = {"mcl_farming:bread", "mcl_farming:beetroot_item", "mcl_farming:potato_item", "mcl_farming:carrot_item"}

local function hunger_per_day()
	if not clock.enabled() then return 0 end
	local value = core.settings and tonumber(core.settings:get("living_villages_hunger_per_day"))
	return math.max(value or DEFAULT_HUNGER_PER_DAY, 0)
end

M.hunger_per_day = hunger_per_day

-- Seconds of game time in a game day, or nil while time stands still.
local function day_seconds()
	local speed = core.settings and tonumber(core.settings:get("time_speed")) or 72
	if speed <= 0 then return nil end
	return 86400 / speed
end

-- Takes off what the clock has run since the points were last read.
local function digest(self)
	if self.child then return end
	local now = clock.read(self)
	local since = self._villages_food_at
	self._villages_food_at = now
	if not since or now <= since or not self._villages_food then return end
	local rate, day = hunger_per_day(), day_seconds()
	if rate <= 0 or not day then return end
	self._villages_food = math.max(self._villages_food - rate * (now - since) / day, 0)
end

function M.points(self)
	digest(self)
	return self._villages_food or 0
end

-- full (may become a parent), fed, hungry or starving. A child is always fed.
function M.state(self)
	if self.child then return "fed" end
	local points = M.points(self)
	if points >= FULL then return "full" end
	if points >= HUNGRY then return "fed" end
	if points > 0 then return "hungry" end
	return "starving"
end

function M.wants(self)
	if self._villages_sleeping then return false end
	if self.child then return self._villages_fed_day ~= core.get_day_count() end
	return M.points(self) < FULL
end

function M.receive(self, item)
	local points = POINTS[item]
	if not points then return false end
	if self.child then
		local timer = self.hornytimer or 0
		self.hornytimer = timer + (CHILD_GROW_TIME - timer) * CHILD_FEED_SHARE
		self._villages_fed_day = core.get_day_count()
	else
		self._villages_food = M.points(self) + points
	end
	local max = self.initial_properties and self.initial_properties.hp_max
	if max and self.health and self.health < max then
		self.health = math.min(self.health + HEAL, max)
		self.object:set_hp(self.health)
	end
	return true
end

-- The item going across and the sound of it being eaten; nothing touches the ground.
function M.show_handover(from, to, item, object)
	local def = core.registered_items and core.registered_items[item]
	local texture = def and def.inventory_image
	if texture and texture ~= "" then
		core.add_particle({
			pos = {x = from.x, y = from.y + 1, z = from.z},
			velocity = {x = to.x - from.x, y = 2, z = to.z - from.z},
			acceleration = {x = 0, y = -4, z = 0},
			expirationtime = 1,
			size = 2,
			texture = texture,
		})
	end
	core.sound_play("mcl_hunger_bite", {max_hear_distance = 12, gain = 0.33, object = object}, true)
end

function M.births_need_food()
	return not core.settings or core.settings:get_bool("living_villages_births_need_food", true)
end

-- Whether this villager is fed well enough to become a parent.
function M.can_parent(self)
	return not M.births_need_food() or M.points(self) >= FULL
end

function M.spend_on_birth(self)
	if M.births_need_food() then self._villages_food = math.max(M.points(self) - FULL, 0) end
end

return M
