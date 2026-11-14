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
-- * woodcutter: a grove of its own, at most GROVE_MAX saplings it planted (GROVE_MAX_JOB
--   for a woodcutter by trade, woodcutter.lua, whose grove is around its chopping block)
--   (`_villages_grove`), on open grass GROVE_MIN to GROVE_RADIUS from its bed with a
--   clear GROVE_CLEAR box above and no path or building near, so a tree never blocks
--   a road. A sapling grown into a tree is felled, its logs taken and a sapling of its
--   kind planted, with a second sapling while the grove is short of trees, as a felled
--   tree's leaves would drop. Wild trees are never cut: a grove short of trees, with no
--   sapling to plant, takes one sapling from under a wild tree, once a day. Any species that grows from a single
--   sapling (SPECIES: oak, birch, spruce, jungle, acacia), so a savanna village cuts
--   acacia. Of the logs it carries past CHARCOAL_KEEP, every CHARCOAL_LOGS become
--   CHARCOAL_MAKES charcoal after a felling, up to KEEP_GATHERED: eight logs smelted with
--   one lump of the charcoal as fuel, as a furnace would, burned in a clamp by the
--   grove. Charcoal stands in for coal (ledger.lua), so the smiths' fuel can come from
--   the village (production.lua).
-- * quarrier (ticket 11): mines the cobble a player's cobblestone generator makes,
--   within QUARRY_RADIUS of its bed, up to QUARRY_KEEP. A generator's cobble is told
--   from terrain by what made it: VoxeLibre's "Lava cooling" ABM (mcl_core/functions.lua)
--   turns flowing lava into cobble where water touches it from the side or above, so a
--   cobble node with lava and water both beside or above it is one; taken, the lava
--   flows back and cools again. Terrain is never dug.
-- * porter (ticket 11): carries goods for others on trade trips (trade_trips.lua), hired
--   at the end of a conversation; labour.lua only chooses it. Its site is the market: it
--   is open when the villager has heard of an item one villager needs and another has
--   spare. Its income is what it has found portering pays (ticket 12): one PORTER_FEE
--   times its hires over its porter days, counted from one hire in two days
--   (`_villages_porter_record`, {days, hires}: days counted here, hires by
--   trade_trips.lua), so a porter nobody hires turns to other work. A flat two fees a day
--   had every unemployed villager portering, unhired, over any small peddling deal.
--   Gathering is learnt the same way (ticket 12b): an activity's rate is scaled by what
--   it has gathered over the days it was chosen, counted from one day at its full rate
--   (`_villages_gather_record`, {[activity] = {days, made}}). A woodcutter with no grove
--   was reckoned at ten logs a day and chose it over every peddling deal while it felled
--   four logs in eleven days (the Markets world, 2026-11-11).
-- * peddler (ticket 12): buys surplus below the going price and sells where it has heard
--   of need, keeping the margin. Its site is the market too: a deal is an item it has
--   heard one villager has spare at one price and another needs at PEDDLE_MARGIN times
--   that or more (M.deal). Its lot is as many as both sides and its emeralds allow, up
--   to PEDDLE_MAX, and its income the spread on it. Choosing it sets `_villages_peddle`:
--   {item, count, bid, sell_at, day, buying}. The bid is BID_SHARE of the way from the
--   asking price to the need's. Buying, its ledger wants the lot at the bid and no more
--   (possessions.assess), so its trade trips (trade_trips.lua) and conversations buy it.
--   Holding the lot, or after PEDDLE_BUY_DAYS, it sells: what it holds is spare, at no
--   less than the bid, through conversations, buyers' trips to it and its market stall
--   (market_stall.lua). Sold out, or after PEDDLE_DAYS, the peddle ends (M.peddle_tick).
--
-- Home. Every radius above is from the villager's bed. One with no bed (a village has
-- more villagers than free beds) works from the nearest village bell within BELL_RADIUS
-- of where it stands when it chooses its day, or with none from that spot
-- (`_villages_labour_home`, chosen afresh each day, so a bed claimed later takes over).
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
local tally = dofile(core.get_modpath("living_villages") .. "/economy_tally.lua")
local wants = dofile(core.get_modpath("living_villages") .. "/wants.lua")
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")

