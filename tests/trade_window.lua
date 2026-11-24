-- Run with: lua tests/trade_window.lua
local shown, chats, logs, handlers = {}, {}, {}, {}
vector = {
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	direction = function() return {x = 1, y = 0, z = 0} end,
}
minetest = {
	get_modpath = function() return "." end,
	log = function(_, line) logs[#logs + 1] = line end,
	show_formspec = function(name, formname, spec) shown[#shown + 1] = {name = name, formname = formname, spec = spec} end,
	close_formspec = function() end,
	chat_send_player = function(name, text) chats[#chats + 1] = text end,
	register_on_player_receive_fields = function(f) handlers.fields = f end,
	register_on_leaveplayer = function(f) handlers.leave = f end,
	formspec_escape = function(text) return text end,
	dir_to_yaw = function() return 0 end,
	registered_items = {},
}
local window = dofile("trade_window.lua")
local premium = dofile("premium.lua")
local EMERALD, BREAD, FISH, IRON = "mcl_core:emerald", "mcl_farming:bread", "mcl_fishing:salmon_raw", "mcl_core:iron_ingot"
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- Reputation's share, bounded.
assert(window.rep_share(0) == 0 and near(window.rep_share(40), 0.1))
assert(window.rep_share(1000) == window.REP_MAX and window.rep_share(-1000) == -window.REP_MAX)
-- Lots: whole emeralds; goods worth less than one come in lots that make one.
local size, price = window.lot(10.2, true)
assert(size == 1 and price == 11)
size, price = window.lot(10.8, false)
assert(size == 1 and price == 10)
size, price = window.lot(0.3, true)
assert(size == 4 and price == 2, size .. " " .. price) -- 4 * 0.3 = 1.2, rounded up
size, price = window.lot(0.3, false)
assert(size == 4 and price == 1)
assert(window.lot(0, true) == nil)

-- Rows (ticket 21c): spare goods it holds at its ask, its value standing in for an item
-- with none; needs at its value, as many lots as it needs and can pay for.
local values = {[BREAD] = 10, [FISH] = 2, [IRON] = 40}
local view = {
	surplus = {[BREAD] = 6, [FISH] = 10}, needs = {[IRON] = 5},
	value = function(item) return values[item] end,
	urgency = function(item) return item == IRON and 3 or 1 end,
}
local rows = window.rows(view, {[BREAD] = 6, [FISH] = 3}, 100, 0)
assert(#rows.sells == 2 and rows.sells[1].item == BREAD and rows.sells[1].price == 10 and rows.sells[1].lots == 6)
assert(rows.sells[2].item == FISH and rows.sells[2].lots == 3, "only what it holds")
assert(#rows.buys == 1 and rows.buys[1].price == 40 and rows.buys[1].lots == 2, "100 emeralds pay for 2 at 40")
assert(rows.buys[1].urgency == 3)
-- With its asks, it sells at them: what a villager would pay it.
local asked = window.rows(view, {[BREAD] = 6}, 100, 0, nil, false, function(item) return item == BREAD and 7.2 or nil end)
assert(asked.sells[1].item == BREAD and asked.sells[1].price == 8, "7.2 rounded up")
-- A friend buys cheaper and is paid more; one it distrusts the other way.
local friend = window.rows(view, {[BREAD] = 6}, 1000, 100)
assert(friend.sells[1].price < 10 and friend.buys[1].price > 40 and friend.buys[1].lots == 5)
local foe = window.rows(view, {[BREAD] = 6}, 1000, -30)
assert(foe.sells[1].price > 10 and foe.buys[1].price < 40)
-- With no emeralds it still shows the need, with no lots.
assert(window.rows(view, {}, 0, 0).buys[1].lots == 0)

-- A category's need (ticket 15): a member is a row only if the player has some, and
-- what it is short of is listed once.
do
	local APPLE, CARROT = "mcl_core:apple", "mcl_farming:carrot_item"
	local hungry = {
		surplus = {}, needs = {[APPLE] = 3, [CARROT] = 4, [IRON] = 1},
		group = {[APPLE] = "food", [CARROT] = "food"},
		categories = {food = {target = 12, held = 0, short = 12}},
		value = function(item) return ({[APPLE] = 4, [CARROT] = 3, [IRON] = 40})[item] end,
	}
	local r = window.rows(hungry, {}, 100, 0, {[CARROT] = 5})
	local items = {}
	for _, entry in ipairs(r.buys) do items[entry.item] = true end
	assert(items[CARROT] and items[IRON] and not items[APPLE], "only the member the player has")
	assert(#r.short == 1 and r.short[1].category == "food" and r.short[1].amount == 12)
	assert(#window.rows(hungry, {}, 100, 0).buys == 3, "no filter without the player's inventory")
end

-- The engine: a right-click opens the window, the buttons trade real goods.
local belongings = {[BREAD] = 6, [EMERALD] = 100}
local possessions = {
	assess = function() return view end,
	held = function(self) return self._villages_belongings end,
	emeralds = function(self) return self._villages_belongings[EMERALD] or 0 end,
	add = function(self, item, n) self._villages_belongings[item] = (self._villages_belongings[item] or 0) + n end,
	take = function(self, item, n)
		local have = self._villages_belongings[item] or 0
		local taken = math.min(have, n)
		self._villages_belongings[item] = have - taken
		return taken
	end,
}
possessions.take_held = possessions.take
possessions.count = function(self, item) return self._villages_belongings[item] or 0 end
values[BREAD] = 20
view.surplus = {[BREAD] = 6}
local gossiped = {}
local rep = 0
local gossip = {reputation = function() return rep end, add = function(_, name, kind) gossiped[#gossiped + 1] = kind end}
local enabled = true
local def = {on_rightclick = function(self) self.vanilla = true end}
-- A keeper's pantry (ticket 33), stubbed: dishes, meals counted, the reserve and its price.
local larder = {[BREAD] = 0}
local till = {dishes = larder, meals = 0, reserve = 0, price = 20, emeralds = 0}
local tavern = {
	stock = function() return till end,
	take = function(_, item, count)
		local taken = math.min(larder[item] or 0, count)
		larder[item] = (larder[item] or 0) - taken
		till.meals = till.meals - taken
		return taken
	end,
	put = function(_, item, count)
		if item == EMERALD then till.emeralds = till.emeralds + count else larder[item] = (larder[item] or 0) + count end
		return true
	end,
}
local fund = {}
-- The cleric's flesh budget (ticket 37b), stubbed: `_budget` emeralds, paid from first.
local flesh_paid = {}
local alms = {
	receive = function(priest, gift) fund[#fund + 1] = {priest = priest, gift = gift} end,
	flesh_budget = function(priest) return priest._budget or 0 end,
	pay_flesh = function(priest, amount)
		if (priest._budget or 0) < amount then return false end
		priest._budget = priest._budget - amount
		flesh_paid[#flesh_paid + 1] = amount
		return true
	end,
}
-- Premium goods (ticket 37) made as a stub stack: the offer's id.
local made = {}
local function make(offer, count)
	made[#made + 1] = offer
	return {item = offer.id, get_count = function() return count or 1 end}
end
-- The live charts (ticket 38c), stubbed: drawn sites by kind, and what each player bought.
local chart_sites = {ocean_temple = {}, woodland_cabin = {}}
local chart_bought = {}
local function unbought(kind, name)
	local list = {}
	for _, site in ipairs(chart_sites[kind]) do
		if not (chart_bought[name] and chart_bought[name][site]) then list[#list + 1] = site end
	end
	return list
end
local charting = {
	available = function(_, kind, name)
		local n = #unbought(kind, name)
		if n > 0 then return n end
		return 0, kind == "ocean_temple" and "still charting the sea" or "still charting the woods"
	end,
	take = function(_, kind, name)
		local site = unbought(kind, name)[1]
		if not site then return nil end
		return {item = "map:" .. site, get_count = function() return 1 end}, function()
			chart_bought[name] = chart_bought[name] or {}
			chart_bought[name][site] = true
		end
	end,
}
window.install(def, {possessions = possessions, gossip = gossip, tavern = tavern, alms = alms, make = make,
	clock = {enabled = function() return enabled end}, charting = charting})

local function inventory(contents)
	local inv = {contents = contents}
	local function parse(text) local item, n = text:match("^(%S+) (%d+)$"); return item, tonumber(n) end
	function inv:contains_item(_, text) local item, n = parse(text); return (self.contents[item] or 0) >= n end
	function inv:room_for_item() return true end
	function inv:remove_item(_, text)
		local item, n = parse(text)
		local taken = math.min(self.contents[item] or 0, n)
		self.contents[item] = (self.contents[item] or 0) - taken
		return {get_count = function() return taken end, item = item}
	end
	function inv:add_item(_, stack)
		if type(stack) == "string" then
			local item, n = parse(stack)
			self.contents[item] = (self.contents[item] or 0) + n
		else
			self.contents[stack.item] = (self.contents[stack.item] or 0) + stack:get_count()
		end
		return {is_empty = function() return true end}
	end
	return inv
end
local player_inv = inventory({[EMERALD] = 200, [IRON] = 10})
local player = {
	is_player = function() return true end, get_player_name = function() return "rskj" end,
	get_pos = function() return {x = 1, y = 0, z = 0} end, get_inventory = function() return player_inv end,
}
local villager = {_id = "vill-1", _profession = "farmer", _villages_belongings = belongings,
	object = {get_pos = function() return {x = 0, y = 0, z = 0} end, set_yaw = function() end}}

def.on_rightclick(villager, player)
assert(not villager.vanilla and shown[#shown].formname == window.FORMNAME, "the mod's window, not vanilla's")
assert(villager._trading_players.rskj, "it stands still while trading")
assert(shown[#shown].spec:find("Bread", 1, true) or shown[#shown].spec:find(BREAD, 1, true))
-- Buy one bread at its ask: its reference price (its base, 10.7), rounded up. Not its value
-- of 20: bread is a farmer's stock in trade, priced by supply (ticket 40a).
local ledger = dofile("ledger.lua")
local prices = dofile("prices.lua")
local asks = dofile("asks.lua")
handlers.fields(player, window.FORMNAME, {sell_one_1 = true})
assert(player_inv.contents[BREAD] == 1 and player_inv.contents[EMERALD] == 189 and belongings[EMERALD] == 111)
assert(belongings[BREAD] == 5 and gossiped[#gossiped] == "trading")
-- A sale like any: its reference price learnt the price, its own ask, so stood, and its ask rose.
assert(near(prices.factor(villager._villages_prices, BREAD), 1))
assert(asks.factor(villager, BREAD) > 1)
-- Sell it iron: urgent, so good gossip too; 111 emeralds pay for 2 at its value of 40.
handlers.fields(player, window.FORMNAME, {buy_all_1 = true})
assert(player_inv.contents[IRON] == 8 and belongings[IRON] == 2 and belongings[EMERALD] == 31)
assert(gossiped[#gossiped] == "minor_positive")
-- A purchase like any: its reference price for iron learnt the 40 it paid.
assert(near(prices.factor(villager._villages_prices, IRON), (40 / ledger.price(IRON)) ^ prices.LEARN_TRADE))
-- No Give field (ticket 36): a farmer takes no donations.
assert(not shown[#shown].spec:find("give_amount", 1, true))
player_inv.contents[EMERALD] = 180
handlers.fields(player, window.FORMNAME, {give = true, give_amount = "50"})
assert(player_inv.contents[EMERALD] == 180 and #fund == 0, "nothing given")
-- Closing lets it go.
handlers.fields(player, window.FORMNAME, {quit = "true"})
assert(not villager._trading_players.rskj)
-- One it distrusts will not trade; children and the economy off keep vanilla's.
rep = window.REFUSE
def.on_rightclick(villager, player)
assert(chats[#chats]:find("will not trade") and not villager._trading_players.rskj)
rep = 0
-- The keeper (ticket 33): the mod's window, selling its pantry's dishes at the dinner
-- price into the pantry, past the meals it keeps for dinner; buying its inputs as anyone.
do
	-- Pure: each dish at the price, as many as the pantry holds past the reserve, all told.
	local r = window.rows(view, {[BREAD] = 6}, 100, 0, nil, false, nil, nil,
		{dishes = {[BREAD] = 10, [FISH] = 3}, meals = 15, reserve = 11, price = 20})
	local bread, fish = r.sells[1], r.sells[2]
	assert(#r.sells == 2 and bread.pantry and bread.price == 20 and bread.lots == 4 and fish.lots == 3,
		"its pantry, not its surplus")
	assert(#r.buys == 1 and r.buys[1].item == IRON, "its needs as anyone's")
	assert(#window.rows(view, {}, 100, 0, nil, false, nil, nil,
		{dishes = {[BREAD] = 10}, meals = 10, reserve = 12, price = 20}).sells == 0, "all kept for dinner")
	-- A friend pays less for a dinner.
	assert(window.rows(view, {}, 100, 40, nil, false, nil, nil,
		{dishes = {[BREAD] = 10}, meals = 10, reserve = 0, price = 20}).sells[1].price == 18)

	local purse = {[EMERALD] = 50}
	local keeper = {_id = "keep-1", _profession = "butcher", _villages_keeper = true, _villages_belongings = purse,
		object = villager.object}
	larder[BREAD], till.meals, till.reserve = 8, 10, 4
	view = {surplus = {[BREAD] = 6}, needs = {}, value = function(item) return values[item] end}
	player_inv.contents[EMERALD], player_inv.contents[BREAD] = 200, 0
	def.on_rightclick(keeper, player)
	assert(not keeper.vanilla and shown[#shown].formname == window.FORMNAME, "the mod's window, not vanilla's")
	assert(shown[#shown].spec:find("tavern keeper", 1, true), "named for its role, not the butcher")
	handlers.fields(player, window.FORMNAME, {sell_all_1 = true})
	assert(player_inv.contents[BREAD] == 6 and player_inv.contents[EMERALD] == 200 - 6 * 20, "10 meals less 4 kept")
	assert(larder[BREAD] == 2 and till.emeralds == 120 and purse[EMERALD] == 50, "paid into the pantry")
	assert(logs[#logs]:find("pantry", 1, true))
	handlers.fields(player, window.FORMNAME, {quit = "true"})
	view = {surplus = {[BREAD] = 6}, needs = {[IRON] = 5}, value = function(item) return values[item] end,
		urgency = function(item) return item == IRON and 3 or 1 end}
end
-- The cleric (ticket 36): a donation goes to the alms fund, and a dinner or more is
-- donation gossip, once a day.
do
	local day = 7
	minetest.get_day_count = function() return day end
	local cleric = {_id = "cler-1", _profession = "cleric", _villages_belongings = {[EMERALD] = 0}, object = villager.object}
	player_inv.contents[EMERALD] = 200
	def.on_rightclick(cleric, player)
	assert(shown[#shown].spec:find("give_amount", 1, true) and shown[#shown].spec:find("alms fund", 1, true))
	local before = #gossiped
	handlers.fields(player, window.FORMNAME, {give = true, give_amount = "40"})
	assert(player_inv.contents[EMERALD] == 160 and fund[1].priest == cleric and fund[1].gift == 40)
	assert(#gossiped == before + 1 and gossiped[#gossiped] == "donation" and cleric._villages_donors.rskj == 7)
	handlers.fields(player, window.FORMNAME, {give = true, give_amount = "40"})
	assert(player_inv.contents[EMERALD] == 120 and #fund == 2 and #gossiped == before + 1, "once a day")
	day = 8
	handlers.fields(player, window.FORMNAME, {give = true, give_amount = "1"})
	assert(#fund == 3 and #gossiped == before + 1 and not cleric._villages_donors, "too small, and yesterday's forgotten")
	handlers.fields(player, window.FORMNAME, {give = true, give_amount = "500"})
	assert(#fund == 3 and chats[#chats]:find("too few"), "no more than it has")
	handlers.fields(player, window.FORMNAME, {quit = "true"})
	minetest.get_day_count = nil
end
enabled = false
local other = {_id = "o", object = villager.object}
def.on_rightclick(other, player)
assert(other.vanilla)
-- The alchemist (ticket 20d): its goods at its asks and its value (ticket 21c, no margins
-- of its own), what its conversions make listed beside what it holds, and only the iron,
-- gold, flint and glass it takes in.
enabled = true
local NUGGET, GOLD_NUGGET, GOLD = "mcl_core:iron_nugget", "mcl_core:gold_nugget", "mcl_core:gold_ingot"
local FLINT, GLASS, PANE = "mcl_core:flint", "mcl_core:glass", "xpanes:pane_natural_flat"
local function row(list, item)
	for i, entry in ipairs(list) do if entry.item == item then return entry, i end end
end
local empty = {surplus = {}, needs = {}, value = function(item) return ledger.price(item) end}
do
	-- Under the gold reserve (24 since ticket 30) plus a gold nugget's 18.
	local held = {[NUGGET] = 41, [GLASS] = 3}
	local r = window.rows(empty, held, 1000, 0, nil, true)
	local ingot = row(r.sells, IRON)
	assert(ingot and ingot.lots == 4 and ingot.held == 0 and ingot.conversion.from == NUGGET, "four ingots from 41")
	assert(ingot.price == math.ceil(ledger.price(IRON)), ingot.price)
	local cheap = window.rows(empty, held, 1000, 0, nil, true, function(item) return item == IRON and 50 or nil end)
	assert(row(cheap.sells, IRON).price == 50, "at its ask")
	-- Made from nuggets, never dearer than nine of them (asks.converted).
	local by_nuggets = window.rows(empty, held, 1000, 0, nil, true, nil,
		function(conversion) return conversion.from == NUGGET and 9 * 3 or nil end)
	assert(row(by_nuggets.sells, IRON).price == 27, row(by_nuggets.sells, IRON).price)
	assert(row(r.sells, NUGGET).lots == 41 and row(r.sells, PANE).lots == 3 and row(r.sells, GLASS).lots == 3)
	assert(not row(r.sells, GOLD_NUGGET), "no gold under the reserve")
	assert(row(window.rows(empty, {[NUGGET] = 42}, 0, 0, nil, true).sells, GOLD_NUGGET).lots == 1, "past it")
	local bid = row(r.buys, IRON)
	assert(bid and bid.price == math.floor(ledger.price(IRON)) and bid.lots == math.floor(1000 / bid.price))
	local gold = row(r.buys, GOLD)
	assert(gold and gold.lots == math.floor(1000 / gold.price), "the gold ingots 1000 pays for")
	assert(row(r.buys, FLINT).lots == 15 and row(r.buys, GLASS).lots == 10, "what 1000 pays for; 13 glass less 3")
	-- At 32 flint and 13 glass it takes no more; panes count as glass.
	r = window.rows(empty, {[FLINT] = 32, [GLASS] = 10, [PANE] = 3}, 1000, 0, nil, true)
	assert(not row(r.buys, FLINT) and not row(r.buys, GLASS) and not row(r.buys, PANE) and row(r.buys, NUGGET))
	-- With the player's goods known, it offers for what the player has, as many as they have.
	r = window.rows(empty, {}, 1000, 0, {[IRON] = 2}, true)
	assert(#r.buys == 1 and r.buys[1].item == IRON and r.buys[1].lots == 2)
	-- Anyone else has no such rows.
	assert(not row(window.rows(empty, held, 1000, 0, nil, false).sells, IRON))
end
-- In the window: buying an ingot takes nine nuggets and pays its pouch; a held ingot goes first.
do
	local pouch = {[NUGGET] = 20, [EMERALD] = 10}
	local alch = {_id = "alch-1", _profession = "cleric", _villages_alchemist = true, _villages_belongings = pouch,
		object = villager.object}
	view = empty
	-- The stub engine has no player lookup, so the window's rows are unfiltered, as here.
	player_inv.contents[EMERALD] = 1000
	def.on_rightclick(alch, player)
	assert(shown[#shown].spec:find("alchemist", 1, true), "named for its trade")
	local rows_now = window.rows(empty, pouch, 10, 0, nil, true)
	local _, index = row(rows_now.sells, IRON)
	handlers.fields(player, window.FORMNAME, {["sell_one_" .. index] = true})
	-- Nine nuggets at their cost and the alchemist's margin (ticket 30): with nothing made
	-- yet, a nugget's cost is its base price.
	local price = math.ceil(ledger.price(IRON) * 1.05 - 1e-9)
	assert(pouch[NUGGET] == 11 and player_inv.contents[IRON] == 8 + 1 and pouch[EMERALD] == 10 + price, pouch[NUGGET])
	assert(logs[#logs]:find("(from 9 mcl_core:iron_nugget)", 1, true))
	pouch[IRON] = 1
	rows_now = window.rows(empty, pouch, pouch[EMERALD], 0, nil, true)
	_, index = row(rows_now.sells, IRON)
	handlers.fields(player, window.FORMNAME, {["sell_one_" .. index] = true})
	assert(pouch[IRON] == 0 and pouch[NUGGET] == 11, "the held ingot, not the nuggets")
	-- Selling it flint: kept as it is, at its value, refused at 32.
	player_inv.contents[FLINT] = 40
	pouch[EMERALD] = 5000
	rows_now = window.rows(empty, pouch, pouch[EMERALD], 0, nil, true)
	_, index = row(rows_now.buys, FLINT)
	handlers.fields(player, window.FORMNAME, {["buy_all_" .. index] = true})
	assert(pouch[FLINT] == 32 and player_inv.contents[FLINT] == 8, tostring(pouch[FLINT]))
	assert(pouch[EMERALD] == 5000 - 32 * math.floor(ledger.price(FLINT)))
	assert(not row(window.rows(empty, pouch, pouch[EMERALD], 0, nil, true).buys, FLINT))
	handlers.fields(player, window.FORMNAME, {quit = "true"})
end
-- Premium trades (ticket 37): the librarian's Special tab lists its books, locked by its
-- tier and the player's band; buying one takes a book and makes the enchanted one.
do
	local BOOK = "mcl_books:book"
	local shelf = {[BOOK] = 2, [EMERALD] = 0}
	local librarian = {_id = "libr-1", _profession = "librarian", _max_trade_tier = 4, _villages_belongings = shelf,
		object = villager.object}
	view = {surplus = {}, needs = {}, value = function(item) return values[item] end}
	player_inv.contents[EMERALD] = 1000
	rep = 40
	def.on_rightclick(librarian, player)
	assert(shown[#shown].spec:find("tabheader[", 1, true), "a Special tab")
	assert(not shown[#shown].spec:find("premium_buy", 1, true), "wares first")
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	local spec = shown[#shown].spec
	assert(spec:find("Book: Mending", 1, true) and spec:find("needs a master", 1, true), "listed, locked")
	assert(spec:find("Book: Efficiency IV", 1, true) and spec:find("can make 2", 1, true))
	-- The rows: Mending, five more at level 5 (locked), then Efficiency IV, the first open one.
	local index
	for i, entry in ipairs(premium.rows("librarian", 4, 40, shelf, 18, function() return 0 end, 0)) do
		if entry.offer.id == "efficiency_4" then index = i end
	end
	assert(index == 7)
	handlers.fields(player, window.FORMNAME, {["premium_buy_1"] = true})
	assert(#made == 0 and shelf[BOOK] == 2, "Mending is locked at an expert")
	-- Efficiency IV: 16 dinners at 18 and a book at its base price, a tenth off at 40.
	local price = math.ceil((16 * 18 + ledger.price(BOOK)) * (1 - window.rep_share(40)) - 1e-9)
	handlers.fields(player, window.FORMNAME, {["premium_buy_" .. index] = true})
	assert(#made == 1 and made[1].id == "efficiency_4" and made[1].enchants.efficiency == 4)
	assert(shelf[BOOK] == 1 and shelf[EMERALD] == price and player_inv.contents[EMERALD] == 1000 - price)
	assert(player_inv.contents.efficiency_4 == 1 and gossiped[#gossiped] == "trading")
	assert(librarian._villages_tally.used[BOOK] == 1, "the book used is tallied")
	assert(logs[#logs]:find("premium 1 efficiency_4", 1, true))
	-- No book left, nothing made.
	shelf[BOOK] = 0
	handlers.fields(player, window.FORMNAME, {["premium_buy_" .. index] = true})
	assert(#made == 1 and chats[#chats]:find("nothing to make", 1, true) and player_inv.contents.efficiency_4 == 1)
	assert(shown[#shown].spec:find("out of stock", 1, true))
	-- Below a friend the level 4 books lock too.
	rep = 20
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	assert(shown[#shown].spec:find("needs a friend (30)", 1, true))
	handlers.fields(player, window.FORMNAME, {quit = "true"})
	-- A shepherd has no Special tab.
	local fisher = {_id = "shep-1", _profession = "shepherd", _villages_belongings = {}, object = villager.object}
	def.on_rightclick(fisher, player)
	assert(not shown[#shown].spec:find("tabheader[", 1, true))
	handlers.fields(player, window.FORMNAME, {quit = "true"})
	rep = 0
end
-- The cleric (ticket 37b): rotten flesh bought from its flesh budget up to FLESH_KEEP, at a
-- third of leather; leather sold three flesh to one; pearls and bottles o' enchanting from
-- glass bottles, capped a day.
do
	local FLESH, LEATHER, BOTTLE = "mcl_mobitems:rotten_flesh", "mcl_mobitems:leather", "mcl_potions:glass_bottle"
	-- Pure: the price falls as its stock fills, to half.
	assert(near(window.flesh_unit(6, 0), 2) and near(window.flesh_unit(6, window.FLESH_KEEP), 1))
	assert(near(window.flesh_unit(6, window.FLESH_KEEP / 2), 1.5))
	local r = window.rows({surplus = {[FLESH] = 9}, needs = {}, value = function() return 5 end}, {[FLESH] = 9}, 0, 0,
		{[FLESH] = 200}, false, nil, function() return 15 end, nil, {budget = 30, unit = 3})
	local sells, buys = r.sells, r.buys
	assert(#sells == 1 and sells[1].item == LEATHER and sells[1].lots == 3 and sells[1].conversion, "three from nine")
	assert(sells[1].price == 15, "never dearer than its flesh")
	assert(#buys == 1 and buys[1].item == FLESH and buys[1].fund and buys[1].price == 3)
	assert(buys[1].lots == 10, "its budget pays for 10")
	-- Never at a loss: the floor from what its flesh cost holds past a hero's discount.
	local floored = window.rows({surplus = {}, needs = {}, value = function() return 5 end}, {[FLESH] = 9}, 0, 100,
		nil, false, nil, function() return 4 end, nil, {budget = 0, unit = 3, floor = 9})
	assert(floored.sells[1].item == LEATHER and floored.sells[1].price == 9, floored.sells[1].price)
	local full = window.rows({surplus = {}, needs = {}, value = function() return 5 end}, {[FLESH] = window.FLESH_KEEP},
		0, 0, {[FLESH] = 200}, false, nil, nil, nil, {budget = 300, unit = 3})
	assert(#full.buys == 0, "no room past its keep")

	-- The window.
	local day = 9
	minetest.get_day_count = function() return day end
	local pouch = {[EMERALD] = 5, [FLESH] = 0, [BOTTLE] = 10}
	local cleric = {_id = "cler-2", _profession = "cleric", _max_trade_tier = 5, _villages_belongings = pouch,
		_budget = 40, object = villager.object}
	view = {surplus = {}, needs = {}, value = function(item) return values[item] end}
	player_inv.contents[FLESH] = 60
	player_inv.contents[EMERALD] = 1000
	rep = 0
	def.on_rightclick(cleric, player)
	local unit = window.flesh_unit(prices.price(nil, LEATHER), 0)
	local lot, price = window.lot(unit, false)
	local rows_now = window.rows(view, pouch, 5, 0, nil, false, nil, nil, nil, {budget = 40, unit = unit})
	local _, index = row(rows_now.buys, FLESH)
	handlers.fields(player, window.FORMNAME, {["buy_all_" .. index] = true})
	local lots = math.floor(40 / price)
	assert(pouch[FLESH] == lots * lot and player_inv.contents[FLESH] == 60 - lots * lot, pouch[FLESH])
	assert(cleric._budget == 40 - lots * price and pouch[EMERALD] == 5, "paid from its budget, not its purse")
	assert(cleric._villages_tally.money.flesh_out == lots * price)
	assert(near(cleric._villages_input_cost[FLESH], price / lot), "its cost book's price per flesh")
	-- Its leather now sells for more than three flesh cost it, whatever its asks say.
	local leather_row = row(window.rows(view, pouch, 5, 0, nil, false, nil, function() return 0.5 end, nil,
		{budget = 0, unit = unit, floor = asks.reservation(cleric, LEATHER)}).sells, LEATHER)
	assert(leather_row and leather_row.price > 3 * price / lot, leather_row and leather_row.price)
	-- Honoured at a master cleric: pearls (8 a day at level 5) and bottles o' enchanting.
	rep = 60
	local function find(rows, id)
		for i, entry in ipairs(rows) do
			if entry.offer.id == id then return entry, i end
		end
	end
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	local special = premium.rows("cleric", 5, 60, pouch, 18, function(item) return prices.price(nil, item) end,
		window.rep_share(60))
	local pearl, at = find(special, "ender_pearl")
	assert(special[1].offer.id == "experience_bottle" and pearl.stock == 8, "level 5 first; its cap at level 5")
	assert(shown[#shown].spec:find("Ender pearl", 1, true) and shown[#shown].spec:find("premium_all_" .. at, 1, true))
	handlers.fields(player, window.FORMNAME, {["premium_all_" .. at] = true})
	assert(made[#made].id == "ender_pearl" and player_inv.contents.ender_pearl == 8 and pouch[BOTTLE] == 2)
	assert(pouch[EMERALD] == 5 + 8 * pearl.price and cleric._villages_tally.money.premium_in == 8 * pearl.price)
	handlers.fields(player, window.FORMNAME, {["premium_buy_" .. at] = true})
	assert(player_inv.contents.ender_pearl == 8 and chats[#chats]:find("all it will today", 1, true))
	-- The next day the cap is fresh, but two bottles make two.
	day = 10
	handlers.fields(player, window.FORMNAME, {["premium_all_" .. at] = true})
	assert(player_inv.contents.ender_pearl == 10 and pouch[BOTTLE] == 0)
	assert(shown[#shown].spec:find("out of stock", 1, true))
	-- A friend gets 2 a day at level 4 and no bottles o' enchanting.
	pouch[BOTTLE] = 9
	local friend = premium.rows("cleric", 5, 35, pouch, 18, function() return 0 end, 0)
	assert(find(friend, "ender_pearl").stock == 2 and find(friend, "experience_bottle").locked)
	handlers.fields(player, window.FORMNAME, {quit = "true"})
	minetest.get_day_count = nil
	rep = 0
end
-- The farmer (ticket 37c): golden carrots from 6 wheat or 8 potatoes, sharing a cap a day.
do
	local WHEAT, POTATO = "mcl_farming:wheat_item", "mcl_farming:potato_item"
	local day = 20
	minetest.get_day_count = function() return day end
	local barn = {[EMERALD] = 0, [WHEAT] = 12, [POTATO] = 40}
	local grower = {_id = "farm-2", _profession = "farmer", _max_trade_tier = 4, _villages_belongings = barn,
		object = villager.object}
	view = {surplus = {}, needs = {}, value = function(item) return values[item] end}
	player_inv.contents[EMERALD] = 5000
	rep = 40
	def.on_rightclick(grower, player)
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	assert(shown[#shown].spec:find("Golden carrot (6 wheat)", 1, true))
	local rows_now = premium.rows("farmer", 4, 40, barn, 18, function(item) return prices.price(nil, item) end,
		window.rep_share(40))
	local wheat_at, potato_at
	for i, entry in ipairs(rows_now) do
		if entry.offer.base == WHEAT then wheat_at = i else potato_at = i end
	end
	assert(rows_now[wheat_at].stock == 2 and rows_now[potato_at].stock == 4, "12 wheat make 2; a friend's cap of 4")
	handlers.fields(player, window.FORMNAME, {["premium_all_" .. wheat_at] = true})
	assert(player_inv.contents.golden_carrot_wheat_item == 2 and barn[WHEAT] == 0)
	assert(barn[EMERALD] == 2 * rows_now[wheat_at].price)
	-- Two left of the shared cap, from potatoes.
	handlers.fields(player, window.FORMNAME, {["premium_all_" .. potato_at] = true})
	assert(player_inv.contents.golden_carrot_potato_item == 2 and barn[POTATO] == 40 - 16)
	handlers.fields(player, window.FORMNAME, {["premium_buy_" .. potato_at] = true})
	assert(player_inv.contents.golden_carrot_potato_item == 2 and chats[#chats]:find("all it will today", 1, true))
	handlers.fields(player, window.FORMNAME, {quit = "true"})
	minetest.get_day_count = nil
	rep = 0
end
-- The tool smith (ticket 37d): a diamond pickaxe takes three diamonds and two sticks.
do
	local DIAMOND, STICK = "mcl_core:diamond", "mcl_core:stick"
	local forge = {[EMERALD] = 0, [DIAMOND] = 4, [STICK] = 1}
	local smith = {_id = "tool-2", _profession = "tool_smith", _max_trade_tier = 5, _villages_belongings = forge,
		object = villager.object}
	view = {surplus = {}, needs = {}, value = function(item) return values[item] end}
	player_inv.contents[EMERALD] = 5000
	rep = 60
	def.on_rightclick(smith, player)
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	assert(shown[#shown].spec:find("Diamond pickaxe: Efficiency V, Unbreaking III", 1, true))
	-- One stick: none can be made, and nothing is taken.
	handlers.fields(player, window.FORMNAME, {premium_buy_1 = true})
	assert(forge[DIAMOND] == 4 and forge[STICK] == 1 and chats[#chats]:find("nothing to make", 1, true))
	forge[STICK] = 3
	local row1 = premium.rows("tool_smith", 5, 60, forge, 18, function(item) return prices.price(nil, item) end,
		window.rep_share(60))[1]
	assert(row1.offer.id == "diamond_pick" and row1.stock == 1)
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	handlers.fields(player, window.FORMNAME, {premium_buy_1 = true})
	assert(made[#made].id == "diamond_pick" and made[#made].enchants.efficiency == 5)
	assert(forge[DIAMOND] == 1 and forge[STICK] == 1 and forge[EMERALD] == row1.price)
	assert(smith._villages_tally.used[DIAMOND] == 3 and smith._villages_tally.used[STICK] == 2)
	assert(logs[#logs]:find("(from 3 mcl_core:diamond, 2 mcl_core:stick)", 1, true))
	handlers.fields(player, window.FORMNAME, {quit = "true"})
	rep = 0
end
-- Diamonds (ticket 37d): the villager receives two for each a player sells it, and learns
-- the price paid per diamond sold.
do
	local DIAMOND = "mcl_core:diamond"
	values[DIAMOND] = 70
	local purse = {[EMERALD] = 1000}
	local armorer = {_id = "arm-3", _profession = "armorer", _villages_belongings = purse, object = villager.object}
	view = {surplus = {}, needs = {[DIAMOND] = 8}, value = function(item) return values[item] end,
		urgency = function() return 1 end}
	player_inv.contents[DIAMOND] = 3
	player_inv.contents[EMERALD] = 0
	def.on_rightclick(armorer, player)
	local _, index = row(window.rows(view, purse, 1000, 0).buys, DIAMOND)
	handlers.fields(player, window.FORMNAME, {["buy_one_" .. index] = true})
	assert(player_inv.contents[DIAMOND] == 2 and player_inv.contents[EMERALD] == 70)
	assert(purse[DIAMOND] == window.DIAMOND_BONUS and purse[EMERALD] == 930, purse[DIAMOND])
	assert(near(prices.factor(armorer._villages_prices, DIAMOND), (70 / ledger.price(DIAMOND)) ^ prices.LEARN_TRADE))
	assert(logs[#logs]:find("received 2", 1, true))
	handlers.fields(player, window.FORMNAME, {quit = "true"})
	values[DIAMOND] = nil
end
-- The fisherman (ticket 37e): an enchanted rod from one past the rod it fishes with.
do
	local ROD = "mcl_fishing:fishing_rod"
	local tackle = {[EMERALD] = 0, [ROD] = 1}
	local fisher2 = {_id = "fish-2", _profession = "fisherman", _max_trade_tier = 5, _villages_belongings = tackle,
		object = villager.object}
	view = {surplus = {}, needs = {}, value = function(item) return values[item] end}
	player_inv.contents[EMERALD] = 5000
	rep = 60
	def.on_rightclick(fisher2, player)
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	assert(shown[#shown].spec:find("Fishing rod: Luck of the Sea III, Lure III", 1, true))
	handlers.fields(player, window.FORMNAME, {premium_buy_1 = true})
	assert(tackle[ROD] == 1 and chats[#chats]:find("nothing to make", 1, true), "never its own rod")
	tackle[ROD] = 2
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	handlers.fields(player, window.FORMNAME, {premium_buy_1 = true})
	assert(made[#made].id == "rod_3" and made[#made].enchants.lure == 3 and tackle[ROD] == 1)
	handlers.fields(player, window.FORMNAME, {quit = "true"})
	rep = 0
end
-- The cartographer (ticket 38c): explorer maps of its village's charted sites, from 8 paper.
do
	local PAPER = "mcl_core:paper"
	local desk = {[EMERALD] = 0, [PAPER] = 24}
	local carto = {_id = "carto-1", _profession = "cartographer", _max_trade_tier = 5, _villages_belongings = desk,
		object = villager.object}
	view = {surplus = {}, needs = {}, value = function(item) return values[item] end}
	player_inv.contents[EMERALD] = 5000
	rep = 60
	-- Nothing charted yet: both rows say why.
	def.on_rightclick(carto, player)
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	local spec = shown[#shown].spec
	assert(spec:find("Woodland explorer map", 1, true) and spec:find("Ocean explorer map", 1, true))
	assert(spec:find("still charting the woods", 1, true) and spec:find("still charting the sea", 1, true))
	assert(not spec:find("premium_buy_", 1, true), "nothing to buy")
	handlers.fields(player, window.FORMNAME, {quit = "true"})
	-- Two temples drawn: the ocean row (second, below the level 4 woodland one) sells them.
	chart_sites.ocean_temple = {"near", "far"}
	def.on_rightclick(carto, player)
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	assert(shown[#shown].spec:find("can make 2", 1, true))
	local made_before, emeralds = #made, player_inv.contents[EMERALD]
	handlers.fields(player, window.FORMNAME, {premium_buy_2 = true})
	assert(player_inv.contents["map:near"] == 1, "the nearest first")
	assert(desk[PAPER] == 16 and #made == made_before, "8 paper taken, made from the chart")
	assert(player_inv.contents[EMERALD] < emeralds and desk[EMERALD] == emeralds - player_inv.contents[EMERALD])
	-- The same player's next map is the next site; then it has none for them.
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	handlers.fields(player, window.FORMNAME, {premium_buy_2 = true})
	assert(player_inv.contents["map:far"] == 1 and desk[PAPER] == 8)
	handlers.fields(player, window.FORMNAME, {tab = "2"})
	assert(shown[#shown].spec:find("still charting the sea", 1, true))
	handlers.fields(player, window.FORMNAME, {premium_buy_2 = true})
	assert(desk[PAPER] == 8, "nothing sold")
	handlers.fields(player, window.FORMNAME, {quit = "true"})
	-- Another player's first is the nearest.
	local inv2 = inventory({[EMERALD] = 5000})
	local player2 = {
		is_player = function() return true end, get_player_name = function() return "other" end,
		get_pos = function() return {x = 1, y = 0, z = 0} end, get_inventory = function() return inv2 end,
	}
	def.on_rightclick(carto, player2)
	handlers.fields(player2, window.FORMNAME, {tab = "2"})
	handlers.fields(player2, window.FORMNAME, {premium_buy_2 = true})
	assert(inv2.contents["map:near"] == 1 and desk[PAPER] == 0)
	handlers.fields(player2, window.FORMNAME, {tab = "2"})
	-- Out of paper: out of stock, though a site is left for them.
	assert(not shown[#shown].spec:find("can make", 1, true))
	handlers.fields(player2, window.FORMNAME, {quit = "true"})
	rep = 0
end
print("trade_window.lua: ok")
