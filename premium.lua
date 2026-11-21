-- Premium trades (docs/villager-economy-design.md, ticket 37), pure: the high-tier goods a
-- villager sells to players only, each made at the sale from a base good it keeps.
--
-- * Unlocking. A row is offered at a level from MIN_LEVEL (3) to 5. The villager's tier
--   (`_max_trade_tier`, which rises on supply days) and the player's reputation with that
--   villager (gossip.lua) each set a level; the lower one counts. Reputation's bands:
--   Known (15) level 3, Friend (30) level 4, Honoured (50) level 5. A Hero (100) unlocks
--   no more, but the window's reputation share (up to a quarter off at 100) applies to
--   premium prices too. Every row at or below the level is offered, not a random pick, so
--   one master librarian sells every top book.
-- * The base good. A profession with premium goods keeps BASE.keep of its base good while
--   at MIN_LEVEL or higher (`keeps`, a target the ledger never sells below), and each sale
--   takes `count` of it. With none held the row is out of stock. This is the one exception
--   to "player trades convert nothing", besides the alchemist's.
-- * Prices. P dinners at the seller's own reference price for a dinner, so premium prices
--   follow the village's food, plus the base's reference value, less the reputation share.
--   P comes from ENCHANTS: a headline enchantment's top level is 32 dinners and each level
--   below costs half; utility ones top out at 24 to 28; treasure ones (Mending, Silk Touch,
--   Infinity) exist only at their one level. A good with several enchantments costs the
--   sum, so gear is never cheaper than the books. SCALE tunes them all.
-- * Levels. An enchantment line sells its maximum level at premium level 5, one below at 4,
--   two below at 3, where that level exists and has a price. That gives the librarian
--   Efficiency IV, Fortune II, Protection III and Unbreaking II at level 4.
-- * Consumables (`goods`, ticket 37b: the cleric's ender pearls and bottles o' enchanting)
--   are one offer from their level up, at a fixed P, with a cap a day per player per
--   villager by the level unlocked (`caps`): more at a higher level is how they scale.
--   A good with several bases (`bases`, ticket 37c: the farmer's golden carrot from wheat
--   or potatoes) is an offer for each, named for it, sharing one cap (`cap`).
-- * Gear (ticket 37d: the smiths' and the armorer's) is a good with its own enchantments
--   (`enchants`, priced from ENCHANTS) made from `inputs`: a piece it made itself (an iron
--   pick) or the real recipe's diamonds and sticks. Every offer carries `inputs`; its
--   `base` and `count` are the first. An input's `leave` is how many it never sells of it
--   (ticket 37e: the rod a fisherman fishes with). A good with no enchantments (the
--   leatherworker's saddle) has its own `dinners`.
-- * Explorer maps (ticket 38c: the cartographer's) carry `chart`, the structure they lead to.
--   Each is the map of a site its village charted (charting.lua); `rows` takes `charted(offer)`
--   for the sites left for the player, so stock is also those, and a row with none its reason.
--
-- Premium goods never enter villager trade, market news or asks: they exist only once a
-- player buys one.
local M = {}

local BOOK = "mcl_books:book"
local ENCHANTED_BOOK = "mcl_enchanting:book_enchanted"
local BOTTLE = "mcl_potions:glass_bottle"
local WHEAT, POTATO = "mcl_farming:wheat_item", "mcl_farming:potato_item"
local DIAMOND, STICK = "mcl_core:diamond", "mcl_core:stick"
local BOW, ROD, LEATHER = "mcl_bows:bow", "mcl_fishing:fishing_rod", "mcl_mobitems:leather"
local PAPER, MAP = "mcl_core:paper", "mcl_maps:filled_map"

M.MIN_LEVEL, M.MAX_LEVEL = 3, 5
M.SCALE = 1
-- Reputation bands, highest first.
M.BANDS = {{rep = 50, level = 5, word = "honoured"}, {rep = 30, level = 4, word = "a friend"},
	{rep = 15, level = 3, word = "known"}}
-- The villager tier each level needs, by name.
M.TIER_WORDS = {[3] = "a journeyman", [4] = "an expert", [5] = "a master"}

-- Enchantments: their maximum level and price in dinners by level.
M.ENCHANTS = {
	mending = {name = "Mending", max = 1, prices = {[1] = 40}},
	silk_touch = {name = "Silk Touch", max = 1, prices = {[1] = 24}},
	infinity = {name = "Infinity", max = 1, prices = {[1] = 24}},
	efficiency = {name = "Efficiency", max = 5, prices = {[3] = 8, [4] = 16, [5] = 32}},
	fortune = {name = "Fortune", max = 3, prices = {[1] = 8, [2] = 16, [3] = 32}},
	unbreaking = {name = "Unbreaking", max = 3, prices = {[1] = 6, [2] = 12, [3] = 24}},
	protection = {name = "Protection", max = 4, prices = {[2] = 7, [3] = 14, [4] = 28}},
	sharpness = {name = "Sharpness", max = 5, prices = {[3] = 8, [4] = 16, [5] = 32}},
	power = {name = "Power", max = 5, prices = {[3] = 8, [4] = 16, [5] = 32}},
	feather_falling = {name = "Feather Falling", max = 4, prices = {[2] = 4, [3] = 8, [4] = 16}},
	lure = {name = "Lure", max = 3, prices = {[1] = 3, [2] = 6, [3] = 12}},
	luck_of_the_sea = {name = "Luck of the Sea", max = 3, prices = {[1] = 4, [2] = 8, [3] = 16}},
}

-- Each profession's premium line: its base good (`item`, how many it keeps, how many a
-- sale takes) and what it makes. `books` are enchantment lines sold as enchanted books;
-- `goods` are consumables {id, makes, level, dinners, caps = {[level] = a day}}, a good's
-- own `bases` ({item, count, label}) in place of the line's base, or gear {id, from,
-- label, level, enchants, inputs = {{item, count}}}. `keeps` ({item = count}) stands for
-- the line's base where it keeps more than one.
M.LINES = {
	librarian = {
		base = {item = BOOK, keep = 4, count = 1},
		books = {"mending", "efficiency", "fortune", "protection", "silk_touch", "unbreaking"},
	},
	-- Ticket 37b: each from a glass bottle, which it makes from glass.
	cleric = {
		base = {item = BOTTLE, keep = 9, count = 1},
		goods = {
			{id = "ender_pearl", makes = "mcl_throwing:ender_pearl", label = "Ender pearl", level = 4, dinners = 4,
				caps = {[4] = 2, [5] = 8}},
			{id = "experience_bottle", makes = "mcl_experience:bottle", label = "Bottle o' enchanting", level = 5,
				dinners = 2, caps = {[5] = 16}},
		},
	},
	-- Ticket 37c: from 6 wheat or 8 potatoes, about two loaves' worth of food each, so one
	-- comes to about seven loaves at their prices (vanilla's six). It keeps 24 of each.
	farmer = {
		keeps = {[WHEAT] = 24, [POTATO] = 24},
		goods = {
			{id = "golden_carrot", makes = "mcl_farming:carrot_item_gold", label = "Golden carrot", level = 4,
				dinners = 3, caps = {[4] = 4, [5] = 16},
				bases = {{item = WHEAT, count = 6, label = "6 wheat"}, {item = POTATO, count = 8, label = "8 potatoes"}}},
		},
	},
	-- Ticket 37d: enchanted gear from an iron piece it made, or from diamonds it buys from
	-- players (8 kept) and sticks (4 kept), as the real recipe takes.
	tool_smith = {
		keeps = {[DIAMOND] = 8, [STICK] = 4},
		goods = {
			{id = "iron_pick", from = "mcl_tools:pick_iron", label = "Iron pickaxe", level = 3,
				enchants = {efficiency = 3, unbreaking = 1}, inputs = {{item = "mcl_tools:pick_iron", count = 1}}},
			{id = "diamond_axe", from = "mcl_tools:axe_diamond", label = "Diamond axe", level = 4,
				enchants = {efficiency = 4, unbreaking = 2}, inputs = {{item = DIAMOND, count = 3}, {item = STICK, count = 2}}},
			{id = "diamond_shovel", from = "mcl_tools:shovel_diamond", label = "Diamond shovel", level = 4,
				enchants = {efficiency = 4, unbreaking = 2}, inputs = {{item = DIAMOND, count = 1}, {item = STICK, count = 2}}},
			{id = "diamond_pick", from = "mcl_tools:pick_diamond", label = "Diamond pickaxe", level = 5,
				enchants = {efficiency = 5, unbreaking = 3}, inputs = {{item = DIAMOND, count = 3}, {item = STICK, count = 2}}},
		},
	},
	weapon_smith = {
		keeps = {[DIAMOND] = 8, [STICK] = 4},
		goods = {
			{id = "iron_sword", from = "mcl_tools:sword_iron", label = "Iron sword", level = 3,
				enchants = {sharpness = 3}, inputs = {{item = "mcl_tools:sword_iron", count = 1}}},
			{id = "diamond_axe", from = "mcl_tools:axe_diamond", label = "Diamond axe", level = 4,
				enchants = {sharpness = 4, unbreaking = 2}, inputs = {{item = DIAMOND, count = 3}, {item = STICK, count = 2}}},
			{id = "diamond_sword", from = "mcl_tools:sword_diamond", label = "Diamond sword", level = 5,
				enchants = {sharpness = 5, unbreaking = 3}, inputs = {{item = DIAMOND, count = 2}, {item = STICK, count = 1}}},
		},
	},
	armorer = {
		keeps = {[DIAMOND] = 8},
		goods = {},
	},
	-- Ticket 37e: the fletcher's bows, from a bow it made.
	fletcher = {
		goods = {
			{id = "bow_power", from = BOW, label = "Bow", level = 3, enchants = {power = 3}, inputs = {{item = BOW, count = 1}}},
			{id = "bow_unbreaking", from = BOW, label = "Bow", level = 4, enchants = {power = 4, unbreaking = 2},
				inputs = {{item = BOW, count = 1}}},
			{id = "bow_infinity", from = BOW, label = "Bow", level = 5, enchants = {power = 5, infinity = 1},
				inputs = {{item = BOW, count = 1}}},
		},
	},
	-- The fisherman's rods, from one it bought past the one it fishes with (wants.lua's rod),
	-- so it keeps one more.
	fisherman = {
		keeps = {[ROD] = 1},
		goods = {
			{id = "rod_1", from = ROD, label = "Fishing rod", level = 3, enchants = {lure = 1, luck_of_the_sea = 1},
				inputs = {{item = ROD, count = 1, leave = 1}}},
			{id = "rod_2", from = ROD, label = "Fishing rod", level = 4, enchants = {lure = 2, luck_of_the_sea = 2},
				inputs = {{item = ROD, count = 1, leave = 1}}},
			{id = "rod_3", from = ROD, label = "Fishing rod", level = 5, enchants = {lure = 3, luck_of_the_sea = 3},
				inputs = {{item = ROD, count = 1, leave = 1}}},
		},
	},
	-- The leatherworker's leather boots it made with Feather Falling II and IV, and a saddle
	-- from 4 leather (VoxeLibre has no recipe for one). It keeps 4 leather.
	leatherworker = {
		keeps = {[LEATHER] = 4},
		goods = {
			{id = "boots_feather_falling_2", from = "mcl_armor:boots_leather", label = "Leather boots", level = 3,
				enchants = {feather_falling = 2}, inputs = {{item = "mcl_armor:boots_leather", count = 1}}},
			{id = "saddle", from = "mcl_mobitems:saddle", label = "Saddle", level = 4, dinners = 8,
				inputs = {{item = LEATHER, count = 4}}},
			{id = "boots_feather_falling", from = "mcl_armor:boots_leather", label = "Leather boots", level = 5,
				enchants = {feather_falling = 4}, inputs = {{item = "mcl_armor:boots_leather", count = 1}}},
		},
	},
}
-- Ticket 38c: the cartographer's explorer maps, each of a site its village charted
-- (charting.lua) and drew (explorer_map.lua), from the empty map's 8 paper: it stands in for
-- the compass no village can make. `chart` names the structure; a map's stock is also the
-- charted sites the player hasn't bought.
M.LINES.cartographer = {
	keeps = {[PAPER] = 16},
	goods = {
		{id = "ocean_explorer_map", from = MAP, label = "Ocean explorer map", level = 3, dinners = 6,
			chart = "ocean_temple", inputs = {{item = PAPER, count = 8}}},
		{id = "woodland_explorer_map", from = MAP, label = "Woodland explorer map", level = 4, dinners = 10,
			chart = "woodland_cabin", inputs = {{item = PAPER, count = 8}}},
	},
}
-- The armorer's: each iron piece it made with Protection II; diamond leggings and boots
-- with Protection III; a diamond helmet and chestplate with Protection IV and Unbreaking III.
for _, piece in ipairs({{"helmet", "Iron helmet"}, {"chestplate", "Iron chestplate"}, {"leggings", "Iron leggings"},
	{"boots", "Iron boots"}}) do
	local item = "mcl_armor:" .. piece[1] .. "_iron"
	table.insert(M.LINES.armorer.goods, {id = "iron_" .. piece[1], from = item, label = piece[2], level = 3,
		enchants = {protection = 2}, inputs = {{item = item, count = 1}}})