local TICK_SECONDS = 2
local RETRY_SECONDS = 60
local SKIP_SECONDS = 300
local REACH = 2.5
local YESTERDAY_BIAS = 1.25
-- Of one gathered good, it keeps no more than this; past it, that good is left.
local KEEP_GATHERED = 32
local FORAGE_RADIUS, FORAGE_HEIGHT = 32, 8
local GROVE_MAX = 8
-- A woodcutter with a chopping block (woodcutter.lua, ticket 16): woodcutting is its job.
local GROVE_MAX_JOB = 12
local GROVE_MIN, GROVE_RADIUS, GROVE_HEIGHT = 8, 20, 6
-- Across (each way from the trunk) and up: the box a grown oak needs.
local GROVE_CLEAR, GROVE_CLEAR_UP = 3, 7
local GROVE_SPACING = 5
local PATH_GAP = 3
local WILD_TREE_RADIUS = 32
-- An acacia's crown leans up to 3 out from its trunk; GROVE_CLEAR keeps others that far.
local BRANCH_RADIUS, TRUNK_MAX = 3, 12
local CHARCOAL = "mcl_core:charcoal_lump"
local CHARCOAL_KEEP, CHARCOAL_LOGS, CHARCOAL_MAKES = 16, 8, 7
local COBBLE = "mcl_core:cobble"
local QUARRY_RADIUS, QUARRY_HEIGHT = 32, 8
-- A Builder wants cobble by the hundred, so a quarrier keeps more of it.
local QUARRY_KEEP = 64
local BELL = "mcl_bells:bell"
local BELL_RADIUS, BELL_HEIGHT = 48, 16
local PEDDLE_MARGIN = 1.5
local PEDDLE_MAX = 16
local BID_SHARE = 1 / 3
local PEDDLE_BUY_DAYS = 1
local PEDDLE_DAYS = 4
-- Where lava or water may touch a generator's cobble from: the four sides and above.
local TOUCHING = {{1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}, {0, 1, 0}}

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
	quarrier = {rate = 32, goods = {[COBBLE] = 1}},
	porter = {rate = 0, goods = {}},
	peddler = {rate = 0, goods = {}},
}
-- trade_trips.lua's PORTER_FEE, in emeralds at ledger.SCALE (ticket 11h).
local PORTER_FEE = 1 * dofile(core.get_modpath("living_villages") .. "/ledger.lua").SCALE
-- A woodcutter's goods are one species at a time: the best price heard for any.
for _, species in ipairs(SPECIES) do
	ACTIVITIES.woodcutter.goods[species.log] = 0.9
	ACTIVITIES.woodcutter.goods[species.sapling] = 0.1
end
local NAMES = {"forager", "woodcutter", "quarrier", "porter", "peddler"}

local M = {
	ACTIVITIES = ACTIVITIES, YESTERDAY_BIAS = YESTERDAY_BIAS, GROVE_MAX = GROVE_MAX,
	KEEP_GATHERED = KEEP_GATHERED, CHARCOAL_KEEP = CHARCOAL_KEEP, QUARRY_KEEP = QUARRY_KEEP,
	PEDDLE_MARGIN = PEDDLE_MARGIN, PEDDLE_MAX = PEDDLE_MAX, BID_SHARE = BID_SHARE,
	PEDDLE_BUY_DAYS = PEDDLE_BUY_DAYS, PEDDLE_DAYS = PEDDLE_DAYS,
}

local function short_id(self)
	return tostring(self._id):sub(1, 6)
end

-- Targets each villager could not reach, by position, until when. Not saved.
local skipped = setmetatable({}, {__mode = "k"})

-- Where its work is reckoned from: a woodcutter's chopping block (ticket 16), its bed,
-- or its day's home (M.choose_home).
local function home(self)
	if self._villages_woodcutter and self._jobsite then return self._jobsite end
	return self._bed or self._villages_labour_home
end
M.home = home

