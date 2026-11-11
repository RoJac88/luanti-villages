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

-- Rows: spare goods it holds at value times the markup; needs at the bid share, as many
-- lots as it needs and can pay for.
local values = {[BREAD] = 10, [FISH] = 2, [IRON] = 40}
local view = {
	surplus = {[BREAD] = 6, [FISH] = 10}, needs = {[IRON] = 5},
	value = function(item) return values[item] end,
	urgency = function(item) return item == IRON and 3 or 1 end,
}
local rows = window.rows(view, {[BREAD] = 6, [FISH] = 3}, 100, 0)
assert(#rows.sells == 2 and rows.sells[1].item == BREAD and rows.sells[1].price == 13 and rows.sells[1].lots == 6)
assert(rows.sells[2].item == FISH and rows.sells[2].lots == 3, "only what it holds")
assert(#rows.buys == 1 and rows.buys[1].price == 36 and rows.buys[1].lots == 2, "100 emeralds pay for 2 at 36")
assert(rows.buys[1].urgency == 3)
-- A friend buys cheaper and is paid more; one it distrusts the other way.
local friend = window.rows(view, {[BREAD] = 6}, 1000, 100)
assert(friend.sells[1].price < 13 and friend.buys[1].price > 36 and friend.buys[1].lots == 5)
local foe = window.rows(view, {[BREAD] = 6}, 1000, -30)
assert(foe.sells[1].price > 13 and foe.buys[1].price < 36)
-- With no emeralds it still shows the need, with no lots.
assert(window.rows(view, {}, 0, 0).buys[1].lots == 0)

-- News: needs heard, dearest first.
local news = window.news({{kind = "has", item = FISH, price = 99}, {kind = "needs", item = IRON, price = 46, count = 30},
	{kind = "needs", item = BREAD, price = 12, count = 3}}, 4)
assert(#news == 2 and news[1].item == IRON)

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
values[BREAD] = 10
view.surplus = {[BREAD] = 6}
local gossiped = {}
local rep = 0
local gossip = {reputation = function() return rep end, add = function(_, name, kind) gossiped[#gossiped + 1] = kind end}
local enabled = true
local def = {on_rightclick = function(self) self.vanilla = true end}
window.install(def, {possessions = possessions, gossip = gossip, news = {heard = function() return {} end},
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
-- Buy one bread for 13.
handlers.fields(player, window.FORMNAME, {sell_one_1 = true})
assert(player_inv.contents[BREAD] == 1 and player_inv.contents[EMERALD] == 187 and belongings[EMERALD] == 113)
assert(belongings[BREAD] == 5 and gossiped[#gossiped] == "trading")
-- Sell it iron: urgent, so good gossip too; 113 emeralds pay for 3 at 36.
handlers.fields(player, window.FORMNAME, {buy_all_1 = true})
assert(player_inv.contents[IRON] == 7 and belongings[IRON] == 3 and belongings[EMERALD] == 113 - 108)
assert(gossiped[#gossiped] == "minor_positive")
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
print("trade_window.lua: ok")
