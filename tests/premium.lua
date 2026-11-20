-- Run with: lua tests/premium.lua
minetest = {get_modpath = function() return "." end}
local premium = dofile("premium.lua")
local BOOK = "mcl_books:book"

-- Levels: the villager's tier and the player's band, the lower counting; none below 3.
assert(premium.band(0) == 0 and premium.band(15) == 3 and premium.band(30) == 4 and premium.band(50) == 5)
assert(premium.band(100) == 5, "a Hero unlocks no more than Honoured")
assert(premium.level(5, 50) == 5 and premium.level(5, 30) == 4 and premium.level(3, 100) == 3)
assert(premium.level(2, 100) == 0 and premium.level(5, 10) == 0, "nothing below level 3")
assert(premium.locked(5, 4, 100) == "needs a master", "the tier first")
assert(premium.locked(5, 5, 40) == "needs honoured (50)" and premium.locked(4, 5, 20) == "needs a friend (30)")
assert(premium.locked(3, 3, 15) == nil and premium.locked(4, 5, 30) == nil)

-- Enchantment levels: the maximum at 5, one below at 4, two below at 3; treasure only at 5.
assert(premium.enchant_level("efficiency", 5) == 5 and premium.enchant_level("efficiency", 3) == 3)
assert(premium.enchant_level("fortune", 4) == 2 and premium.enchant_level("protection", 4) == 3)
assert(premium.enchant_level("unbreaking", 3) == 1)
assert(premium.enchant_level("mending", 5) == 1 and premium.enchant_level("mending", 4) == nil)
assert(premium.enchant_level("silk_touch", 4) == nil)

-- The librarian: every book at every level, the top six at 5, four at 4 and four at 3.
local offers = premium.offers("librarian")
local by_level, ids = {}, {}
for _, offer in ipairs(offers) do
	by_level[offer.level] = (by_level[offer.level] or 0) + 1
	ids[offer.id] = offer
	assert(offer.base == BOOK and offer.count == 1 and offer.from == BOOK)
	assert(offer.makes == "mcl_enchanting:book_enchanted")