end
for _, piece in ipairs({{"leggings", "Diamond leggings", 7, 4, {protection = 3}},
	{"boots", "Diamond boots", 4, 4, {protection = 3}},
	{"helmet", "Diamond helmet", 5, 5, {protection = 4, unbreaking = 3}},
	{"chestplate", "Diamond chestplate", 8, 5, {protection = 4, unbreaking = 3}}}) do
	table.insert(M.LINES.armorer.goods, {id = "diamond_" .. piece[1], from = "mcl_armor:" .. piece[1] .. "_diamond",
		label = piece[2], level = piece[4], enchants = piece[5], inputs = {{item = DIAMOND, count = piece[3]}}})
end

local ROMAN = {"I", "II", "III", "IV", "V"}

-- The enchantment level a line sells at premium `level`, or nil.
function M.enchant_level(enchant, level)
	local def = M.ENCHANTS[enchant]
	if not def then return nil end
	local at = def.max - (M.MAX_LEVEL - level)
	if at < 1 or not def.prices[at] then return nil end
	return at
end

-- A label for enchantments {name = level}: "Efficiency V", "Mending".
function M.describe(enchants)
	local names = {}
	for enchant, at in pairs(enchants) do
		local def = M.ENCHANTS[enchant]
		names[#names + 1] = def.max == 1 and def.name or (def.name .. " " .. (ROMAN[at] or tostring(at)))
	end
	table.sort(names)
	return table.concat(names, ", ")
end

-- The premium in dinners of enchantments {name = level}.
function M.dinners(enchants)
	local total = 0
	for enchant, at in pairs(enchants) do total = total + M.ENCHANTS[enchant].prices[at] end
	return total
end

-- The line of a villager, or nil: not a child, the keeper, the alchemist or a Builder.
function M.line(villager)
	if villager.child or villager._villages_keeper or villager._villages_alchemist or villager._villages_builder then
		return nil
	end
	return M.LINES[villager._profession]
end

-- Every offer of a profession, at every level: {id, makes, enchants, level, dinners,
-- label, base, count}, highest level first, then dearest.
function M.offers(profession)
	local line = M.LINES[profession]
	if not line then return {} end
	local list = {}
	for _, good in ipairs(line.goods or {}) do
		if good.inputs then
			local first = good.inputs[1]
			list[#list + 1] = {id = good.id, makes = good.from, from = good.from, enchants = good.enchants,
				chart = good.chart, level = good.level, dinners = good.dinners or M.dinners(good.enchants),
				label = good.enchants and (good.label .. ": " .. M.describe(good.enchants)) or good.label,
				inputs = good.inputs, base = first.item, count = first.count}
		else
			local bases = good.bases or {{item = line.base.item, count = line.base.count}}
			for _, base in ipairs(bases) do
				local several = #bases > 1
				list[#list + 1] = {id = several and (good.id .. "_" .. base.item:gsub("^.*:", "")) or good.id,
					cap = good.id, makes = good.makes, from = good.makes, level = good.level, dinners = good.dinners,
					label = several and string.format("%s (%s)", good.label, base.label) or good.label, caps = good.caps,
					inputs = {{item = base.item, count = base.count}}, base = base.item, count = base.count}
			end
		end
	end
	for level = M.MAX_LEVEL, M.MIN_LEVEL, -1 do
		for _, enchant in ipairs(line.books or {}) do
			local at = M.enchant_level(enchant, level)
			if at then
				local enchants = {[enchant] = at}
				list[#list + 1] = {id = enchant .. "_" .. at, makes = ENCHANTED_BOOK, from = BOOK, enchants = enchants,
					level = level, dinners = M.dinners(enchants), label = "Book: " .. M.describe(enchants),
					inputs = {{item = line.base.item, count = line.base.count}}, base = line.base.item,
					count = line.base.count}
			end
		end
	end
	table.sort(list, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		if a.dinners ~= b.dinners then return a.dinners > b.dinners end
		return a.id < b.id
	end)
	return list
end

-- The level reputation `rep` unlocks: 0 below the lowest band.
function M.band(rep)
	for _, band in ipairs(M.BANDS) do
		if (rep or 0) >= band.rep then return band.level end
	end
	return 0
end

-- The level unlocked for a player at reputation `rep` with a villager at `tier`.
function M.level(tier, rep)
	local level = math.min(tier or 1, M.band(rep))
	return level >= M.MIN_LEVEL and level or 0
end

-- Why an offer at `level` is locked, or nil: the villager's tier first.
function M.locked(level, tier, rep)
	if (tier or 1) < level then return "needs " .. M.TIER_WORDS[level] end
	if M.band(rep) < level then
		for _, band in ipairs(M.BANDS) do
			if band.level == level then return string.format("needs %s (%d)", band.word, band.rep) end
		end
	end
	return nil
end

-- What it keeps of its base good: {item = count}, or nil below MIN_LEVEL or with no line.
function M.keeps(villager)
	local line = M.line(villager)
	if not line or (villager._max_trade_tier or 1) < M.MIN_LEVEL then return nil end
	if line.keeps then
		local keeps = {}
		for item, count in pairs(line.keeps) do keeps[item] = count end
		return keeps
	end
	return line.base and {[line.base.item] = line.base.keep} or nil
end

-- An offer's price in whole emeralds: its dinners at `dinner` emeralds a dinner (the
-- seller's reference price), plus its inputs at `value(item)` (their reference values;
-- a number stands for the one base's), less reputation's `share`. At least 1.
function M.price(offer, dinner, value, share)
	local inputs = 0
	if type(value) == "function" then
		for _, input in ipairs(offer.inputs or {{item = offer.base, count = offer.count}}) do
			inputs = inputs + (value(input.item) or 0) * input.count
		end
	else
		inputs = (value or 0) * offer.count
	end
	local total = offer.dinners * M.SCALE * dinner + inputs
	return math.max(math.ceil(total * (1 - (share or 0)) - 1e-9), 1)
end

-- How many sales what it holds (`held`) makes inputs for.
function M.stock(offer, held)
	local stock = math.huge
	for _, input in ipairs(offer.inputs or {{item = offer.base, count = offer.count}}) do
		stock = math.min(stock, math.floor(math.max((held[input.item] or 0) - (input.leave or 0), 0) / input.count))
	end
	return stock
end

-- How many more of a capped offer the player may buy today at unlocked `level`, having
-- bought `sold`; nil for an offer with no cap.
function M.left(offer, level, sold)
	if not offer.caps then return nil end
	local cap = 0
	for at, count in pairs(offer.caps) do
		if at <= level and count > cap then cap = count end
	end
	return math.max(cap - (sold or 0), 0)
end

-- The window's rows for a villager: every offer of its profession, each {offer, price,
-- stock (sales its base held allows, and today's cap), locked (nil or why), left (nil, or
-- what today's cap leaves)}. `held` is what it holds, `dinner` its reference price for a
-- dinner, `value(item)` a base's reference value, `share` reputation's share, `sold` what
-- the player bought of each offer today ({id = count}, nil for none). `charted(offer)`
-- (ticket 38c) gives a map's sites left for the player, and why none: a row's `reason`.
function M.rows(profession, tier, rep, held, dinner, value, share, sold, charted)
	local rows = {}
	local level = M.level(tier, rep)
	for _, offer in ipairs(M.offers(profession)) do
		local stock = M.stock(offer, held)
		local left = M.left(offer, level, sold and sold[offer.cap or offer.id])
		local reason
		if offer.chart then
			local sites, why = 0, "can't chart here"
			if charted then sites, why = charted(offer) end
			if sites < 1 then reason = why end
			stock = math.min(stock, sites)
		end
		rows[#rows + 1] = {offer = offer, price = M.price(offer, dinner, value, share),
			stock = left and math.min(stock, left) or stock, left = left, locked = M.locked(offer.level, tier, rep),
			reason = reason}
	end
	return rows
end

-- What a player bought today of each offer from this villager ({id = count}, nil for
-- none), from `_villages_premium_sold` ({day, players = {name = {id = count}}}).
function M.sold_today(villager, name, day)
	local record = villager._villages_premium_sold
	return record and record.day == day and record.players[name] or nil
end

-- Notes `count` of an offer sold to a player today; yesterday's are dropped.
function M.note_sold(villager, name, id, count, day)
	local record = villager._villages_premium_sold
	if not record or record.day ~= day then
		record = {day = day, players = {}}
		villager._villages_premium_sold = record
	end
	local own = record.players[name] or {}
	record.players[name] = own
	own[id] = (own[id] or 0) + count
end

return M
