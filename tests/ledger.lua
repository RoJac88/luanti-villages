-- Run with: lua tests/ledger.lua
minetest = {get_modpath = function() return "." end}
local ledger = dofile("ledger.lua")
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- Base prices from VoxeLibre's tables, times SCALE (ticket 11h): vanilla's emerald is
-- 64 of the economy's, so the cheapest goods are worth whole emeralds.
local S = ledger.SCALE
assert(S == 64)
assert(near(ledger.price("mcl_farming:wheat_item"), S / 20), "the farmer buys 20 wheat for one")
assert(near(ledger.price("mcl_farming:bread"), S / 6), "and sells 6 bread for one")
assert(near(ledger.price("mcl_core:iron_ingot"), S / 4))
assert(near(ledger.price("mcl_core:stick"), 2), "32 sticks for one: the cheapest, worth 2")
-- Bought (18 for one) and sold (one for one) somewhere: the geometric mean.
assert(near(ledger.price("mcl_wool:white"), S * math.sqrt(1 / 18)))
-- Emeralds and a second ingredient: 1 emerald and 6 raw cod (15 for one) make 6 cooked.
assert(near(ledger.price("mcl_fishing:fish_cooked"), S * (1 + 6 / 15) / 6))
-- Hand prices for what no table has, and none for what nothing prices.
assert(near(ledger.price("mcl_core:tree"), S * 0.25) and ledger.price("mcl_core:cobble"))
assert(ledger.price("mcl_core:emerald") == 1)
assert(ledger.price("no:such_item") == nil)
-- Every item that appears in a trade has a price, except what only comes with something else.
local tables = dofile("trade_tables.lua")
local unpriced = {}
for _, profession in pairs(tables.professions) do
	for _, trade in ipairs(profession.trades) do
		for _, s in ipairs(trade.offered) do
			if not ledger.price(s.item) then unpriced[#unpriced + 1] = s.item end
		end
	end
end
assert(#unpriced == 0, "unpriced: " .. table.concat(unpriced, ", "))

-- The dependency graph.
local smith = ledger.inputs("tool_smith")
assert(smith["mcl_core:coal_lump"] == 15 and smith["mcl_core:iron_ingot"] == 4)
assert(smith["mcl_core:flint"] == 30, "capped at 32 but 30 fits")
assert(ledger.inputs("tool_smith", 1)["mcl_core:iron_ingot"] == nil, "only up to its tier")
assert(next(ledger.inputs("farmer")) == nil, "a farmer grows what its table buys")
assert(ledger.inputs("shepherd")["mcl_wool:white"] == nil and ledger.inputs("shepherd")["mcl_dye:black"] == 12)
assert(ledger.outputs("farmer")["mcl_farming:bread"] and ledger.outputs("farmer")["mcl_farming:wheat_item"])
assert(ledger.inputs("keeper")["mcl_farming:wheat_item"] and ledger.outputs("keeper")["mcl_farming:bread"])
assert(next(ledger.inputs("nitwit")) == nil and next(ledger.inputs("unemployed")) == nil)
local flint = ledger.producers("mcl_core:flint")
assert(#flint == 1 and flint[1] == "fletcher")
local bread = table.concat(ledger.producers("mcl_farming:bread"), ",")
assert(bread == "farmer,keeper", bread)

-- Urgency: 1 at the target, up to 3 with nothing, down toward 0.5 well past it.
assert(ledger.urgency(10, 10) == 1 and ledger.urgency(0, 10) == 3 and near(ledger.urgency(5, 10), 2))
assert(ledger.urgency(12, 10) == 1, "within the reserve")
assert(ledger.urgency(26, 10) < 1 and ledger.urgency(1000, 10) > 0.5)
assert(ledger.urgency(0, 0) == 1 and near(ledger.urgency(4, 0), 0.5), "wanted not at all")

-- Preferences: one or two, always the same for a villager.
local p1, p2 = ledger.preferences("abc"), ledger.preferences("abc")
local n = 0
for item, count in pairs(p1) do n = n + 1; assert(p2[item] == count and count >= 1) end
assert(n == 1 or n == 2)

-- One villager: a hungry toolsmith with a little coal and a lot of bread.
local foods = {["mcl_farming:bread"] = 4, ["mcl_farming:carrot_item"] = 1}
local smithy = ledger.assess({
	id = "sam", profession = "tool_smith", max_tier = 1, food_points = 2, hunger_per_day = 4, foods = foods,
	held = {["mcl_core:coal_lump"] = 5, ["mcl_farming:bread"] = 1, ["mcl_core:emerald"] = 9, ["mcl_core:stick"] = 40},
})
-- Food (ticket 15, by its points from any food): 3 days at 4 a day, less the 2 it has,
-- 10 points; the loaf it carries gives 4, so 6 short: 2 loaves, or 6 carrots, or 2 apples.
assert(smithy.categories.food.target == 10 and smithy.categories.food.short == 6)
assert(smithy.needs["mcl_farming:bread"] == 2 and smithy.needs["mcl_farming:carrot_item"] == 6)
assert(smithy.needs["mcl_core:apple"] == 2 and smithy.group["mcl_core:apple"] == "food")
-- Fuel by burn seconds: its trade table's 15 coal, 1200 s, less 5 lumps' 400: 10 lumps.
assert(smithy.needs["mcl_core:coal_lump"] == 10 and smithy.needs["mcl_core:charcoal_lump"] == 10)
assert(smithy.surplus["mcl_core:stick"] and not smithy.surplus["mcl_core:emerald"], "emeralds are money, not surplus")
-- It values coal above the price, sticks below it.
assert(smithy.value("mcl_core:coal_lump") > ledger.price("mcl_core:coal_lump"))
assert(smithy.value("mcl_core:stick") < ledger.price("mcl_core:stick"))
assert(smithy.value("mcl_core:emerald") == 1 and smithy.value("no:such_item") == nil)
-- A fed villager wants no food.
local fed = ledger.assess({id = "sam", profession = "nitwit", food_points = 20, hunger_per_day = 4, foods = foods, held = {}})
assert(not fed.categories.food and not fed.needs["mcl_farming:bread"])
-- One that has eaten its fill of bread needs no apples: the points are what count.
local loaded = ledger.assess({id = "sam", profession = "nitwit", food_points = 2, hunger_per_day = 4,
	held = {["mcl_farming:bread"] = 6}})
assert(not loaded.needs["mcl_core:apple"] and loaded.surplus["mcl_farming:bread"] == 2, "24 points, 10 wanted and a reserve of 3")
-- A Builder's missing materials add to what it wants.
local builder = ledger.assess({id = "bo", profession = "mason", max_tier = 1, extra = {["mcl_core:cobble"] = 40}, held = {}})
assert(builder.needs["mcl_core:cobble"] == 40)
-- top: the largest worth first.
local top = ledger.top(smithy.needs, smithy.value, 1)
-- Logs for its own sticks (ticket 11d) are the tool smith's dearest need, of any species.
assert(#top == 1 and smithy.group[top[1].item] == "log", top[1].item)
assert(smithy.needs["mcl_core:tree"] == 4 and smithy.needs["mcl_core:birchtree"] == 4 and smithy.needs["mcl_core:wood"] == 8)
-- Birch logs fill a need for logs; logs it needs are no fuel to it.
local birch = ledger.assess({id = "sam", profession = "tool_smith", max_tier = 1,
	held = {["mcl_core:birchtree"] = 4, ["mcl_core:coal_lump"] = 15}})
assert(not birch.needs["mcl_core:tree"] and birch.categories.log.held == 4)
assert(not birch.needs["mcl_core:coal_lump"] and birch.categories.fuel.held == 1200)
-- To one that needs no logs, logs are fuel.
local burns_logs = ledger.assess({id = "m", profession = "armorer", max_tier = 1, held = {["mcl_core:sprucetree"] = 16}})
assert(burns_logs.categories.fuel.held == 16 * 15 and burns_logs.group["mcl_core:sprucetree"] == "fuel")
-- worth caps a value whatever the need: a good that wears out is worth what it brings.
local capped = ledger.assess({id = "f", profession = "farmer", held = {},
	extra = {["mcl_farming:hoe_stone"] = 1}, worth = {["mcl_farming:hoe_stone"] = 100}})
assert(capped.needs["mcl_farming:hoe_stone"] == 1)
assert(capped.value("mcl_farming:hoe_stone") == 100, capped.value("mcl_farming:hoe_stone"))
-- The need itself is as urgent as any wanted whole, whatever the cap.
assert(capped.urgency("mcl_farming:hoe_stone") == ledger.MAX_URGENCY)
local cheap = ledger.assess({id = "f", profession = "farmer", held = {},
	extra = {["mcl_farming:hoe_stone"] = 1}, worth = {["mcl_farming:hoe_stone"] = 500}})
assert(cheap.value("mcl_farming:hoe_stone") == ledger.price("mcl_farming:hoe_stone") * ledger.MAX_URGENCY)

-- A crafting profession wants its recipes' inputs (recipes.lua), and coal where they smelt.
local smith_inputs = ledger.inputs("tool_smith", 1)
assert(smith_inputs["mcl_core:cobble"] == 12 and smith_inputs["mcl_core:stick"] == 8, smith_inputs["mcl_core:cobble"])
assert(ledger.inputs("mason", 1)["mcl_core:coal_lump"] == 4, "bricks are smelted")
assert(ledger.outputs("librarian")["mcl_books:book"] and ledger.outputs("tool_smith")["mcl_tools:pick_stone"])
-- Charcoal and coal are both fuel: the two count together toward one target.
local burner = ledger.assess({
	id = "sam", profession = "tool_smith", max_tier = 1,
	held = {["mcl_core:coal_lump"] = 5, ["mcl_core:charcoal_lump"] = 6},
})
assert(burner.needs["mcl_core:coal_lump"] == 4 and burner.needs["mcl_core:charcoal_lump"] == 4)
assert(burner.value("mcl_core:charcoal_lump") > ledger.price("mcl_core:charcoal_lump"), "needed like coal")
local stocked = ledger.assess({id = "sam", profession = "tool_smith", max_tier = 1, held = {["mcl_core:charcoal_lump"] = 30}})
assert(not stocked.needs["mcl_core:coal_lump"] and stocked.surplus["mcl_core:charcoal_lump"] == 11)

print("ledger.lua: ok")
