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
-- on, only children, free, once a day each (food.lua): adults, the farmer and its
-- household too, eat their dinner at the tavern or from what they own (possessions.lua),
-- and one with no money relies on alms (alms.lua). Its bread goes to its work chest past
-- BREAD_KEEP in the pouch, for the keeper to fetch and pay for (keeper_supply.lua); up to
-- OWN_BREAD loaves go in its belongings first, for its own dinner and to sell. The keeper's
-- emeralds left in its chest go in its belongings when it next stores its surplus. With
-- the economy off it feeds everyone free, as it always did.
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local field = dofile(core.get_modpath("living_villages") .. "/farm_field.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local compost = dofile(core.get_modpath("living_villages") .. "/farm_compost.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local wants = dofile(core.get_modpath("living_villages") .. "/wants.lua")
local news = dofile(core.get_modpath("living_villages") .. "/market_news.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")

-- Farm output (ticket 18). VoxeLibre's crops take some 2800 s of loaded time to ripen
-- beside their own kind, so a farmer mostly waits on its field. In the work stage, with
-- nothing else to do, it tends growing crops: each tend grows a crop one stage with
-- TEND_CHANCE times its hoe's gain (rate - 1, wants.lua), at most 1; a plot is tended at
-- most once in TEND_SECONDS, by any farmer. About 3.5 tends a plot a work day: a stone
-- hoe adds some 1.5 stages a day to a plot's 3, an iron one 3; by hand it does not tend.
local TEND_CHANCE = 0.85
local TEND_SECONDS = 120
-- How often it looks again at the other farmers' composters and what the village asks.
local LOOK_SECONDS = 30
local OTHERS_RANGE = 2 * field.RADIUS
local COMPOSTERS = {"mcl_composters:composter", "mcl_composters:composter_ready"}
for level = 1, 7 do COMPOSTERS[#COMPOSTERS + 1] = "mcl_composters:composter_" .. level end

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
	[BREAD] = 2,
	[BONE_MEAL] = BONE_MEAL_LIMIT_WITH_CHEST,
}
-- With the economy on, loaves over the keep go to its belongings, up to this many, for its
-- own dinners and to sell, before the rest goes in the chest for the keeper.
local OWN_BREAD = 4
-- With the economy on, wheat over the keep goes to its belongings, up to this much, for
-- sale to villagers (a leatherworker breeds its herd on it, herd.lua), before the rest
-- goes in the chest: the pouch and the chest are not goods it trades.
local SALE_WHEAT = 8
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

-- When each plot may next be tended, by whichever farmer (not saved).
local tended = {}

-- The claimed composters near its own, its own included, looked up every LOOK_SECONDS.
local function other_farms(self, session, now)
	if session.others and now < session.others_at then return session.others end
	local job = self._jobsite
	local r = OTHERS_RANGE
	local found = {}
	local minp = {x = job.x - r, y = job.y - field.HEIGHT, z = job.z - r}
	local maxp = {x = job.x + r, y = job.y + field.HEIGHT, z = job.z + r}
	for _, pos in ipairs(core.find_nodes_in_area(minp, maxp, COMPOSTERS)) do
		if core.get_meta(pos):get_string("villager") ~= "" then found[#found + 1] = pos end
	end
	session.others, session.others_at = found, now + LOOK_SECONDS
	return found
end

-- What a harvest of each crop is worth to the village (field.harvest_worth): at the best
-- price it has heard asked for the crop or what it makes, or, with no crop asked for at
-- all, at base prices. Looked up every LOOK_SECONDS.
local function crop_worth(self, session, now)
	if session.worth and now < session.worth_at then return session.worth end
	local asked = clock.enabled() and news.asking(news.heard(self, now)) or {}
	local any = false
	for _, crop in ipairs(field.CROPS) do
		if (asked[crop.product] or 0) > 0 or (crop.makes and (asked[crop.makes.item] or 0) > 0) then any = true end
	end
	local worth = field.harvest_worth(function(item)
		if any then return asked[item] end
		return ledger.price(item)
	end)
	session.worth, session.worth_at = worth, now + LOOK_SECONDS
	return worth
end

-- How likely a tend is to grow a crop, by the hoe in use: 0 by hand.
local function tend_chance(self)
	return math.min(TEND_CHANCE * (wants.tool_rate(self, "harvest") - 1), 1)
end

-- The growing crops not tended lately.
local function tendable(growing, now)
	local list = {}
	for _, crop in ipairs(growing) do
		if now >= (tended[key(crop.pos)] or 0) then list[#list + 1] = crop.pos end
	end
	return list
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
	-- A hoe multiplies the harvest and wears (wants.lua, ticket 18); a book makes the next
	-- job come sooner.
	local yield = wants.tool_use(self, "harvest", possessions.take_held, now)
	local drops = field.harvest(pos, yield)
	if not drops then return end
	session.next_at = now + TICK_SECONDS / wants.reading_rate(self, possessions.take_held, now)
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
	local own = clock.enabled() and ({[WHEAT] = SALE_WHEAT, [BREAD] = OWN_BREAD})[item]
	if own then
		local room = own - possessions.count(self, item)
		local moved = room > 0 and stock.take(self, item, math.min(room, extra)) or 0
		if moved > 0 then
			possessions.add(self, item, moved)
			extra = extra - moved
		end
		if extra <= 0 then return end
	end
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

local function plant(self, pos, session, now)
	local seed = field.choose_seed(pos, function(name) return stock.count(self, name) end,
		session and crop_worth(self, session, now))
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

-- Whether it feeds this villager: with the economy on, a child only (adults eat at the
-- tavern or from what they own); with it off, everyone, as it always did.
local function feeds(self, target)
	return not clock.enabled() or (target.child and target ~= self)
end

local function deal_for(self, target, session)
	if not feeds(self, target) or not spare_food(self, session) then return nil end
	return "free"
end

-- Whether to seek this villager out: someone it can serve now, or, while it has no food
-- at all, someone it would serve once it fetches some (plot_jobs).
local function worth_seeking(self, target, session)
	if deal_for(self, target, session) then return true end
	return feeds(self, target) and not spare_food(self, session)
end

-- Feeds the villager on its terms, from what the farmer can spare.
local function hand_over(self, target, session)
	local deal = deal_for(self, target, session)
	if not deal then return false end
	local given
	while food.wants(target) do
		local item = spare_food(self, session)
		if not item then break end
		stock.take(self, item, 1)
		food.receive(target, item)
		given = item
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
			positions = seeds and #farm.empty == 0 and field.tillable(self._jobsite, farm.soil, farm.others, #farm.own_soil) or {},
			wanted = seeds,
			work = function(_, pos) field.till(pos, #farm.own_soil) end,
		},
		{
			positions = field.least_grown(farm.growing),
			wanted = stock.count(self, BONE_MEAL) > 0,
			work = fertilise,
		},
		{
			positions = tendable(farm.growing, now),
			wanted = tend_chance(self) > 0,
			work = function(_, pos)
				tended[key(pos)] = now + TEND_SECONDS
				field.tend(pos, tend_chance(self))
			end,
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
	local others = other_farms(self, session, now)
	local farm = field.scan(self._jobsite, others)
	farm.others = others
	session.sowing = #farm.empty > 0 or #field.tillable(self._jobsite, farm.soil, others, #farm.own_soil) > 0
	-- With the economy off it looks after itself first (on, it eats its own bread at dinner).
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
