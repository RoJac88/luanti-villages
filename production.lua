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
-- Which recipe: of those it has the inputs and fuel for, and whose output it holds fewer
-- than its target plus STOCK of (see below for one nobody wants), the one that adds most by its own values (ledger.lua):
-- the output's value less the inputs' and the fuel's. Its targets include its recipes'
-- inputs, so a librarian short of books values making them above a bookshelf. An output
-- it has heard someone needs (market_news.lua) is worth at least the best price asked,
-- so a tool smith makes the hoe a farmer wants before a shovel no one does (ticket 11d).
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
local tally = dofile(core.get_modpath("living_villages") .. "/economy_tally.lua")
local news = dofile(core.get_modpath("living_villages") .. "/market_news.lua")
local wants = dofile(core.get_modpath("living_villages") .. "/wants.lua")

local DEFAULT_CRAFT_SECONDS = 120
local JOBSITE_REACH = 3
local STEP_SECONDS = 5
-- It stops making an output once it holds this many past its target, or one if
-- no one asks for it and it has no target for it.
local STOCK = 16
local UNASKED_STOCK = 1
local SMELTS_PER_LUMP = 8
-- Burn seconds per smelt: a lump of coal's 80 make 8 (goods.lua's fuel).
local SMELT_SECONDS = 10
local COAL, CHARCOAL = ledger.COAL, "mcl_core:charcoal_lump"
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
-- Most crafts in one step, should a long gap have banked many.
local MAX_PER_STEP = 4
local DEFAULT_TIER_SUPPLY_DAYS = 3
local MAX_TIER = 5
-- mobs_mc/villager.lua's badges, by tier.
local BADGES = {"mobs_mc_stone.png", "mobs_mc_iron.png", "mobs_mc_gold.png", "mobs_mc_emerald.png", "mobs_mc_diamond.png"}

local M = {RECIPES = recipes, STOCK = STOCK, UNASKED_STOCK = UNASKED_STOCK, SMELTS_PER_LUMP = SMELTS_PER_LUMP, JOBSITE_REACH = JOBSITE_REACH}

local function short_id(self)
	return tostring(self._id):sub(1, 6)
end

function M.craft_seconds()
	local value = core.settings and tonumber(core.settings:get("living_villages_craft_seconds"))
	return math.max(value or DEFAULT_CRAFT_SECONDS, 1)
end

-- A keeper and a Builder (a mason to vanilla, builder.lua) have work of their own.
function M.recipes(self)
	if self._villages_keeper or self._villages_builder then return nil end
	return recipes[self._profession]
end

-- An input any species of which will do (ticket 15): a recipe written with oak logs or
-- planks takes any log or planks, and planks made from a log are of its species. The
-- members, or nil for an input wanted as itself.
local function kinds(item)
	local category = goods.target_category(item)
	if category == "log" or category == "planks" then return goods.CATEGORIES[category] end
	return nil
end

-- How many of an input there are by `count(item)`, any species counted.
local function have(item, count)
	local members = kinds(item)
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
	local profession = self._profession or ""
	if fuel_lists[profession] then return fuel_lists[profession] end
	local inputs = {}
	for _, recipe in ipairs(recipes[profession] or {}) do
		for _, input in ipairs(recipe.from) do
			inputs[input[1]] = true
			for member in pairs(kinds(input[1]) or {}) do inputs[member] = true end
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
		if have(input[1], function(item) return held[item] end) < input[2] then return false end
	end
	return not recipe.fuel or fuel_available(self, held) >= recipe.fuel
end

local function worth(view, item, count)
	return (view.value(item) or 0) * count
end

-- What a craft adds by the villager's own values, its output at no less than `asks`
-- (market_news.asking) holds for it.
function M.gain(recipe, view, asks)
	local made = math.max(view.value(recipe.makes) or 0, asks and asks[recipe.makes] or 0)
	local gain = made * recipe.count
	for _, input in ipairs(recipe.from) do gain = gain - worth(view, input[1], input[2]) end
	if recipe.fuel then gain = gain - worth(view, COAL, recipe.fuel / SMELTS_PER_LUMP) end
	return gain
