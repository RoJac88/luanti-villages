-- Explorer maps (ticket 38b, docs/villager-economy-design.md): the map of a charted site
-- (charting.lua), drawn once, with the structure's icon painted into it.
--
-- mcl_maps draws a map by generating its land and reading the nodes; its renderer is local,
-- and its HUD has no way to add a marker. So this draws its own copy of that picture (the
-- same colors.json, the same height shading, y -32 to 63, 128 pixels over 256 nodes: its
-- level 2, where a new map is level 1, 128 nodes), paints the icon into the pixels, and writes the PNG where mcl_maps keeps its own,
-- under an id of ours. The item is then an ordinary mcl_maps:filled_map: mcl_maps loads it,
-- draws the player's arrow and the off-map dots, copies it at the crafting grid and shows it
-- in item frames, icon and all. It is locked, so the cartography table won't zoom it: zooming
-- calls mcl_maps.regenerate_map, which would redraw it without its icon.
local core = minetest
local M = {}

M.ZOOM = 2
M.SIZE = 64 * 2 ^ M.ZOOM -- nodes a side
M.PIXELS = 128
M.MIN_Y, M.MAX_Y = -32, 63 -- mcl_maps' overworld range

-- Icons, our own drawing: 9 by 9, "." clear.
M.ICONS = {
	ocean_temple = {
		label = "Ocean Explorer Map",
		palette = {k = {16, 28, 40}, a = {64, 196, 184}, b = {24, 118, 120}},
		rows = {
			"....k....",
			"...kak...",
			"..kaaak..",
			"..kbbbk..",
			".kaaaaak.",
			".kbbbbbk.",
			"kaaaaaaak",
			"kbbabbabk",
			"kkkkkkkkk",
		},
	},
	woodland_cabin = {
		label = "Woodland Explorer Map",
		-- A red roof and pale walls: green or brown would vanish into a dark oak forest.
		palette = {k = {24, 20, 16}, g = {150, 44, 32}, w = {214, 182, 128}, d = {92, 58, 32}},
		rows = {
			"....k....",
			"...kgk...",
			"..kgggk..",
			".kgggggk.",
			"kkkkkkkkk",
			".kwwwwwk.",
			".kwkwdwk.",
			".kwwwdwk.",
			".kkkkkkk.",
		},
	},
}

-- The map's centre and corners for a site, as mcl_maps' configure_map rounds any map with
-- overlap allowed (its default): to the half-size grid, plus a quarter.
function M.area(pos)
	local half = M.SIZE / 2
	local cx = (math.floor(pos.x / half) + 0.5) * half
	local cz = (math.floor(pos.z / half) + 0.5) * half
	return cx, cz, {x = cx - half, y = M.MIN_Y, z = cz - half}, {x = cx + half - 1, y = M.MAX_Y, z = cz + half - 1}
end