-- A bedless villager's home for the day: the nearest bell near it, or where it stands.
function M.choose_home(self)
	if self._bed then
		self._villages_labour_home = nil
		return self._bed
	end
	local pos = self.object and self.object:get_pos()
	if not pos then return self._villages_labour_home end
	pos = vector.round(pos)
	local best, best_distance
	for _, bell in ipairs(core.find_nodes_in_area(
		{x = pos.x - BELL_RADIUS, y = pos.y - BELL_HEIGHT, z = pos.z - BELL_RADIUS},
		{x = pos.x + BELL_RADIUS, y = pos.y + BELL_HEIGHT, z = pos.z + BELL_RADIUS}, {BELL})) do
		local distance = vector.distance(pos, bell)
		if distance <= BELL_RADIUS and (not best or distance < best_distance) then best, best_distance = bell, distance end
	end
	self._villages_labour_home = best and vector.new(best) or pos
	return self._villages_labour_home
end

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

-- An open cell beside pos with a floor, to stand in and reach pos from, or nil. A cell
-- holding `avoid` (cane, which is not walkable but no place to stand) is passed over.
local function beside(pos, avoid)
	for _, offset in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
		local cell = {x = pos.x + offset[1], y = pos.y, z = pos.z + offset[2]}
		local here = core.get_node_or_nil(cell)
		local head = core.get_node_or_nil({x = cell.x, y = cell.y + 1, z = cell.z})
		local floor = core.get_node_or_nil({x = cell.x, y = cell.y - 1, z = cell.z})
		if here and head and floor and not walkable(here.name) and not walkable(head.name) and walkable(floor.name)
			and here.name ~= avoid and head.name ~= avoid then
			return cell
		end
	end
	return nil
end

function M.eligible(self)
	if self.child or not self._id or not clock.enabled() or self._villages_keeper then return false end
	return self._profession == "nitwit" or (self._profession == "unemployed" and not self._jobsite)
end

-- Whether it has heard of a trade waiting: an item one villager needs and another has.
function M.trade_waiting(heard)
	local needed, offered = {}, {}
	for _, entry in ipairs(heard) do
		if entry.kind == "needs" then
			-- A category's need (ticket 15) is a need for any of its members.
			for item in pairs(news.items_of(entry)) do
				needed[item] = needed[item] or {}
				needed[item][entry.who] = true
			end
		end
		if entry.kind == "has" then offered[entry.item] = offered[entry.item] or {} offered[entry.item][entry.who] = true end
	end
	for item, buyers in pairs(needed) do
		for seller in pairs(offered[item] or {}) do
			for buyer in pairs(buyers) do
				if buyer ~= seller then return true end
			end
		end
	end
	return false
end

-- The best deal a peddler with `emeralds` has heard of, or nil: {item, count, bid,
-- sell_at, income}. The asking price is what the one with it spare values it at, the
-- selling price what the one in need does.
function M.deal(heard, emeralds)
	local best
	for _, has in ipairs(heard) do
		if has.kind == "has" and has.price and has.price > 0 then
			for _, need in ipairs(heard) do
				-- A category's need (ticket 15) takes any member, at its price per unit.
				local sell_at, want = need.price, need.count or 0
				if need.kind == "needs" and need.group and need.item ~= has.item and goods.fills(need, has.item) then
					local per = need.price / goods.units(need.group, need.item)
					local units = goods.units(need.group, has.item)
					sell_at = per * units
					want = math.floor(want * goods.units(need.group, need.item) / units)
				end
				if need.kind == "needs" and goods.fills(need, has.item) and need.who ~= has.who and sell_at
					and sell_at >= has.price * PEDDLE_MARGIN then
					local bid = has.price + (sell_at - has.price) * BID_SHARE
					local count = math.min(has.count or 0, want, PEDDLE_MAX, math.floor((emeralds or 0) / bid))
					local income = count * (sell_at - bid)
					if count >= 1 and (not best or income > best.income
						or (income == best.income and has.item < best.item)) then
						best = {item = has.item, count = count, bid = bid, sell_at = sell_at, income = income}
					end
				end
			end
		end
	end
	return best
end

-- What portering is worth a day to one with this record: a fee per hire it has had per
-- porter day, starting from one hire in two days.
function M.porter_income(record)
	record = record or {}
	return PORTER_FEE * ((record.hires or 0) + 1) / ((record.days or 0) + 2)
end

