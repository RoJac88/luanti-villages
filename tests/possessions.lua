-- Run with: lua tests/possessions.lua
local now = 0
local nodes, metas, sizes, dropped, logs = {}, {}, {}, {}, {}
local settings = {}
local protected = {}
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

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	settings = {
		get = function(_, name) return settings[name] end,
		get_bool = function(_, name, default)
			if settings[name] == nil then return default end
			return settings[name]
		end,
	},
	log = function(_, message) table.insert(logs, message) end,
	is_protected = function(pos) return protected[key(pos)] == true end,
	pos_to_string = function(p) return "(" .. key(p) .. ")" end,
	string_to_pos = function(s)
		if s == "" then return nil end
		return parse(s)
	end,
	add_item = function(pos, item) table.insert(dropped, item) end,
	get_node_or_nil = function(pos) return {name = nodes[key(pos)] or "air"} end,
	get_meta = function(pos)
		local k = key(pos)
		metas[k] = metas[k] or {}
		return {
			get_string = function(_, field) return metas[k][field] or "" end,
			set_string = function(_, field, value) metas[k][field] = value end,
			get_inventory = function() return {get_size = function() return sizes[k] or 0 end} end,
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
				table.insert(found, p)
			end
		end
		table.sort(found, function(a, b) return key(a) < key(b) end)
		return found
	end,
}

minetest.log = function(_, message) table.insert(logs, message) end
local possessions = dofile("possessions.lua")
local stock = dofile("farm_stock.lua")

local function chest(pos, name)
	nodes[key(pos)] = name or "mcl_chests:chest_small"
	sizes[key(pos)] = 27
end
local function bed(pos, owner)
	nodes[key(pos)] = "mcl_beds:bed_red_bottom"
	metas[key(pos)] = {villager = owner}
end

-- Belongings: kept apart from the work pouch.
local v = {_id = "ann", _profession = "farmer"}
possessions.add(v, "mcl_core:emerald", 2)
possessions.add(v, "mcl_core:emerald")
assert(possessions.emeralds(v) == 3 and possessions.total(v) == 3)
assert(possessions.take(v, "mcl_core:emerald", 5) == 3 and v._villages_belongings == nil)
assert(possessions.take(v, "mcl_core:emerald", 1) == 0)
assert(v._villages_farm_pouch == nil, "the work pouch is not touched")

-- Endowment: 3 to 6 emeralds once, and a kit for the first profession that has one.
assert(possessions.endow(v))
local emeralds = possessions.emeralds(v)
assert(emeralds >= 3 and emeralds <= 6)
assert(possessions.count(v, "mcl_farming:bread") == 3 and v._villages_kit == "farmer")
assert(not possessions.endow(v), "only once")
v._profession = "librarian"
assert(not possessions.endow(v), "no second kit after a change of job")
assert(possessions.count(v, "mcl_core:paper") == 0)
-- The same villager always gets the same number.
local twin = {_id = "ann", _profession = "nitwit"}
possessions.endow(twin)
assert(possessions.emeralds(twin) == emeralds and possessions.total(twin) == emeralds, "nitwits get no kit")
-- A child gets nothing yet; grown up, it does.
local kid = {_id = "kid", child = true, _profession = "unemployed"}
assert(not possessions.endow(kid) and kid._villages_belongings == nil)
kid.child = nil
assert(possessions.endow(kid) and possessions.emeralds(kid) >= 3 and not kid._villages_kit)
kid._profession = "mason"
assert(possessions.endow(kid) and possessions.count(kid, "mcl_core:stone") == 8, "kit with its first job")

