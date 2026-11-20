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
assert(near(ledger.price("mcl_core:stick"), 2), "32 sticks for one: the cheapest, worth 2")
-- Bought (18 for one) and sold (one for one) somewhere: the geometric mean. Grey wool is
-- priced so; white wool, dyed from grey, starts at no less than grey and dye (ticket 21d).
assert(near(ledger.price("mcl_wool:grey"), S * math.sqrt(1 / 18)))
assert(near(ledger.price("mcl_wool:white"), ledger.price("mcl_wool:grey") + ledger.price("mcl_dye:white")))
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

-- The alchemist's goods at what their inputs cost (ticket 20): stone 3.2, a log 16, and
-- half a lump of coal a craft (ticket 28c).
local stone, log = ledger.price("mcl_core:stone"), ledger.price("mcl_core:tree")
local fuel = ledger.price("mcl_core:coal_lump") / 2
assert(near(stone, S / 20) and near(log, 16))
assert(near(ledger.price("mcl_core:iron_nugget"), 4 * stone + fuel))
assert(near(ledger.price("mcl_core:iron_ingot"), 9 * ledger.price("mcl_core:iron_nugget")), "nine nuggets, not vanilla's 16")
assert(near(ledger.price("mcl_core:gold_nugget"), 2 * ledger.price("mcl_core:iron_ingot")))
assert(near(ledger.price("mcl_core:gold_ingot"), 9 * ledger.price("mcl_core:gold_nugget")))
assert(near(ledger.price("mcl_core:flint"), 4 * log + fuel))
assert(near(ledger.price("mcl_core:glass"), 2 * stone + fuel), "cheaper than vanilla's 16")
assert(near(ledger.price("xpanes:pane_natural_flat"), ledger.price("mcl_core:glass")))
-- Goods made from them at no less than COST_FLOOR times their inputs and fuel, so every
-- recipe that takes iron, gold or flint gains at base prices.
local recipes = dofile("recipes.lua")
local floored = {["mcl_core:iron_ingot"] = true, ["mcl_core:iron_nugget"] = true, ["mcl_core:gold_ingot"] = true,
	["mcl_core:gold_nugget"] = true, ["mcl_core:flint"] = true}
local checked = 0
for profession, list in pairs(recipes) do
	for _, recipe in ipairs(list) do
		local cost, uses = (recipe.fuel or 0) / 8 * ledger.price("mcl_core:coal_lump"), false
		for _, input in ipairs(recipe.from) do
			cost = cost + (ledger.price(input[1]) or 0) * input[2]
			uses = uses or floored[input[1]] == true
		end
		if uses then
			checked = checked + 1
			local made = ledger.price(recipe.makes) * recipe.count
			assert(made >= ledger.COST_FLOOR * cost - 1e-9, profession .. " loses on " .. recipe.makes)
		end
	end
end
assert(checked == 12, "the four iron pieces, the iron axe, pick, hoe and sword (ticket 37d), the cauldron, the clock, arrows and the labourers' lantern: "
	.. checked)
-- Priced by their floor alone, as no trade table prices them (ticket 29).
assert(near(ledger.price("mcl_tools:pick_iron"), ledger.COST_FLOOR * (3 * ledger.price("mcl_core:iron_ingot")
	+ 2 * ledger.price("mcl_core:stick") + 3 / 8 * ledger.price("mcl_core:coal_lump"))))
assert(near(ledger.price("mcl_cauldrons:cauldron"), ledger.COST_FLOOR * (7 * ledger.price("mcl_core:iron_ingot")
	+ 7 / 8 * ledger.price("mcl_core:coal_lump"))))
-- The cleric's clock: one gold ingot and one iron (ticket 29).
assert(near(ledger.price("mcl_clock:clock"), ledger.COST_FLOOR * (ledger.price("mcl_core:gold_ingot")
	+ ledger.price("mcl_core:iron_ingot"))))
-- 724 and 439 before the alchemist's fuel (ticket 28c) went into an ingot's cost.
assert(math.floor(ledger.price("mcl_armor:helmet_iron") + 0.5) == 856)
assert(math.floor(ledger.price("mcl_tools:axe_iron") + 0.5) == 518)
assert(near(ledger.price("mcl_armor:helmet_iron"), ledger.COST_FLOOR * (5 * ledger.price("mcl_core:iron_ingot")
	+ 5 / 8 * ledger.price("mcl_core:coal_lump"))))

