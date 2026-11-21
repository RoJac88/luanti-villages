-- Run with: lua tests/cost_book.lua
minetest = {get_modpath = function() return "." end}
local book = dofile("cost_book.lua")
local function near(a, b) return math.abs(a - b) < 1e-9 end
local BEEF, FISH = "mcl_mobitems:beef", "mcl_fishing:fish_raw"
local COOKED = "mcl_fishing:fish_cooked"
local FLESH = "mcl_mobitems:rotten_flesh"

-- What is kept (ticket 43a): a recipe's input, a conversion's source, a keeper's food, a
-- peddler's lot.
local butcher = {_profession = "butcher"}
assert(book.kept(butcher, BEEF) and book.kept(butcher, FISH), "the butcher's raw inputs")
assert(not book.kept(butcher, "mcl_core:cobble"), "nothing its trade takes")
assert(book.kept({_profession = "cleric"}, FLESH), "the cleric's leather source")
assert(book.kept({_profession = "woodcutter"}, "mcl_core:tree"), "the woodcutter's planks source")
assert(book.kept({_profession = "mason"}, "mcl_core:clay_lump"))
assert(book.kept({_villages_keeper = true}, COOKED), "a keeper's dish, bought to sell on")
assert(not book.kept({_villages_keeper = true}, "mcl_armor_stand:armor_stand"))
assert(book.kept({_villages_alchemist = true}, "mcl_core:cobble"), "a category input's member")
local peddler = {_villages_peddle = {item = "mcl_core:glass", count = 10}}
assert(book.kept(peddler, "mcl_core:glass") and not book.kept(peddler, BEEF))
assert(not book.kept({}, BEEF) and not book.kept(nil, BEEF))

-- An average over about KEEP bought.
book.note(butcher, "mcl_core:cobble", 4, 4)
assert(butcher._villages_input_cost == nil, "not kept, not noted")
book.note(butcher, BEEF, 10, 4)
assert(near(book.cost(butcher, BEEF), 0.4))
book.note(butcher, BEEF, 8, 8)
assert(near(book.cost(butcher, BEEF), (0.4 * book.KEEP + 8) / (book.KEEP + 8)))
book.note(butcher, BEEF, 0, 5)
book.note(butcher, BEEF, 3, -1)
assert(near(book.cost(butcher, BEEF), (0.4 * book.KEEP + 8) / (book.KEEP + 8)), "nothing or a refund: no note")
assert(book.cost(butcher, FISH) == nil)

-- The alchemist's category book is reached by the same call, with what it holds.
local alch = {_villages_alchemist = true, _villages_prices = {}}
book.note(alch, "mcl_core:cobble", 10, 2, {["mcl_core:cobble"] = 10})
assert(near(alch._villages_input_cost.stone, 0.2), "its stone, per unit")
assert(near(book.cost(alch, "mcl_core:cobble"), 0.2), "and the cobble itself")

-- Older books fold in once: the cleric's flesh, the keeper's dishes, food only.
local cleric = {_profession = "cleric", _villages_flesh_cost = 1.5}
assert(book.cost(cleric, FLESH) == 1.5 and cleric._villages_flesh_cost == nil)
local keeper = {_villages_keeper = true, _villages_input_cost = {[COOKED] = 3},
	_villages_dish_cost = {[COOKED] = 9, ["mcl_farming:bread"] = 2, ["mcl_wool:white_carpet"] = 40}}
assert(book.cost(keeper, COOKED) == 3, "the book's own entry stands")
assert(book.cost(keeper, "mcl_farming:bread") == 2)
assert(book.cost(keeper, "mcl_wool:white_carpet") == nil and keeper._villages_dish_cost == nil)
local empty = {_villages_dish_cost = {["mcl_wool:white_carpet"] = 40}}
assert(book.book(empty) == nil and empty._villages_input_cost == nil, "nothing left, no book")

print("cost_book.lua: ok")
