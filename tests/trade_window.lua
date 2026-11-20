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
window.install(def, {possessions = possessions, gossip = gossip,
	clock = {enabled = function() return enabled end}})

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
-- Buy one bread at its ask: its value of 20, over its reference price (its base, 10.7).
local ledger = dofile("ledger.lua")
local prices = dofile("prices.lua")
local asks = dofile("asks.lua")
handlers.fields(player, window.FORMNAME, {sell_one_1 = true})
assert(player_inv.contents[BREAD] == 1 and player_inv.contents[EMERALD] == 180 and belongings[EMERALD] == 120)
assert(belongings[BREAD] == 5 and gossiped[#gossiped] == "trading")
-- A sale like any: its reference price learnt the 20 paid, and its ask rose.
assert(near(prices.factor(villager._villages_prices, BREAD), (20 / ledger.price(BREAD)) ^ prices.LEARN_TRADE))
assert(asks.factor(villager, BREAD) > 1)
-- Sell it iron: urgent, so good gossip too; 120 emeralds pay for 3 at its value of 40.
handlers.fields(player, window.FORMNAME, {buy_all_1 = true})
assert(player_inv.contents[IRON] == 7 and belongings[IRON] == 3 and belongings[EMERALD] == 0)
assert(gossiped[#gossiped] == "minor_positive")
-- A purchase like any: its reference price for iron learnt the 40 it paid.
assert(near(prices.factor(villager._villages_prices, IRON), (40 / ledger.price(IRON)) ^ prices.LEARN_TRADE))
-- Closing lets it go.
handlers.fields(player, window.FORMNAME, {quit = "true"})
assert(not villager._trading_players.rskj)
-- One it distrusts will not trade; children, keepers and the economy off keep vanilla's.
rep = window.REFUSE
def.on_rightclick(villager, player)
assert(chats[#chats]:find("will not trade") and not villager._trading_players.rskj)
rep = 0
local keeper = {_id = "k", _villages_keeper = true, object = villager.object}
def.on_rightclick(keeper, player)
assert(keeper.vanilla)
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
	assert(row(r.buys, GOLD) and row(r.buys, GOLD).lots == 0, "a gold ingot is more than it has")
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
	assert(pouch[NUGGET] == 11 and player_inv.contents[IRON] == 7 + 1 and pouch[EMERALD] == 10 + price, pouch[NUGGET])
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
print("trade_window.lua: ok")