-- The dependency graph.
local smith = ledger.inputs("tool_smith")
assert(smith["mcl_core:coal_lump"] == 15 and smith["mcl_core:diamond"] == 1)
assert(ledger.inputs("tool_smith", 1)["mcl_core:diamond"] == nil, "only up to its tier")
-- A trade's want for iron, gold or flint counts only where the profession's recipes take it
-- (ticket 20): the tool smith's flint and the leatherworker's flint go. The tool smith's iron
-- stays, for its iron pick, and the cleric's gold, for its clock (ticket 29).
assert(smith["mcl_core:iron_ingot"] and smith["mcl_core:flint"] == nil)
assert(ledger.inputs("cleric")["mcl_core:gold_ingot"])
-- Ticket 37b: only players sell the cleric rotten flesh, at its window, and it makes its
-- bottles from glass.
assert(not ledger.inputs("cleric")["mcl_mobitems:rotten_flesh"] and not ledger.inputs("cleric")["mcl_potions:glass_bottle"])
assert(ledger.inputs("cleric")["mcl_core:glass"] == 12)
assert(ledger.inputs("leatherworker")["mcl_core:flint"] == nil)
assert(ledger.inputs("weapon_smith")["mcl_core:iron_ingot"] and not ledger.inputs("weapon_smith")["mcl_core:flint"])
assert(ledger.inputs("armorer")["mcl_core:iron_ingot"] == 32 and ledger.inputs("fletcher")["mcl_core:flint"] == 26)
assert(next(ledger.inputs("farmer")) == nil, "a farmer grows what its table buys")
assert(ledger.inputs("shepherd")["mcl_wool:white"] == nil and ledger.inputs("shepherd")["mcl_dye:black"] == 12)
assert(ledger.outputs("farmer")["mcl_farming:bread"] and ledger.outputs("farmer")["mcl_farming:wheat_item"])
-- The keeper buys bread and cooked fish ready made; only farmers bake, only butchers cook.
assert(ledger.inputs("keeper")["mcl_farming:bread"] and ledger.inputs("keeper")["mcl_fishing:fish_cooked"])
assert(not ledger.inputs("keeper")["mcl_farming:wheat_item"] and not ledger.inputs("keeper")["mcl_fishing:fish_raw"])
assert(ledger.outputs("keeper")["mcl_farming:bread"])
assert(next(ledger.inputs("nitwit")) == nil and next(ledger.inputs("unemployed")) == nil)
local flint = ledger.producers("mcl_core:flint")
assert(#flint == 2 and flint[1] == "alchemist" and flint[2] == "fletcher", "and the alchemist (ticket 20)")
assert(next(ledger.inputs("alchemist")) == nil, "its inputs follow what it holds (alchemist.targets)")
local bread = table.concat(ledger.producers("mcl_farming:bread"), ",")
assert(bread == "farmer,keeper", bread)

-- Urgency: 1 at the target, up to 3 with nothing, down toward 0.5 well past it.
assert(ledger.urgency(10, 10) == 1 and ledger.urgency(0, 10) == 3 and near(ledger.urgency(5, 10), 2))
assert(ledger.urgency(12, 10) == 1, "within the reserve")
assert(ledger.urgency(26, 10) < 1 and ledger.urgency(1000, 10) > 0.5)
assert(ledger.urgency(0, 0) == 1 and near(ledger.urgency(4, 0), 0.5), "wanted not at all")

-- One villager: a hungry toolsmith with a little coal and a lot of bread.
local foods = {["mcl_farming:bread"] = 4, ["mcl_farming:carrot_item"] = 1}
local smithy = ledger.assess({
	id = "sam", profession = "tool_smith", max_tier = 1, food_points = 2, hunger_per_day = 4, foods = foods,
	held = {["mcl_core:coal_lump"] = 5, ["mcl_farming:bread"] = 1, ["mcl_core:emerald"] = 100, ["mcl_core:stick"] = 40},
})
-- Food (ticket 15, by its points from any food): with over five dinners' emeralds, 2 days
-- at 4 a day, 8 points; the loaf it carries gives 4, so 4 short: a loaf, 4 carrots, 2 apples.
assert(smithy.categories.food.target == 8 and smithy.categories.food.short == 4)
assert(smithy.needs["mcl_farming:bread"] == 1 and smithy.needs["mcl_farming:carrot_item"] == 4)
assert(smithy.needs["mcl_core:apple"] == 2 and smithy.group["mcl_core:apple"] == "food")
-- With less money it relies on the tavern; starving, it wants a day's food.
local poor = ledger.assess({id = "sam", profession = "nitwit", food_points = 2, hunger_per_day = 4, foods = foods,
	held = {["mcl_core:emerald"] = ledger.STOCK_MONEY}})
assert(not poor.categories.food)
local starving = ledger.assess({id = "sam", profession = "nitwit", food_points = 0, hunger_per_day = 4, foods = foods,
	held = {["mcl_core:emerald"] = 3}})
assert(starving.categories.food.target == 4)
-- Fuel by burn seconds: its trade table's 15 coal, 1200 s, less 5 lumps' 400: 10 lumps.
assert(smithy.needs["mcl_core:coal_lump"] == 10 and smithy.needs["mcl_core:charcoal_lump"] == 10)
assert(smithy.surplus["mcl_core:stick"] and not smithy.surplus["mcl_core:emerald"], "emeralds are money, not surplus")
-- It values coal above the price, sticks below it.
assert(smithy.value("mcl_core:coal_lump") > ledger.price("mcl_core:coal_lump"))
assert(smithy.value("mcl_core:stick") < ledger.price("mcl_core:stick"))
assert(smithy.value("mcl_core:emerald") == 1 and smithy.value("no:such_item") == nil)
-- A fed villager with little money wants no food.
local fed = ledger.assess({id = "sam", profession = "nitwit", food_points = 20, hunger_per_day = 4, foods = foods, held = {}})
assert(not fed.categories.food and not fed.needs["mcl_farming:bread"])
-- One with its fill of bread needs no apples: the points are what count.
local loaded = ledger.assess({id = "sam", profession = "nitwit", food_points = 2, hunger_per_day = 4,
	held = {["mcl_farming:bread"] = 6, ["mcl_core:emerald"] = 200}})
assert(not loaded.needs["mcl_core:apple"] and loaded.surplus["mcl_farming:bread"] == 3, "24 points, 8 wanted and a reserve of 3")
-- A Builder's missing materials add to what it wants.
local builder = ledger.assess({id = "bo", profession = "mason", max_tier = 1, extra = {["mcl_core:cobble"] = 40}, held = {}})
local plain = ledger.assess({id = "bo", profession = "mason", max_tier = 1, held = {}})
assert(builder.needs["mcl_core:cobble"] == 40 + (plain.needs["mcl_core:cobble"] or 0))
-- top: the largest worth first.
local top = ledger.top(smithy.needs, smithy.value, 1)
-- Ingots for its iron pick (ticket 29) are the tool smith's dearest need; then logs for its
-- own sticks (ticket 11d), of any species.
assert(#top == 1 and top[1].item == "mcl_core:iron_ingot", top[1].item)
top = ledger.top(smithy.needs, smithy.value, 2)
assert(smithy.group[top[2].item] == "log", top[2].item)
assert(smithy.needs["mcl_core:tree"] == 4 and smithy.needs["mcl_core:birchtree"] == 4 and smithy.needs["mcl_core:wood"] == 12, "four wooden picks' planks")
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

-- Variety (ticket 34): a food's value times its factor; needs and other goods unchanged.
do
	local BREAD = "mcl_farming:bread"
	local function input(variety)
		return {id = "v", profession = "nitwit", max_tier = 1, held = {["mcl_core:emerald"] = 500}, food_points = 6,
			hunger_per_day = 4, foods = {}, variety = variety}
	end
	local plain = ledger.assess(input())
	local tired = ledger.assess(input(function(item) return item == BREAD and 0.6 or 1 end))
	assert(math.abs(tired.value(BREAD) - 0.6 * plain.value(BREAD)) < 1e-9, tired.value(BREAD) .. " " .. plain.value(BREAD))
	assert(tired.variety(BREAD) == 0.6 and plain.variety(BREAD) == 1)
	assert(tired.needs[BREAD] == plain.needs[BREAD])
	local all = ledger.assess(input(function() return 0.5 end))
	assert(all.value("mcl_core:coal_lump") == plain.value("mcl_core:coal_lump"), "food only")
end

print("ledger.lua: ok")
