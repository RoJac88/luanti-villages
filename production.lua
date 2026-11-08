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
-- one not at all (food.lua's states).
--
-- Which recipe: of those it has the inputs and fuel for, and whose output it holds fewer
-- than its target plus STOCK of, the one that adds most by its own values (ledger.lua):
-- the output's value less the inputs' and the fuel's. Its targets include its recipes'
-- inputs, so a librarian short of books values making them above a bookshelf.
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
-- With the economy off nothing is made and every restock goes through.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local recipes = dofile(core.get_modpath("living_villages") .. "/recipes.lua")

local DEFAULT_CRAFT_SECONDS = 120
local JOBSITE_REACH = 3
local STEP_SECONDS = 5
-- It stops making an output once it holds this many past its target.
local STOCK = 16
local SMELTS_PER_LUMP = 8
local COAL, CHARCOAL = ledger.COAL, "mcl_core:charcoal_lump"
-- Most crafts in one step, should a long gap have banked many.
local MAX_PER_STEP = 4

local M = {RECIPES = recipes, STOCK = STOCK, SMELTS_PER_LUMP = SMELTS_PER_LUMP, JOBSITE_REACH = JOBSITE_REACH}

local function short_id(self)
	return tostring(self._id):sub(1, 6)
end

function M.craft_seconds()
	local value = core.settings and tonumber(core.settings:get("living_villages_craft_seconds"))
	return math.max(value or DEFAULT_CRAFT_SECONDS, 1)
end

function M.recipes(self)
	if self._villages_keeper then return nil end
	return recipes[self._profession]
end

local function fuel_available(self, held)
	return (self._villages_fuel or 0) + SMELTS_PER_LUMP * ((held[COAL] or 0) + (held[CHARCOAL] or 0))
end

-- Whether `held` (possessions.held) covers one craft.
function M.can_make(self, recipe, held)
	for _, input in ipairs(recipe.from) do
		if (held[input[1]] or 0) < input[2] then return false end
	end
	return not recipe.fuel or fuel_available(self, held) >= recipe.fuel
end

local function worth(view, item, count)
	return (view.value(item) or 0) * count
end

-- What a craft adds by the villager's own values.
function M.gain(recipe, view)
	local gain = worth(view, recipe.makes, recipe.count)
	for _, input in ipairs(recipe.from) do gain = gain - worth(view, input[1], input[2]) end
	if recipe.fuel then gain = gain - worth(view, COAL, recipe.fuel / SMELTS_PER_LUMP) end
	return gain
end

-- The recipe it would make next, or nil. `held` and `view` default to its own.
function M.choose(self, held, view)
	local list = M.recipes(self)
	if not list then return nil end
	held = held or possessions.held(self)
	view = view or possessions.assess(self)
	local best, best_gain
	for _, recipe in ipairs(list) do
		local stocked = (held[recipe.makes] or 0) >= (view.targets[recipe.makes] or 0) + STOCK
		if not stocked and M.can_make(self, recipe, held) then
			local gain = M.gain(recipe, view)
			if not best or gain > best_gain or (gain == best_gain and recipe.makes < best.makes) then
				best, best_gain = recipe, gain
			end
		end
	end
	return best
end

local function burn(self, smelts)
	while (self._villages_fuel or 0) < smelts do
		local lump = possessions.take_held(self, CHARCOAL, 1) == 1 or possessions.take_held(self, COAL, 1) == 1
		if not lump then return false end
		self._villages_fuel = (self._villages_fuel or 0) + SMELTS_PER_LUMP
	end
	self._villages_fuel = self._villages_fuel - smelts
	if self._villages_fuel <= 0 then self._villages_fuel = nil end
	return true
end

-- Makes one craft of the recipe, if it still holds what it takes. Returns whether it did.
function M.make(self, recipe)
	if not M.can_make(self, recipe, possessions.held(self)) then return false end
	for _, input in ipairs(recipe.from) do possessions.take_held(self, input[1], input[2]) end
	if recipe.fuel and not burn(self, recipe.fuel) then return false end
	possessions.add(self, recipe.makes, recipe.count)
	core.log("action", string.format("[living_villages] production: villager %s (%s) made %d %s",
		short_id(self), tostring(self._profession), recipe.count, recipe.makes))
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

local function rate(self)
	local state = food.state(self)
	if state == "starving" then return 0 end
	if state == "hungry" then return 0.5 end
	return 1
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