local function clamp(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end

-- mcl_maps' do_generate_map, as a pixel list of {r, g, b, a}: rows from the north (max z)
-- down, columns from the west. `node(x, y, z)` returns name and param2.
function M.render(node, colors, minp, maxp)
	local pixels = {}
	local xsize, zsize = maxp.x - minp.x + 1, maxp.z - minp.z + 1
	local xstep, zstep = math.ceil(xsize / M.PIXELS), math.ceil(zsize / M.PIXELS)
	for z = zsize, 1, -zstep do
		local map_z = minp.z + z - 1
		local last_height
		for x = 1, xsize, xstep do
			local map_x = minp.x + x - 1
			local cagg, height = {0, 0, 0, 0}, nil
			local solid_under_air = -1
			for map_y = maxp.y, minp.y, -1 do
				local name, param2 = node(map_x, map_y, map_z)
				if name ~= "air" then
					local color = colors[name]
					if color and type(color[1]) == "table" then color = color[(param2 or 0) + 1] or color[1] end
					if color then
						if solid_under_air == 0 then
							cagg, height = {0, 0, 0, 0}, nil
							solid_under_air = 1
						end
						local alpha = cagg[4]
						if alpha < 255 then
							local a = (color[4] or 255) * (255 - alpha) / 255
							local f = a / 255
							cagg[1] = cagg[1] + f * color[1]
							cagg[2] = cagg[2] + f * color[2]
							cagg[3] = cagg[3] + f * color[3]
							alpha = cagg[4] + a
							cagg[4] = alpha
						end
						if alpha > 140 and not height then height = map_y end
						if alpha >= 250 and solid_under_air > 0 then
							if last_height and height then
								local dheight = math.max(-48, math.min((height - last_height) * 8, 48))
								cagg[1], cagg[2], cagg[3] = cagg[1] + dheight, cagg[2] + dheight, cagg[3] + dheight
							end
							cagg[4] = 255
							break
						end
					end
				elseif solid_under_air == -1 then
					solid_under_air = 0
				end
			end
			pixels[#pixels + 1] = {clamp(cagg[1]), clamp(cagg[2]), clamp(cagg[3]), clamp(cagg[4])}
			last_height = height
		end
	end
	return pixels, xsize / xstep, zsize / zstep
end

-- The pixel a node position falls on (0-based column and row).
function M.pixel_of(pos, minp, maxp)
	local step = (maxp.x - minp.x + 1) / M.PIXELS
	return math.floor((pos.x - minp.x) / step), math.floor((maxp.z - pos.z) / step)
end

-- Paints `kind`'s icon centred on pixel (px, py), clipped to the map.
function M.paint(pixels, w, h, px, py, kind)
	local icon = M.ICONS[kind]
	local n = #icon.rows
	local half = math.floor(n / 2)
	for r = 1, n do
		local row = icon.rows[r]
		for c = 1, #row do
			local colour = icon.palette[row:sub(c, c)]
			local x, y = px - half + c - 1, py - half + r - 1
			if colour and x >= 0 and x < w and y >= 0 and y < h then
				pixels[y * w + x + 1] = {colour[1], colour[2], colour[3], 255}
			end
		end
	end
end

function M.id(kind, cx, cz, n)
	return string.format("%d_overworld_%d_%d_lv_%s%d", cx, cz, M.ZOOM, kind, n)
end

function M.filename(id)
	return "mcl_maps_map_" .. id .. ".png"
end

-- What a chart keeps of a drawn map.
function M.info(kind, pos, n)
	local cx, cz, minp, maxp = M.area(pos)
	return {id = M.id(kind, cx, cz, n), cx = cx, cz = cz, minp = minp, maxp = maxp, kind = kind}
end

-- The item for a drawn map (`info`), as mcl_maps' configure_map sets one up, locked, and
-- named for its kind.
function M.item(make_stack, info, pos_to_string, colorize)
	local stack = make_stack("mcl_maps:filled_map")
	local meta = stack:get_meta()
	meta:set_string("mcl_maps:id", info.id)
	meta:set_int("mcl_maps:cx", info.cx)
	meta:set_string("mcl_maps:dim", "overworld")
	meta:set_int("mcl_maps:cz", info.cz)
	meta:set_int("mcl_maps:zoom", M.ZOOM)
	meta:set_string("mcl_maps:minp", pos_to_string(info.minp))
	meta:set_string("mcl_maps:maxp", pos_to_string(info.maxp))
	meta:set_int("mcl_maps:locked", 1)
	local level = "Level " .. M.ZOOM
	meta:set_string("description", M.ICONS[info.kind].label .. "\n" .. (colorize and colorize("#AAAAAA", level) or level))
	return stack
end

-- The engine side: generates the map's land (twice, as mcl_maps does, so structures the first
-- pass triggered are placed), draws it with the icon at `pos` and writes the PNG. Calls
-- cb(info) when written, or cb(nil) if the land couldn't be generated.
local colors
function M.draw(engine, kind, pos, n, cb)
	local info = M.info(kind, pos, n)
	local function failed(action)
		return action == engine.EMERGE_CANCELLED or action == engine.EMERGE_ERRORED
	end
	local bad = false
	engine.emerge_area(info.minp, info.maxp, function(_, action, remaining)
		if failed(action) then bad = true end
		if remaining > 0 then return end
		if bad then return cb(nil) end
		engine.emerge_area(info.minp, info.maxp, function(_, action2, left)
			if failed(action2) then bad = true end
			if left > 0 then return end
			if bad then return cb(nil) end
			if not colors then
				local file = io.open(engine.get_modpath("mcl_maps") .. "/colors.json", "r")
				colors = file and engine.parse_json(file:read("*all")) or {}
				if file then file:close() end
			end
			local vars = rawget(_G, "mcl_vars")
			local raw = vars and vars.get_node_name_raw
			local function node(x, y, z)
				if raw then
					local name, _, param2 = raw(x, y, z)
					return name, param2
				end
				local nd = engine.get_node({x = x, y = y, z = z})
				return nd.name, nd.param2
			end
			local pixels, w, h = M.render(node, colors, info.minp, info.maxp)
			local px, py = M.pixel_of(pos, info.minp, info.maxp)
			M.paint(pixels, w, h, px, py, kind)
			local bytes = {}
			for i, p in ipairs(pixels) do bytes[i] = string.char(p[1], p[2], p[3], p[4]) end
			local dir = engine.get_worldpath() .. "/mcl_maps"
			engine.mkdir(dir)
			engine.safe_file_write(dir .. "/" .. M.filename(info.id), engine.encode_png(w, h, table.concat(bytes)))
			cb(info)
		end)
	end)
end

return M
