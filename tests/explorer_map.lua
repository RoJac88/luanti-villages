-- Run with: lua tests/explorer_map.lua
minetest = {get_modpath = function() return "." end}
local map = dofile("explorer_map.lua")

-- The area: 256 nodes a side at level 2, centred as mcl_maps centres any map.
local cx, cz, minp, maxp = map.area({x = 166, y = -10, z = -122})
assert(cx == 192 and cz == -64, cx .. "," .. cz)
assert(minp.x == 64 and maxp.x == 319 and minp.z == -192 and maxp.z == 63)
assert(minp.y == -32 and maxp.y == 63)
-- The site is always on the map, at least 64 from an edge.
for _, p in ipairs({{x = 0, z = 0}, {x = 127, z = -1}, {x = -128, z = 128}, {x = 1449, z = -3001}}) do
	local _, _, a, b = map.area(p)
	assert(p.x - a.x >= 64 and b.x - p.x >= 63 and p.z - a.z >= 64 and b.z - p.z >= 63)
end

-- Rendering, on a stub world: grass at y 10 in the west half, water to y 0 over sand in the east.
local colors = {
	["mcl_core:dirt_with_grass"] = {{100, 200, 50}, {90, 180, 40}},
	["mcl_core:water_source"] = {0, 0, 255, 128},
	["mcl_core:sand"] = {220, 210, 160},
}
local function node(x, y, z)
	if x < 0 then
		if y == 10 then return "mcl_core:dirt_with_grass", 1 end
		return y < 10 and "mcl_core:stone" or "air", 0
	end
	if y <= 0 and y > -5 then return "mcl_core:water_source", 0 end
	if y == -5 then return "mcl_core:sand", 0 end
	return "air", 0
