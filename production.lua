-- Crafting at the jobsite (docs/villager-economy-design.md, ticket 8), for the
-- professions in recipes.lua, and the restock that now depends on it.
--
-- Making. Over work-stage economic clock time (economy_clock.lua) spent within
-- JOBSITE_REACH of its jobsite, a villager banks seconds in `_villages_craft`. Each
-- item a recipe gives costs living_villages_craft_seconds (120) of them, so a craft of 4
-- arrows takes four times one of a pickaxe. When the bank covers the recipe it would
-- choose, it takes the inputs from its belongings, then its stash wherever it stands
-- (possessions.take_held), and the made items go into its belongings. With nothing it
-- can make, nothing is banked. A hungry villager banks at half the rate and a starving
-- one at a quarter (food.lua's states; ticket 18: at none, a starving village could
-- never cook its way out, ColonyFood 2026-11-13); one reading a book (wants.lua) a fifth
-- faster.
--
-- Which recipe (ticket 21d, production by margin): of those it has the inputs and fuel
-- for, and whose output it holds fewer than its target plus STOCK of (see below for one
-- nobody wants; the alchemist's `upto` instead), the one that earns most per second of
-- work (M.cost): the output at what it reckons it trades for (possessions.prices_of, its
-- reference price times its ask factor), less the inputs and fuel reckoned the same way
-- (ledger.margin). One that earns less than nothing is not made: its inputs sell for
-- more as they are, and a crafter with nothing that pays labours (M.idle_today). An
-- output it has heard someone needs (market_news.lua) is reckoned at no less than the
-- best price asked, so a tool smith makes the hoe a farmer wants before a shovel no one
-- does (ticket 11d).
-- Nor does it make what nobody wants: an output it has heard no one ask for and does
-- not want itself (no target) it makes only while it holds none, so its inputs are left
-- for what is asked for (run 48: a tool smith spent the sticks for a farmer's second
-- hoe on shovels).
--
-- Fuel. `_villages_fuel` is smelts left from the last lump burned. A recipe that needs
-- more burns a coal or charcoal lump (charcoal first, it is the village's own) for 8.
--
-- Restocking. Vanilla unlocks a villager's traded-out offers in do_work when it reaches
-- its jobsite (mobs_mc/villager.lua's file-local unlock_trades, from the one place that
-- sets order to "work"). Neither can be wrapped, so do_custom is: when a call turns the
-- order to "work" and changes `_trades`, and the villager is starving, or is a crafting
-- profession that can make nothing from what it holds, `_trades` goes back to what it
-- was. It tries again on its next arrival. The fisherman's own restock (fisherman.lua)
-- is untouched.
--
-- Tiers (ticket 9). A craft whose inputs and fuel all came from its belongings is made
-- from village supply: belongings fill only from its kit, its own work and trades with
-- villagers, while a stash may hold what a player left. On living_villages_tier_supply_days
-- (3) separate days with such a craft at its current tier (`_villages_tier_supply`:
-- {tier, days, day}), it goes up a tier, up to 5, as vanilla's first trade at the top
-- tier does: `_max_trade_tier`, then `_max_tradenum` and the badge, which vanilla sets in
-- file-local functions mirrored here (update_max_tradenum, set_textures). Vanilla's
-- own route still runs; whichever comes first wins.
--
-- Each craft is noted in its daily tally (economy_tally.lua): the output made, the
-- inputs and lumps used.
--
-- With the economy off nothing is made and every restock goes through.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local recipes = dofile(core.get_modpath("living_villages") .. "/recipes.lua")
local commission = dofile(core.get_modpath("living_villages") .. "/commission.lua")
local tally = dofile(core.get_modpath("living_villages") .. "/economy_tally.lua")
local news = dofile(core.get_modpath("living_villages") .. "/market_news.lua")
local wants = dofile(core.get_modpath("living_villages") .. "/wants.lua")

local DEFAULT_CRAFT_SECONDS = 120
-- Seconds of game time between an idle crafter's looks for something to make again.
local IDLE_RECHECK = 60
local JOBSITE_REACH = 3
local STEP_SECONDS = 5
-- How often a labourer waiting looks again for the labour recipe to buy for.
local PLAN_SECONDS = 60
-- It stops making an output once it holds this many past its target, or one if
-- no one asks for it and it has no target for it.
local STOCK = 16
-- The most of one input it wants for what it hears asked for (input_demand, ticket 39f),
-- beyond its batch: with ledger.lua's batch of 4, ledger's INPUT_CAP (32).
local DEMAND_CAP = 28
local UNASKED_STOCK = 1
local SMELTS_PER_LUMP = 8
-- Burn seconds per smelt: a lump of coal's 80 make 8 (goods.lua's fuel).
local SMELT_SECONDS = 10
local COAL, CHARCOAL = ledger.COAL, "mcl_core:charcoal_lump"
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local alchemist = dofile(core.get_modpath("living_villages") .. "/alchemist.lua")
local premium = dofile(core.get_modpath("living_villages") .. "/premium.lua")
-- Most crafts in one step, should a long gap have banked many.
local MAX_PER_STEP = 4
local DEFAULT_TIER_SUPPLY_DAYS = 3
local MAX_TIER = 5
-- mobs_mc/villager.lua's badges, by tier.
local BADGES = {"mobs_mc_stone.png", "mobs_mc_iron.png", "mobs_mc_gold.png", "mobs_mc_emerald.png", "mobs_mc_diamond.png"}

local M = {IDLE_RECHECK = IDLE_RECHECK, RECIPES = recipes, STOCK = STOCK, UNASKED_STOCK = UNASKED_STOCK, SMELTS_PER_LUMP = SMELTS_PER_LUMP, JOBSITE_REACH = JOBSITE_REACH, DEMAND_CAP = DEMAND_CAP}

local function short_id(self)
	return tostring(self._id):sub(1, 6)
end

-- Its trade, for the log: an alchemist is a cleric to vanilla (alchemist.lua).
local function trade_name(self)
	return self._villages_alchemist and "alchemist" or tostring(self._profession)
end

function M.craft_seconds()
	local value = core.settings and tonumber(core.settings:get("living_villages_craft_seconds"))
	return math.max(value or DEFAULT_CRAFT_SECONDS, 1)
end

-- A keeper and a Builder (a mason to vanilla, builder.lua) have work of their own; an
-- alchemist (a cleric to vanilla, alchemist.lua) has its own list.
function M.recipes(self)
	if self._villages_alchemist then return recipes.alchemist end
	if self._villages_keeper or self._villages_builder then return nil end
	return recipes[self._profession]
end

-- Seconds of economic clock in an ordinary working day for this villager, from its
-- timetable and time_speed (common.lua).
local function work_day_seconds(self)
	local speed = tonumber(core.settings and core.settings:get("time_speed")) or 72
	if speed <= 0 then speed = 72 end
	return common.work_day_ticks(self) * 86400 / (24000 * speed)
end

-- What one craft of the recipe costs in banked seconds: its `share` of a working day
-- (the alchemist's, recipes.lua), its own `seconds` an item (the butcher's cooking,
-- ticket 39f), or living_villages_craft_seconds an item.
function M.cost(self, recipe)
	if recipe.share then return recipe.share * work_day_seconds(self) end
	return (recipe.seconds or M.craft_seconds()) * recipe.count
end

-- An input any species of which will do (ticket 15): a recipe written with oak logs or
-- planks takes any log or planks, and planks made from a log are of its species. An input
-- that names a category (its third field, the alchemist's stone) takes any member. The
-- members, or nil for an input wanted as itself.
local function kinds(item, named)
	if named then return goods.CATEGORIES[named] end
	local category = goods.target_category(item)
	if category == "log" or category == "planks" then return goods.CATEGORIES[category] end
	return nil
end

-- How many of an input there are by `count(item)`, any species (or member of the
-- `named` category) counted.
local function have(item, count, named)
	local members = kinds(item, named)
	if not members then return count(item) or 0 end
	local total = 0
	for member in pairs(members) do total = total + (count(member) or 0) end
	return total
end
M.have = have

-- What it burns, best first: charcoal, coal, then any other fuel (goods.lua) that none
-- of its recipes takes as an input (ticket 15), as {item, smelts}.
local fuel_lists = {}
local function fuels(self)
	-- An alchemist burns logs too, after charcoal and coal, though its flint takes them: its
	-- ledger counts logs toward its fuel, and wood is what it is to buy (ticket 28c).
	local alchemist = self._villages_alchemist == true
	local profession = alchemist and "alchemist" or self._profession or ""
	if fuel_lists[profession] then return fuel_lists[profession] end
	local inputs = {}
	for _, recipe in ipairs(alchemist and {} or recipes[profession] or {}) do
		for _, input in ipairs(recipe.from) do
			inputs[input[1]] = true
			for member in pairs(kinds(input[1], input[3]) or {}) do inputs[member] = true end
		end
	end
	local others = {}
	for item, seconds in pairs(goods.CATEGORIES.fuel) do
		if item ~= COAL and item ~= CHARCOAL and not inputs[item] then
			others[#others + 1] = {item = item, smelts = seconds / SMELT_SECONDS}
		end
	end
	table.sort(others, function(a, b) return a.item < b.item end)
	local list = {{item = CHARCOAL, smelts = SMELTS_PER_LUMP}, {item = COAL, smelts = SMELTS_PER_LUMP}}
	for _, entry in ipairs(others) do list[#list + 1] = entry end
	fuel_lists[profession] = list
	return list
end

local function fuel_in(self, counts)
	local total = 0
	for _, fuel in ipairs(fuels(self)) do total = total + fuel.smelts * (counts(fuel.item) or 0) end
	return total
end

local function fuel_available(self, held)
	return (self._villages_fuel or 0) + fuel_in(self, function(item) return held[item] end)
end

-- Whether `held` (possessions.held) covers one craft.
function M.can_make(self, recipe, held)
	for _, input in ipairs(recipe.from) do
		if have(input[1], function(item) return held[item] end, input[3]) < input[2] then return false end
	end
	return not recipe.fuel or fuel_available(self, held) >= recipe.fuel
end

-- What a craft earns over its inputs and fuel (ledger.margin) at `price_of` (default its
-- own, possessions.prices_of), its output at no less than `asks` (market_news.asking)
-- holds for it. Nil if its output has no price.
function M.gain(recipe, price_of, asks)
	local function priced(item)
		local price = price_of(item)
		if item == recipe.makes and asks and asks[item] then return math.max(price or 0, asks[item]) end
		return price
	end
	return ledger.margin(recipe, priced)
end

-- The recipe it would make next, or nil. `held`, `view` and `asks` default to its own,
-- `list` to its recipes (M.recipes).
function M.choose(self, held, view, asks, list)
	list = list or M.recipes(self)
	if not list then return nil end
	held = held or possessions.held(self)
	view = view or possessions.assess(self)
	asks = asks or news.asking(news.heard(self, core.get_gametime()))
	-- A commission's output counts at the price it is paid (ticket 26b).
	local commissioned = commission.of(self)
	if commissioned then
		local unit = commissioned.price / math.max(commissioned.count, 1)
		if (asks[commissioned.item] or 0) < unit then
			local lifted = {}
			for item, ask in pairs(asks) do lifted[item] = ask end
			lifted[commissioned.item] = unit
			asks = lifted
		end
	end
	-- A good it wants for itself counts at its own value (ticket 26d).
	local price_of = possessions.lifted(possessions.prices_of(self), view.own_use)
	-- The base good of its premium trades (premium.keeps, ticket 37) is no craft's input:
	-- a librarian's bookshelves leave its four books for the enchanted ones.
	local usable = held
	local keeps = premium.keeps(self)
	if keeps then
		usable = setmetatable({}, {__index = held})
		for item, count in pairs(keeps) do usable[item] = math.max((held[item] or 0) - count, 0) end
	end
	-- A ranked list (the alchemist's) stops at each recipe's `upto` and breaks ties by rank.
	local ranked = list[1] and list[1].rank
	local best, best_rate
	for _, recipe in ipairs(list) do
		local stock_held = have(recipe.makes, function(item) return held[item] end)
		local stocked
		if ranked then
			stocked = recipe.upto ~= nil and stock_held >= recipe.upto
		else
			local target = view.targets[recipe.makes] or 0
			-- Its own need counts, a category's (food, ticket 15) included.
			local wanted = target > 0 or (asks[recipe.makes] or 0) > 0 or (view.needs[recipe.makes] or 0) > 0
			stocked = stock_held >= (wanted and target + STOCK or UNASKED_STOCK)
		end
		if not stocked and M.can_make(self, recipe, usable) then
			local gain = M.gain(recipe, price_of, asks)
			-- A craft seeded at its inputs' cost pays 0, give or take rounding. A ranked list's
			-- (the alchemist's) is made at a loss too, by rank after any that pays: it works
			-- its stand and spends its budget on stone and wood (ticket 28).
			if gain and (gain >= -1e-6 or ranked) then
				local rate = math.max(gain, 0) / M.cost(self, recipe)
				local better = not best or rate > best_rate
				if not better and rate == best_rate then
					if ranked then better = recipe.rank < best.rank else better = recipe.makes < best.makes end
				end
				if better then best, best_rate = recipe, rate end
			end
		end
	end
	return best
end

-- Burns lumps for `smelts`, noting each in `used`. Returns whether there was enough.
local function burn(self, smelts, used)
	while (self._villages_fuel or 0) < smelts do
		local burned
		for _, fuel in ipairs(fuels(self)) do
			if possessions.take_held(self, fuel.item, 1) == 1 then burned = fuel break end
		end
		if not burned then return false end
		used[burned.item] = (used[burned.item] or 0) + 1
		self._villages_fuel = (self._villages_fuel or 0) + burned.smelts
	end
	self._villages_fuel = self._villages_fuel - smelts
	if self._villages_fuel <= 0 then self._villages_fuel = nil end
	return true
end

-- Whether its belongings alone cover one craft, fuel included.
function M.supplied(self, recipe)
	for _, input in ipairs(recipe.from) do
		if have(input[1], function(item) return possessions.count(self, item) end, input[3]) < input[2] then
			return false
		end
	end
	if not recipe.fuel then return true end
	return (self._villages_fuel or 0) + fuel_in(self, function(item) return possessions.count(self, item) end)
		>= recipe.fuel
end

function M.tier_supply_days()
	local value = core.settings and tonumber(core.settings:get("living_villages_tier_supply_days"))
	return math.max(value or DEFAULT_TIER_SUPPLY_DAYS, 1)
end

-- Mirrors mobs_mc/villager.lua's update_max_tradenum: the trades up to the tier.
local function update_max_tradenum(self)
	local trades = self._trades and core.deserialize and core.deserialize(self._trades)
	if type(trades) ~= "table" then return end
	for i, trade in ipairs(trades) do
		if trade.tier > self._max_trade_tier then
			self._max_tradenum = i - 1
			return
		end
	end
	self._max_tradenum = #trades
end

-- Swaps the badge vanilla's set_textures put on its texture.
local function set_badge(self, from, to)
	local properties = self.object and self.object.get_properties and self.object:get_properties()
	local texture = properties and properties.textures and properties.textures[1]
	if type(texture) ~= "string" or not BADGES[from] or not BADGES[to] then return end
	local first, last = texture:find("^" .. BADGES[from], 1, true)
	if not first then return end
	self.object:set_properties({textures = {texture:sub(1, first - 1) .. "^" .. BADGES[to] .. texture:sub(last + 1)}})
end

-- Counts today toward the next tier, and goes up one when the days are in.
function M.count_supply(self)
	local tier = self._max_trade_tier or 1
	if tier >= MAX_TIER then return false end
	local today = core.get_day_count()
	local record = self._villages_tier_supply
	if not record or record.tier ~= tier then record = {tier = tier, days = 0} end
	if record.day ~= today then record.days, record.day = record.days + 1, today end
	self._villages_tier_supply = record
	if record.days < M.tier_supply_days() then return false end
	self._max_trade_tier = tier + 1
	self._villages_tier_supply = nil
	update_max_tradenum(self)
	set_badge(self, tier, tier + 1)
	core.log("action", string.format("[living_villages] production: villager %s (%s) rose to tier %d on village supply",
		short_id(self), trade_name(self), tier + 1))
	return true
end

-- Makes one craft of the recipe, if it still holds what it takes. Returns whether it did.
-- A labourer's craft (`labour`, ticket 23a) counts toward no tier.
function M.make(self, recipe, labour)
	if not M.can_make(self, recipe, possessions.held(self)) then return false end
	local supplied = M.supplied(self, recipe)
	local used = {}
	local held = possessions.held(self)
	local log_used
	for _, input in ipairs(recipe.from) do
		local members = kinds(input[1], input[3])
		if not members then
			possessions.take_held(self, input[1], input[2])
			used[input[1]] = (used[input[1]] or 0) + input[2]
		else
			-- Any species, the one it holds most of first.
			local list = {}
			for member in pairs(members) do
				if (held[member] or 0) > 0 then list[#list + 1] = member end
			end
			table.sort(list, function(a, b)
				if held[a] ~= held[b] then return held[a] > held[b] end
				return a < b
			end)
			local left = input[2]
			for _, member in ipairs(list) do
				if left <= 0 then break end
				local took = possessions.take_held(self, member, math.min(left, held[member]))
				if took > 0 then
					used[member] = (used[member] or 0) + took
					left = left - took
					if goods.SPECIES[member] and not log_used then log_used = member end
				end
			end
		end
	end
	if recipe.fuel and not burn(self, recipe.fuel, used) then return false end
	-- Planks from a log are of its species.
	local makes = recipe.makes
	if log_used and goods.CATEGORIES.planks[makes] then makes = goods.SPECIES[log_used] end
	-- An alchemist's stock is at what it cost to make (ticket 30).
	alchemist.made(self, makes, recipe.count, possessions.count(self, makes))
	possessions.add(self, makes, recipe.count)
	tally.note(self, {[makes] = recipe.count}, used)
	core.log("action", string.format("[living_villages] production: villager %s (%s) made %d %s",
		short_id(self), trade_name(self), recipe.count, makes))
	if supplied and not labour then M.count_supply(self) end
	return true
end

-- Whether it is at work by its jobsite now.
-- Idle crafters (ticket 19b). A crafter that can make nothing when its work day starts,
-- for want of inputs or because it holds all its goods will sell, labours that day as a
-- nitwit does (labour.lua), keeping its profession and jobsite. Asked again each day in
-- the work stage, so goods that came in overnight bring it back to its jobsite.
-- `_villages_idle` holds the day and the answer.
function M.idle_today(self)
	if self.child or not self._id or not self._jobsite or self._villages_woodcutter then return false end
	-- A shepherd's flock is its work: dyeing is a side line, never a reason to labour. An
	-- alchemist waits at its stand for stone and logs (ticket 20).
	if self._profession == "shepherd" or self._villages_alchemist then return false end
	if self._profession == "nitwit" or self._profession == "unemployed" or not M.recipes(self) then return false end
	local day = core.get_day_count()
	local now = core.get_gametime and core.get_gametime() or 0
	local idle = self._villages_idle
	-- Idle, it asks again every IDLE_RECHECK (experiment E6): the butcher found no fish at
	-- the work bell, bought some on a trip, and laboured the rest of the day with it.
	if idle and idle.day == day and not (idle.idle and now - (idle.at or 0) >= IDLE_RECHECK
		and common.schedule_stage(nil, self) == "work") then
		return idle.idle
	end
	if common.schedule_stage(nil, self) ~= "work" then return false end
	local nothing = M.choose(self) == nil
	local logged = idle and idle.day == day
	self._villages_idle = {day = day, idle = nothing, at = now}
	if nothing and logged then return true end
	if not nothing and logged then
		core.log("action", string.format("[living_villages] production: villager %s (%s) has work again and goes back to it",
			short_id(self), trade_name(self)))
	end
	if nothing then
		core.log("action", string.format("[living_villages] production: villager %s (%s) has nothing to make today and labours",
			short_id(self), trade_name(self)))
	end
	return nothing
end

function M.at_work(self)
	local jobsite = self._jobsite
	local pos = self.object and self.object:get_pos()
	if self.child or self._villages_sleeping or not jobsite or not pos then return false end
	if vector.distance(pos, jobsite) > JOBSITE_REACH then return false end
	return common.schedule_stage(nil, self) == "work"
end

local HUNGRY_RATE, STARVING_RATE = 0.5, 0.25

local function rate(self)
	local state = food.state(self)
	-- A book being read (wants.lua, ticket 11e) speeds it up.
	local reading = wants.reading_rate(self, possessions.take_held, core.get_gametime())
	if state == "starving" then return STARVING_RATE * reading end
	if state == "hungry" then return HUNGRY_RATE * reading end
	return reading
end

local last_read = setmetatable({}, {__mode = "k"})
local next_step = setmetatable({}, {__mode = "k"})
local next_demand = setmetatable({}, {__mode = "k"})

-- Banks `elapsed` in `field` and makes what that covers from `list` (nil: its own
-- recipes). Returns the crafts made, and whether it found nothing to make.
local function bank_and_make(self, elapsed, field, list, labour)
	local made, nothing = 0, false
	local banked = (self[field] or 0) + elapsed * rate(self)
	while made < MAX_PER_STEP do
		local recipe = M.choose(self, nil, nil, nil, list)
		if not recipe then
			banked, nothing = 0, true
			break
		end
		local cost = M.cost(self, recipe)
		if banked < cost or not M.make(self, recipe, labour) then break end
		banked = banked - cost
		made = made + 1
	end
	self[field] = banked > 0 and banked or nil
	return made, nothing
end

-- Banks the clock time since the last step, if it was at work, and makes what that
-- covers. Returns the crafts made.
function M.work(self, elapsed)
	return (bank_and_make(self, elapsed, "_villages_craft", nil, false))
end

-- Labourers' crafts (ticket 23a). A villager labouring (labour.lua) banks the work-stage
-- time its activity has no job for (`waiting`: no tree ready, a generator between blocks,
-- nothing in bloom, a porter not hired, no activity at all) in `_villages_labour_craft`,
-- apart from a crafter's bank at its jobsite, at the same hunger rates, and makes from
-- recipes.labour what pays best, at home, at no block. Time working its activity banks
-- nothing, so crafting never takes it from its labour.
--
-- Its plan (`_villages_labour_plan`, {day, checked, index} into recipes.labour), looked
-- for every PLAN_SECONDS while it waits: the labour recipe that would pay best had it the
-- inputs, of the goods someone has asked for or it wants itself. possessions.assess wants that recipe's inputs, one craft's worth, so
-- market news tells them and it buys them as a crafter buys its own.
M.LABOUR = recipes.labour

-- Returns the crafts made, and whether it found nothing to make.
function M.labour_work(self, elapsed)
	return bank_and_make(self, elapsed, "_villages_labour_craft", recipes.labour, true)
end

-- The labour recipe it would make were the inputs to hand, of the goods wanted; nil if
-- none pays more than its inputs. `view` and `asks` default to its own.
function M.labour_plan(self, view, asks)
	view = view or possessions.assess(self)
	asks = asks or news.asking(news.heard(self, core.get_gametime()))
	local price_of = possessions.lifted(possessions.prices_of(self), view.own_use)
	local held = possessions.held(self)
	local best, best_rate
	for _, recipe in ipairs(recipes.labour) do
		local target = view.targets[recipe.makes] or 0
		local wanted = target > 0 or (asks[recipe.makes] or 0) > 0
		local stock_held = have(recipe.makes, function(item) return held[item] end)
		if wanted and stock_held < target + STOCK then
			local gain = M.gain(recipe, price_of, asks)
			if gain and gain > 1e-6 then
				local rate = gain / M.cost(self, recipe)
				if not best or rate > best_rate or (rate == best_rate and recipe.makes < best.makes) then
					best, best_rate = recipe, rate
				end
			end
		end
	end
	return best
end

local labour_read = setmetatable({}, {__mode = "k"})
local labour_next = setmetatable({}, {__mode = "k"})

-- One step of a labourer in its work stage (labour.lua's do_custom). Returns the crafts made.
function M.labour_step(self, now, waiting)
	if now < (labour_next[self] or 0) then return 0 end
	labour_next[self] = now + STEP_SECONDS
	local reading = clock.read(self)
	local last = labour_read[self]
	labour_read[self] = reading
	if not waiting or not last or reading <= last then return 0 end
	local made = M.labour_work(self, reading - last)
	local day = core.get_day_count()
	local plan = self._villages_labour_plan
	-- A commission is its plan while it lasts (ticket 26b, possessions.labour_plan).
	if not commission.labour_of(self) and not (plan and plan.day == day and now - (plan.checked or 0) < PLAN_SECONDS) then
		local asks = news.asking(news.heard(self, now))
		local view = possessions.assess(self)
		local recipe = M.labour_plan(self, view, asks)
		self._villages_labour_plan = {day = day, checked = now, index = recipe and M.labour_index(recipe),
			caps = recipe and M.labour_caps(self, recipe, asks, view)}
		if recipe then
			core.log("action", string.format("[living_villages] production: villager %s (labourer) would make %s",
				short_id(self), recipe.makes))
		end
	end
	return made
end

-- What each of a labour recipe's inputs is worth to it at most (ledger.imputed), its
-- output priced as M.gain prices it, at no less than the best bid heard (`asks`): the plan
-- is chosen by that gain, so its inputs are bid for by it too. Capped at the reference
-- price, a lantern wanted at 1,550 left nuggets worth what a lantern costs to make, and
-- a painting wanted at 500 left wool at 40 against the shepherds' 90: no labourer ever
-- set off to buy them (ColonyFood, 2026-11-15; ticket 23d).
function M.labour_caps(self, recipe, asks, view)
	view = view or possessions.assess(self)
	local price_of = possessions.lifted(possessions.prices_of(self), view.own_use)
	local function priced(item)
		local price = price_of(item)
		if item == recipe.makes and asks and asks[item] then return math.max(price or 0, asks[item]) end
		return price
	end
	return ledger.imputed({recipe}, priced, MAX_TIER)
end

-- A labour recipe's place in recipes.labour, which the plan keeps (two make torches).
function M.labour_index(recipe)
	for i, entry in ipairs(recipes.labour) do
		if entry == recipe then return i end
	end
end

-- Ticket 39f: for a recipe whose inputs follow demand (recipes.lua's `demand`, the
-- butcher's cooking), how many of each input it wants beyond its batch: what it heard
-- asked for of the output, less what it holds of it, up to DEMAND_CAP. A need for one item
-- counts in full, each villager's once; a category's (the keeper's dishes, a villager's
-- food) is shared among the outputs that fill it, in their units. Item to count, or nil.
function M.input_demand(self, heard, list)
	list = list or M.recipes(self)
	if not list then return nil end
	local outputs, fills = {}, {}
	for _, recipe in ipairs(list) do
		if recipe.demand then outputs[recipe.makes] = recipe end
	end
	if not next(outputs) then return nil end
	-- How many of its outputs fill each category.
	local function share(group)
		if fills[group] == nil then
			local n = 0
			for item in pairs(outputs) do if goods.units(group, item) then n = n + 1 end end
			fills[group] = n
		end
		return fills[group]
	end
	local by_who = {}
	for _, entry in ipairs(heard) do
		if entry.kind == "needs" and (entry.count or 0) > 0 then
			for item in pairs(outputs) do
				local count
				if entry.item == item then
					count = entry.count
				elseif entry.group and goods.units(entry.group, item) and goods.units(entry.group, entry.item) then
					local units = entry.count * goods.units(entry.group, entry.item)
					count = units / goods.units(entry.group, item) / share(entry.group)
				end
				if count then
					local key = item .. "|" .. tostring(entry.who)
					by_who[key] = math.max(by_who[key] or 0, count)
				end
			end
		end
	end
	local asked = {}
	for key, count in pairs(by_who) do
		local item = key:match("^(.-)|")
		asked[item] = (asked[item] or 0) + count
	end
	local held = possessions.held(self)
	local found
	for item, recipe in pairs(outputs) do
		local short = math.ceil((asked[item] or 0) - (held[item] or 0) - 1e-6)
		if short > 0 then
			local crafts = math.ceil(short / recipe.count)
			for _, input in ipairs(recipe.from) do
				found = found or {}
				found[input[1]] = math.min((found[input[1]] or 0) + crafts * input[2], DEMAND_CAP)
			end
		end
	end
	return found
end

function M.step(self, now)
	if now < (next_step[self] or 0) then return end
	next_step[self] = now + STEP_SECONDS
	-- What its demand recipes' inputs follow (input_demand), read by possessions.assess.
	if now >= (next_demand[self] or 0) then
		next_demand[self] = now + PLAN_SECONDS
		local list = M.recipes(self)
		self._villages_input_demand = list and M.input_demand(self, news.heard(self, core.get_gametime()), list) or nil
	end
	local reading = clock.read(self)
	local last = last_read[self]
	last_read[self] = reading
	if not last or reading <= last or not M.recipes(self) or not M.at_work(self) then return end
	M.work(self, reading - last)
end

-- Why this villager's restock is held back, or nil.
function M.restock_held(self)
	if not clock.enabled() or self.child then return nil end
	if food.state(self) == "starving" then return "starving" end
	-- A shepherd's goods are its flock's wool, not its dyeing (19h); a cleric's are its
	-- vanilla trades', not its clock (ticket 29).
	if self._profession == "shepherd" or (self._profession == "cleric" and not self._villages_alchemist) then
		return nil
	end
	local list = M.recipes(self)
	if not list then return nil end
	local held = possessions.held(self)
	for _, recipe in ipairs(list) do
		if M.can_make(self, recipe, held) then return nil end
	end
	return "nothing to craft with"
end

-- Puts back trades a vanilla do_custom call unlocked, if the restock is held.
-- order_before and trades_before are the villager's from just before the call.
function M.guard_restock(self, order_before, trades_before)
	if order_before == "work" or self.order ~= "work" or self._trades == trades_before then return false end
	local reason = M.restock_held(self)
	if not reason then return false end
	self._trades = trades_before
	core.log("action", string.format("[living_villages] production: villager %s (%s) did not restock: %s",
		short_id(self), trade_name(self), reason))
	return true
end

function M.install(def)
	if not clock.enabled() then return end
	local original = def.do_custom
	def.do_custom = function(self, dtime)
		local order, trades = self.order, self._trades
		local result = original(self, dtime)
		M.guard_restock(self, order, trades)
		if result ~= false then M.step(self, core.get_gametime()) end
		return result
	end
end

-- Its tier and the village-supplied days toward the next, for the inspector.
function M.tier_status(self)
	local tier = self._max_trade_tier or 1
	if tier >= MAX_TIER then return "tier " .. tier .. " (top)" end
	local record = self._villages_tier_supply
	local days = record and record.tier == tier and record.days or 0
	return string.format("tier %d, %d/%d days of village supply", tier, days, M.tier_supply_days())
end

-- One line for the inspector.
function M.status(self)
	local list = M.recipes(self)
	if not list then return "not a crafting profession" end
	local recipe = M.choose(self)
	local banked = math.floor((self._villages_craft or 0) + 0.5)
	local fuel = self._villages_fuel and (", " .. self._villages_fuel .. " smelts of fuel") or ""
	if not recipe then return "nothing to craft with" .. fuel end
	return string.format("making %s, %d/%d s%s", recipe.makes:gsub("^.*:", ""), banked,
		math.floor(M.cost(self, recipe) + 0.5), fuel)
end

return M