-- Expected income of each activity from what it has heard, with `emeralds` to buy with
-- and its portering `record`.
-- The share of an activity's full rate it has found it gathers, from its `yields`
-- record, counted from one day at the full rate.
function M.yield_share(activity, yields)
	local rate = ACTIVITIES[activity] and ACTIVITIES[activity].rate or 0
	local record = yields and yields[activity]
	if rate <= 0 or not record then return 1 end
	return math.min(1, ((record.made or 0) + rate) / (((record.days or 0) + 1) * rate))
end

function M.incomes(heard, emeralds, record, yields)
	local prices = news.asking(heard)
	local incomes = {}
	for name, activity in pairs(ACTIVITIES) do
		local income = 0
		if name == "porter" then
			income = M.trade_waiting(heard) and M.porter_income(record) or 0
		elseif name == "peddler" then
			local deal = M.deal(heard, emeralds)
			income = deal and deal.income or 0
		elseif name == "woodcutter" then
			for _, species in ipairs(SPECIES) do
				local here = activity.rate * (0.9 * (prices[species.log] or 0) + 0.1 * (prices[species.sapling] or 0))
				income = math.max(income, here)
			end
		else
			for item, share in pairs(activity.goods) do income = income + activity.rate * share * (prices[item] or 0) end
		end
		incomes[name] = income * M.yield_share(name, yields)
	end
	return incomes
end

-- The day's activity among `available` (a set of names), or nil if none. roll is in [0, 1).
function M.choose(heard, available, yesterday, roll, emeralds, record, yields)
	local incomes = M.incomes(heard, emeralds, record, yields)
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

-- Where to stand to cut the cane whose top is at pos: beside its column's foot, or
-- beside the block above it. Nil if neither has room and a floor.
local function beside_cane(pos)
	local foot = vector.new(pos)
	while true do
		local below = core.get_node_or_nil({x = foot.x, y = foot.y - 1, z = foot.z})
		if not (below and below.name == CANE) then break end
		foot.y = foot.y - 1
	end
	return beside(foot, CANE) or beside({x = foot.x, y = foot.y + 1, z = foot.z}, CANE)
end
M.beside_cane = beside_cane

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
	local bed = home(self)
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
	local bed = home(self)
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
	local bed = home(self)
	if not bed then return nil end
	local minp, maxp = area(bed, WILD_TREE_RADIUS, FORAGE_HEIGHT)
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

-- How far a trunk keeps leaves alive in VoxeLibre (mcl_core.update_leaves).
local LEAF_REACH = 6

-- The distance VoxeLibre's find_node_near measures: the largest of the three.
local function reach(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y), math.abs(a.z - b.z))
end

-- Leaves decay in VoxeLibre only once no trunk is within LEAF_REACH, and grove trees
-- stand GROVE_SPACING apart, so a felled tree's crown would be kept by its
-- neighbours for ever. Its own leaves (those nearer one of its logs than any standing
-- trunk) are turned to their orphan kind, which the game's leaf decay removes.
local function orphan_leaves(species, felled)
	local orphan = species.leaves .. "_orphan"
	if not core.registered_nodes[orphan] then return end
	local minp, maxp = vector.new(felled[1]), vector.new(felled[1])
	for _, log in ipairs(felled) do
		for _, axis in ipairs({"x", "y", "z"}) do
			minp[axis] = math.min(minp[axis], log[axis] - LEAF_REACH)
			maxp[axis] = math.max(maxp[axis], log[axis] + LEAF_REACH)
		end
	end
	local far = LEAF_REACH * 2
	local standing = core.find_nodes_in_area(
		{x = minp.x - LEAF_REACH, y = minp.y - LEAF_REACH, z = minp.z - LEAF_REACH},
		{x = maxp.x + LEAF_REACH, y = maxp.y + LEAF_REACH, z = maxp.z + LEAF_REACH}, {"group:tree"})
	for _, leaf in ipairs(core.find_nodes_in_area(minp, maxp, {species.leaves})) do
		local own = far
		for _, log in ipairs(felled) do own = math.min(own, reach(leaf, log)) end
		local kept = far
		for _, trunk in ipairs(standing) do kept = math.min(kept, reach(leaf, trunk)) end
		if own <= LEAF_REACH and own < kept and core.get_meta(leaf):get_int("player_leaves") ~= 1 then
			core.set_node(leaf, {name = orphan})
		end
	end
