-- Work for those without a job (docs/villager-economy-design.md, ticket 7): a nitwit, or
-- an unemployed villager with no jobsite, picks up an activity for the day and spends
-- its work stage at it, gathering goods into its belongings (possessions.lua) to eat
-- or to sell at the end of a conversation (exchange.lua). Vanilla's job claim runs
-- before this every tick (get_a_job in mobs_mc/villager.lua's do_activity), so an
-- unemployed villager that finds a jobsite takes it, and labour stops once it has one.
--
-- The choice, made at the first work tick of each game day (`_villages_labour`):
-- each activity's expected income, the best price the villager has heard asked for its
-- goods (market news, market_news.lua) times the rate it gathers them, with yesterday's
-- choice counted YESTERDAY_BIAS times over so a village does not all switch at once.
-- With no price heard for any, it picks at random among the activities it has a site
-- for. An activity with no site is never chosen.
--
-- Activities take only what comes back:
-- * forager: within FORAGE_RADIUS of its bed, sweet berry bushes at their last two
--   stages (left at the first, as a player's picking leaves them), sugar cane above its
--   bottom block, and apples lying on the ground. Flowers and mushrooms do not come
--   back once picked, so they are left.
-- * woodcutter: a grove of its own, at most GROVE_MAX saplings it planted
--   (`_villages_grove`), on open grass GROVE_MIN to GROVE_RADIUS from its bed with a
--   clear GROVE_CLEAR box above and no path or building near, so a tree never blocks
--   a road. A sapling grown into a tree is felled, its logs taken and a sapling of its
--   kind planted. Wild trees are never cut: with no sapling and no grove it takes one
--   sapling from under a wild tree, once a day. Any species that grows from a single
--   sapling (SPECIES: oak, birch, spruce, jungle, acacia), so a savanna village cuts
--   acacia. Charcoal waits for jobsite crafting (ticket 8).
--
-- Trips are planned walks (navigation.lua's gopath), within 50 of the bed, so vanilla
-- never calls the villager home mid-trip. A trunk is solid, so a trip to a tree ends on
-- an open cell beside it. A target it could not reach is passed over for SKIP_SECONDS
-- (kept in memory only). With the economy off nothing happens.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local news = dofile(core.get_modpath("living_villages") .. "/market_news.lua")

local TICK_SECONDS = 2
local RETRY_SECONDS = 60
local SKIP_SECONDS = 300
local REACH = 2.5
local YESTERDAY_BIAS = 1.25
-- Of one gathered good, it keeps no more than this; past it, that good is left.
local KEEP_GATHERED = 32
local FORAGE_RADIUS, FORAGE_HEIGHT = 32, 8
local GROVE_MAX = 8
local GROVE_MIN, GROVE_RADIUS, GROVE_HEIGHT = 8, 20, 6
-- Across (each way from the trunk) and up: the box a grown oak needs.
local GROVE_CLEAR, GROVE_CLEAR_UP = 3, 7
local GROVE_SPACING = 5
local PATH_GAP = 3
local WILD_TREE_RADIUS = 32
-- An acacia's crown leans up to 3 out from its trunk; GROVE_CLEAR keeps others that far.
local BRANCH_RADIUS, TRUNK_MAX = 3, 12

-- Trees that grow from one sapling: log, sapling and leaves.
local SPECIES = {
	{log = "mcl_core:tree", sapling = "mcl_core:sapling", leaves = "mcl_core:leaves"},
	{log = "mcl_core:birchtree", sapling = "mcl_core:birchsapling", leaves = "mcl_core:birchleaves"},
	{log = "mcl_core:sprucetree", sapling = "mcl_core:sprucesapling", leaves = "mcl_core:spruceleaves"},
	{log = "mcl_core:jungletree", sapling = "mcl_core:junglesapling", leaves = "mcl_core:jungleleaves"},
	{log = "mcl_core:acaciatree", sapling = "mcl_core:acaciasapling", leaves = "mcl_core:acacialeaves"},
}
local BY_LOG, BY_SAPLING, LOGS, SAPLINGS = {}, {}, {}, {}
for _, species in ipairs(SPECIES) do
	BY_LOG[species.log], BY_SAPLING[species.sapling] = species, species
	LOGS[#LOGS + 1], SAPLINGS[#SAPLINGS + 1] = species.log, species.sapling
end
local BERRY = "mcl_farming:sweet_berry"
local CANE = "mcl_core:reeds"
local APPLE = "mcl_core:apple"
local RIPE_BUSHES = {["mcl_farming:sweet_berry_bush_2"] = {1, 2}, ["mcl_farming:sweet_berry_bush_3"] = {2, 3}}
local PICKED_BUSH = "mcl_farming:sweet_berry_bush_1"
local GRASS = {"mcl_core:dirt_with_grass"}
-- What may stand where a tree will grow.
local OPEN = {"air", "group:plant", "group:flower", "group:grass"}

-- Rates in goods per work stage, for the choice; the goods and their shares.
local ACTIVITIES = {
	forager = {rate = 12, goods = {[BERRY] = 0.5, [APPLE] = 0.25, [CANE] = 0.25}},
	woodcutter = {rate = 10, goods = {}},
}
-- A woodcutter's goods are one species at a time: the best price heard for any.
for _, species in ipairs(SPECIES) do
	ACTIVITIES.woodcutter.goods[species.log] = 0.9
	ACTIVITIES.woodcutter.goods[species.sapling] = 0.1
end
local NAMES = {"forager", "woodcutter"}

local M = {
	ACTIVITIES = ACTIVITIES, YESTERDAY_BIAS = YESTERDAY_BIAS, GROVE_MAX = GROVE_MAX,
	KEEP_GATHERED = KEEP_GATHERED,
}

local function short_id(self)
	return tostring(self._id):sub(1, 6)
end

-- Targets each villager could not reach, by position, until when. Not saved.
local skipped = setmetatable({}, {__mode = "k"})

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function is_skipped(self, pos)
	local list = skipped[self]
	return list ~= nil and (list[key(pos)] or 0) > core.get_gametime()
end

local function skip(self, pos)
	skipped[self] = skipped[self] or {}
	skipped[self][key(pos)] = core.get_gametime() + SKIP_SECONDS
end

local function walkable(name)
	if name == "air" then return false end
	local def = core.registered_nodes and core.registered_nodes[name]
	return not def or def.walkable ~= false
end

-- An open cell beside pos with a floor, to stand in and reach pos from, or nil.
local function beside(pos)
	for _, offset in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
		local cell = {x = pos.x + offset[1], y = pos.y, z = pos.z + offset[2]}
		local here = core.get_node_or_nil(cell)
		local head = core.get_node_or_nil({x = cell.x, y = cell.y + 1, z = cell.z})
		local floor = core.get_node_or_nil({x = cell.x, y = cell.y - 1, z = cell.z})
		if here and head and floor and not walkable(here.name) and not walkable(head.name) and walkable(floor.name) then
			return cell
		end
	end
	return nil
end

function M.eligible(self)
	if self.child or not self._id or not clock.enabled() or self._villages_keeper then return false end
	return self._profession == "nitwit" or (self._profession == "unemployed" and not self._jobsite)
end

-- The best price asked for each item among what it has heard.
local function asking_prices(heard)
	local best = {}
	for _, entry in ipairs(heard) do
		if entry.kind == "needs" and entry.price and entry.price > (best[entry.item] or 0) then
			best[entry.item] = entry.price
		end
	end
	return best
end

-- Expected income of each activity from what it has heard.
function M.incomes(heard)
	local prices = asking_prices(heard)
	local incomes = {}
	for name, activity in pairs(ACTIVITIES) do
		local income = 0
		if name == "woodcutter" then
			for _, species in ipairs(SPECIES) do
				local here = activity.rate * (0.9 * (prices[species.log] or 0) + 0.1 * (prices[species.sapling] or 0))
				income = math.max(income, here)
			end
		else
			for item, share in pairs(activity.goods) do income = income + activity.rate * share * (prices[item] or 0) end
		end
		incomes[name] = income
	end
	return incomes
end

-- The day's activity among `available` (a set of names), or nil if none. roll is in [0, 1).
function M.choose(heard, available, yesterday, roll)
	local incomes = M.incomes(heard)
	local best, best_score
	local open = {}
	for _, name in ipairs(NAMES) do
		if available[name] then
			open[#open + 1] = name
			local score = incomes[name] * (name == yesterday and YESTERDAY_BIAS or 1)
			if score > 0 and (not best_score or score > best_score) then best, best_score = name, score end
		end
	end
	if best then return best end
	if #open == 0 then return nil end
	return open[math.floor(roll * #open) + 1]
end

local function area(center, radius, height)
	return {x = center.x - radius, y = center.y - height, z = center.z - radius},
		{x = center.x + radius, y = center.y + height, z = center.z + radius}
end

-- Forager sites.

local function ripe_bushes(bed)
	local names = {}
	for name in pairs(RIPE_BUSHES) do names[#names + 1] = name end
	local minp, maxp = area(bed, FORAGE_RADIUS, FORAGE_HEIGHT)
	return core.find_nodes_in_area(minp, maxp, names)
end

-- Cane tops: a cane block on a cane block, the highest of its column.
local function cane_tops(bed)
	local found = {}
	local minp, maxp = area(bed, FORAGE_RADIUS, FORAGE_HEIGHT)
	for _, pos in ipairs(core.find_nodes_in_area(minp, maxp, {CANE})) do
		local below = core.get_node_or_nil({x = pos.x, y = pos.y - 1, z = pos.z})
		local above = core.get_node_or_nil({x = pos.x, y = pos.y + 1, z = pos.z})
		if below and below.name == CANE and not (above and above.name == CANE) then found[#found + 1] = pos end
	end
	return found
end

local function fallen(bed, items)
	local found = {}
	for _, object in ipairs(core.get_objects_inside_radius(bed, FORAGE_RADIUS)) do
		local entity = object:get_luaentity()
		local name = entity and entity.name == "__builtin:item" and ItemStack(entity.itemstring):get_name()
		if name and items[name] then found[#found + 1] = {pos = vector.round(object:get_pos()), object = object} end
	end
	return found
end

-- Every forager target, as {pos, kind, object}.
function M.forage_targets(self)
	local bed = self._bed
	local targets = {}
	if not bed then return targets end
	if possessions.count(self, BERRY) < KEEP_GATHERED then
		for _, pos in ipairs(ripe_bushes(bed)) do targets[#targets + 1] = {pos = pos, kind = "berries"} end
	end
	if possessions.count(self, CANE) < KEEP_GATHERED then
		for _, pos in ipairs(cane_tops(bed)) do targets[#targets + 1] = {pos = pos, kind = "cane"} end
	end
	if possessions.count(self, APPLE) < KEEP_GATHERED then
		for _, item in ipairs(fallen(bed, {[APPLE] = true})) do
			targets[#targets + 1] = {pos = item.pos, kind = "apple", object = item.object}
		end
	end
	return targets
end

-- Gathers at one target. Returns the item and how many, or nil.
function M.forage(self, target)
	if target.kind == "berries" then
		local node = core.get_node_or_nil(target.pos)
		local yield = node and RIPE_BUSHES[node.name]
		if not yield then return nil end
		local count = math.random(yield[1], yield[2])
		core.swap_node(target.pos, {name = PICKED_BUSH})
		possessions.add(self, BERRY, count)
		return BERRY, count
	elseif target.kind == "cane" then
		local count, pos = 0, vector.new(target.pos)
		while true do
			local node = core.get_node_or_nil(pos)
			local below = core.get_node_or_nil({x = pos.x, y = pos.y - 1, z = pos.z})
			if not (node and node.name == CANE and below and below.name == CANE) then break end
			core.remove_node(pos)
			count = count + 1
			pos.y = pos.y - 1
		end
		if count == 0 then return nil end
		possessions.add(self, CANE, count)
		return CANE, count
	elseif target.kind == "apple" then
		local object = target.object
		local entity = object and object:get_luaentity()
		if not entity or not entity.itemstring then return nil end
		local stack = ItemStack(entity.itemstring)
		object:remove()
		possessions.add(self, stack:get_name(), stack:get_count())
		return stack:get_name(), stack:get_count()
	end
	return nil
end

-- Woodcutter sites.

local function grove(self)
	self._villages_grove = self._villages_grove or {}
	return self._villages_grove
end

local function count_in(minp, maxp, names)
	return #core.find_nodes_in_area(minp, maxp, names)
end

-- Whether an oak may grow from a sapling at pos (the cell above the grass): open above
-- and around, no path or building near, and no other grove tree too close.
function M.grove_spot_ok(self, pos)
	local minp = {x = pos.x - GROVE_CLEAR, y = pos.y, z = pos.z - GROVE_CLEAR}
	local maxp = {x = pos.x + GROVE_CLEAR, y = pos.y + GROVE_CLEAR_UP - 1, z = pos.z + GROVE_CLEAR}
	local volume = (2 * GROVE_CLEAR + 1) ^ 2 * GROVE_CLEAR_UP
	if count_in(minp, maxp, OPEN) < volume then return false end
	local pmin = {x = pos.x - PATH_GAP, y = pos.y - 2, z = pos.z - PATH_GAP}
	local pmax = {x = pos.x + PATH_GAP, y = pos.y, z = pos.z + PATH_GAP}
	if count_in(pmin, pmax, {"group:path", "group:door", "group:bed"}) > 0 then return false end
	for _, other in ipairs(grove(self)) do
		if vector.distance(other, pos) < GROVE_SPACING then return false end
	end
	return true
end

-- A new grove spot, nearest the bed first, or nil.
function M.grove_spot(self)
	local bed = self._bed
	if not bed then return nil end
	local minp, maxp = area(bed, GROVE_RADIUS, GROVE_HEIGHT)
	local candidates = {}
	for _, ground in ipairs(core.find_nodes_in_area_under_air(minp, maxp, GRASS)) do
		local pos = {x = ground.x, y = ground.y + 1, z = ground.z}
		local distance = vector.distance(pos, bed)
		if distance >= GROVE_MIN and distance <= GROVE_RADIUS then
			candidates[#candidates + 1] = {pos = pos, distance = distance}
		end
	end
	table.sort(candidates, function(a, b) return a.distance < b.distance end)
	for _, candidate in ipairs(candidates) do
		if M.grove_spot_ok(self, candidate.pos) then return candidate.pos end
	end
	return nil
end

-- A wild tree to take a sapling from under: the foot of a trunk with its own leaves
-- above, which the logs in a house never have. Returns its position and species.
local function wild_tree(self)
	if not self._bed then return nil end
	local minp, maxp = area(self._bed, WILD_TREE_RADIUS, FORAGE_HEIGHT)
	for _, pos in ipairs(core.find_nodes_in_area(minp, maxp, LOGS)) do
		local species = BY_LOG[core.get_node_or_nil(pos).name]
		local below = core.get_node_or_nil({x = pos.x, y = pos.y - 1, z = pos.z})
		if species and below and not BY_LOG[below.name] and not is_skipped(self, pos) and beside(pos)
			and count_in({x = pos.x - 3, y = pos.y, z = pos.z - 3}, {x = pos.x + 3, y = pos.y + 10, z = pos.z + 3}, {species.leaves}) > 0 then
			return pos, species
		end
	end
	return nil
end

-- A sapling it carries, or nil.
local function carried_sapling(self)
	for _, sapling in ipairs(SAPLINGS) do
		if possessions.count(self, sapling) > 0 then return sapling end
	end
	return nil
end

-- Fells the grove tree standing at pos: its trunk and branches, of its own species.
-- Returns the log and how many.
function M.fell(pos)
	local species = BY_LOG[core.get_node_or_nil(pos).name]
	if not species then return nil, 0 end
	local logs = 0
	local minp = {x = pos.x - BRANCH_RADIUS, y = pos.y, z = pos.z - BRANCH_RADIUS}
	local maxp = {x = pos.x + BRANCH_RADIUS, y = pos.y + TRUNK_MAX, z = pos.z + BRANCH_RADIUS}
	for _, log in ipairs(core.find_nodes_in_area(minp, maxp, {species.log})) do
		core.remove_node(log)
		logs = logs + 1
	end
	return species.log, logs
end

-- The woodcutter's next job: {pos, kind, index}, or nil.
function M.wood_target(self)
	local spots = grove(self)
	for i, pos in ipairs(spots) do
		local node = core.get_node_or_nil(pos)
		local species = node and BY_LOG[node.name]
		if species and possessions.count(self, species.log) < KEEP_GATHERED * 2 then
			return {pos = pos, kind = "fell", index = i}
		end
		if node and not species and not BY_SAPLING[node.name] then return {pos = pos, kind = "replant", index = i} end
	end
	if carried_sapling(self) and #spots < GROVE_MAX then
		local spot = M.grove_spot(self)
		if spot then return {pos = spot, kind = "plant"} end
	end
	if #spots == 0 and not carried_sapling(self) and self._villages_sapling_day ~= core.get_day_count() then
		local tree, species = wild_tree(self)
		if tree then return {pos = tree, kind = "sapling", sapling = species.sapling} end
	end
	return nil
end

-- Plants a sapling it carries at pos, `prefer`'s kind if it has one.
local function plant(self, pos, prefer)
	local below = core.get_node_or_nil({x = pos.x, y = pos.y - 1, z = pos.z})
	if not below or core.get_item_group(below.name, "soil_sapling") == 0 then return false end
	local sapling = (prefer and possessions.count(self, prefer) > 0) and prefer or carried_sapling(self)
	if not sapling or possessions.take(self, sapling, 1) < 1 then return false end
	core.set_node(pos, {name = sapling})
	return true
end

-- Works one woodcutter job. Returns the item gained and how many, or nil.
function M.cut(self, target)
	local spots = grove(self)
	if target.kind == "fell" then
		local log, logs = M.fell(target.pos)
		if not log then return nil end
		local sapling = BY_LOG[log].sapling
		possessions.add(self, log, logs)
		possessions.add(self, sapling, 1)
		if not plant(self, target.pos, sapling) then table.remove(spots, target.index) end
		return log, logs
	elseif target.kind == "replant" then
		local node = core.get_node_or_nil(target.pos)
		if not (node and node.name == "air" and plant(self, target.pos)) then table.remove(spots, target.index) end
		return nil
	elseif target.kind == "plant" then
		if M.grove_spot_ok(self, target.pos) and plant(self, target.pos) then
			spots[#spots + 1] = vector.new(target.pos)
		end
		return nil
	elseif target.kind == "sapling" then
		self._villages_sapling_day = core.get_day_count()
		possessions.add(self, target.sapling, 1)
		return target.sapling, 1
	end
	return nil
end

-- The day.

local function available(self)
	local open = {}
	if #M.forage_targets(self) > 0 then open.forager = true end
	if #grove(self) > 0 or carried_sapling(self) or wild_tree(self) then open.woodcutter = true end
	return open
end

-- Today's activity, choosing it first if the day is new.
function M.today(self)
	local day = core.get_day_count()
	local labour = self._villages_labour
	if labour and labour.day == day then return labour.activity end
	local yesterday = labour and labour.activity
	local activity = M.choose(news.heard(self), available(self), yesterday, math.random())
	self._villages_labour = {day = day, activity = activity}
	if activity then
		core.log("action", string.format("[living_villages] villager %s (%s) works as a %s today",
			short_id(self), tostring(self._profession), activity))
	else
		local trees = 0
		if self._bed then
			local minp, maxp = area(self._bed, WILD_TREE_RADIUS, FORAGE_HEIGHT)
			trees = #core.find_nodes_in_area(minp, maxp, LOGS)
		end
		core.log("action", string.format("[living_villages] villager %s (%s) finds no work today (bed %s, %d logs near)",
			short_id(self), tostring(self._profession), self._bed and core.pos_to_string(self._bed) or "none", trees))
	end
	return activity
end

local function busy(self)
	local walk = self._villages_goto_route
	return self.state == "gowp" or self.following ~= nil or (walk ~= nil and walk.status == "planning")
end

local function nearest(pos, targets)
	local best, best_distance
	for _, target in ipairs(targets) do
		local distance = vector.distance(pos, target.pos)
		if not best or distance < best_distance then best, best_distance = target, distance end
	end
	return best, best_distance
end

local function work(self, activity, target)
	local item, count
	if activity == "forager" then item, count = M.forage(self, target) else item, count = M.cut(self, target) end
	if item then
		core.log("action", string.format("[living_villages] villager %s gathered %d %s", short_id(self), count, item))
	elseif target.kind == "plant" or target.kind == "replant" then
		core.log("action", string.format("[living_villages] villager %s tended its grove at %s (%d trees)",
			short_id(self), core.pos_to_string(target.pos), #(self._villages_grove or {})))
	end
end

-- One tick of the work stage.
function M.step(self, now)
	if self._villages_labour_target then
		-- A walk that ended without arriving: try again later.
		core.log("action", string.format("[living_villages] villager %s did not reach %s",
			short_id(self), core.pos_to_string(self._villages_labour_target)))
		skip(self, self._villages_labour_target)
		self._villages_labour_target = nil
		self._villages_labour_next = now + RETRY_SECONDS
		return
	end
	if now < (self._villages_labour_next or 0) then return end
	self._villages_labour_next = now + TICK_SECONDS
	local activity = M.today(self)
	local pos = self.object:get_pos()
	if not activity or not pos then return end
	local target, distance
	if activity == "forager" then
		local open = {}
		for _, candidate in ipairs(M.forage_targets(self)) do
			if not is_skipped(self, candidate.pos) then open[#open + 1] = candidate end
		end
		target, distance = nearest(pos, open)
	else
		target = M.wood_target(self)
		if target and is_skipped(self, target.pos) then target = nil end
		distance = target and vector.distance(pos, target.pos)
	end
	if not target then
		self._villages_labour_next = now + RETRY_SECONDS
		return
	end
	if distance <= REACH then return work(self, activity, target) end
	-- Trunks are solid: stand beside one.
	local goal = target.pos
	if target.kind == "sapling" or target.kind == "fell" then goal = beside(target.pos) end
	if not goal then
		skip(self, target.pos)
		return
	end
	self._villages_labour_target = vector.new(target.pos)
	local started = self:gopath(goal, function(entity)
		entity._villages_labour_target = nil
		local at = entity.object:get_pos()
		if at and vector.distance(at, target.pos) <= REACH + 1 then
			work(entity, activity, target)
		else
			skip(entity, target.pos)
		end
	end, true)
	if started == false then
		self._villages_labour_target = nil
		self._villages_labour_next = now + RETRY_SECONDS
		skip(self, target.pos)
		core.log("action", string.format("[living_villages] villager %s (%s) found no way to %s",
			short_id(self), activity, core.pos_to_string(target.pos)))
	else
		core.log("action", string.format("[living_villages] villager %s (%s) sets off to %s at %s",
			short_id(self), activity, target.kind, core.pos_to_string(target.pos)))
	end
end

function M.install(def)
	if not clock.enabled() then return end
	local original = def.do_custom
	def.do_custom = function(self, dtime)
		local result = original(self, dtime)
		if result == false or not M.eligible(self) then return result end
		if common.schedule_stage(nil, self) ~= "work" then
			self._villages_labour_target = nil
			return result
		end
		if not busy(self) then M.step(self, core.get_gametime()) end
		return result
	end
end

-- One line for the inspector.
function M.status(self)
	if not M.eligible(self) then return "not looking for work" end
	local labour = self._villages_labour
	if not labour or labour.day ~= core.get_day_count() then return "not chosen today" end
	local text = labour.activity or "nothing to do"
	if labour.activity == "woodcutter" then text = text .. ", grove of " .. #(self._villages_grove or {}) end
	return text
end

return M