-- Death drops what it owns, in stacks.
local rich = {_id = "rich"}
possessions.add(rich, "mcl_core:stone", 70)
possessions.drop_all(rich, {x = 0, y = 0, z = 0})
table.sort(dropped)
assert(#dropped == 2 and dropped[1] == "mcl_core:stone 6" and dropped[2] == "mcl_core:stone 64")
assert(rich._villages_belongings == nil)

-- The stash: the nearest chest to its bed.
local ann_bed = {x = 0, y = 0, z = 0}
bed(ann_bed, "ann")
v._bed = ann_bed
local near, far = {x = 2, y = 0, z = 0}, {x = 5, y = 0, z = 0}
chest(near)
chest(far)
assert(vector.equals(possessions.claim_stash(v), near))
assert(metas[key(near)].villages_owner == "ann" and metas[key(near)].villages_owner_bed == "(0,0,0)")
assert(vector.equals(possessions.claim_stash(v), near), "kept")
assert(possessions.stash_status(v) == "(2,0,0)")

-- Work chests leave stashes out.
assert(#stock.find_chests(ann_bed, 8) == 1 and vector.equals(stock.find_chests(ann_bed, 8)[1], far))

-- Another villager with a bed beside hers takes the next free chest, never hers.
local bob_bed = {x = 0, y = 0, z = 1}
bed(bob_bed, "bob")
local bob = {_id = "bob", _bed = bob_bed}
assert(vector.equals(possessions.claim_stash(bob), far))

-- Work chests are never stashes: by a jukebox, beside a composter, by a bench.
local cy = {_id = "cy", _bed = {x = 100, y = 0, z = 0}}
bed(cy._bed, "cy")
local pantry = {x = 101, y = 0, z = 0}
chest(pantry)
nodes[key({x = 104, y = 0, z = 0})] = "mcl_jukebox:jukebox"
assert(possessions.claim_stash(cy) == nil, "pantry")
nodes[key({x = 104, y = 0, z = 0})] = "mcl_composters:composter_2"
assert(possessions.claim_stash(cy), "a composter 3 away does not make it a farm's")
metas[key(pantry)], cy._villages_stash = nil, nil
nodes[key({x = 104, y = 0, z = 0})] = nil
nodes[key({x = 102, y = 0, z = 0})] = "mcl_composters:composter_2"
assert(possessions.claim_stash(cy) == nil, "farm chest")
nodes[key({x = 102, y = 0, z = 0})] = "living_villages:builder_block"
assert(possessions.claim_stash(cy) == nil, "builder's chest")
nodes[key({x = 102, y = 0, z = 0})] = nil
protected[key(pantry)] = true
assert(possessions.claim_stash(cy) == nil, "protected")
protected[key(pantry)] = nil
sizes[key(pantry)] = 0
assert(possessions.claim_stash(cy) == nil, "no inventory yet")
sizes[key(pantry)] = 27
assert(vector.equals(possessions.claim_stash(cy), pantry))

-- A double chest is claimed whole.
local dee = {_id = "dee", _bed = {x = 200, y = 0, z = 0}}
bed(dee._bed, "dee")
chest({x = 202, y = 0, z = 0}, "mcl_chests:chest_left")
chest({x = 202, y = 0, z = 1}, "mcl_chests:chest_right")
possessions.claim_stash(dee)
assert(metas["202,0,0"].villages_owner == "dee" and metas["202,0,1"].villages_owner == "dee")

-- Succession: the bed passes to someone else, and the chest with it.
metas[key(ann_bed)].villager = "eve"
local eve = {_id = "eve", _bed = ann_bed}
assert(vector.equals(possessions.claim_stash(eve), near), "ann no longer holds the bed")
assert(metas[key(near)].villages_owner == "eve" and logs[#logs]:find("inherits"))
-- Ann's claim is gone; she has no stash until she finds one.
assert(possessions.stash_status(v) == "(2,0,0) (claim lost)")
-- But a holder still in its bed keeps its chest.
local fay = {_id = "fay", _bed = {x = 0, y = 0, z = -1}}
bed(fay._bed, "fay")
local got = possessions.claim_stash(fay)
assert(not got or not vector.equals(got, near), "eve still holds the bed")

-- Moving to another bed gives up the old chest and claims by the new one.
local new_bed = {x = 300, y = 0, z = 0}
bed(new_bed, "bob")
chest({x = 301, y = 0, z = 0})
bob._bed = new_bed
assert(vector.equals(possessions.claim_stash(bob), {x = 301, y = 0, z = 0}))
assert(metas[key(far)].villages_owner == "", "old stash released")

-- No bed, no stash; a child has none.
assert(possessions.claim_stash({_id = "gus"}) == nil)
assert(possessions.claim_stash({_id = "hal", child = true, _bed = ann_bed}) == nil)

-- step does both, once a minute.
local ivy = {_id = "ivy", _profession = "farmer", _bed = {x = 400, y = 0, z = 0}}
bed(ivy._bed, "ivy")
chest({x = 401, y = 0, z = 0})
possessions.step(ivy, now)
assert(ivy._villages_endowed and ivy._villages_stash)
ivy._villages_stash = nil
possessions.step(ivy, now + 1)
assert(ivy._villages_stash == nil, "waits a minute")
now = now + possessions.CLAIM_SECONDS
possessions.step(ivy, now)
assert(ivy._villages_stash)

-- install drops belongings on death; off with the economy.
local def = {do_custom = function() return "vanilla" end, on_die = function() return "died" end}
possessions.install(def)
local jo = {_id = "jo", object = {get_pos = function() return {x = 0, y = 0, z = 0} end}}
possessions.add(jo, "mcl_core:emerald", 4)
dropped = {}
assert(def.on_die(jo, nil) == "died" and dropped[1] == "mcl_core:emerald 4")
assert(def.do_custom(jo, 0.1) == "vanilla" and jo._villages_endowed)
settings.living_villages_economy = false
local plain = {do_custom = function() end}
local before = plain.do_custom
possessions.install(plain)
assert(plain.do_custom == before)

-- Eating (ticket 4): at or below 8 points, the best food it carries, then its stash's
-- if it stands by it; not above 8, and not a child.
settings.living_villages_economy = nil
local kim = {_id = "kim", _villages_food = 9, _villages_belongings = {["mcl_farming:bread"] = 2, ["mcl_farming:carrot_item"] = 3}}
assert(#possessions.eat(kim) == 0, "not hungry enough")
kim._villages_food = 8
local eaten = possessions.eat(kim)
assert(#eaten == 1 and eaten[1] == "mcl_farming:bread" and kim._villages_food == 12)
assert(possessions.food_carried(kim) == 4 + 3)
kim._villages_food = 0
possessions.eat(kim)
assert(kim._villages_food == 7 and possessions.count(kim, "mcl_farming:bread") == 0 and possessions.count(kim, "mcl_farming:carrot_item") == 0)
-- Its stash, only within reach.
local kim_bed, kim_chest = {x = 500, y = 0, z = 0}, {x = 502, y = 0, z = 0}
bed(kim_bed, "kim")
chest(kim_chest)
kim._bed = kim_bed
assert(possessions.claim_stash(kim))
local larder = {["mcl_farming:bread"] = 3}
local stash_meta = minetest.get_meta
minetest.get_meta = function(pos)
	local meta = stash_meta(pos)
	if key(pos) == key(kim_chest) then
		meta.get_inventory = function()
			return {
				get_size = function() return 27 end,
				remove_item = function(_, _, item)
					local name = item:match("^%S+")
					local n = (larder[name] or 0) > 0 and 1 or 0
					larder[name] = (larder[name] or 0) - n
					return {get_count = function() return n end}
				end,
			}
		end
	end
	return meta
end
local kim_at = {x = 520, y = 0, z = 0}
kim.object = {get_pos = function() return kim_at end}
kim._villages_food = 4
assert(#possessions.eat(kim) == 0 and larder["mcl_farming:bread"] == 3, "too far from its stash")
kim_at = {x = 501, y = 0, z = 0}
possessions.eat(kim)
assert(kim._villages_food == 12 and larder["mcl_farming:bread"] == 1)
minetest.get_meta = stash_meta
assert(#possessions.eat({_id = "tot", child = true, _villages_belongings = {["mcl_farming:bread"] = 1}}) == 0)

print("possessions.lua: ok")