end

-- Fells the grove tree standing at pos: its trunk and branches, of its own species.
-- Its leaves are left to decay. Returns the log and how many.
function M.fell(pos)
	local species = BY_LOG[core.get_node_or_nil(pos).name]
	if not species then return nil, 0 end
	local minp = {x = pos.x - BRANCH_RADIUS, y = pos.y, z = pos.z - BRANCH_RADIUS}
	local maxp = {x = pos.x + BRANCH_RADIUS, y = pos.y + TRUNK_MAX, z = pos.z + BRANCH_RADIUS}
	local felled = core.find_nodes_in_area(minp, maxp, {species.log})
	for _, log in ipairs(felled) do core.remove_node(log) end
	if #felled > 0 then orphan_leaves(species, felled) end
	return species.log, #felled
end

local function grove_max(self)
	return self._villages_woodcutter and GROVE_MAX_JOB or GROVE_MAX
end

-- The woodcutter's next job: {pos, kind, index}, or nil.
function M.wood_target(self)
	local spots = grove(self)
	local max = grove_max(self)
	for i, pos in ipairs(spots) do
		local node = core.get_node_or_nil(pos)
		local species = node and BY_LOG[node.name]
		if species and possessions.count(self, species.log) < KEEP_GATHERED * 2 then
			return {pos = pos, kind = "fell", index = i}
		end
		if node and not species and not BY_SAPLING[node.name] then return {pos = pos, kind = "replant", index = i} end
	end
	if carried_sapling(self) and #spots < max then
		local spot = M.grove_spot(self)
		if spot then return {pos = spot, kind = "plant"} end
	end
	-- A grove short of trees takes a sapling from under a wild tree, once a day.
	if #spots < max and not carried_sapling(self) and self._villages_sapling_day ~= core.get_day_count() then
		local tree, species = wild_tree(self)
		if tree then return {pos = tree, kind = "sapling", sapling = species.sapling} end
	end
	return nil
end

-- Quarrier sites.

local function touched_by(pos, group)
	for _, offset in ipairs(TOUCHING) do
		local node = core.get_node_or_nil({x = pos.x + offset[1], y = pos.y + offset[2], z = pos.z + offset[3]})
		if node and core.get_item_group(node.name, group) > 0 then return true end
	end
	return false
end

-- Whether the cobble at pos is a generator's: lava and water both beside or above it.
function M.is_generated(pos)
	local node = core.get_node_or_nil(pos)
	return node ~= nil and node.name == COBBLE and touched_by(pos, "lava") and touched_by(pos, "water")
end