end
local _, _, a, b = map.area({x = 0, z = 0})
local pixels, w, h = map.render(node, colors, a, b)
assert(w == 128 and h == 128 and #pixels == 128 * 128)
local west = pixels[1 + 10]
assert(west[1] == 90 and west[2] == 180 and west[4] == 255, "grass, by param2, opaque")
local east = pixels[1 + 120]
assert(east[3] > east[1] and east[4] == 255, "water blended over sand")
assert(east[1] > 0, "the sand shows through")
-- Shading: a column higher than the one west of it is lighter.
local function step_node(x, y, z)
	local top = x < 64 and 5 or 9
	if y == top then return "mcl_core:sand", 0 end
	return "air", 0
end
pixels = map.render(step_node, colors, a, b)
local lo = map.pixel_of({x = 62, z = 0}, a, b)
local hi = map.pixel_of({x = 64, z = 0}, a, b)
assert(pixels[1 + hi][1] > pixels[1 + lo][1], "the step up shaded lighter")

-- Pixels: north (max z) at the top.
local px, py = map.pixel_of({x = a.x, z = b.z}, a, b)
assert(px == 0 and py == 0)
px, py = map.pixel_of({x = b.x, z = a.z}, a, b)
assert(px == 127 and py == 127)
px, py = map.pixel_of({x = 0, z = 0}, a, b) -- a map from x -64 to 191, z -64 to 191
assert(px == 32 and py == 95, px .. "," .. py)

-- The icon: painted centred on the site, clipped at the edges.
local blank = {}
for i = 1, 128 * 128 do blank[i] = {1, 2, 3, 255} end
map.paint(blank, 128, 128, 64, 63, "ocean_temple")
local temple = map.ICONS.ocean_temple
local function at(x, y) return blank[y * 128 + x + 1] end
assert(at(64, 59)[1] == temple.palette.k[1] and at(64, 59)[2] == temple.palette.k[2], "the apex, 4 above")
assert(at(64, 60)[2] == temple.palette.a[2], "teal below it")
assert(at(63, 59)[1] == 1, "clear pixels leave the map")
assert(at(60, 67)[1] == temple.palette.k[1], "the base's corner")
map.paint(blank, 128, 128, 0, 0, "woodland_cabin")
assert(at(0, 0)[1] == map.ICONS.woodland_cabin.palette.k[1], "clipped, not wrapped")
for _, icon in pairs(map.ICONS) do
	assert(#icon.rows == 9)
	for _, row in ipairs(icon.rows) do
		assert(#row == 9)
		for c in row:gmatch(".") do assert(c == "." or icon.palette[c], "every colour in the palette") end
	end
end

-- The id and file: under mcl_maps' naming, our own suffix.
assert(map.id("ocean_temple", 192, -64, 7) == "192_overworld_-64_2_lv_ocean_temple7")
assert(map.filename("x") == "mcl_maps_map_x.png")

-- The item: an ordinary filled map, locked, named for its kind.
local function make_stack(name)
	local fields = {}
	local meta = {
		set_string = function(_, k, v) fields[k] = v end,
		set_int = function(_, k, v) fields[k] = v end,
	}
	return {name = name, fields = fields, get_meta = function() return meta end}
end
local info = map.info("woodland_cabin", {x = 755, y = 5, z = 1239}, 3)
local stack = map.item(make_stack, info, function(p) return p.x .. "," .. p.y .. "," .. p.z end)
assert(stack.name == "mcl_maps:filled_map")
local f = stack.fields
assert(f["mcl_maps:id"] == info.id and info.id:find("woodland_cabin3$"))
assert(f["mcl_maps:cx"] == info.cx and f["mcl_maps:cz"] == info.cz and f["mcl_maps:zoom"] == 2)
assert(f["mcl_maps:dim"] == "overworld" and f["mcl_maps:locked"] == 1)
assert(f["mcl_maps:minp"] == info.minp.x .. ",-32," .. info.minp.z)
assert(f["mcl_maps:maxp"] == info.maxp.x .. ",63," .. info.maxp.z)
assert(f.description:find("^Woodland Explorer Map\nLevel 2"))

-- Drawing: the land generated twice, then the PNG written where mcl_maps looks.
local emerges, written, made = {}, {}, {}
local engine = {
	EMERGE_CANCELLED = 0, EMERGE_ERRORED = 1, EMERGE_FROM_DISK = 2, EMERGE_GENERATED = 3,
	emerge_area = function(p1, p2, cb) emerges[#emerges + 1] = {p1 = p1, p2 = p2, cb = cb} end,
	get_modpath = function() return "/nonexistent" end,
	parse_json = function() return {} end,
	get_node = function() return {name = "air", param2 = 0} end,
	get_worldpath = function() return "/world" end,
	mkdir = function(d) made[#made + 1] = d end,
	encode_png = function(w2, h2, data) return {w = w2, h = h2, bytes = #data} end,
	safe_file_write = function(path, data) written[path] = data end,
}
local result
map.draw(engine, "ocean_temple", {x = 166, y = -10, z = -122}, 1, function(r) result = r end)
assert(#emerges == 1 and emerges[1].p1.x == 64 and emerges[1].p2.x == 319 and emerges[1].p1.y == -32)
emerges[1].cb(nil, engine.EMERGE_GENERATED, 1)
emerges[1].cb(nil, engine.EMERGE_GENERATED, 0)
assert(#emerges == 2 and not result, "a second pass for the structures the first placed")
emerges[2].cb(nil, engine.EMERGE_FROM_MEMORY, 0)
assert(result and result.id == "192_overworld_-64_2_lv_ocean_temple1")
local png = written["/world/mcl_maps/mcl_maps_map_" .. result.id .. ".png"]
assert(png and png.w == 128 and png.h == 128 and png.bytes == 128 * 128 * 4)
assert(made[1] == "/world/mcl_maps")
-- Land that can't be generated: no map.
emerges, result = {}, "unset"
map.draw(engine, "ocean_temple", {x = 0, y = 0, z = 0}, 2, function(r) result = r end)
emerges[1].cb(nil, engine.EMERGE_CANCELLED, 0)
assert(result == nil and #emerges == 1)

print("explorer_map tests passed")
