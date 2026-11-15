-- Run with: lua tests/money.lua
-- Money (ticket 21a): the money factor, gifts in the trade window, and emeralds left in a
-- stash, trapped chests too.
local now = 0
local nodes, metas, lists, logs = {}, {}, {}, {}
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
local function parse(k)
	local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
	return {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
end

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	equals = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	add = function(a, n) return {x = a.x + n, y = a.y + n, z = a.z + n} end,
	subtract = function(a, n) return {x = a.x - n, y = a.y - n, z = a.z - n} end,
}

local function stack(name, count)
	return {get_name = function() return name end, get_count = function() return count end,
		is_empty = function() return count == 0 end}
end

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	get_day_count = function() return 1 end,
	get_timeofday = function() return 0.4 end,
	settings = {get = function() return nil end, get_bool = function(_, _, default) return default end},
	log = function(_, message) logs[#logs + 1] = message end,
	is_protected = function() return false end,
	pos_to_string = function(p) return "(" .. key(p) .. ")" end,
	string_to_pos = function(s) if s == "" then return nil end return parse(s) end,
	get_node_or_nil = function(pos) return {name = nodes[key(pos)] or "air"} end,
	get_meta = function(pos)
		local k = key(pos)
		metas[k] = metas[k] or {}
		lists[k] = lists[k] or {}
		return {
			get_string = function(_, field) return metas[k][field] or "" end,
			set_string = function(_, field, value) metas[k][field] = value end,
			get_inventory = function()
				return {
					get_size = function() return nodes[k] and 27 or 0 end,
					get_list = function()
						local out = {}
						for name, count in pairs(lists[k]) do out[#out + 1] = stack(name, count) end
						return out
					end,
					remove_item = function(_, _, text)
						local name, count = text:match("^(%S+) (%d+)$")
						local have = lists[k][name] or 0
						local taken = math.min(have, tonumber(count))
						lists[k][name] = have - taken > 0 and have - taken or nil
						return stack(name, taken)
					end,
				}
			end,
		}
	end,
	find_nodes_in_area = function(minp, maxp, names)
		local wanted = {}
		for _, name in ipairs(names) do wanted[name] = true end
		local found = {}
		for k, name in pairs(nodes) do
			local p = parse(k)
			if wanted[name] and p.x >= minp.x and p.x <= maxp.x and p.y >= minp.y and p.y <= maxp.y
				and p.z >= minp.z and p.z <= maxp.z then
				found[#found + 1] = p
			end
		end
		table.sort(found, function(a, b) return key(a) < key(b) end)
		return found
	end,
	get_objects_inside_radius = function() return {} end,
	registered_items = {},
	registered_nodes = {},
	get_item_group = function() return 0 end,
}

local ledger = dofile("ledger.lua")
local possessions = dofile("possessions.lua")
possessions.stage_of = function() return "work" end
local exchange = dofile("exchange.lua")
local window = dofile("trade_window.lua")

local EMERALD = "mcl_core:emerald"
local BREAD = "mcl_farming:bread"
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- The money factor: 1 at the cushion, an eighth's worth to the broke, more to the rich.
assert(ledger.CUSHION == 4 * ledger.DINNER)
assert(ledger.lambda(nil) == 1 and near(ledger.lambda(ledger.CUSHION), 1))
assert(ledger.lambda(0) == ledger.LAMBDA_SPAN and ledger.lambda(1) == ledger.LAMBDA_SPAN)
assert(near(ledger.lambda(3110), (ledger.CUSHION / 3110) ^ ledger.GAMMA))
assert(ledger.lambda(3110) > 0.1 and ledger.lambda(3110) < 0.2)
assert(ledger.lambda(1e9) == 1 / ledger.LAMBDA_SPAN)

-- Every value is divided by it; `real` is the value with no money in it.
local function villager(id, held, fields)
	local pos = {x = 0, y = 1, z = 0}
	local v = {_id = id, _profession = "nitwit", _villages_food = 12, _villages_belongings = held,
		object = {get_pos = function() return pos end}}
	for k, value in pairs(fields or {}) do v[k] = value end
	return v
end
local poor = villager("poor", {[EMERALD] = 30}, {_villages_food = 0})
local rich = villager("rich", {[EMERALD] = 3000}, {_villages_food = 0})
local poor_view, rich_view = possessions.assess(poor), possessions.assess(rich)
assert(rich_view.value(BREAD) > poor_view.value(BREAD) * 4, "the rich pay more for the same need")
assert(near(rich_view.real(BREAD), rich_view.value(BREAD) * rich_view.lambda))
-- The rich buy at an ask the poor pass up.
local baker = villager("baker", {[BREAD] = 40})
baker._villages_asks = {[BREAD] = 2}
local ask = exchange.asking(baker, poor, BREAD)
assert(poor_view.value(BREAD) < ask and rich_view.value(BREAD) >= ask, poor_view.value(BREAD) .. " " .. ask)
assert(exchange.offer(baker, possessions.assess(baker), poor, poor_view) == nil, "too dear for the poor")
local trade = exchange.offer(baker, possessions.assess(baker), rich, rich_view)
assert(trade and trade.item == BREAD and trade.pay)
-- A porter's purse is its client's: the money factor leaves it out.
local porter = villager("pat", {[EMERALD] = 300}, {_villages_trade_trip = {client = {purse = 280}, spent = 30}})
assert(possessions.money(porter) == 50)
assert(possessions.money(villager("keep", {[EMERALD] = 5}, {_villages_keeper = true})) == nil)

-- Gifts: gossip by size, and what a Give field may hold.
assert(#window.gift_gossip(window.GIFT_MINOR - 1) == 0)
local kinds = window.gift_gossip(window.GIFT_MINOR)
assert(#kinds == 1 and kinds[1] == "minor_positive")
kinds = window.gift_gossip(window.GIFT_MAJOR)
assert(#kinds == 2 and kinds[1] == "major_positive")
assert(window.gift_amount("64") == 64 and window.gift_amount(" 12.7") == 12)
assert(window.gift_amount("") == nil and window.gift_amount("0") == nil and window.gift_amount("-5") == nil)
assert(window.gift_amount("abc") == nil and window.gift_amount("nan") == nil and window.gift_amount("inf") == nil)

-- A trapped chest by its bed is its stash, labelled with its owner, and the emeralds a
-- player leaves in it are collected when it gets up, from beside its bed.
local bed = {x = 10, y = 1, z = 10}
nodes[key(bed)] = "mcl_beds:bed_red_bottom"
metas[key(bed)] = {villager = "ann"}
local chest = {x = 16, y = 1, z = 10}
nodes[key(chest)] = "mcl_chests:trapped_chest_small"
local at = {x = 10, y = 1, z = 11}
local ann = {_id = "ann", _profession = "farmer", _bed = bed, _villages_belongings = {[EMERALD] = 5},
	_villages_endowed = true, _villages_emerald_scale = 64, _villages_kit = "farmer",
	object = {get_pos = function() return at end}}
assert(vector.equals(possessions.claim_stash(ann), chest))
assert(metas[key(chest)].infotext == "Stash of the farmer ann", metas[key(chest)].infotext)
lists[key(chest)][EMERALD] = 200
-- Six away it is out of reach for the day's look...
assert(possessions.collect_stash_emeralds(ann) == 0)
-- ...but not on getting up.
now = 100
ann._villages_sleeping = true
possessions.step(ann, now)
ann._villages_sleeping = nil
possessions.step(ann, now + 1)
assert(possessions.emeralds(ann) == 205 and not lists[key(chest)][EMERALD])
assert(logs[#logs]:find("villager ann collected 200 emerald(s) from its stash at (16,1,10)", 1, true), logs[#logs])
-- An opened trapped chest is swapped for its `_on` node, and is still its stash.
nodes[key(chest)] = "mcl_chests:trapped_chest_on_small"
assert(vector.equals(possessions.claim_stash(ann), chest))
-- The label follows its job.
ann._profession = "fletcher"
possessions.claim_stash(ann)
assert(metas[key(chest)].infotext == "Stash of the fletcher ann")

print("money.lua: ok")
