-- What a villager's goods cost it, as bought (ticket 43a, docs/villager-economy-design.md):
-- one book per villager, `_villages_input_cost`, read by its asks (asks.lua) and the
-- keeper's plate cost (dinner.lua). Pure but for the villager it is handed.
--
-- * Item entries ({[item] = emeralds}) hold what one unit cost it, averaged over about KEEP
--   bought: each purchase weighs its count against KEEP units of the old cost. A purchase
--   is noted (M.note) when the item is
--   - an input of a recipe its trade makes (recipes.lua; a category input, any member of
--     it), the butcher's beef and fish (ticket 42) or the mason's clay,
--   - a conversion's source its trade takes (goods.lua), the cleric's rotten flesh (37b),
--   - or bought to sell on: a keeper's food (its dishes, ticket 39b, and its raw plates'
--     potatoes: dinner.note_cost) and a peddler's lot (labour.lua).
--   Fuel is not noted: a recipe's fuel is reckoned at the reference price for coal.
-- * Category entries ({stone = .., log = .., fuel = ..}) are the alchemist's (ticket 30,
--   alchemist.bought): what a unit of the category cost, over what it holds. M.note passes
--   its purchases on to it, so every purchase reaches the book by one call.
--
-- Before it, a cook's inputs, the alchemist's categories, the cleric's flesh
-- (`_villages_flesh_cost`) and the keeper's dishes (`_villages_dish_cost`) were four books
-- noted from three places each. The last two are folded in when the book is first read
-- (M.book).
local core = minetest
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local recipes = dofile(core.get_modpath("living_villages") .. "/recipes.lua")
local food = dofile(core.get_modpath("living_villages") .. "/food.lua")
local alchemist = dofile(core.get_modpath("living_villages") .. "/alchemist.lua")

local KEEP = 8
local FIELD = "_villages_input_cost"
local FLESH = "mcl_mobitems:rotten_flesh"
local M = {KEEP = KEEP, FIELD = FIELD}

-- The trade whose recipes and conversions it buys for.
local function trade_of(villager)
	if villager[alchemist.FLAG] then return "alchemist" end
	if villager._villages_keeper then return "keeper" end
	return villager._profession
end
M.trade_of = trade_of

local function takes(input, item)
	if input[1] == item then return true end
	local members = input[3] and goods.CATEGORIES[input[3]]
	return members ~= nil and members[item] ~= nil
end

-- Whether a purchase of the item goes into its book.
function M.kept(villager, item)
	if not villager or not item then return false end
	local trade = trade_of(villager)
	if trade == "keeper" and food.POINTS[item] then return true end
	local peddle = villager._villages_peddle
	if peddle and peddle.item == item then return true end
	if not trade then return false end
	for _, recipe in ipairs(recipes[trade] or {}) do
		for _, input in ipairs(recipe.from) do
			if takes(input, item) then return true end
		end
	end
	for _, conversion in ipairs(goods.CONVERSIONS[trade] or {}) do
		if conversion.from == item then return true end
	end
	return false
end

-- Its book, {[item or category] = emeralds}, or nil for none; the cleric's and the keeper's
-- older fields folded in, once.
function M.book(villager)
	if not villager then return nil end
	local book = villager[FIELD]
	local flesh, dishes = villager._villages_flesh_cost, villager._villages_dish_cost
	if flesh or dishes then
		book = book or {}
		if flesh and flesh > 0 and not book[FLESH] then book[FLESH] = flesh end
		for item, cost in pairs(dishes or {}) do
			-- Its armor stand and carpets were noted as dishes (ticket 40d): food only.
			if food.POINTS[item] and not book[item] then book[item] = cost end
		end
		villager._villages_flesh_cost, villager._villages_dish_cost = nil, nil
		villager[FIELD] = next(book) and book or nil
		book = villager[FIELD]
	end
	return book
end

-- What one of the item cost it, as noted, or nil.
function M.cost(villager, item)
	local book = M.book(villager)
	return book and book[item] or nil
end

-- Notes `count` of the item for `paid` emeralds, whatever the item: the keeper's potato,
-- noted at the baked potato it becomes (dinner.note_cost).
function M.record(villager, item, count, paid)
	if not villager or not item or not count or count <= 0 or not paid or paid < 0 then return end
	local book = M.book(villager) or {}
	local before = book[item]
	book[item] = before and (before * KEEP + paid) / (KEEP + count) or paid / count
	villager[FIELD] = book
end

-- A purchase of `count` of the item for `paid` emeralds: into its book if kept (M.kept), and
-- an alchemist's category book (`held`, what it holds now, the purchase in it).
function M.note(villager, item, count, paid, held)
	if not villager or not paid then return end
	if held then alchemist.bought(villager, held, item, count, paid) end
	if M.kept(villager, item) then M.record(villager, item, count, paid) end
end

return M
