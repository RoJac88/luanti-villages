-- The farmer's working day, built on VoxeLibre's legacy villager AI. A claimed
-- composter anchors the farm. About once a second, in the work stage, the farmer
-- does the next job within its reach, or else walks to the most pressing one.
--
-- Vanilla's do_work calls the farmer back to its composter every few seconds, so
-- while it has work here common.activity_override answers for it, as flock.lua
-- does for a shepherd. With nothing to do it lets vanilla have it again, which is
-- also when vanilla's do_work unlocks its trades.
--
-- Who it feeds (docs/villager-economy-design.md, The farmer's food). With the economy
-- on: itself, its household (villagers whose beds are within HOUSEHOLD_RADIUS of its
-- own, the same house as near as beds tell) and every child, free and as much as they
-- want; a starving villager one item free; anyone else who carries no food and has an
-- emerald buys a bundle, as many of the food as vanilla's trades sell for one emerald
-- (six loaves), eats what it wants of it and keeps the rest (possessions.lua). The
-- emerald goes in the farmer's belongings, as do any the keeper leaves in its chest
-- for the food it fetched (keeper_supply.lua), which it collects when it next stores
-- its surplus. With the economy off it feeds everyone free, as it always did.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local field = dofile(core.get_modpath("living_villages") .. "/farm_field.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local compost = dofile(core.get_modpath("living_villages") .. "/farm_compost.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")

local TICK_SECONDS = 1
local IDLE_SECONDS = 5
-- From a cell beside a plot, including diagonally, with room for standing off centre.
local REACH = 2.5
-- A place the farmer could not walk to is left alone for this long.
local SKIP_SECONDS = 60
-- Stay put this long after a job, ready for the next.
local HOLD_SECONDS = 2

local WHEAT = "mcl_farming:wheat_item"
local BREAD = "mcl_farming:bread"
local BONE_MEAL = compost.BONE_MEAL
-- Three wheat to the loaf, as in the crafting recipe. A farmer stops baking at this
-- many loaves, as it has nobody to give them to.
local WHEAT_PER_BREAD = 3
local BREAD_LIMIT = 12
-- What it composts, and how much of each it keeps for sowing and eating. Bread goes
-- to villagers, so it is never composted.
local COMPOST_KEEP = {
	["mcl_farming:wheat_seeds"] = 8,
	["mcl_farming:beetroot_seeds"] = 8,
	["mcl_farming:potato_item"] = 8,
	["mcl_farming:carrot_item"] = 8,
	["mcl_farming:beetroot_item"] = 8,
	[WHEAT] = WHEAT_PER_BREAD,
}
-- It stops composting once it holds this much bone meal, so the surplus is not all
-- turned into something it cannot use. With a chest for the surplus it needs less.
local BONE_MEAL_LIMIT = 32
local BONE_MEAL_LIMIT_WITH_CHEST = 4
-- What it holds on to when it goes to a chest. Anything else it picks up goes in whole.
local DEPOSIT_KEEP = {
	["mcl_farming:wheat_seeds"] = 16,
	["mcl_farming:beetroot_seeds"] = 16,
	["mcl_farming:potato_item"] = 16,
	["mcl_farming:carrot_item"] = 16,
	["mcl_farming:beetroot_item"] = 16,
	[WHEAT] = WHEAT_PER_BREAD,
	[BREAD] = 8,
	[BONE_MEAL] = BONE_MEAL_LIMIT_WITH_CHEST,
}
-- A trip to a chest waits for this much over the keep, unless the pouch is full.
local DEPOSIT_TRIGGER = 8
local WITHDRAW_SEEDS = 8
local SEEDS = {
	"mcl_farming:wheat_seeds", "mcl_farming:beetroot_seeds", "mcl_farming:potato_item", "mcl_farming:carrot_item",
}
local CHEST_SCAN_SECONDS = 60
-- Handing food over: from this far off, to those this near its farm. It keeps a few
-- of the crops that are also its seed.
local HANDOVER_REACH = 3
local DELIVERY_RADIUS = 32
local FOOD_SEED_KEEP = {["mcl_farming:potato_item"] = 4, ["mcl_farming:carrot_item"] = 4}
local WITHDRAW_FOOD = 8
-- Beds this near its own, across and up or down, are its household's.
local HOUSEHOLD_RADIUS, HOUSEHOLD_HEIGHT = 5, 4
local EMERALD = "mcl_core:emerald"
-- A round feeds a few villagers, or gives up after chasing them this many times, and
-- the next waits a while: villagers walk about, and the field needs tending too.
local ROUND_FED = 4
local ROUND_WALKS = 8
local ROUND_SECONDS = 120

-- Live working state. Not saved: a reload clears the farmer's route anyway
-- (navigation.lua), and it picks its next job from what it finds.
local sessions = setmetatable({}, {__mode = "k"})

local function session_of(self)
	local session = sessions[self]
	if not session then
		session = {skip = {}, next_at = 0, hold_until = 0}
		sessions[self] = session
	end
	return session
end

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function valid_farmer(self)
	if self.child or self._profession ~= "farmer" or not self._jobsite or not self._id then return false end
	local node = core.get_node_or_nil(self._jobsite)
	return node and common.is_composter_node(node.name)
		and core.get_meta(self._jobsite):get_string("villager") == self._id
end

local function is_trading(self)
	return self._trading_players ~= nil and next(self._trading_players) ~= nil
end

local function skipped(session, pos, now)
	local until_time = session.skip[key(pos)]
	return until_time ~= nil and until_time > now
end

-- The nearest of the positions it has not given up on.
local function nearest(session, pos, positions, now)
	local best, best_distance
	for _, candidate in ipairs(positions) do
		if not skipped(session, candidate, now) then
			local distance = vector.distance(pos, candidate)
			if not best_distance or distance < best_distance then best, best_distance = candidate, distance end
		end
	end
	return best, best_distance
end

local function face(self, pos, target)
	local dx, dz = target.x - pos.x, target.z - pos.z
	if (dx ~= 0 or dz ~= 0) and self.turn_in_direction then self:turn_in_direction(dx, dz) end
end

local function hold_still(self)
	self.state = "stand"
	self.order = "stand"
	self.object:set_velocity(vector.zero())
end

local function release(self, session)
	session.away = false
	session.hold_until = 0
	if self.order == "stand" then self.order = nil end
end

local function walk_to(self, session, target, now)
	self._villages_farm_target = vector.new(target)
	self._villages_farm_route = nil
	local started = self:gopath(target, function(entity)
		entity._villages_farm_target = nil
		entity._villages_farm_route = nil
	end, true)
	if started then return true end
	session.skip[key(target)] = now + SKIP_SECONDS
	self._villages_farm_target = nil
	self._villages_farm_route = nil
	return false
end

-- The chests near its farm, looked for now and then so one a player places gets used.
local function chests_of(self, session, now)
	if not session.chests or now >= session.chests_at then
		session.chests = stock.find_chests(self._jobsite)
		session.chests_at = now + CHEST_SCAN_SECONDS
	end
	return session.chests
end

-- Where its surplus goes: the chest nearest its composter, both halves if it is a double
-- chest, and no other. A player who wants it out of some chest, a Builder's say, places
-- one nearer, and a full one makes it wait rather than fill the next. Chests only touch
-- when they are halves of one, as the kinds it uses merge.
local function own_chest(chests)
	local first = chests[1]
	if not first then return {} end
	local own = {first}
	for i = 2, #chests do
		if vector.distance(chests[i], first) == 1 then table.insert(own, chests[i]) end
	end
	return own
end

-- Something a farm yields that it has no use for, such as a poison potato. With no
-- chest to put it in it stays where it fell, rather than filling the pouch for good.
local function harvest(self, pos, session, now)
	local drops = field.harvest(pos)
	if not drops then return end
	local has_chest = #chests_of(self, session, now) > 0
	for _, drop in ipairs(drops) do
		local name = drop:match("^%S+")
		if has_chest or DEPOSIT_KEEP[name] then
			stock.add_itemstring(self, drop)
		else
			core.add_item(pos, drop)
		end
	end
end

-- The item most over what it keeps, and by how much.
local function excess_item(self)
	local best, best_extra = nil, 0
	for name in pairs(self._villages_farm_pouch or {}) do
		local extra = stock.count(self, name) - (DEPOSIT_KEEP[name] or 0)
		if extra > best_extra or (extra == best_extra and best and name < best) then
			best, best_extra = name, extra
		end
	end
	return best, best_extra
end

local function wants_to_deposit(self)
	local item, extra = excess_item(self)
	if not item then return false end
	-- Something it never keeps is only ever on its way to a chest.
	return extra >= DEPOSIT_TRIGGER or not DEPOSIT_KEEP[item] or not stock.has_harvest_room(self)
end

-- Emeralds left in its chest for food taken from it go in its belongings.
local function collect_pay(self, pos)
	local count = stock.chest_count(pos, EMERALD)
	if count == 0 then return 0 end
	local moved = core.get_meta(pos):get_inventory():remove_item("main", EMERALD .. " " .. count):get_count()
	if moved > 0 then possessions.add(self, EMERALD, moved) end
	return moved
end

local function deposit(self, pos, session, now)
	if clock.enabled() then collect_pay(self, pos) end
	local item, extra = excess_item(self)
	if not item then return end
	local _, fitted = stock.put_in_chest(self, pos, item, extra)
	if fitted then
		core.sound_play("default_chest_close", {pos = pos, gain = 0.3, max_hear_distance = 16}, true)
	else
		session.skip[key(pos)] = now + SKIP_SECONDS
	end
end

-- The chests holding seeds, for a farmer with empty plots and none of its own.
local function chests_with_seeds(session, chests, now)
	local found = {}
	if not stock.may_withdraw() then return found end
	for _, chest in ipairs(chests) do
		if not skipped(session, chest, now) then
			for _, seed in ipairs(SEEDS) do
				if stock.chest_count(chest, seed) > 0 then
					table.insert(found, chest)
					break
				end
			end
		end
	end
	return found
end

local function withdraw_seeds(self, pos)
	for _, seed in ipairs(SEEDS) do
		if stock.take_from_chest(self, pos, seed, WITHDRAW_SEEDS) > 0 then return end
	end
end

local function plant(self, pos)
	local seed = field.choose_seed(pos, function(name) return stock.count(self, name) end)
	if seed and field.plant(pos, seed) then stock.take(self, seed, 1) end
end

local function has_seed(self)
	for name in pairs(self._villages_farm_pouch or {}) do
		if field.is_seed(name) then return true end
	end
	return false
end

local function fertilise(self, pos)
	if stock.count(self, BONE_MEAL) > 0 and field.fertilise(pos, BONE_MEAL) then
		stock.take(self, BONE_MEAL, 1)
	end
end

local function can_bake(self)
	return stock.count(self, WHEAT) >= WHEAT_PER_BREAD and stock.count(self, BREAD) < BREAD_LIMIT
end

-- The item it has most of beyond what it keeps, or nil.
local function surplus_item(self, has_chest)
	local limit = has_chest and BONE_MEAL_LIMIT_WITH_CHEST or BONE_MEAL_LIMIT
	if stock.count(self, BONE_MEAL) >= limit then return nil end
	local best, best_extra = nil, 0
	for name, keep in pairs(COMPOST_KEEP) do
		-- Wheat is for bread while there is room for more.
		if name ~= WHEAT or not can_bake(self) then
			local extra = stock.count(self, name) - keep
			if extra > best_extra or (extra == best_extra and best and name < best) then
				best, best_extra = name, extra
			end
		end
	end
	return best_extra > 0 and best or nil
end

local function composter_has_work(self, name, has_chest)
	if compost.is_ready(name) or can_bake(self) then return true end
	return compost.takes_items(name) and surplus_item(self, has_chest) ~= nil
end

-- One thing at the composter: take the bone meal, bake a loaf or add an item.
local function work_composter(self, pos, session, now)
	local collected = compost.collect(pos)
	if collected then
		stock.add(self, collected)
		return
	end
	if can_bake(self) then
		stock.take(self, WHEAT, WHEAT_PER_BREAD)
		stock.add(self, BREAD)
		return
	end
	local node = core.get_node_or_nil(pos)
	local item = surplus_item(self, #chests_of(self, session, now) > 0)
	if item and node and compost.takes_items(node.name) and compost.add_item(pos, item) then
		stock.take(self, item, 1)
	end
end

-- The food it can give away, best first, or nil. While it has ground waiting to be
-- sown, a crop that is also its seed goes in the ground rather than down a throat:
-- one potato planted is several later.
local function spare_food(self, session)
	for _, item in ipairs(food.FOODS) do
		if not (session.sowing and field.is_seed(item))
			and stock.count(self, item) > (FOOD_SEED_KEEP[item] or 0) then
			return item
		end
	end
	return nil
end

local function same_house(a, b)
	return a ~= nil and b ~= nil and math.abs(a.x - b.x) <= HOUSEHOLD_RADIUS
		and math.abs(a.z - b.z) <= HOUSEHOLD_RADIUS and math.abs(a.y - b.y) <= HOUSEHOLD_HEIGHT
end

-- How many of the food one emerald buys, from vanilla's prices (ledger.lua).
local function bundle(item)
	local price = ledger.price(item)
	if not price or price <= 0 then return nil end
	return math.max(1, math.floor(1 / price + 0.5))
end

-- The best food it has a whole bundle of to spare, and the bundle's size.
local function food_for_sale(self, session)
	for _, item in ipairs(food.FOODS) do
		local size = bundle(item)
		if size and not (session.sowing and field.is_seed(item))
			and stock.count(self, item) - (FOOD_SEED_KEEP[item] or 0) >= size then
			return item, size
		end
	end
	return nil
end

-- What a villager gets from it: free (all it wants), sale (a bundle for an emerald),
-- handout (one item), or nil.
local function terms(self, target)
	if target == self or target.child or not clock.enabled() or same_house(self._bed, target._bed) then
		return "free"
	end
	if possessions.emeralds(target) > 0 and possessions.food_carried(target) == 0 then return "sale" end
	if food.state(target) == "starving" then return "handout" end
	return nil
end

-- The terms it can meet with what it has now: one who would buy but finds no whole
-- bundle on offer still gets a handout if it is starving.
local function deal_for(self, target, session)
	local deal = terms(self, target)
	if deal == "sale" and not food_for_sale(self, session) then
		deal = food.state(target) == "starving" and "handout" or nil
	end
	if deal and deal ~= "sale" and not spare_food(self, session) then return nil end
	return deal
end

-- Whether to seek this villager out: someone it can serve now, or, while it has no food
-- at all, someone it would serve once it fetches some (plot_jobs).
local function worth_seeking(self, target, session)
	if deal_for(self, target, session) then return true end
	return terms(self, target) ~= nil and not spare_food(self, session)
end

local function sell(self, target, session)
	local item, size = food_for_sale(self, session)
	if not item or possessions.take(target, EMERALD, 1) < 1 then return nil end
	possessions.add(self, EMERALD, 1)
	stock.take(self, item, size)
	local left = size
	while left > 0 and food.wants(target) do
		food.receive(target, item)
		left = left - 1
	end
	if left > 0 then possessions.add(target, item, left) end
	core.log("action", string.format("[living_villages] farmer %s sold %d %s to %s for an emerald",
		tostring(self._id), size, item, tostring(target._id)))
	return item
end

-- Feeds the villager on its terms, from what the farmer can spare.
local function hand_over(self, target, session)
	local deal = deal_for(self, target, session)
	if not deal then return false end
	local given
	if deal == "sale" then
		given = sell(self, target, session)
	else
		while food.wants(target) do
			local item = spare_food(self, session)
			if not item then break end
			stock.take(self, item, 1)
			food.receive(target, item)
			given = item
			if deal == "handout" then break end
		end
	end
	if given and target ~= self then
		food.show_handover(self.object:get_pos(), target.object:get_pos(), given, target.object)
	end
	return given ~= nil
end

local function round_open(session, now)
	return now >= (session.round_next or 0)
end

local function round_progress(session, now, fed, walked)
	session.round_fed = (session.round_fed or 0) + fed
	session.round_walks = (session.round_walks or 0) + walked
	if session.round_fed >= ROUND_FED or session.round_walks >= ROUND_WALKS then
		session.round_next = now + ROUND_SECONDS
		session.round_fed, session.round_walks = 0, 0
	end
end

-- The villagers near the farm short of food, by the cell each stands in.
local function hungry_villagers(self, session, now)
	local positions, by_cell = {}, {}
	if not round_open(session, now) then return positions, by_cell end
	for _, object in ipairs(core.get_objects_inside_radius(self._jobsite, DELIVERY_RADIUS)) do
		local other = object:get_luaentity()
		local at = other and other ~= self and other.name == "mobs_mc:villager" and object:get_pos()
		if at and other._id and food.wants(other) and worth_seeking(self, other, session) then
			local cell = vector.round(at)
			table.insert(positions, cell)
			by_cell[key(cell)] = other
		end
	end
	return positions, by_cell
end

local function chests_with_food(session, chests, now)
	local found = {}
	if not stock.may_withdraw() then return found end
	for _, chest in ipairs(chests) do
		if not skipped(session, chest, now) then
			for _, item in ipairs(food.FOODS) do
				if stock.chest_count(chest, item) > 0 then
					table.insert(found, chest)
					break
				end
			end
		end
	end
	return found
end

local function withdraw_food(self, pos)
	for _, item in ipairs(food.FOODS) do
		if stock.take_from_chest(self, pos, item, WITHDRAW_FOOD) > 0 then return end
	end
end

-- The jobs, most pressing first. wanted says whether to do that kind
-- of job at all now, and each kind lists its places. Tilling waits until there are
-- seeds for what it opens up, and nothing already open is left unsown.
local function plot_jobs(self, session, farm, now)
	local seeds = has_seed(self)
	local chests = chests_of(self, session, now)
	local composter = core.get_node_or_nil(self._jobsite).name
	compost.nudge(self._jobsite, composter)
	local hungry, hungry_by_cell = hungry_villagers(self, session, now)
	local has_food = spare_food(self, session) ~= nil
	return {
		{
			positions = hungry,
			wanted = has_food,
			reach = HANDOVER_REACH,
			work = function(_, cell)
				if hand_over(self, hungry_by_cell[key(cell)], session) then round_progress(session, now, 1, 0) end
			end,
			on_walk = function() round_progress(session, now, 0, 1) end,
		},
		{positions = own_chest(chests), wanted = #chests > 0 and wants_to_deposit(self), work = deposit},
		{positions = farm.mature, wanted = stock.has_harvest_room(self), work = harvest},
		{positions = farm.empty, wanted = seeds, work = plant},
		{
			positions = seeds and #farm.empty == 0 and field.tillable(self._jobsite, farm.soil) or {},
			wanted = seeds,
			work = function(_, pos) field.till(pos, #farm.soil) end,
		},
		{
			positions = field.least_grown(farm.growing),
			wanted = stock.count(self, BONE_MEAL) > 0,
			work = fertilise,
		},
		{positions = {self._jobsite}, wanted = composter_has_work(self, composter, #chests > 0), work = work_composter, last_resort = true},
		{
			positions = not seeds and #farm.empty > 0 and chests_with_seeds(session, chests, now) or {},
			wanted = not seeds,
			work = withdraw_seeds,
		},
		{
			positions = #hungry > 0 and not has_food and chests_with_food(session, chests, now) or {},
			wanted = not has_food,
			work = withdraw_food,
		},
	}
end

-- One job within reach, or one walk to the most pressing job. Returns "worked",
-- "walking", or nil for nothing to do.
local function next_step(self, session, pos, now)
	local farm = field.scan(self._jobsite)
	session.sowing = #farm.empty > 0 or #field.tillable(self._jobsite, farm.soil) > 0
	-- It looks after itself first: a farmer can be a parent too.
	if hand_over(self, self, session) then return "worked" end
	local jobs = plot_jobs(self, session, farm, now)
	-- Work in reach goes first, so one walk does a whole patch of plots. But the composter
	-- is always in reach of a farmer stood at it, and would swallow the surplus before
	-- it ever walked to a chest or a hungry villager, so it waits for those.
	local pending = false
	for _, job in ipairs(jobs) do
		if job.wanted then
			local target, distance = nearest(session, pos, job.positions, now)
			if target and distance <= (job.reach or REACH) and not (job.last_resort and pending) then
				face(self, pos, target)
				job.work(self, target, session, now)
				return "worked"
			end
			pending = pending or target ~= nil
		end
	end
	for _, job in ipairs(jobs) do
		if job.wanted then
			-- A plot it cannot reach gives way to the next nearest, a tick later.
			local target = nearest(session, pos, job.positions, now)
			if target then
				if job.on_walk then job.on_walk() end
				if walk_to(self, session, target, now) then return "walking" end
				return "worked"
			end
		end
	end
	return nil
end

local function tick(self, session, now)
	if self._villages_farm_target then
		local route = self._villages_farm_route
		if route and route.status == "planning" then return end
		if route and route.status == "retry" then
			session.skip[key(self._villages_farm_target)] = now + SKIP_SECONDS
		end
		self._villages_farm_target = nil
		self._villages_farm_route = nil
	end
	if now < session.next_at then return end
	session.next_at = now + TICK_SECONDS
	local pos = self.object:get_pos()
	if not pos then return end
	local step = next_step(self, session, pos, now)
	if step == "worked" then
		session.away = true
		session.hold_until = now + HOLD_SECONDS
	elseif step == "walking" then
		session.away = true
		session.hold_until = 0
	else
		release(self, session)
		session.next_at = now + IDLE_SECONDS
	end
end

local M = {}

-- common.activity_override: a farmer with work in its field is not called back.
function M.activity_override(villager, stage)
	if stage ~= "work" then return nil end
	local session = sessions[villager]
	if session and session.away then return "farm" end
	return nil
end

function M.install(def)
	local original_custom = def.do_custom
	local original_die = def.on_die

	def.do_custom = function(self, dtime)
		local result = original_custom(self, dtime)
		if result == false then return result end
		if not common.is_work_time(self) or not valid_farmer(self) or self.following or is_trading(self) then
			local session = sessions[self]
			if session and session.away then release(self, session) end
			return result
		end
		if self.state == "gowp" then return result end

		local session = session_of(self)
		local now = core.get_gametime()
		tick(self, session, now)
		if self.state ~= "gowp" and session.hold_until >= now then
			hold_still(self)
			-- As for a fishing session: do_states would turn a standing villager away.
			return false
		end
		return result
	end

	def.on_die = function(self, pos, cause)
		stock.drop_all(self, pos or self.object:get_pos())
		if original_die then return original_die(self, pos, cause) end
	end
end

-- One line for the Lookup Tool inspector (diagnostic.lua).
function M.status(villager)
	if villager._profession ~= "farmer" then return "not a farmer" end
	if not valid_farmer(villager) then return "no claimed composter" end
	if not common.is_work_time(villager) then return "off work" end
	local session = sessions[villager]
	if not session then return "not ticked yet" end
	if villager._villages_farm_target then return "on its way to " .. key(villager._villages_farm_target) end
	if session.away then return "working in its field" end
	return "nothing to do just now"
end

-- What it carries, for the same.
function M.pouch_status(villager)
	local parts = {}
	for name, count in pairs(villager._villages_farm_pouch or {}) do
		table.insert(parts, count .. " " .. name:gsub("^.*:", ""))
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "empty"
end

M.sessions = sessions
return M