-- Every generator cobble within reach of its bed, as {pos, kind = "cobble"}.
function M.quarry_targets(self)
	local bed = home(self)
	local targets = {}
	if not bed or possessions.count(self, COBBLE) >= QUARRY_KEEP then return targets end
	local minp, maxp = area(bed, QUARRY_RADIUS, QUARRY_HEIGHT)
	for _, pos in ipairs(core.find_nodes_in_area(minp, maxp, {COBBLE})) do
		if M.is_generated(pos) then targets[#targets + 1] = {pos = pos, kind = "cobble"} end
	end
	return targets
end

-- Mines one generator cobble. Returns the item and how many, or nil.
function M.quarry(self, target)
	if not M.is_generated(target.pos) then return nil end
	core.remove_node(target.pos)
	possessions.add(self, COBBLE, 1)
	if core.sound_play then
		core.sound_play("default_dig_cracky", {pos = target.pos, gain = 0.5, max_hear_distance = 16}, true)
	end
	return COBBLE, 1
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

-- Turns logs it carries past CHARCOAL_KEEP into charcoal, the commonest log first.
-- Returns the charcoal made.
function M.burn_charcoal(self)
	local made = 0
	while possessions.count(self, CHARCOAL) < KEEP_GATHERED do
		local total, most, most_count = 0, nil, 0
		for _, log in ipairs(LOGS) do
			local count = possessions.count(self, log)
			total = total + count
			if count > most_count then most, most_count = log, count end
		end
		if total < CHARCOAL_KEEP + CHARCOAL_LOGS or most_count < CHARCOAL_LOGS then break end
		possessions.take(self, most, CHARCOAL_LOGS)
		possessions.add(self, CHARCOAL, CHARCOAL_MAKES)
		tally.note(self, {[CHARCOAL] = CHARCOAL_MAKES}, {[most] = CHARCOAL_LOGS})
		made = made + CHARCOAL_MAKES
	end
	if made > 0 then
		core.log("action", string.format("[living_villages] villager %s burned %d charcoal", short_id(self), made))
	end
	return made
end

-- Works one woodcutter job. Returns the item gained and how many, or nil.
function M.cut(self, target)
	local spots = grove(self)
	if target.kind == "fell" then
		local log, logs = M.fell(target.pos)
		if not log then return nil end
		local sapling = BY_LOG[log].sapling
		possessions.add(self, log, logs)
		-- One for its spot and, while the grove is short of trees, one more, as a felled
		-- tree's leaves would drop: so a grove grows past its first tree.
		possessions.add(self, sapling, #spots < grove_max(self) and 2 or 1)
		if not plant(self, target.pos, sapling) then table.remove(spots, target.index) end
		M.burn_charcoal(self)
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
	if #M.quarry_targets(self) > 0 then open.quarrier = true end
	if M.trade_waiting(news.heard(self)) then open.porter = true end
	if self._villages_peddle or M.deal(news.heard(self), possessions.emeralds(self)) then open.peddler = true end
	return open
end

-- Starts a peddle from the best deal heard. Returns it, or nil.
function M.start_peddle(self, heard, day)
	local deal = M.deal(heard, possessions.emeralds(self))
	if not deal then return nil end
	self._villages_peddle = {item = deal.item, count = deal.count, bid = deal.bid, sell_at = deal.sell_at,
		day = day, buying = true}
	core.log("action", string.format("[living_villages] villager %s peddles %d %s: buys at up to %.1f, heard of need at %.1f",
		short_id(self), deal.count, deal.item, deal.bid, deal.sell_at))
	return self._villages_peddle
end

-- Moves a peddle on: from buying to selling once it holds the lot or the buying days
-- are over, and to its end once sold out or its days are over.
function M.peddle_tick(self, day)
	local peddle = self._villages_peddle
	if not peddle then return nil end
	local held = possessions.count(self, peddle.item)
	if peddle.buying and (held >= peddle.count or day > peddle.day + PEDDLE_BUY_DAYS - 1) then
		peddle.buying = nil
		core.log("action", string.format("[living_villages] villager %s has %d %s to peddle", short_id(self), held, peddle.item))
	end
	if not peddle.buying and (held == 0 or day >= peddle.day + PEDDLE_DAYS) then
		core.log("action", string.format("[living_villages] villager %s ends its peddle of %s (%d left)",
			short_id(self), peddle.item, held))
		self._villages_peddle = nil
		return nil
	end
	return peddle
end

-- Today's activity, choosing it first if the day is new.
function M.today(self)
	local day = core.get_day_count()
	local labour = self._villages_labour
	if labour and labour.day == day then return labour.activity end
	local yesterday = labour and labour.activity
	-- A woodcutter's job is woodcutting: no choice to make (ticket 16).
	if self._villages_woodcutter then
		self._villages_labour = {day = day, activity = "woodcutter"}
		return "woodcutter"
	end
	M.peddle_tick(self, day)
	M.choose_home(self)
	local heard = news.heard(self)
	local activity = M.choose(heard, available(self), yesterday, math.random(), possessions.emeralds(self),
		self._villages_porter_record, self._villages_gather_record)
	-- A peddle under way goes on: what it bought is still to sell.
	if self._villages_peddle and activity ~= "peddler" then activity = "peddler" end
	if activity == "peddler" and not self._villages_peddle and not M.start_peddle(self, heard, day) then
		activity = nil
	end
	self._villages_labour = {day = day, activity = activity}
	if activity == "porter" then
		local record = self._villages_porter_record or {days = 0, hires = 0}
		record.days = record.days + 1
		self._villages_porter_record = record
	elseif activity and (ACTIVITIES[activity].rate or 0) > 0 then
		local yields = self._villages_gather_record or {}
		local record = yields[activity] or {days = 0, made = 0}
		record.days = record.days + 1
		yields[activity] = record
		self._villages_gather_record = yields
	end
	if activity then
		core.log("action", string.format("[living_villages] villager %s (%s) works as a %s today",
			short_id(self), tostring(self._profession), activity))
	else
		local trees = 0
		local from = home(self)
		if from then
			local minp, maxp = area(from, WILD_TREE_RADIUS, FORAGE_HEIGHT)
			trees = #core.find_nodes_in_area(minp, maxp, LOGS)
		end
		local where = self._bed and ("bed " .. core.pos_to_string(self._bed))
			or (from and ("no bed, works from " .. core.pos_to_string(from))) or "no bed"
		-- What it heard, so a log tells no deal from no news (ticket 12).
		local kinds = {needs = 0, has = 0}
		for _, entry in ipairs(heard) do kinds[entry.kind] = (kinds[entry.kind] or 0) + 1 end
		core.log("action", string.format("[living_villages] villager %s (%s) finds no work today (%s, %d logs near, "
			.. "heard %d news: %d needs, %d has, no peddling deal)",
			short_id(self), tostring(self._profession), where, trees, #heard, kinds.needs, kinds.has))
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
	if activity == "forager" then
		item, count = M.forage(self, target)
	elseif activity == "quarrier" then
		item, count = M.quarry(self, target)
	else
		item, count = M.cut(self, target)
	end
	if item then
		-- A tool makes the next one come sooner, and wears (wants.lua).
		local use = (target.kind == "fell" and "fell") or (target.kind == "cobble" and "mine") or nil
		if use then
			local now = core.get_gametime()
			self._villages_labour_next = now + TICK_SECONDS / wants.use(self, use, possessions.take_held, now)
		end
		tally.note(self, {[item] = count})
		-- Saplings and charcoal are not what the rate counts.
		local labour = self._villages_labour
		local record = labour and self._villages_gather_record and self._villages_gather_record[labour.activity]
		if record and not item:find("sapling") then record.made = record.made + count end
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
	-- A peddler's work is its trades: buying, then selling (M.peddle_tick).
	if activity == "peddler" then
		M.peddle_tick(self, core.get_day_count())
		return
	end
	-- A porter's work is its trips (trade_trips.lua).
	if not activity or not pos or activity == "porter" then return end
	local target, distance
	if activity == "forager" or activity == "quarrier" then
		local open = {}
		local candidates = activity == "forager" and M.forage_targets(self) or M.quarry_targets(self)
		for _, candidate in ipairs(candidates) do
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
	-- A sapling is planted from beside its spot, not standing on it: a tree that grows
	-- around a villager suffocates it.
	if target.kind == "sapling" or target.kind == "fell" or target.kind == "plant" or target.kind == "replant" then
		goal = beside(target.pos)
	end
	-- A generator's cobble is solid too: beside it, or a step lower with it at head height.
	if target.kind == "cobble" then
		goal = beside(target.pos) or beside({x = target.pos.x, y = target.pos.y - 1, z = target.pos.z})
	end
	-- A cane top stands in the air above its column: beside the column's foot, where
	-- there is ground, or a step up (it was walked to itself, and never reached).
	if target.kind == "cane" then goal = beside_cane(target.pos) end
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
	if self._villages_woodcutter then return "woodcutter by trade, grove of " .. #(self._villages_grove or {}) end
	if not M.eligible(self) then return "not looking for work" end
	local labour = self._villages_labour
	if not labour or labour.day ~= core.get_day_count() then return "not chosen today" end
	local text = labour.activity or "nothing to do"
	if labour.activity == "woodcutter" then text = text .. ", grove of " .. #(self._villages_grove or {}) end
	if labour.activity == "porter" then text = text .. (self._villages_trade_trip and ", on a trip" or ", waiting for hire") end
	local peddle = self._villages_peddle
	if labour.activity == "peddler" and peddle then
		text = text .. string.format(", %s %d %s at %.1f", peddle.buying and "buying" or "selling",
			peddle.buying and peddle.count or possessions.count(self, peddle.item), peddle.item, peddle.bid)
	end
	return text
end

return M
