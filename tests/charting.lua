-- Run with: lua tests/charting.lua
local function new_vector(x, y, z) return {x = x, y = y, z = z} end
vector = {
	new = function(x, y, z) if type(x) == "table" then return new_vector(x.x, x.y, x.z) end return new_vector(x, y, z) end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	round = function(p) return new_vector(math.floor(p.x + 0.5), math.floor(p.y + 0.5), math.floor(p.z + 0.5)) end,
}
minetest = {get_modpath = function() return "." end}
local charting = dofile("charting.lua")

-- Chunk maths: 80 nodes from -32, as the engine aligns them.
local size, offset = charting.chunk_geometry(5)
assert(size == 80 and offset == 32)
local cx, cz = charting.chunk_of(-32, 47, size, offset)
assert(cx == 0 and cz == 0)
cx, cz = charting.chunk_of(-33, 48, size, offset)
assert(cx == -1 and cz == 1)
local x0, z0 = charting.chunk_min(1, -1, size, offset)
assert(x0 == 48 and z0 == -112)

-- Nearest first, ties in a fixed order, and only within the radius.
local list = charting.offsets(2)
assert(list[1][1] == 0 and list[1][2] == 0)
assert(list[2][1] == -1 and list[2][2] == 0 and list[5][1] == 1 and list[5][2] == 0, "ties by dx then dz")
for i = 2, #list do assert(list[i][3] >= list[i - 1][3]) end
assert(#list == 13, "a disc of radius 2")
assert(charting.offsets(2) == list, "cached")
assert(charting.radius_chunks("ocean_temple", 80) == 38 and charting.radius_chunks("woodland_cabin", 80) == 75)

-- The v7 terrain height: alt where it is higher, else blended by height_select.
local values = {height_select = 0.25, terrain_persist = 0.6, terrain_base = 10, terrain_alt = 2}
local seen_persist = {}
local function noise(name, _, _, persist)
	if persist then seen_persist[name] = persist end
	return values[name]
end
assert(charting.base_level(noise, 0, 0) == 10 * 0.25 + 2 * 0.75)
assert(seen_persist.terrain_base == 0.6 and seen_persist.terrain_alt == 0.6, "persistence from its noise")
values.terrain_alt = 20
assert(charting.base_level(noise, 0, 0) == 20)
values.height_select, values.terrain_alt = 3, 2
assert(charting.base_level(noise, 0, 0) == 10, "height_select clamped to 1")

-- The classifier: deep ocean by height, RoofedForest by biome on land.
local function env_with(level, biome)
	return {size = 80, offset = 32, water_level = 1, level = level, biome = biome or function() return "Plains" end}
end
assert(charting.likely("ocean_temple", 0, 0, env_with(function() return -20 end)))
assert(not charting.likely("ocean_temple", 0, 0, env_with(function() return -3 end)), "too shallow")
-- 12 of 16 samples deep is enough, 11 is not.
local function deep_west(columns)
	return function(x) return (x - (-32)) < columns * 20 and -20 or 10 end
end
assert(charting.likely("ocean_temple", 0, 0, env_with(deep_west(3))))
assert(not charting.likely("ocean_temple", 0, 0, env_with(deep_west(2))))
local forest = function() return "RoofedForest" end
assert(charting.likely("woodland_cabin", 0, 0, env_with(function() return 12 end, forest)))
assert(not charting.likely("woodland_cabin", 0, 0, env_with(function() return -5 end, forest)), "under the sea")
assert(not charting.likely("woodland_cabin", 0, 0, env_with(function() return 12 end)), "another biome")
local asked_y
charting.likely("woodland_cabin", 0, 0, env_with(function() return 12.7 end, function(_, y) asked_y = y return "RoofedForest" end))
assert(asked_y == 12, "the biome at the ground's height")

-- Sites: within the radius, not twice, nearest first, at most three.
local chart = charting.new_chart("ocean_temple", {x = 0, y = 5, z = 0})
assert(charting.wants(chart))
assert(charting.add_site(chart, {x = 900, y = -10, z = 0}))
assert(not charting.add_site(chart, {x = 920, y = -12, z = 10}), "the same temple")
assert(not charting.add_site(chart, {x = 3100, y = -10, z = 0}), "beyond 3000")
assert(charting.add_site(chart, {x = 100, y = -10, z = 0}))
assert(chart.sites[1].pos.x == 100, "nearest first")
assert(charting.add_site(chart, {x = 0, y = -10, z = 2000}))
assert(not charting.wants(chart), "three is enough")
assert(not charting.add_site(chart, {x = 50, y = -10, z = 0}), "full")
assert(charting.describe(chart, 80):find("full"))

-- The walk: unlikely chunks passed within a budget, a likely one held until passed.
chart = charting.new_chart("ocean_temple", {x = 0, y = 5, z = 0})
local ocean_east = env_with(function(x) return x >= 200 and -20 or 10 end)
local index, ccx, ccz = charting.next_chunk(chart, ocean_east, 5)
assert(index == nil and chart.cursor == 5 and not chart.done, "out of budget, nothing likely near")
index, ccx, ccz = charting.next_chunk(chart, ocean_east, 1000)
assert(index and ccx >= 3, "the first chunk east of x 200")
local cursor = chart.cursor
assert(cursor == index - 1, "held before it")
local again = charting.next_chunk(chart, ocean_east, 1000)
assert(again == index, "the same chunk again until passed (a restart)")
charting.passed(chart, index)
assert(chart.cursor == index)
local nxt = charting.next_chunk(chart, ocean_east, 1000)
assert(nxt > index)
-- No ocean at all: done at the radius, and says so.
chart = charting.new_chart("ocean_temple", {x = 0, y = 5, z = 0})
local dry = env_with(function() return 10 end)
for _ = 1, 100 do if chart.done then break end charting.next_chunk(chart, dry, 100) end
assert(chart.done and not charting.wants(chart))
local passed, total = charting.progress(chart, 80)
assert(passed == total)
assert(charting.describe(chart, 80):find("none within 3000"))

-- Sales (ticket 38c): each player the nearest drawn site they haven't bought; the chart
-- keeps three ahead of its keenest buyer.
chart = charting.new_chart("ocean_temple", {x = 0, y = 5, z = 0})
charting.add_site(chart, {x = 100, y = -10, z = 0})
charting.add_site(chart, {x = 500, y = -10, z = 0})
charting.add_site(chart, {x = 900, y = -10, z = 0})
local maps = {["100,-10,0"] = {id = "m1"}, ["900,-10,0"] = {id = "m3"}}
local site, info, count = charting.choose(chart, "ann", maps)
assert(site.pos.x == 100 and info.id == "m1" and count == 2, "only drawn sites")
charting.note_bought(chart, "ann", site)
site, info, count = charting.choose(chart, "ann", maps)
assert(site.pos.x == 900 and count == 1, "past the undrawn one")
assert(charting.choose(chart, "bob", maps).pos.x == 100, "another player starts at the nearest")
assert(charting.most_bought(chart) == 1)
assert(charting.wants(chart), "refills behind a sale")
assert(charting.add_site(chart, {x = 1300, y = -10, z = 0}))
assert(not charting.wants(chart) and not charting.add_site(chart, {x = 1700, y = -10, z = 0}))
charting.note_bought(chart, "ann", chart.sites[3])
assert(not charting.choose(chart, "ann", maps), "ann has every drawn one")
assert(charting.reason(chart, "ann", maps) == "still charting the sea")
assert(charting.reason(nil, "ann", maps, "woodland_cabin") == "still charting the woods")
chart.done = true
assert(charting.reason(chart, "ann", maps) == "still charting the sea", "two left to draw")
maps["500,-10,0"], maps["1300,-10,0"] = {id = "m2"}, {id = "m4"}
charting.note_bought(chart, "ann", chart.sites[2])
charting.note_bought(chart, "ann", chart.sites[4])
assert(charting.reason(chart, "ann", maps) == "knows of no other ocean temple within 3,000 blocks")
local empty = charting.new_chart("woodland_cabin", {x = 0, y = 5, z = 0})
empty.done = true
assert(charting.reason(empty, "ann", {}) == "knows of no woodland cabin within 6,000 blocks")

-- Old land: clusters of signature nodes, big enough, with the cabin's head nearby.
local temple = charting.KINDS.ocean_temple.signature
local nodes = {}
for i = 1, 200 do nodes[#nodes + 1] = {x = 1000 + i % 18, y = -10 + i % 20, z = 500 + (i * 7) % 18} end
for i = 1, 20 do nodes[#nodes + 1] = {x = -400 + i % 3, y = 2, z = 0} end -- a player's prismarine wall
local centres = charting.clusters(temple, nodes)
assert(#centres == 1 and math.abs(centres[1].x - 1009) <= 2 and math.abs(centres[1].z - 509) <= 2)
local cabin = charting.KINDS.woodland_cabin.signature
local deepslate = {}
for i = 1, 48 do deepslate[#deepslate + 1] = {x = 200 + i % 8, y = 20, z = 300 + i % 6} end
assert(#charting.clusters(cabin, deepslate, {}) == 0, "no head: a player's build")
assert(#charting.clusters(cabin, deepslate, {{x = 204, y = 24, z = 302}}) == 1)
assert(#charting.clusters(cabin, deepslate, {{x = 400, y = 24, z = 302}}) == 0, "a head far off")

-- install: the hook, seen sites, charts from cartographers, the search and the scan.
local storage_data = {}
local storage = {get_string = function(_, k) return storage_data[k] or "" end,
	set_string = function(_, k, v) storage_data[k] = v end}
local registered = {}
local placed_ok = true
local structures = {
	registered_structures = {ocean_temple = {}, woodland_cabin = {}},
	place_structure = function() return placed_ok end,
}
local villages_made = {}
local village_index = {
	read_village = function(pos) return villages_made[1] end,
	update_village = function(pos) villages_made[1] = {center = vector.new(pos)} return villages_made[1] end,
}
local cartographer = {name = "mobs_mc:villager", _profession = "cartographer", _max_trade_tier = 3,
	object = {get_pos = function() return {x = 10, y = 5, z = 10} end}}
local emerges = {}
local finds = {}
local logged = {}
local serialized
local engine = {
	settings = {get = function() return nil end},
	get_mapgen_setting = function(k)
		return ({mg_name = "v7", chunksize = "5", water_level = "1"})[k]
	end,
	get_mapgen_setting_noiseparams = function(name) return {name = name} end,
	-- Ocean east of x 200 (alt and base both), RoofedForest nowhere.
	get_perlin = function(np)
		return {get_2d = function(_, p)
			if np.name == "mgv7_np_height_select" then return 0.5 end
			if np.name == "mgv7_np_terrain_persist" then return 0.6 end
			return p.x >= 200 and -20 or 10
		end}
	end,
	get_biome_data = function() return {biome = 1} end,
	get_biome_name = function() return "Plains" end,
	serialize = function(v) serialized = v return "S" end,
	deserialize = function(s) if s == "S" then return serialized end return nil end,
	log = function(_, line) logged[#logged + 1] = line end,
	luaentities = {cartographer},
	EMERGE_GENERATED = 3, EMERGE_FROM_DISK = 2, EMERGE_CANCELLED = 0, EMERGE_ERRORED = 1,
	emerge_area = function(minp, maxp, cb) emerges[#emerges + 1] = {minp = minp, maxp = maxp, cb = cb} end,
	find_nodes_in_area = function(minp, maxp, names) return finds[names[1]] or {} end,
	register_globalstep = function(f) registered.step = f end,
	register_chatcommand = function(name, def) registered[name] = def end,
}
-- Maps (ticket 38b) are drawn by explorer_map.lua; here each draw waits for the test.
local draws = {}
local maps_stub = {draw = function(_, kind, pos, n, cb) draws[#draws + 1] = {kind = kind, pos = pos, n = n, cb = cb} end}
local function drawn(i) draws[i].cb({id = "map" .. draws[i].n, kind = draws[i].kind}) end
local charting_api = charting.install({engine = engine, storage = storage, structures = structures,
	village_index = village_index, explorer_map = maps_stub})
assert(charting_api)
-- A temple placed before any chart is seen, and offered to the chart made later.
assert(structures.place_structure({x = 600, y = -8, z = 40}, {name = "ocean_temple"}) == true)
assert(#charting.state.seen == 1)
placed_ok = false
structures.place_structure({x = 2000, y = -8, z = 40}, {name = "ocean_temple"})
assert(#charting.state.seen == 1, "a failed placement isn't a site")
placed_ok = true
structures.place_structure({x = 10, y = 8, z = 10}, {name = "desert_temple"})
assert(#charting.state.seen == 1, "only the two kinds")
-- The first step enlists the tier 3 cartographer: an ocean chart only, holding the seen temple.
registered.step(0.1)
local charts = charting.state.charts
local ids = {}
for id in pairs(charts) do ids[#ids + 1] = id end
assert(#ids == 1 and charts[ids[1]].kind == "ocean_temple", "no woodland chart below tier 4")
local ocean = charts[ids[1]]
assert(#ocean.sites == 1 and ocean.sites[1].pos.x == 600)
-- Its map is drawn before any search: a site is sold only once drawn.
assert(#draws == 1 and #emerges == 0 and draws[1].kind == "ocean_temple" and draws[1].pos.x == 600)
assert(select(2, registered.living_villages_charts.func("admin", "")):find("not drawn yet"))
registered.step(5)
assert(#draws == 1 and #emerges == 0, "one thing at a time")
drawn(1)
assert(charting.state.maps["600,-8,40"].id == "map1")
assert(not select(2, registered.living_villages_charts.func("admin", "")):find("not drawn yet"))
registered.step(1)
assert(#emerges == 0, "pausing after the draw")
registered.step(1.5)
-- Then it generates the first likely chunk, east of x 200.
assert(#emerges == 1 and emerges[1].minp.x >= 200 and emerges[1].minp.y == -32 and emerges[1].maxp.y == 47)
-- Nothing else starts while it is in flight.
registered.step(5)
assert(#emerges == 1)
-- Generated: a temple placed there is caught by the hook.
structures.place_structure({x = emerges[1].minp.x + 40, y = -12, z = emerges[1].minp.z + 40}, {name = "ocean_temple"})
assert(#ocean.sites == 2)
local held = ocean.cursor
emerges[1].cb(nil, engine.EMERGE_GENERATED, 1)
emerges[1].cb(nil, engine.EMERGE_GENERATED, 0)
assert(ocean.cursor == held + 1, "passed")
-- The pause, then the next chunk: old land from disk, scanned over its full height.
registered.step(1)
assert(#emerges == 1, "pausing")
registered.step(2)
assert(#emerges == 1 and #draws == 2, "the new site's map first")
drawn(2)
registered.step(2.5)
assert(#emerges == 2)
local old = emerges[2]
local ox, oz = old.minp.x, old.minp.z
finds["mcl_ocean:prismarine"] = {}
for i = 1, 200 do finds["mcl_ocean:prismarine"][i] = {x = ox + 30 + i % 18, y = -10 + i % 20, z = oz + 30 + i % 18} end
old.cb(nil, engine.EMERGE_FROM_DISK, 0)
assert(#emerges == 3 and emerges[3].minp.y == -32 and emerges[3].maxp.y == 79, "the rest of its height")
emerges[3].cb(nil, engine.EMERGE_FROM_DISK, 0)
assert(#ocean.sites == 3, "the scanned temple")
assert(not charting.wants(ocean), "full: no more searching")
registered.step(5)
assert(#emerges == 3 and #draws == 3)
-- A map that can't be drawn isn't tried again until a restart.
draws[3].cb(nil)
registered.step(5)
assert(#draws == 3)
-- A cancelled emerge isn't passed: tried again.
ocean.sites[3] = nil
registered.step(5)
assert(#emerges == 4)
local before = ocean.cursor
emerges[4].cb(nil, engine.EMERGE_CANCELLED, 0)
assert(ocean.cursor == before)
-- Saved, and the command lists it.
assert(storage_data.charting == "S" and serialized.charts)
local ok, text = registered.living_villages_charts.func("admin", "")
assert(ok and text:find("ocean temple") and text:find("searching"))
-- "start" charts both kinds at a given spot, as a tier 4 cartographer would.
ok, text = registered.living_villages_charts.func("admin", "start -500,700")
assert(ok and text:find("ocean temples and woodland cabins") and text:find("%-500,0,700"), text)
assert(charts["woodland_cabin@-500,0,700"] and charts["ocean_temple@-500,0,700"])
charts["woodland_cabin@-500,0,700"], charts["ocean_temple@-500,0,700"] = nil, nil
assert(not registered.living_villages_charts.func("admin", "start"), "no player, no x,z")
assert(not registered.living_villages_charts.func("admin", "bogus"))
-- "give": every drawn map of the village nearest the player.
local given = {}
maps_stub.item = function(_, info) return info end
engine.get_player_by_name = function()
	return {get_pos = function() return {x = 20, y = 0, z = 0} end,
		get_inventory = function() return {add_item = function(_, _, stack)
			given[#given + 1] = stack
			return {is_empty = function() return true end}
		end} end}
end
ok, text = registered.living_villages_charts.func("admin", "give")
local with_maps = 0
for _, site in ipairs(ocean.sites) do
	if charting.state.maps[charting.key(site.pos)] then with_maps = with_maps + 1 end
end
assert(ok and with_maps >= 1 and #given == with_maps and given[1].id:find("^map"), text)
assert(text == string.format("Gave %d explorer map(s).", with_maps))
engine.get_player_by_name = nil
-- The trade window's view (ticket 38c): maps for sale at the cartographer's village.
do
	local api = charting_api
	local pos = {x = 12, y = 5, z = 9}
	local n = api.available(pos, "ocean_temple", "rskj")
	assert(n >= 1, "drawn sites for sale")
	local stack, note = api.take(pos, "ocean_temple", "rskj")
	assert(stack and stack.id:find("^map"))
	note()
	assert(api.available(pos, "ocean_temple", "rskj") == n - 1, "one fewer for that player")
	assert(api.available(pos, "ocean_temple", "other") == n)
	local zero, why = api.available(pos, "woodland_cabin", "rskj")
	assert(zero == 0 and why == "still charting the woods", "no woodland chart yet")
	village_index.read_village = function() return nil end
	zero, why = api.available(pos, "ocean_temple", "rskj")
	assert(zero == 0 and why == "still charting the sea", "no village record")
	assert(api.take(pos, "ocean_temple", "rskj") == nil)
	village_index.read_village = function() return villages_made[1] end
end
-- At tier 4 the woodland chart starts too.
cartographer._max_trade_tier = 4
registered.step(31)
local kinds = {}
for _, c in pairs(charts) do kinds[c.kind] = true end
assert(kinds.woodland_cabin)

-- Not on singlenode, nor without mcl_structures; a disabled structure gets no chart.
engine.get_mapgen_setting = function(k) return ({mg_name = "singlenode"})[k] end
assert(not charting.install({engine = engine, storage = storage, structures = structures, village_index = village_index}))
assert(not charting.install({engine = engine, storage = storage, village_index = village_index}))
engine.get_mapgen_setting = function(k) return ({mg_name = "valleys", chunksize = "5", water_level = "1"})[k] end
structures.is_disabled = function(name) return name == "woodland_cabin" end
storage_data = {}
serialized = nil
cartographer._max_trade_tier = 5
emerges = {}
assert(charting.install({engine = engine, storage = storage, structures = structures, village_index = village_index}))
registered.step(0.1)
local only = {}
for _, c in pairs(charting.state.charts) do only[#only + 1] = c end
assert(#only == 1 and only[1].kind == "ocean_temple", "the cabin is disabled")
assert(only[1].done, "another mapgen charts from seen sites only")
assert(#emerges == 0)

print("charting tests passed")
