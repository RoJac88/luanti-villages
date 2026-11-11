-- The mod's own trade window (docs/villager-economy-design.md, ticket 14), in place of
-- vanilla's trade tables with the economy on. A villager trades only what it really
-- has, at what it really thinks things are worth (ledger.lua, prices.lua):
--
-- * It sells its spare goods (its ledger's surplus), from its belongings and its
--   stash, at its value times MARKUP.
-- * It buys what it needs, up to its need, at BID_SHARE of its value, and only with
--   the emeralds it carries. A villager in need is a standing order: this is how the
--   player takes part in the village's economy.
-- * News: the needs it heard from others (market news), as a pointer to who wants
--   what. It is not a contract.
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
-- nothing.
--
-- Vanilla's tables, tiers and rare goods (enchanted books, diamond gear) are left out of
-- player trade, to be brought back once the economy works. `_trades` is left alone:
-- vanilla and this mod read it as the mark of a villager that keeps its job. The keeper
-- (its menu, keeper.lua), the Builder (its status window) and children keep their own
-- right-click; with the economy off every villager keeps vanilla's.
local core = minetest

local EMERALD = "mcl_core:emerald"
local FORMNAME = "living_villages:trade"
local MARKUP = 1.25
local BID_SHARE = 0.9
local REP_STEP = 1 / 400
local REP_MAX = 0.25
local REFUSE = -40
local URGENT = 2
local ROWS = 6
local NEWS_ROWS = 4
local REACH = 6
-- What a category's amount counts (goods.lua).
local UNITS = {food = "points", fuel = "seconds", log = "logs", planks = "planks"}

local M = {
	FORMNAME = FORMNAME, MARKUP = MARKUP, BID_SHARE = BID_SHARE, REP_STEP = REP_STEP,
	REP_MAX = REP_MAX, REFUSE = REFUSE, URGENT = URGENT, ROWS = ROWS,
}

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
-- ({item = count}), its emeralds, its reputation for the player, and what the player
-- has ({item = count}, nil for no filter):
-- {sells = {{item, lot, price, lots}}, buys = {{item, lot, price, lots, urgency}},
-- short = {{category, amount}}}. `lots` is how many lots it has to sell, or wants and
-- can pay for. A category's members are bought only as the player has them.
function M.rows(view, held, emeralds, reputation, player_has)
	local share = M.rep_share(reputation)
	local sells, buys = {}, {}
	for item, spare in pairs(view.surplus or {}) do
		local have = math.min(spare, held[item] or 0)
		local value = view.value(item)
		if item ~= EMERALD and have > 0 and value then
			local lot, price = M.lot(value * MARKUP * (1 - share), true)
			if lot and have >= lot then
				sells[#sells + 1] = {item = item, lot = lot, price = price, lots = math.floor(have / lot)}
			end
		end
	end
	local group = view.group or {}
	for item, need in pairs(view.needs or {}) do
		local value = view.value(item)
		local shown = not group[item] or not player_has or (player_has[item] or 0) > 0
		if item ~= EMERALD and value and shown then
			local lot, price = M.lot(value * BID_SHARE * (1 + share), false)
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

-- The needs it heard from others, dearest first, at most n.
function M.news(heard, n)
	local list = {}
	for _, entry in ipairs(heard or {}) do
		if entry.kind == "needs" and entry.price then list[#list + 1] = entry end
	end
	table.sort(list, function(a, b)
		if a.price ~= b.price then return a.price > b.price end
		return a.item < b.item
	end)
	local out = {}
	for i = 1, math.min(n or NEWS_ROWS, #list) do out[i] = list[i] end
	return out
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

function M.install(def, deps)
	local possessions, gossip, news, clock = deps.possessions, deps.gossip, deps.news, deps.clock
	local sessions = {}

	local function reputation(villager, name)
		return gossip and gossip.reputation(villager, name) or 0
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
		local view = possessions.assess(villager)
		return M.rows(view, possessions.held(villager), possessions.emeralds(villager), reputation(villager, name),
			player_has(name)), view
	end

	local function form(villager, name)
		local rows = current_rows(villager, name)
		sessions[name].rows = rows
		local r = reputation(villager, name)
		local parts = {
			"formspec_version[4]", "size[13,15]",
			string.format("label[0.5,0.6;%s]", esc(string.format("%s, %s. Purse: %d emeralds. You are %s to it (%d).",
				(villager.nametag and villager.nametag ~= "" and villager.nametag) or "Villager",
				tostring(villager._profession or "villager"), possessions.emeralds(villager), reputation_word(r), r))),
			"label[0.5,1.3;It sells]", "label[6.8,1.3;It buys]",
		}
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
		parts[#parts + 1] = string.format("label[0.5,%g;Heard at market:]", y)
		local heard = M.news(news.heard(villager), NEWS_ROWS)
		for i, entry in ipairs(heard) do
			local home = entry.home and string.format(" (home %d,%d)", entry.home.x, entry.home.z) or ""
			parts[#parts + 1] = string.format("label[0.5,%g;%s]", y + i * 0.45,
				esc(entry.group
					and string.format("someone needs %s, such as %d %s, worth %d each to them%s", entry.group,
						entry.count or 0, description(entry.item), math.floor(entry.price + 0.5), home)
					or string.format("someone needs %d %s, worth %d each to them%s", entry.count or 0,
						description(entry.item), math.floor(entry.price + 0.5), home)))
		end
		if #heard == 0 then parts[#parts + 1] = string.format("label[0.5,%g;nothing]", y + 0.45) end
		parts[#parts + 1] = "list[current_player;main;0.5,9.4;9,4;]"
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
		local taken = possessions.take_held(villager, entry.item, count)
		if taken < count then
			if taken > 0 then possessions.add(villager, entry.item, taken) end
			return
		end
		inv:remove_item("main", EMERALD .. " " .. pay)
		possessions.add(villager, EMERALD, pay)
		inv:add_item("main", entry.item .. " " .. count)
		if gossip then gossip.add(villager, name, "trading") end
		log("%s bought %d %s from villager %s for %d emerald(s)", name, count, entry.item,
			tostring(villager._id):sub(1, 6), pay)
	end

	-- The player sells `lots` lots of a row the villager buys.
	local function player_sells(player, villager, entry, lots)
		local inv = player:get_inventory()
		local name = player:get_player_name()
		lots = math.min(lots, entry.lots)
		local count, pay = entry.lot * lots, entry.price * lots
		if lots < 1 then return end
		if possessions.emeralds(villager) < pay then return end
		local stack = inv:remove_item("main", entry.item .. " " .. count)
		if stack:get_count() < count then
			inv:add_item("main", stack)
			core.chat_send_player(name, "You have too few of those.")
			return
		end
		possessions.take(villager, EMERALD, pay)
		possessions.add(villager, entry.item, count)
		local left = inv:add_item("main", EMERALD .. " " .. pay)
		if not left:is_empty() and core.add_item then core.add_item(player:get_pos(), left) end
		if gossip then
			gossip.add(villager, name, "trading")
			if entry.urgency >= URGENT then gossip.add(villager, name, "minor_positive") end
		end
		log("%s sold %d %s to villager %s for %d emerald(s)%s", name, count, entry.item,
			tostring(villager._id):sub(1, 6), pay, entry.urgency >= URGENT and ", an urgent need" or "")
	end

	local original_rightclick = def.on_rightclick
	def.on_rightclick = function(self, clicker)
		local name = clicker and clicker.is_player and clicker:is_player() and clicker:get_player_name()
		if not name or not clock.enabled() or self.child or self._villages_keeper or self._villages_builder
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
