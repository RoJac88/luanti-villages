-- The mod's own trade window (docs/villager-economy-design.md, ticket 14), in place of
-- vanilla's trade tables with the economy on. A villager trades only what it really
-- has, at the prices it trades at with villagers (ticket 21c: the player is one more
-- trader in the market, not a customer at a margin):
--
-- * It sells its spare goods (its ledger's surplus), from its belongings and its
--   stash, at its ask (asks.lua), the price a villager would pay it; an item with no ask
--   at its value.
-- * It buys what it needs, up to its need, at its value (ledger.lua: its reference price
--   times its urgency over the money factor), and only with the emeralds it carries. A
--   villager in need is a standing order: this is how the player takes part in the
--   village's economy.
-- * Each trade teaches it the price, as a villager's does: what it sold goes through
--   asks.sold (its reference price learns, its ask rises), what it bought through
--   prices.learn. A player who buys up a good makes it dearer; one who floods a good
--   makes it cheaper. A villager never both needs and has spare of an item, so it offers
--   no spread on its own goods; the player's margin is between villagers.
--
-- A price is whole emeralds for a lot: one item, or as many as make up one emerald for
-- goods worth less (M.lot).
--
-- Reputation (gossip.lua) moves both sides by up to REP_MAX: REP_STEP a point, cheaper
-- to buy and better paid for one it thinks well of. Below REFUSE it will not trade with
-- the player at all. Every trade is "trading" gossip, as vanilla's are, and selling it
-- something it needs urgently (urgency at least URGENT, ledger.lua) is good gossip
-- besides ("minor_positive").
--
-- A need by purpose (goods.lua, ticket 15: food, fuel, logs, planks) takes any member.
-- The window says what it is short of ("food: 12 points") and lists as rows only the
-- members the player has with them, each at its own units' worth. Player trades convert
-- nothing, but for the alchemist's.
--
-- The alchemist (ticket 20d) sells its goods (alchemist.GOODS) at its asks, as anyone, and
-- lists what its conversions make (goods.lua: an ingot while it holds 9 nuggets, gold
-- only past its reserve, a pane a glass), a held one first; buying one takes the nuggets
-- from its pouch. It buys iron and gold, nuggets or ingots, at any time; flint while it
-- holds fewer than FLINT_KEEP; glass or panes while it holds GLASS_KEEP or fewer; each at
-- its value for one more, from its emeralds, kept as they are. Its other needs (stone,
-- logs) are bought as anyone's.
--
-- Donations (ticket 36; a Give field for every villager from ticket 21a until then). Only
-- the cleric's window has one, below the rows: what the player gives goes to the alms fund
-- as a villager's donation does (alms.lua's receive: the cleric keeps a tenth), and from
-- there to the village's poor. A donation of DONATION_MIN or more (a dinner at the
-- cleric's scale) is "donation" gossip (gossip.lua), at most once a day per player
-- (`_villages_donors`): it caps low and passes on little, so money alone buys a player a
-- few percent off at most, and a good name has to be earned by trade and errands. A
-- player may still give anyone emeralds by throwing them to it (possessions.pick_up) or
-- leaving them in its stash, for no gossip at all.
--
-- Rotten flesh and leather (ticket 37b). The cleric buys rotten flesh from players, from
-- anyone it will trade with, while it holds fewer than FLESH_KEEP, at a third of its
-- reference price for leather (`flesh_unit`), down to half that as its stock fills. It pays
-- from its flesh budget (alms.lua: the fund past its alms and the cleric's own emeralds past
-- its savings), not from its purse alone. It sells leather made three flesh to one, as the
-- alchemist sells ingots, to players here and to villagers in the market (goods.lua's
-- conversions), and never at a loss or break even: at least asks.PROFIT times what the
-- flesh cost it, and an emerald over (its cost book's price for flesh, cost_book.lua;
-- asks.reservation). No villager sells it flesh: a cleric does not want it as an input
-- (ledger.lua). What it pays a player is money out of the village, the tally's
-- `flesh_out`; what a player pays for premium goods comes back in, `premium_in`.
--
-- Diamonds (ticket 37d). A villager that buys diamonds from a player receives DIAMOND_BONUS
-- (2) for each one sold, the second out of nowhere, so a smith's diamond gear can sell at a
-- profit and still leave the player better off than mining and crafting. Its reference
-- price learns the price paid per diamond the player sold, so the bonus does not lower
-- what it pays next time.
--
-- The tavern keeper (ticket 33) sells the dishes in its pantry (tavern_pantry.lua: a
-- keeper.dishes item), each one dinner at its posted dinner price (dinner.lua), paid into
-- the pantry, its till, as a player's meal is (player_meals.lua). It keeps the last
-- evening's demand (dinner.demand) in meals, cookable potatoes counted, for the village's
-- dinner. It buys its inputs (ledger.lua's keeper role) as anyone, from its float. With
-- no pantry it sells what it holds, as anyone.
--
-- Premium trades (ticket 37, premium.lua): a villager with a premium line (the librarian's
-- enchanted books, the cleric's pearls, the farmer's golden carrots, the smiths' and the
-- armorer's enchanted gear) has a Special tab listing every premium good of its profession, each at
-- its price (P dinners at its reference price for a dinner, plus the base good, less the
-- reputation share), unlocked by its tier and the player's reputation band, or greyed with
-- why it is locked. Buying one takes its inputs from the villager (out of stock without
-- them) and makes the good at the sale: the other conversion in player trade. The emeralds go
-- to the villager, the base used is noted in its tally (economy_tally.lua), and it is
-- "trading" gossip. Premium goods never go through asks or prices: no villager trades them.
--
-- Vanilla's tables and their random rare goods are left out of player trade. `_trades` is left alone:
-- vanilla and this mod read it as the mark of a villager that keeps its job. The Builder
-- (its status window) and children keep their own right-click; with the economy off every
-- villager keeps vanilla's (the keeper its menu, keeper.lua).
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local goods = dofile(core.get_modpath("living_villages") .. "/goods.lua")
local dinner = dofile(core.get_modpath("living_villages") .. "/dinner.lua")
local alchemist = dofile(core.get_modpath("living_villages") .. "/alchemist.lua")
local cost_book = dofile(core.get_modpath("living_villages") .. "/cost_book.lua")
local premium = dofile(core.get_modpath("living_villages") .. "/premium.lua")
local tally = dofile(core.get_modpath("living_villages") .. "/economy_tally.lua")

local EMERALD = "mcl_core:emerald"
local FORMNAME = "living_villages:trade"
local REP_STEP = 1 / 400
local REP_MAX = 0.25
local REFUSE = -40
local URGENT = 2
local DONATION_MIN = ledger.DINNER
local NUGGET, INGOT = "mcl_core:iron_nugget", "mcl_core:iron_ingot"
local GOLD_NUGGET, GOLD = "mcl_core:gold_nugget", "mcl_core:gold_ingot"
local FLINT, GLASS, PANE = "mcl_core:flint", "mcl_core:glass", "xpanes:pane_natural_flat"
local FLESH, LEATHER = "mcl_mobitems:rotten_flesh", "mcl_mobitems:leather"
local DIAMOND = "mcl_core:diamond"
-- Diamonds a villager receives for each one a player sells it.
local DIAMOND_BONUS = 2
-- The most rotten flesh the cleric holds: 32 leather's worth.
local FLESH_KEEP = 96
-- What it buys from a player: iron and gold at any time, flint and glass up to a stock.
local ALCHEMY_BUYS = {NUGGET, INGOT, GOLD_NUGGET, GOLD, FLINT, GLASS, PANE}
local ROWS = 6
-- Premium rows on the Special tab, in two columns.
local PREMIUM_ROWS = 14
local REACH = 6
-- What a category's amount counts (goods.lua).
local UNITS = {food = "points", fuel = "seconds", log = "logs", planks = "planks"}

local M = {
	FORMNAME = FORMNAME, REP_STEP = REP_STEP,
	REP_MAX = REP_MAX, REFUSE = REFUSE, URGENT = URGENT, ROWS = ROWS, DONATION_MIN = DONATION_MIN,
	PREMIUM_ROWS = PREMIUM_ROWS, FLESH_KEEP = FLESH_KEEP, DIAMOND_BONUS = DIAMOND_BONUS,
}

-- What the cleric pays for one rotten flesh: a third of its reference price for leather
-- (`leather`), less as its stock (`held`) nears FLESH_KEEP, down to half that.
function M.flesh_unit(leather, held)
	local room = math.max(FLESH_KEEP - (held or 0), 0) / FLESH_KEEP
	return (leather or 0) / 3 * (0.5 + 0.5 * room)
end

-- Whether a donation of `amount` emeralds on `day` is good gossip: DONATION_MIN or more,
-- its dinners at `scale` (the cleric's dinner.scale, ticket 21e; 1 unset), and none yet
-- that day from the player (`last`, the day of its last one that counted).
function M.donation_counts(amount, scale, last, day)
	return amount >= DONATION_MIN * (scale or 1) and last ~= day
end

-- Whether the villager takes donations in its window: the cleric.
function M.takes_donations(villager)
	return villager._profession == "cleric" and not villager._villages_keeper and not villager._villages_alchemist
end

-- The emeralds a Donate field asks for: a whole number over 0, or nil.
function M.gift_amount(text)
	local amount = tonumber(text)
	if not amount or amount ~= amount or amount < 1 or amount == math.huge then return nil end
	return math.floor(amount)
end

-- Pure pricing.

-- Reputation's share off the player's price, from -REP_MAX to REP_MAX.
function M.rep_share(reputation)
	return math.max(-REP_MAX, math.min(REP_MAX, (reputation or 0) * REP_STEP))
end

-- The lot a price per item of `unit` emeralds is quoted for, and that lot's price,
-- rounded `up` (what the player pays) or down (what the villager pays). Nil for none.
function M.lot(unit, up)
	if not unit or unit <= 0 then return nil end
	local size = unit >= 1 and 1 or math.ceil(1 / unit)
	local price = unit * size
	price = up and math.ceil(price - 1e-9) or math.floor(price + 1e-9)
	if price < 1 then return nil end
	return size, price
end

-- The rows of the window, from a villager's view (ledger.assess), what it holds
-- ({item = count}), its emeralds, its reputation for the player, what the player
-- has ({item = count}, nil for no filter), whether it is the alchemist, and its asks
-- (`ask(item)`, asks.ask with its view; nil for none, when its value stands in):
-- {sells = {{item, lot, price, lots}}, buys = {{item, lot, price, lots, urgency}},
-- short = {{category, amount}}}. `lots` is how many lots it has to sell, or wants and
-- can pay for. A category's members are bought only as the player has them.
-- How many more of an item the alchemist takes from a player: none past its keep for
-- flint and glass (panes count as glass), any number of iron or gold.
local function alchemy_room(item, held)
	if item == FLINT then return math.max(alchemist.FLINT_KEEP - (held[FLINT] or 0), 0) end
	if item == GLASS or item == PANE then
		return math.max(alchemist.GLASS_KEEP + 1 - (held[GLASS] or 0) - (held[PANE] or 0), 0)
	end
	return math.huge
end

-- The price per item it sells at: its ask, or its value for an item with none.
local function asking(view, ask, item)
	return ask and ask(item) or view.value(item)
end

-- The alchemist's rows for its own goods (see the header): sells, buys. `held` is what
-- it holds, `share` reputation's share; a sell row made by conversion carries `held` (how
-- many it holds as they are) and `conversion` (goods.lua) to make the rest.
function M.alchemy_rows(view, held, emeralds, share, player_has, ask, converted)
	local sells, buys = {}, {}
	local made = {}
	for _, conversion in ipairs(goods.CONVERSIONS.alchemist) do
		local count = goods.yield(conversion, held[conversion.from] or 0)
		if count > 0 then made[conversion.to] = {count = count, conversion = conversion} end
	end
	for item in pairs(alchemist.GOODS) do
		local price = asking(view, ask, item)
		local own, from = held[item] or 0, made[item]
		-- Made by conversion: never dearer than its sources (asks.converted).
		if from and converted then price = converted(from.conversion) or price end
		local have = own + (from and from.count or 0)
		if price and have > 0 then
			local lot, lot_price = M.lot(price * (1 - share), true)
			if lot and have >= lot then
				sells[#sells + 1] = {item = item, lot = lot, price = lot_price, lots = math.floor(have / lot),
					held = own, conversion = from and from.conversion or nil}
			end
		end
	end
	for _, item in ipairs(ALCHEMY_BUYS) do
		local price = view.value(item)
		local lot, lot_price = M.lot((price or 0) * (1 + share), false)
		local room = alchemy_room(item, held)
		if lot and room >= lot and (not player_has or (player_has[item] or 0) > 0) then
			local lots = math.min(math.floor(room / lot), math.floor((emeralds or 0) / lot_price))
			if player_has then lots = math.min(lots, math.floor((player_has[item] or 0) / lot)) end
			buys[#buys + 1] = {item = item, lot = lot, price = lot_price, lots = lots, urgency = 1}
		end
	end
	return sells, buys
end

-- The cleric's rows for flesh and leather (see the header): sells, buys. `cleric` is
-- {budget = emeralds it can pay for flesh, unit = what it pays for one (M.flesh_unit),
-- floor = the least a leather made from its flesh sells for (asks.reservation), nil for none},
-- which holds after the reputation share too.
function M.cleric_rows(view, held, share, player_has, ask, converted, cleric)
	local sells, buys = {}, {}
	local conversion = goods.CONVERSIONS.cleric[1]
	local made = goods.yield(conversion, held[FLESH] or 0)
	local own = held[LEATHER] or 0
	local price = asking(view, ask, LEATHER)
	if made > 0 and converted then price = converted(conversion) or price end
	if price and own + made > 0 then
		local unit = price * (1 - share)
		if made > 0 and cleric.floor then unit = math.max(unit, cleric.floor) end
		local lot, lot_price = M.lot(unit, true)
		if lot and own + made >= lot then
			sells[#sells + 1] = {item = LEATHER, lot = lot, price = lot_price, lots = math.floor((own + made) / lot),
				held = own, conversion = made > 0 and conversion or nil}
		end
	end
	local room = FLESH_KEEP - (held[FLESH] or 0)
	local lot, lot_price = M.lot((cleric.unit or 0) * (1 + share), false)
	if lot and room >= lot and (not player_has or (player_has[FLESH] or 0) > 0) then
		local lots = math.min(math.floor(room / lot), math.floor((cleric.budget or 0) / lot_price))
		if player_has then lots = math.min(lots, math.floor((player_has[FLESH] or 0) / lot)) end
		buys[#buys + 1] = {item = FLESH, lot = lot, price = lot_price, lots = lots, urgency = 1, fund = true}
	end
	return sells, buys
end

-- The keeper's sell rows from its pantry (see the header): `tavern` is {dishes = {item =
-- count}, meals = meals it holds, reserve = meals it keeps, price = a dinner's}. Each
-- row sells as many of its dish as the pantry holds past the reserve, all told.
function M.keeper_rows(tavern, share)
	local sells = {}
	local spare = math.max((tavern.meals or 0) - (tavern.reserve or 0), 0)
	local lot, price = M.lot((tavern.price or 0) * (1 - share), true)
	if not lot then return sells end
	for item, count in pairs(tavern.dishes or {}) do
		local have = math.min(count, spare)
		if have >= lot then
			sells[#sells + 1] = {item = item, lot = lot, price = price, lots = math.floor(have / lot), pantry = true}
		end
	end
	return sells
end

-- `tavern` (may be nil) is a keeper's pantry, as M.keeper_rows takes it: its dishes are
-- what it sells, in place of its surplus. `cleric` (may be nil) is the cleric's flesh
-- budget and price, as M.cleric_rows takes it.
function M.rows(view, held, emeralds, reputation, player_has, is_alchemist, ask, converted, tavern, cleric)
	local share = M.rep_share(reputation)
	local sells, buys = {}, {}
	if is_alchemist then sells, buys = M.alchemy_rows(view, held, emeralds, share, player_has, ask, converted) end
	if tavern then sells = M.keeper_rows(tavern, share) end
	if cleric then sells, buys = M.cleric_rows(view, held, share, player_has, ask, converted, cleric) end
	for item, spare in pairs(not tavern and view.surplus or {}) do
		local have = math.min(spare, held[item] or 0)
		local unit = asking(view, ask, item)
		local own_row = (is_alchemist and alchemist.GOODS[item]) or (cleric and (item == FLESH or item == LEATHER))
		if item ~= EMERALD and have > 0 and unit and not own_row then
			local lot, price = M.lot(unit * (1 - share), true)
			if lot and have >= lot then
				sells[#sells + 1] = {item = item, lot = lot, price = price, lots = math.floor(have / lot)}
			end
		end
	end
	local group = view.group or {}
	for item, need in pairs(view.needs or {}) do
		local value = view.value(item)
		local shown = not group[item] or not player_has or (player_has[item] or 0) > 0
		if item ~= EMERALD and value and shown and not (is_alchemist and alchemist.GOODS[item])
			and not (cleric and item == FLESH) then
			local lot, price = M.lot(value * (1 + share), false)
			if lot and need >= lot then
				local lots = math.min(math.floor(need / lot), math.floor((emeralds or 0) / price))
				buys[#buys + 1] = {item = item, lot = lot, price = price, lots = lots,
					urgency = view.urgency and view.urgency(item) or 1}
			end
		end
	end
	-- Dearest lots first: what matters most to it.
	local function order(a, b)
		local wa, wb = a.price / a.lot, b.price / b.lot
		if wa ~= wb then return wa > wb end
		return a.item < b.item
	end
	table.sort(sells, order)
	table.sort(buys, order)
	local short = {}
	for category, state in pairs(view.categories or {}) do
		if (state.short or 0) > 0 then short[#short + 1] = {category = category, amount = state.short} end
	end
	table.sort(short, function(a, b) return a.category < b.category end)
	return {sells = sells, buys = buys, short = short}
end

-- The engine.

local function description(item)
	local def = core.registered_items and core.registered_items[item]
	local text = def and def.description or item
	if core.strip_colors then text = core.strip_colors(text) end
	return (text:gsub("\n.*", ""))
end

local function esc(text)
	return core.formspec_escape and core.formspec_escape(text) or text
end

local function reputation_word(r)
	if r >= 100 then return "a hero" end
	if r >= 30 then return "a friend" end
	if r > -15 then return "a stranger" end
	return "not to be trusted"
end

-- The keeper's pantry as the window trades with it, in the engine: `stock(keeper)` (nil
-- without a pantry), `take(keeper, item, count)` (how many it took) and `put(keeper,
-- item, count)` (whether it fitted).
function M.pantry_till()
	local modpath = core.get_modpath("living_villages")
	local keeper = dofile(modpath .. "/keeper.lua")
	local pantry = dofile(modpath .. "/tavern_pantry.lua")
	local supply = dofile(modpath .. "/keeper_supply.lua")
	local function chests(villager)
		local jukebox = keeper.claimed_jukebox(villager)
		return jukebox, jukebox and pantry.chests(jukebox)
	end
	return {
		stock = function(villager)
			local jukebox, found = chests(villager)
			if not found then return nil end
			local dishes = {}
			for _, item in ipairs(keeper.dishes()) do
				local count = pantry.count(found, item)
				if count > 0 then dishes[item] = count end
			end
			local day = core.get_day_count and core.get_day_count() or 0
			return {dishes = dishes, meals = supply.meals(found), reserve = dinner.demand(villager),
				price = dinner.posted(jukebox, villager, day)}
		end,
		take = function(villager, item, count)
			local _, found = chests(villager)
			local taken = 0
			while found and taken < count and pantry.take(found, item) do taken = taken + 1 end
			return taken
		end,
		put = function(villager, item, count)
			local _, found = chests(villager)
			return found ~= nil and pantry.put(found, item, count)
		end,
	}
end

function M.install(def, deps)
	local possessions, gossip, clock = deps.possessions, deps.gossip, deps.clock
	-- The live charts (charting.lua's install), for the cartographer's explorer maps (38c).
	local charting = deps.charting
	local asks = deps.asks or dofile(core.get_modpath("living_villages") .. "/asks.lua")
	local prices = deps.prices or dofile(core.get_modpath("living_villages") .. "/prices.lua")
	local tavern = deps.tavern or M.pantry_till()
	-- Loaded when first used: alms.lua brings in the cleric and market news.
	local alms_module = deps.alms
	local function alms()
		alms_module = alms_module or dofile(core.get_modpath("living_villages") .. "/alms.lua")
		return alms_module
	end
	local sessions = {}
	-- Makes `count` (1 unset) of a premium good (premium.offers' entry) as an item stack:
	-- its source item with its enchantments. Only consumables come more than one at a time.
	local make = deps.make or function(offer, count)
		local stack = ItemStack(offer.from)
		for enchant, level in pairs(offer.enchants or {}) do mcl_enchanting.enchant(stack, enchant, level) end
		stack:set_count(count or 1)
		return stack
	end

	local function reputation(villager, name)
		return gossip and gossip.reputation(villager, name) or 0
	end

	-- Its premium rows for the player (premium.rows), or nil with no premium line.
	local function premium_rows(villager, name)
		if not premium.line(villager) then return nil end
		local r = reputation(villager, name)
		local function value(item) return prices.price(villager._villages_prices, item) or 0 end
		local day = core.get_day_count and core.get_day_count() or 0
		local function charted(offer)
			local pos = villager.object and villager.object:get_pos()
			if not charting or not pos then return 0, "can't chart here" end
			return charting.available(pos, offer.chart, name)
		end
		return premium.rows(villager._profession, villager._max_trade_tier or 1, r, possessions.held(villager),
			dinner.reference(villager), value, M.rep_share(r), premium.sold_today(villager, name, day), charted)
	end

	-- What the player carries: {item = count}.
	local function player_has(name)
		local player = core.get_player_by_name and core.get_player_by_name(name)
		local inv = player and player:get_inventory()
		if not inv then return nil end
		local has = {}
		for _, stack in ipairs(inv:get_list("main") or {}) do
			if not stack:is_empty() then
				has[stack:get_name()] = (has[stack:get_name()] or 0) + stack:get_count()
			end
		end
		return has
	end

	local function current_rows(villager, name)
		-- What the player carries counts as about (ticket 39e): its mutton finds the butcher.
		local carried = player_has(name)
		local view = possessions.assess(villager, carried)
		local function ask(item) return asks.ask(villager, item, view) end
		local function converted(conversion) return asks.converted(villager, conversion, view) end
		local held = possessions.held(villager)
		local cleric
		if M.takes_donations(villager) then
			cleric = {budget = alms().flesh_budget(villager),
				unit = M.flesh_unit(prices.price(villager._villages_prices, LEATHER), held[FLESH]),
				floor = asks.reservation(villager, LEATHER, view)}
		end
		return M.rows(view, held, possessions.emeralds(villager), reputation(villager, name),
			carried, villager._villages_alchemist == true, ask, converted,
			villager._villages_keeper and tavern.stock(villager) or nil, cleric), view
	end

	local function form(villager, name)
		local session = sessions[name]
		local rows = current_rows(villager, name)
		session.rows = rows
		local special = premium_rows(villager, name)
		session.premium = special
		if not special then session.tab = nil end
		local r = reputation(villager, name)
		local parts = {
			"formspec_version[4]", "size[13,14.6]",
			string.format("label[0.5,0.6;%s]", esc(string.format("%s, %s. Purse: %d emeralds. You are %s to it (%d).",
				(villager.nametag and villager.nametag ~= "" and villager.nametag) or "Villager",
				villager._villages_alchemist and "alchemist" or villager._villages_keeper and "tavern keeper"
					or tostring(villager._profession or "villager"),
				possessions.emeralds(villager), reputation_word(r), r))),
		}
		if special then
			parts[#parts + 1] = string.format("tabheader[0,0;tab;Wares,Special;%d;false;true]",
				session.tab == "special" and 2 or 1)
		end
		if session.tab == "special" then
			-- Two columns of premium rows: what it makes, its price, and its stock or the lock.
			for i = 1, math.min(PREMIUM_ROWS, #special) do
				local entry = special[i]
				local x, y = i <= PREMIUM_ROWS / 2 and 0.5 or 6.8, 1.6 + ((i - 1) % (PREMIUM_ROWS / 2)) * 0.95
				local status = entry.locked or (entry.stock > 0 and string.format("can make %d", entry.stock))
					or (entry.left == 0 and "sold out to you today") or entry.reason or "out of stock"
				parts[#parts + 1] = string.format("item_image[%g,%g;0.8,0.8;%s]", x, y, entry.offer.makes)
				parts[#parts + 1] = string.format("label[%g,%g;%s]", x + 0.9, y + 0.2,
					esc(string.format("%s: %d em", entry.offer.label, entry.price)))
				parts[#parts + 1] = string.format("label[%g,%g;%s]", x + 0.9, y + 0.6,
					esc((entry.locked and "Locked, " or "") .. status))
				if not entry.locked and entry.stock > 0 then
					parts[#parts + 1] = string.format("button[%g,%g;0.9,0.7;premium_buy_%d;1]", x + 4.2, y + 0.05, i)
					if entry.left and entry.stock > 1 then
						parts[#parts + 1] = string.format("button[%g,%g;0.9,0.7;premium_all_%d;All]", x + 5.1, y + 0.05, i)
					end
				end
			end
			parts[#parts + 1] = "label[0.5,1.3;Made to order]"
			if #special == 0 then parts[#parts + 1] = "label[0.5,2;Nothing special.]" end
			parts[#parts + 1] = string.format("list[current_player;main;0.5,%g;9,4;]", 1.6 + ROWS * 0.95 + 0.6)
			return table.concat(parts)
		end
		parts[#parts + 1] = "label[0.5,1.3;It sells]"
		parts[#parts + 1] = "label[6.8,1.3;It buys]"
		local function row(x, y, entry, kind, index)
			local count = entry.lot > 1 and (" x" .. entry.lot) or ""
			parts[#parts + 1] = string.format("item_image[%g,%g;0.8,0.8;%s]", x, y, entry.item)
			parts[#parts + 1] = string.format("label[%g,%g;%s]", x + 0.9, y + 0.2,
				esc(string.format("%s%s: %d em", description(entry.item), count, entry.price)))
			parts[#parts + 1] = string.format("label[%g,%g;%s]", x + 0.9, y + 0.6,
				esc(kind == "sell" and string.format("has %d", entry.lots * entry.lot)
					or entry.lots > 0 and string.format("wants %d", entry.lots * entry.lot)
					or "can't pay for one"))
			if entry.lots > 0 then
				parts[#parts + 1] = string.format("button[%g,%g;0.9,0.7;%s_one_%d;1]", x + 4.2, y + 0.05, kind, index)
				parts[#parts + 1] = string.format("button[%g,%g;0.9,0.7;%s_all_%d;All]", x + 5.1, y + 0.05, kind, index)
			end
		end
		for i = 1, math.min(ROWS, #rows.sells) do row(0.5, 1.6 + (i - 1) * 0.95, rows.sells[i], "sell", i) end
		for i = 1, math.min(ROWS, #rows.buys) do row(6.8, 1.6 + (i - 1) * 0.95, rows.buys[i], "buy", i) end
		if #rows.sells == 0 then parts[#parts + 1] = "label[0.5,2;Nothing to spare.]" end
		if #rows.buys == 0 then parts[#parts + 1] = "label[6.8,2;Needs nothing.]" end
		local y = 1.6 + ROWS * 0.95 + 0.2
		if #rows.short > 0 then
			local list = {}
			for i, entry in ipairs(rows.short) do
				list[i] = string.format("%s %d %s", entry.category, math.ceil(entry.amount), UNITS[entry.category] or "")
			end
			parts[#parts + 1] = string.format("label[6.8,%g;%s]", y - 0.25,
				esc("Short of: " .. table.concat(list, ", ") .. " (any kind)"))
		end
		parts[#parts + 1] = string.format("list[current_player;main;0.5,%g;9,4;]", y + 0.4)
		if M.takes_donations(villager) then
			parts[#parts + 1] = string.format("field[0.5,%g;2,0.7;give_amount;;]", y + 5.6)
			parts[#parts + 1] = string.format("button[2.6,%g;4,0.7;give;Donate to the alms fund]", y + 5.6)
		end
		return table.concat(parts)
	end

	local function show(name)
		local session = sessions[name]
		if not session then return end
		core.show_formspec(name, FORMNAME, form(session.villager, name))
	end

	local function close(name)
		local session = sessions[name]
		if not session then return end
		local trading = session.villager._trading_players
		if trading then trading[name] = nil end
		sessions[name] = nil
	end

	local function log(text, ...)
		core.log("action", "[living_villages] trade window: " .. string.format(text, ...))
	end

	-- The player buys dishes from the keeper's pantry, paying into it.
	local function player_buys_dishes(player, villager, entry, count, pay)
		local inv = player:get_inventory()
		local name = player:get_player_name()
		local taken = tavern.take(villager, entry.item, count)
		if taken < count then
			if taken > 0 then tavern.put(villager, entry.item, taken) end
			return
		end
		inv:remove_item("main", EMERALD .. " " .. pay)
		if not tavern.put(villager, EMERALD, pay) then possessions.add(villager, EMERALD, pay) end
		inv:add_item("main", entry.item .. " " .. count)
		if gossip then gossip.add(villager, name, "trading") end
		log("%s bought %d %s from the keeper %s's pantry for %d emerald(s)", name, count, entry.item,
			tostring(villager._id):sub(1, 6), pay)
	end

	-- The player buys `lots` lots of a row the villager sells.
	local function player_buys(player, villager, entry, lots)
		local inv = player:get_inventory()
		local name = player:get_player_name()
		lots = math.min(lots, entry.lots)
		local count, pay = entry.lot * lots, entry.price * lots
		if lots < 1 then return end
		if not inv:contains_item("main", EMERALD .. " " .. pay) then
			core.chat_send_player(name, "You have too few emeralds for that.")
			return
		end
		if not inv:room_for_item("main", entry.item .. " " .. count) then
			core.chat_send_player(name, "You have no room for that.")
			return
		end
		if entry.pantry then return player_buys_dishes(player, villager, entry, count, pay) end
		-- The alchemist's own first, then made from its sources (whole batches, past any
		-- reserve), as a sale to a villager would be.
		local from, from_count = nil, 0
		local own = entry.conversion and math.min(count, entry.held or 0) or count
		if own < count then
			from = entry.conversion.from
			local made
			from_count, made = goods.sources_for(entry.conversion, count - own)
			if made ~= count - own
				or possessions.count(villager, from) - (entry.conversion.reserve or 0) < from_count then
				return
			end
		end
		local taken = possessions.take_held(villager, entry.item, own)
		if taken < own then
			if taken > 0 then possessions.add(villager, entry.item, taken) end
			return
		end
		if from then
			local used = possessions.take_held(villager, from, from_count)
			if used < from_count then
				if used > 0 then possessions.add(villager, from, used) end
				if taken > 0 then possessions.add(villager, entry.item, taken) end
				return
			end
		end
		inv:remove_item("main", EMERALD .. " " .. pay)
		possessions.add(villager, EMERALD, pay)
		inv:add_item("main", entry.item .. " " .. count)
		-- A sale like any (ticket 21c): its reference price learns the price, its ask rises.
		local day = core.get_day_count and core.get_day_count() or 0
		asks.sold(villager, entry.item, day, count, pay / count)
		-- What it made by conversion sold its sources too (asks.converted prices from them).
		if from then asks.sold(villager, from, day, from_count, pay * (count - own) / count / from_count) end
		if gossip then gossip.add(villager, name, "trading") end
		log("%s bought %d %s from villager %s for %d emerald(s)%s", name, count, entry.item,
			tostring(villager._id):sub(1, 6), pay, from and string.format(" (from %d %s)", from_count, from) or "")
	end

	-- The player sells `lots` lots of a row the villager buys.
	local function player_sells(player, villager, entry, lots)
		local inv = player:get_inventory()
		local name = player:get_player_name()
		lots = math.min(lots, entry.lots)
		local count, pay = entry.lot * lots, entry.price * lots
		if lots < 1 then return end
		if entry.fund then
			if alms().flesh_budget(villager) < pay then return end
		elseif possessions.emeralds(villager) < pay then
			return
		end
		local stack = inv:remove_item("main", entry.item .. " " .. count)
		if stack:get_count() < count then
			inv:add_item("main", stack)
			core.chat_send_player(name, "You have too few of those.")
			return
		end
		if entry.fund then
			-- The cleric's flesh (ticket 37b): from its flesh budget, money out of the village.
			-- Its cost book notes it below, and its leather never sells under that.
			alms().pay_flesh(villager, pay)
			tally.money(villager, "flesh_out", pay)
		else
			possessions.take(villager, EMERALD, pay)
		end
		local received = entry.item == DIAMOND and count * DIAMOND_BONUS or count
		possessions.add(villager, entry.item, received)
		-- A purchase like any (ticket 21c): its reference price learns the price, and its cost
		-- book (cost_book.lua, ticket 43a: a cook's inputs, the alchemist's, the cleric's flesh).
		prices.learn(villager, entry.item, pay / count)
		cost_book.note(villager, entry.item, received, pay, possessions.held(villager))
		local left = inv:add_item("main", EMERALD .. " " .. pay)
		if not left:is_empty() and core.add_item then core.add_item(player:get_pos(), left) end
		if gossip then
			gossip.add(villager, name, "trading")
			if entry.urgency >= URGENT then gossip.add(villager, name, "minor_positive") end
		end
		log("%s sold %d %s to villager %s for %d emerald(s)%s%s", name, count, entry.item,
			tostring(villager._id):sub(1, 6), pay, entry.urgency >= URGENT and ", an urgent need" or "",
			received > count and string.format(", received %d", received) or "")
	end

	-- The player buys a premium good (the Special tab's `entry`, premium.rows): its base good
	-- is taken from the villager and the good made at the sale.
	-- `all`: as many as its stock, today's cap and the player's emeralds allow (consumables).
	local function player_buys_premium(player, villager, entry, all)
		local inv = player:get_inventory()
		local name = player:get_player_name()
		local offer = entry.offer
		if entry.locked then return end
		if entry.stock < 1 then
			core.chat_send_player(name, entry.left == 0 and "It has made you all it will today."
				or "It has nothing to make that from.")
			return
		end
		local count = 1
		if all and entry.left then
			count = entry.stock
			while count > 1 and not inv:contains_item("main", EMERALD .. " " .. entry.price * count) do count = count - 1 end
		end
		local pay = entry.price * count
		if not inv:contains_item("main", EMERALD .. " " .. pay) then
			core.chat_send_player(name, "You have too few emeralds for that.")
			return
		end
		-- An explorer map (38c) is the nearest charted site's the player hasn't bought.
		local stack, note_map
		if offer.chart then
			local pos = villager.object and villager.object:get_pos()
			if charting and pos then stack, note_map = charting.take(pos, offer.chart, name) end
			if not stack then
				core.chat_send_player(name, "It has no map to sell you.")
				return
			end
		else
			stack = make(offer, count)
		end
		if not inv:room_for_item("main", stack) then
			core.chat_send_player(name, "You have no room for that.")
			return
		end
		-- Every input (ticket 37d: a diamond pick's diamonds and sticks), or none of them.
		local used = {}
		for _, input in ipairs(offer.inputs) do
			local need = input.count * count
			local got = possessions.take_held(villager, input.item, need)
			if got > 0 then used[input.item] = (used[input.item] or 0) + got end
			if got < need then
				for item, n in pairs(used) do possessions.add(villager, item, n) end
				return
			end
		end
		inv:remove_item("main", EMERALD .. " " .. pay)
		possessions.add(villager, EMERALD, pay)
		inv:add_item("main", stack)
		local day = core.get_day_count and core.get_day_count() or 0
		premium.note_sold(villager, name, offer.cap or offer.id, count, day)
		if note_map then note_map() end
		tally.note(villager, nil, used, day)
		tally.money(villager, "premium_in", pay, day)
		if gossip then gossip.add(villager, name, "trading") end
		local from = {}
		for _, input in ipairs(offer.inputs) do from[#from + 1] = (input.count * count) .. " " .. input.item end
		log("%s bought premium %d %s (%s) from villager %s for %d emerald(s) (from %s)", name, count, offer.id,
			offer.label, tostring(villager._id):sub(1, 6), pay, table.concat(from, ", "))
	end

	-- The player donates `amount` emeralds to the cleric's alms fund.
	local function player_donates(player, villager, amount)
		local inv = player:get_inventory()
		local name = player:get_player_name()
		if not amount then
			core.chat_send_player(name, "Donate how many emeralds?")
			return
		end
		local taken = inv:remove_item("main", EMERALD .. " " .. amount)
		if taken:get_count() < amount then
			inv:add_item("main", taken)
			core.chat_send_player(name, "You have too few emeralds for that.")
			return
		end
		alms().receive(villager, amount)
		local day = core.get_day_count and core.get_day_count() or 0
		local donors = villager._villages_donors or {}
		for donor, last in pairs(donors) do
			if last ~= day then donors[donor] = nil end
		end
		local counts = M.donation_counts(amount, dinner.scale(villager), donors[name], day)
		if counts then
			donors[name] = day
			if gossip then gossip.add(villager, name, "donation") end
		end
		villager._villages_donors = next(donors) and donors or nil
		core.chat_send_player(name, "The cleric thanks you for your gift to the poor.")
		log("%s donated %d emerald(s) to cleric %s%s", name, amount, tostring(villager._id):sub(1, 6),
			counts and "" or ", no gossip")
	end

	local original_rightclick = def.on_rightclick
	def.on_rightclick = function(self, clicker)
		local name = clicker and clicker.is_player and clicker:is_player() and clicker:get_player_name()
		if not name or not clock.enabled() or self.child or self._villages_builder
			or not self._id then
			return original_rightclick(self, clicker)
		end
		local r = reputation(self, name)
		if r <= REFUSE then
			core.chat_send_player(name, "This villager will not trade with you.")
			return
		end
		self._trading_players = self._trading_players or {}
		self._trading_players[name] = true
		sessions[name] = {villager = self}
		if self.state == "gowp" then self.state = "stand" end
		local pos, at = self.object:get_pos(), clicker:get_pos()
		if pos and at and self.object.set_yaw then
			self.object:set_yaw(core.dir_to_yaw(vector.direction(pos, at)))
		end
		show(name)
	end

	if not core.register_on_player_receive_fields then return end
	core.register_on_player_receive_fields(function(player, formname, fields)
		if formname ~= FORMNAME then return false end
		local name = player:get_player_name()
		local session = sessions[name]
		if not session then return true end
		if fields.quit then
			close(name)
			return true
		end
		local villager = session.villager
		local pos, at = villager.object and villager.object:get_pos(), player:get_pos()
		if not pos or not at or vector.distance(pos, at) > REACH then
			close(name)
			core.close_formspec(name, FORMNAME)
			return true
		end
		if fields.tab then
			session.tab = fields.tab == "2" and "special" or nil
			show(name)
			return true
		end
		for field in pairs(fields) do
			local how, index = field:match("^premium_(%a+)_(%d+)$")
			if index and (how == "buy" or how == "all") then
				-- The rows as they stand now, so a stale window cannot trade at old prices.
				local rows = premium_rows(villager, name)
				local shown = session.premium and session.premium[tonumber(index)]
				local entry = rows and rows[tonumber(index)]
				if entry and shown and entry.offer.id == shown.offer.id then
					player_buys_premium(player, villager, entry, how == "all")
				end
				show(name)
				return true
			end
		end
		if (fields.give or fields.key_enter_field == "give_amount") and M.takes_donations(villager) then
			player_donates(player, villager, M.gift_amount(fields.give_amount))
			show(name)
			return true
		end
		for field in pairs(fields) do
			local kind, amount, index = field:match("^(%a+)_(%a+)_(%d+)$")
			if kind == "sell" or kind == "buy" then
				-- The rows as they stand now, so a stale window cannot trade at old prices.
				local rows = current_rows(villager, name)
				local shown = session.rows and session.rows[kind .. "s"][tonumber(index)]
				local entry = rows[kind .. "s"][tonumber(index)]
				if entry and shown and entry.item == shown.item then
					local lots = amount == "all" and entry.lots or 1
					if kind == "sell" then player_buys(player, villager, entry, lots)
					else player_sells(player, villager, entry, lots) end
				end
				show(name)
				break
			end
		end
		return true
	end)

	if core.register_on_leaveplayer then
		core.register_on_leaveplayer(function(player) close(player:get_player_name()) end)
	end
end

return M