end

-- The recipe it would make next, or nil. `held`, `view` and `asks` default to its own.
function M.choose(self, held, view, asks)
	local list = M.recipes(self)
	if not list then return nil end
	held = held or possessions.held(self)
	view = view or possessions.assess(self)
	asks = asks or news.asking(news.heard(self, core.get_gametime()))
	local best, best_gain
	for _, recipe in ipairs(list) do
		local target = view.targets[recipe.makes] or 0
		-- Its own need counts, a category's (food, ticket 15) included.
		local wanted = target > 0 or (asks[recipe.makes] or 0) > 0 or (view.needs[recipe.makes] or 0) > 0
		local stock_held = have(recipe.makes, function(item) return held[item] end)
		local stocked = stock_held >= (wanted and target + STOCK or UNASKED_STOCK)
		if not stocked and M.can_make(self, recipe, held) then
			local gain = M.gain(recipe, view, asks)
			if not best or gain > best_gain or (gain == best_gain and recipe.makes < best.makes) then
				best, best_gain = recipe, gain
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
		if have(input[1], function(item) return possessions.count(self, item) end) < input[2] then return false end
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
		short_id(self), tostring(self._profession), tier + 1))
	return true
end

-- Makes one craft of the recipe, if it still holds what it takes. Returns whether it did.
function M.make(self, recipe)
	if not M.can_make(self, recipe, possessions.held(self)) then return false end
	local supplied = M.supplied(self, recipe)
	local used = {}
	local held = possessions.held(self)
	local log_used
	for _, input in ipairs(recipe.from) do
		local members = kinds(input[1])
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
	possessions.add(self, makes, recipe.count)
	tally.note(self, {[makes] = recipe.count}, used)
	core.log("action", string.format("[living_villages] production: villager %s (%s) made %d %s",
		short_id(self), tostring(self._profession), recipe.count, makes))
	if supplied then M.count_supply(self) end
	return true
end

-- Whether it is at work by its jobsite now.
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

-- Banks the clock time since the last step, if it was at work, and makes what that
-- covers. Returns the crafts made.
function M.work(self, elapsed)
	local made = 0
	local banked = (self._villages_craft or 0) + elapsed * rate(self)
	while made < MAX_PER_STEP do
		local recipe = M.choose(self)
		if not recipe then
			banked = 0
			break
		end
		local cost = M.craft_seconds() * recipe.count
		if banked < cost or not M.make(self, recipe) then break end
		banked = banked - cost
		made = made + 1
	end
	self._villages_craft = banked > 0 and banked or nil
	return made
end

function M.step(self, now)
	if now < (next_step[self] or 0) then return end
	next_step[self] = now + STEP_SECONDS
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
	local list = M.recipes(self)
	if not list then return nil end
	local held = possessions.held(self)
	for _, recipe in ipairs(list) do
		if M.can_make(self, recipe, held) then return nil end
	end
	return "nothing to craft with"
end

-- Puts back trades a vanilla do_custom call unlocked, if the restock is held. `before`
-- is {order, trades} from just before the call.
function M.guard_restock(self, before)
	if before.order == "work" or self.order ~= "work" or self._trades == before.trades then return false end
	local reason = M.restock_held(self)
	if not reason then return false end
	self._trades = before.trades
	core.log("action", string.format("[living_villages] production: villager %s (%s) did not restock: %s",
		short_id(self), tostring(self._profession), reason))
	return true
end

function M.install(def)
	if not clock.enabled() then return end
	local original = def.do_custom
	def.do_custom = function(self, dtime)
		local before = {order = self.order, trades = self._trades}
		local result = original(self, dtime)
		M.guard_restock(self, before)
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
		M.craft_seconds() * recipe.count, fuel)
end

return M
