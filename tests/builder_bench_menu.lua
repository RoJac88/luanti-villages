-- Run with: lua tests/builder_bench_menu.lua
-- The bench's window, on a stand-in for builder.lua, whose options(), catalog_options() and
-- orders tests/builder.lua covers.
local WORLD = "/world"
local BENCH_POS = {x = 0, y = 1, z = 0}
local BENCH = "living_villages:builder_block"

local settings, files, dirs, shown, closed = {}, {}, {}, {}, 0
local protected, privileged, bench_there, overrides, receive, leave = false, true, true, nil, nil, nil
local stored = {}
local media, media_accepted = {}, true

minetest = {
	get_modpath = function(name)
		if name == "living_villages" then return "." end
		return minetest.schemedit_on and "/mods/schemedit" or nil
	end,
	get_worldpath = function() return WORLD end,
	settings = {get = function(_, name) return settings[name] end},
	log = function() end,
	sha1 = function(text) return "h" .. text end,
	mkdir = function(path) dirs[#dirs + 1] = path return true end,
	get_dir_list = function(directory)
		local found = {}
		for path in pairs(files) do
			local dir, file = path:match("^(.*)/([^/]+)$")
			if dir == directory then found[#found + 1] = file end
		end
		return found
	end,
	read_schematic = function() return nil end,
	dynamic_add_media = function(args, callback)
		media[#media + 1] = {args = args, callback = callback}
		return media_accepted
	end,
	safe_file_write = function(path, content) files[path] = content return true end,
	write_json = function(value) stored[#stored + 1] = value return "json" .. #stored end,
	parse_json = function(text) return stored[tonumber(text:match("%d+") or 0)] end,
	registered_nodes = {},
	registered_items = {["mcl_core:cobble"] = {description = "Cobblestone\nHard"}},
	formspec_escape = function(text) return (text:gsub("[,;%[%]\\]", "\\%0")) end,
	colorize = function(_, text) return text end,
	get_translator = function()
		return function(message, ...)
			local args = {...}
			return (message:gsub("@(%d)", function(i) return args[tonumber(i)] end))
		end
	end,
	show_formspec = function(name, form, text) shown[#shown + 1] = {name = name, form = form, text = text} end,
	close_formspec = function() closed = closed + 1 end,
	get_node_or_nil = function() return bench_there and {name = BENCH} or nil end,
	is_protected = function() return protected end,
	check_player_privs = function() return privileged end,
	explode_table_event = function(text)
		local kind, row, column = text:match("^(%u+):(%d+):(%d+)$")
		if not kind then return {type = "INV", row = 0, column = 0} end
		return {type = kind, row = tonumber(row), column = tonumber(column)}
	end,
	override_item = function(name, fields) overrides = {name = name, fields = fields} end,
	register_on_player_receive_fields = function(fn) receive = fn end,
	register_on_leaveplayer = function(fn) leave = fn end,
}
vector = {distance = function(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end}

local real_open = io.open
io.open = function(path, mode)
	if not path:find("^" .. WORLD) then return real_open(path, mode) end
	local content = files[path]
	if content == nil then return nil end
	return {
		seek = function(_, whence) return whence == "end" and #content or 0 end,
		read = function() return content end,
		close = function() end,
	}
end

local menu = dofile("builder_bench_menu.lua")

local project, options_calls, catalog_calls = nil, 0, 0
local rows = {
	default = {
		{name = "small_house", share = 0.75, built = 3, is_next = true, size = {x = 9, y = 9, z = 8}, blocks = 204},
		{name = "well", share = 0.25, built = 1, size = {x = 6, y = 7, z = 8}, blocks = 112},
	},
	select = {
		{name = "cottage", built = 2, size = {x = 5, y = 4, z = 6}, blocks = 90, price = 448,
			materials = {
				{item = "mcl_core:cobble", count = 50}, {item = "b", count = 4}, {item = "c", count = 3},
				{item = "d", count = 2}, {item = "e", count = 1},
			}},
		{name = "shed", built = 0, size = {x = 3, y = 3, z = 3}, blocks = 20, price = 320},
		{name = "alien, one", built = 0, problem = {code = "unknown_nodes", nodes = {"nope:gone", "nope:also"}}},
	},
}
local economy_report, order, priced_for
local orders, refunds = {}, {}
local builder = {
	options = function()
		options_calls = options_calls + 1
		return {rows = rows.default, reason = "every bed is taken (4)"}
	end,
	catalog_options = function(_, name)
		catalog_calls = catalog_calls + 1
		priced_for = name
		return {rows = rows.select, directory = WORLD .. "/schems"}
	end,
	order_of = function() return order end,
	place_order = function(_, who, name)
		orders[#orders + 1] = {who = who:get_player_name(), name = name}
		if order then return false, "busy" end
		if name == "shed" then return false, "no_emeralds" end
		order = {name = name, player = who:get_player_name(), price = 448, state = "waiting"}
		return true, 448
	end,
	refund = function(_, who)
		refunds[#refunds + 1] = who:get_player_name()
		if order and order.state == "failed" and order.player == who:get_player_name() then
			local price = order.price
			order = nil
			return true, price
		end
		return false, "no_refund"
	end,
	load_project = function() return project end,
	economy = function() return economy_report end,
}
menu.install(builder)

local function player(name, pos)
	return {
		get_player_name = function() return name or "ann" end,
		get_pos = function() return pos or {x = 1, y = 1, z = 1} end,
		is_player = function() return true end,
	}
end
local function has(form, text) return form:find(text, 1, true) ~= nil end
local function last() return shown[#shown].text end
local function send(fields, who) return receive(who or player(), menu.FORM, fields) end
local function click()
	return overrides.fields.on_rightclick(BENCH_POS, nil, player(), "stack")
end

-- It takes over the bench's right-click, and hands the wielded item back.
assert(overrides.name == BENCH)
assert(click() == "stack")
assert(shown[#shown].name == "ann" and shown[#shown].form == menu.FORM)
assert(has(last(), "formspec_version[4]"))
-- A non-player clicking opens nothing.
do
	local before = #shown
	overrides.fields.on_rightclick(BENCH_POS, nil, nil, "stack")
	overrides.fields.on_rightclick(BENCH_POS, nil, {is_player = function() return false end}, "stack")
	assert(#shown == before)
end

-- Other forms are not its business.
assert(receive(player(), "other", {}) == false)

-- Default tab: a row per building of the mix, first selected, what is next and why; nothing to order.
do
	local form = last()
	assert(has(form, "tabheader[0,0;tabs;Default,Select schematic,Economy;1;false;false]"))
	assert(has(form, "The Builder builds what the village needs."))
	assert(has(form, "Small house") and has(form, "75%") and has(form, "Well"))
	assert(has(form, ";projects;") and form:find(";2]", 1, true), "first building selected, past the header")
	assert(has(form, "Size: 9 by 8\\, 9 high") and has(form, "Blocks: 204") and has(form, "Next to be built"))
	assert(has(form, "Next\\, because every bed is taken (4)."))
	assert(not has(form, "order;"))
	-- An order button sent on this tab does nothing.
	send({order = "x"})
	assert(#orders == 0)
end

-- Select schematic: the directory's schematics, priced for this player.
do
	send({tabs = "2"})
	local form = last()
	assert(has(form, ";2;false") and priced_for == "ann")
	assert(has(form, "Cottage") and has(form, "Files from <world>/schems"))
	assert(has(form, "448") and has(form, "Price"))
	-- Only the first four materials, first lines of their descriptions.
	assert(has(form, "50 Cobblestone") and not has(form, "Hard"))
	assert(has(form, "0.6,0.6;mcl_core:cobble]") and has(form, "0.6,0.6;d]") and not has(form, "0.6,0.6;e]"))
	assert(has(form, ";order;Order for 448 emeralds]"))
	assert(not has(form, "Share:"))
end

-- Selecting reads nothing again. Row 1 is the header, and a stale row does nothing.
do
	local before = catalog_calls
	send({projects = "CHG:3:2"})
	assert(has(last(), "Order for 320 emeralds") and has(last(), "Shed"))
	send({projects = "CHG:1:2"})
	assert(has(last(), "Order for 320 emeralds"), "the header is not a building")
	send({projects = "CHG:99:1"})
	send({projects = "INV"})
	assert(has(last(), "Order for 320 emeralds"))
	assert(catalog_calls == before)
end

-- A schematic that cannot be built says why, its name escaped, and has no price.
do
	send({projects = "CHG:4:1"})
	local form = last()
	assert(has(form, "Alien\\, one"))
	assert(has(form, "Uses blocks this world does not have: nope:gone\\, nope:also"))
	assert(not has(form, "order;"))
end

-- Refresh reads again. Clicking a tab already showing does not.
do
	send({projects = "CHG:2:1"})
	local before = catalog_calls
	send({refresh = "Refresh"})
	assert(catalog_calls == before + 1)
	send({tabs = "2"})
	assert(catalog_calls == before + 1)
end

-- Ordering: what the builder refuses is said; the order is the server's selection.
do
	send({projects = "CHG:3:1"})
	send({order = "Order", selected = "../../secrets", name = "cottage"})
	assert(orders[#orders].name == "shed" and orders[#orders].who == "ann")
	assert(has(last(), "You do not have the emeralds.") and order == nil)
	send({projects = "CHG:2:1"})
	send({order = "Order"})
	assert(orders[#orders].name == "cottage")
	local form = last()
	assert(has(form, "Ordered for 448 emeralds."))
	assert(has(form, "Ordered by ann: Cottage\\, to be started when the Builder is free."))
	assert(not has(form, "order;"), "one order at a time")
	order.state = "started"
	send({refresh = "Refresh"})
	assert(has(last(), "The Builder is looking for a site."))
end

-- A protected bench: only looking.
do
	local count = #orders
	order = nil
	protected = true
	send({refresh = "Refresh"})
	assert(not has(last(), "order;") and has(last(), "This bench is protected") and has(last(), "Price: 448 emeralds"))
	send({order = "Order"})
	assert(#orders == count and has(last(), "This bench is protected"))
	protected = false
end

-- No site: the player who paid sees the refund button and takes it; nobody else does.
do
	order = {name = "cottage", player = "ann", price = 448, state = "failed"}
	overrides.fields.on_rightclick(BENCH_POS, nil, player("bob"), "stack")
	send({tabs = "2"}, player("bob"))
	assert(has(last(), "No site was found for ann's Cottage. 448 emeralds can be refunded to them."))
	assert(not has(last(), ";refund;"))
	send({refund = "x"}, player("bob"))
	assert(has(last(), "There is nothing to refund to you.") and order ~= nil)
	send({quit = "true"}, player("bob"))
	send({refresh = "Refresh"})
	assert(has(last(), ";refund;Take the refund]"))
	send({refund = "x"})
	assert(order == nil and has(last(), "448 emeralds refunded."))
	assert(has(last(), "order;Order for"), "free to order again")
end

-- What it is doing now, on the Default tab.
do
	send({tabs = "1"})
	project = {building = "small_house", state = "requires_materials"}
	send({refresh = "Refresh"})
	assert(has(last(), "Now: Small house\\, requires materials"))
	project = nil
	send({tabs = "2"})
end

-- An empty directory says so.
do
	local kept = rows.select
	rows.select = {}
	send({refresh = "Refresh"})
	assert(has(last(), "Nothing here yet."))
	rows.select = kept
	send({refresh = "Refresh"})
end

-- A selection that has left the directory falls to the first row.
do
	send({projects = "CHG:3:1"})
	local kept = rows.select
	rows.select = {kept[1]}
	send({refresh = "Refresh"})
	assert(has(last(), "Cottage") and not has(last(), "Shed"))
	rows.select = kept
end

-- A picture: sent on selection, shown on arrival, in place of the materials and in its shape.
do
	local DIR = WORLD .. "/schems"
	local PNG = "\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\1\144\0\0\0\200"
	files[DIR .. "/cottage.png"] = PNG
	-- Off the cottage before it has a picture, so that nothing goes out yet.
	send({refresh = "Refresh"})
	send({projects = "CHG:3:1"})
	local with_image = rows.select[1]
	with_image.image = "cottage.png"
	media = {}
	send({projects = "CHG:3:1"})
	assert(#media == 0, "nothing is sent for what nobody looks at")
	send({projects = "CHG:2:1"})
	assert(#media == 1 and media[1].args.to_player == "ann" and media[1].args.filepath == DIR .. "/cottage.png")
	local texture = media[1].args.filename
	assert(texture:find("^living_villages_preview_") and texture:find("%.png$"))
	assert(not has(last(), "]image[9") and has(last(), "50 Cobblestone"), "materials until it arrives")

	-- Looking again while it is on its way does not send it again.
	send({projects = "CHG:2:1"})
	assert(#media == 1, "not sent while on its way")

	-- Selecting something else meanwhile: its arrival does not pull the window back.
	send({projects = "CHG:3:1"})
	local count = #shown
	media[1].callback("ann")
	assert(#shown == count)
	send({projects = "CHG:2:1"})
	assert(#media == 1, "not sent twice")
	assert(has(last(), texture) and not has(last(), "50 Cobblestone"))
	-- 400 by 200 in a 5 by 2.7 box.
	assert(has(last(), "image[9.60,2.42;5.00,2.50;" .. texture .. "]"))

	-- Arriving while it is being looked at shows it at once.
	files[DIR .. "/cottage.png"] = PNG .. "edited"
	send({refresh = "Refresh"})
	assert(#media == 2 and not has(last(), "]image[9"))
	count = #shown
	media[2].callback("ann")
	assert(#shown == count + 1 and has(last(), media[2].args.filename))

	-- Another player gets their own copy.
	overrides.fields.on_rightclick(BENCH_POS, nil, player("bob"), "stack")
	send({tabs = "2"}, player("bob"))
	assert(media[3].args.to_player == "bob")
	leave(player("bob"))
	-- Not one that closed the window before it came.
	overrides.fields.on_rightclick(BENCH_POS, nil, player("cy"), "stack")
	send({tabs = "2"}, player("cy"))
	send({quit = "true"}, player("cy"))
	count = #shown
	media[#media].callback("cy")
	assert(#shown == count)

	-- Leaving forgets what a client was sent.
	click()
	send({tabs = "2"})
	local before = #media
	leave(player())
	click()
	send({tabs = "2"})
	assert(#media == before + 1, "a client back again needs it again")

	-- What the engine refuses, or no real picture, leaves the materials.
	files[DIR .. "/cottage.png"] = PNG .. "again"
	media_accepted = false
	send({refresh = "Refresh"})
	assert(not has(last(), "]image[9") and has(last(), "50 Cobblestone"))
	media_accepted = true
	before = #media
	files[DIR .. "/cottage.png"] = "not a picture at all"
	send({refresh = "Refresh"})
	assert(#media == before and not has(last(), "]image[9") and has(last(), "50 Cobblestone"))
	with_image.image = nil
	files[DIR .. "/cottage.png"] = nil
end

-- Too far, or the bench gone: the window closes and nothing is done.
do
	click()
	send({tabs = "2"})
	local before, count = closed, #orders
	send({order = "Order"}, player("ann", {x = 50, y = 1, z = 0}))
	assert(closed == before + 1 and #orders == count)
	local shown_count = #shown
	send({order = "Order"})
	assert(#shown == shown_count and #orders == count, "that window is forgotten")

	click()
	send({tabs = "2"})
	bench_there = false
	send({order = "Order"})
	assert(closed == before + 2 and #orders == count)
	bench_there = true
end

-- Quit and leaving forget it; a late send is ignored. Fields it does not know change nothing.
do
	click()
	local count = #shown
	send({bogus = "1"})
	assert(#shown == count)
	send({quit = "true"})
	send({refresh = "Refresh"})
	assert(#shown == count)
	click()
	leave(player())
	count = #shown
	send({refresh = "Refresh"})
	assert(#shown == count)
end

-- Two players have their own views.
do
	click()
	overrides.fields.on_rightclick(BENCH_POS, nil, player("bob"), "stack")
	send({tabs = "2"}, player("bob"))
	assert(shown[#shown].name == "bob" and has(last(), ";2;false"))
	send({refresh = "Refresh"})
	assert(shown[#shown].name == "ann" and has(last(), ";1;false"))
end

-- The Economy tab: what the Builder heard, and what is seen around the bench.
do
	click()
	local calls = options_calls
	economy_report = {
		heard = true,
		present = {farmer = 2, builder = 1, weapon_smith = 1},
		shortages = {{item = "mcl_core:cobble", count = 12, villagers = 2, worth = 3}},
		gluts = {},
		gaps = {{profession = "mason", score = 3, items = {"mcl_core:cobble"}}},
		idle = {{id = "nit123456", profession = "nitwit", activity = "forager"}, {id = "une", profession = "unemployed"}},
		today = {made = {{item = "mcl_core:cobble", count = 4}}, used = {}},
		yesterday = {made = {}, used = {}},
	}
	send({tabs = "3"})
	local form = last()
	assert(has(form, "Select schematic,Economy;3;"))
	assert(has(form, "Heard by the Builder") and has(form, "Seen around the bench"))
	assert(has(form, "item_image[") and has(form, "12 Cobblestone\\, 2 villagers"), form)
	assert(has(form, "No glut heard of."))
	assert(has(form, "Mason (Cobblestone)") and has(form, "A building for the first comes when nothing is more pressing."))
	assert(has(form, "Builder 1\\, Farmer 2\\, Weapon smith 1"))
	assert(has(form, "Nitwit nit123: forager\\, Unemployed une: nothing to do"))
	assert(has(form, "Made: 4 Cobblestone") and has(form, "Used: nothing"))
	assert(not has(form, "order;") and options_calls == calls, "only looks")
	-- Refresh reads it again.
	economy_report.gluts = {{item = "mcl_core:cobble", count = 40, villagers = 1, worth = 5}}
	send({refresh = "Refresh"})
	assert(has(last(), "40 Cobblestone"))
	-- Without the Builder near, nothing heard; with the economy off, it says so.
	economy_report = {heard = false, present = {}, idle = {},
		today = {made = {}, used = {}}, yesterday = {made = {}, used = {}}}
	send({refresh = "Refresh"})
	assert(has(last(), "no news to tell") and has(last(), "No villagers loaded.") and has(last(), "None."))
	economy_report = nil
	send({refresh = "Refresh"})
	assert(has(last(), "economy is off"))
	-- Back to the Default tab.
	send({tabs = "1"})
	assert(has(last(), ";1;false") and has(last(), "Small house"))
end

io.open = real_open
print("builder_bench_menu: ok")