end
assert(#offers == 14 and by_level[5] == 6 and by_level[4] == 4 and by_level[3] == 4)
assert(offers[1].id == "mending_1" and offers[1].dinners == 40, "highest level, dearest first")
-- Level 4 is the user's list: Efficiency IV, Unbreaking II, Fortune II, Protection III.
for _, id in ipairs({"efficiency_4", "unbreaking_2", "fortune_2", "protection_3"}) do
	assert(ids[id] and ids[id].level == 4, id)
end
assert(ids.efficiency_5.dinners == 32 and ids.fortune_3.dinners == 32 and ids.protection_4.dinners == 28)
assert(ids.silk_touch_1.dinners == 24 and ids.unbreaking_3.dinners == 24)
assert(ids.efficiency_4.dinners == 16 and ids.fortune_1.dinners == 8 and ids.protection_2.dinners == 7)
assert(ids.efficiency_5.label == "Book: Efficiency V" and ids.mending_1.label == "Book: Mending")
assert(#premium.offers("shepherd") == 0)
-- A good with several enchantments costs the sum.
assert(premium.dinners({efficiency = 5, unbreaking = 3}) == 56)
assert(premium.describe({unbreaking = 3, efficiency = 5}) == "Efficiency V, Unbreaking III")

-- Prices: dinners at the seller's dinner, plus the base, less reputation's share.
assert(premium.price(ids.mending_1, 18, 16, 0) == 736)
assert(premium.price(ids.mending_1, 18, 16, 0.125) == 644, "honoured, an eighth off")
assert(premium.price(ids.mending_1, 9, 16, 0) == 376, "follows the price of a dinner")
assert(premium.price({dinners = 0, count = 1}, 18, 0, 0) == 1, "at least one")

-- The base it keeps: from journeyman up, never for the keeper, the alchemist or a child.
assert(premium.keeps({_profession = "librarian", _max_trade_tier = 2}) == nil)
assert(premium.keeps({_profession = "librarian", _max_trade_tier = 3})[BOOK] == 4)
assert(premium.keeps({_profession = "librarian", _max_trade_tier = 5, child = true}) == nil)
assert(premium.keeps({_profession = "cleric", _max_trade_tier = 5, _villages_alchemist = true}) == nil)
assert(premium.keeps({_profession = "fisherman", _max_trade_tier = 5}) == nil)

-- Rows: every offer, its price, the sales its books allow, and why it is locked.
local rows = premium.rows("librarian", 4, 50, {[BOOK] = 3}, 18, function() return 16 end, 0.125)
assert(#rows == 14 and rows[1].offer.id == "mending_1" and rows[1].locked == "needs a master")
assert(rows[1].stock == 3)
local open = 0
for _, row in ipairs(rows) do
	if not row.locked then open = open + 1 end
end
assert(open == 8, "levels 4 and 3 at an expert")
local none = premium.rows("librarian", 5, 60, {}, 18, function() return 16 end, 0)
assert(none[1].stock == 0 and not none[1].locked, "out of stock, not locked")

-- The cleric (ticket 37b): pearls from level 4, bottles o' enchanting at 5, each from a
-- glass bottle, capped a day by the level unlocked.
do
	local BOTTLE = "mcl_potions:glass_bottle"
	local list = premium.offers("cleric")
	assert(#list == 2 and list[1].id == "experience_bottle" and list[2].id == "ender_pearl")
	assert(list[2].level == 4 and list[2].dinners == 4 and list[2].base == BOTTLE and list[2].makes == "mcl_throwing:ender_pearl")
	assert(list[1].dinners == 2 and list[1].makes == "mcl_experience:bottle")
	assert(premium.left(list[2], 4, 0) == 2 and premium.left(list[2], 5, 3) == 5 and premium.left(list[2], 5, 9) == 0)
	assert(premium.left(ids.mending_1, 5, 3) == nil, "books have no cap")
	assert(premium.keeps({_profession = "cleric", _max_trade_tier = 3})[BOTTLE] == 9)
	local v = {}
	premium.note_sold(v, "rskj", "ender_pearl", 3, 4)
	premium.note_sold(v, "rskj", "ender_pearl", 2, 4)
	assert(premium.sold_today(v, "rskj", 4).ender_pearl == 5 and premium.sold_today(v, "other", 4) == nil)
	assert(premium.sold_today(v, "rskj", 5) == nil, "a new day")
	premium.note_sold(v, "rskj", "ender_pearl", 1, 5)
	assert(premium.sold_today(v, "rskj", 5).ender_pearl == 1 and v._villages_premium_sold.day == 5)
	-- Rows: stock is the lesser of its bottles and what today's cap leaves.
	local r = premium.rows("cleric", 5, 60, {[BOTTLE] = 20}, 18, function() return 7 end, 0, {ender_pearl = 6})
	assert(r[2].stock == 2 and r[2].left == 2 and r[1].stock == 16)
	assert(r[2].price == 4 * 18 + 7)
end

-- The farmer (ticket 37c): a golden carrot from 6 wheat or 8 potatoes, two offers sharing
-- one cap a day, 4 at level 4 and 16 at level 5; it keeps 24 of each.
do
	local WHEAT, POTATO = "mcl_farming:wheat_item", "mcl_farming:potato_item"
	local keeps = premium.keeps({_profession = "farmer", _max_trade_tier = 3})
	assert(keeps[WHEAT] == 24 and keeps[POTATO] == 24)
	assert(premium.keeps({_profession = "farmer", _max_trade_tier = 2}) == nil)
	local list = premium.offers("farmer")
	assert(#list == 2)
	local by = {}
	for _, offer in ipairs(list) do by[offer.base] = offer end
	assert(by[WHEAT].id == "golden_carrot_wheat_item" and by[WHEAT].count == 6 and by[WHEAT].cap == "golden_carrot")
	assert(by[POTATO].count == 8 and by[POTATO].label == "Golden carrot (8 potatoes)")
	assert(by[WHEAT].makes == "mcl_farming:carrot_item_gold" and by[WHEAT].level == 4 and by[WHEAT].dinners == 3)
	local value = function(item) return item == WHEAT and 3.2 or 2.5 end
	local r = premium.rows("farmer", 5, 60, {[WHEAT] = 30, [POTATO] = 16}, 18, value, 0, {golden_carrot = 10})
	local rw, rp
	for _, row in ipairs(r) do
		if row.offer.base == WHEAT then rw = row else rp = row end
	end
	assert(rw.price == math.ceil(3 * 18 + 6 * 3.2) and rp.price == 3 * 18 + 8 * 2.5)
	assert(rw.stock == 5 and rp.stock == 2, "its base, and the 6 the shared cap leaves")
	assert(rw.left == 6 and rp.left == 6)
	local friend = premium.rows("farmer", 5, 35, {[WHEAT] = 60}, 18, value, 0, {golden_carrot = 1})
	assert(friend[1].stock == 3 or friend[2].stock == 3, "4 a day at level 4")
	assert(premium.rows("farmer", 3, 60, {[WHEAT] = 60}, 18, value, 0)[1].locked == "needs an expert")
end

print("premium ok")
