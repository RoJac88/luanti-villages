-- Run with: lua tests/builder_catalog.lua
-- Files are a table standing in for the disk, through io.open and the engine's calls.
local stock_world = dofile("tests/support/stock_world.lua")
stock_world.install(stock_world.new())

local WORLD = "/world"
local files = {}
local schematics = {}
local settings = {}
local logged = {}

io.open = function(path)
	local content = files[path]
	if content == nil then return nil end
	local at = 0
	return {
		seek = function(_, whence, offset)
			at = whence == "end" and #content or (offset or 0)
			return at
		end,
		read = function() return content end,
		close = function() end,
	}
end

minetest.get_worldpath = function() return WORLD end
minetest.settings = {get = function(_, name) return settings[name] end}
minetest.log = function(level, message) logged[#logged + 1] = {level, message} end
minetest.sha1 = function(content) return "sha:" .. content end
minetest.get_dir_list = function(directory)
	local found = {}
	for path in pairs(files) do
		local dir, file = path:match("^(.*)/([^/]+)$")
		if dir == directory then found[#found + 1] = file end
	end
	return found
end
minetest.read_schematic = function(path)
	local schematic = schematics[files[path]]
	if schematic == "throws" then error("corrupt") end
	return schematic
end
-- JSON is the engine's business: this keeps the table, or says no.
local stored = {}
minetest.write_json = function(value)
	local id = "json" .. (#stored + 1)
	stored[#stored + 1] = value
	stored[id] = value
	return id
end
minetest.parse_json = function(text)
	return stored[text]
end
local write_ok = true
minetest.safe_file_write = function(path, content)
	if write_ok then files[path] = content end
	return write_ok
end

local catalog = dofile("builder_catalog.lua")
local site = dofile("builder_site.lua")

-- A size.x by size.y by size.z block of one node.
local function solid(x, y, z, name, prob)
	local data = {}
	for i = 1, x * y * z do data[i] = {name = name or "mcl_core:cobble", prob = prob or 254} end
	return {size = {x = x, y = y, z = z}, data = data}
end

local function add(directory, name, schematic)
	local content = directory .. "/" .. name
	files[directory .. "/" .. name .. ".mts"] = content
	schematics[content] = schematic
end

local function entry_of(result, name)
	for _, entry in ipairs(result.entries) do
		if entry.name == name then return entry end
	end
end

local function near(a, b)
	return math.abs(a - b) < 1e-9
end

-- Where each source reads from, and the setting cannot climb out of the world.
assert(catalog.directory(catalog.SCHEMEDIT) == WORLD .. "/schems")
assert(catalog.directory(catalog.FOLDER) == WORLD .. "/builder_schems")
assert(catalog.directory("stock") == nil and catalog.directory(nil) == nil)
settings.living_villages_builder_schem_dir = "packs/castles"
assert(catalog.directory(catalog.FOLDER) == WORLD .. "/packs/castles")
for _, bad in ipairs({"../other", "a/../..", "/etc", "a//b", "a/", "a\\b", ".", "..", "a b"}) do
	settings.living_villages_builder_schem_dir = bad
	assert(not catalog.valid_folder(bad), bad)
	assert(catalog.directory(catalog.FOLDER) == WORLD .. "/builder_schems", bad)
end
assert(logged[#logged][1] == "warning")
settings.living_villages_builder_schem_dir = nil

local DIR = WORLD .. "/schems"

-- Listing takes .mts files only, whatever the case of the suffix, in order.
files[DIR .. "/zeta.mts"] = "x"
files[DIR .. "/alpha.MTS"] = "x"
files[DIR .. "/alpha.png"] = "x"
files[DIR .. "/notes.txt"] = "x"
files[DIR .. "/.mts"] = "x"
files[DIR .. "/nested/inner.mts"] = "x"
do
	local names = catalog.list(DIR)
	assert(#names == 2 and names[1] == "alpha" and names[2] == "zeta")
	assert(#catalog.list(WORLD .. "/nothing_here") == 0)
end
files = {}

-- A schematic's facts, voids and air not counting.
do
	local schematic = solid(3, 1, 1)
	schematic.data[2] = {name = "air", prob = 254}
	schematic.data[3] = {name = "mcl_core:cobble", prob = 0}
	local measured = catalog.measure(schematic)
	assert(measured.blocks == 1 and measured.materials[1].item == "mcl_core:cobble" and measured.materials[1].count == 1)
	assert(#measured.unknown == 0 and #measured.no_item == 0)
	-- A void of a node that does not exist here is no problem either.
	schematic.data[3].name = "nope:gone"
	assert(#catalog.measure(schematic).unknown == 0)
	-- A low-probability cell may still be placed, so it counts.
	schematic.data[3] = {name = "nope:gone", prob = 2}
	assert(catalog.measure(schematic).unknown[1] == "nope:gone")
end

-- Materials come most-used first, then by name.
do
	local schematic = solid(4, 1, 1)
	schematic.data[1].name = "mcl_core:wood"
	schematic.data[2].name = "mcl_core:brick_block"
	local list = catalog.measure(schematic).materials
	assert(list[1].item == "mcl_core:cobble" and list[1].count == 2)
	assert(list[2].item == "mcl_core:brick_block" and list[3].item == "mcl_core:wood")
end

-- Reach is from the ring's outer row, at standing height, to the worst low block, and from a
-- column on the ring's inner row, level with it, to the worst high one.
do
	-- One block: 2 across (the ring), level with where it stands at y 1 once raised.
	local flat = solid(1, 2, 1)
	flat.data[1].name = "air"
	assert(near(catalog.measure(flat).reach, 2))
	-- The middle of a 9 wide floor at y 0 is 4 + 2 across and 1 down.
	assert(near(catalog.measure(solid(9, 1, 9)).reach, math.sqrt(37)))
	-- A column 12 high: its worst low block is at y 5, 4 up; above that, from scaffolding, 1 across.
	assert(near(catalog.measure(solid(1, 12, 1)).reach, math.sqrt(4 + 16)))
	-- With scaffolding only above 10, y 10 is reached from the ground.
	assert(near(catalog.measure(solid(1, 12, 1), nil, 10).reach, math.sqrt(4 + 81)))
	-- A 21 wide roof at y 20: its middle is 10 in from a side, 11 from the column.
	local roof = solid(21, 21, 21)
	for i, cell in ipairs(roof.data) do
		local y = math.floor((i - 1) / 21) % 21
		if y ~= 20 then cell.name = "air" end
	end
	assert(near(catalog.measure(roof).reach, 11))
	-- So a building 32 high can be built, which it could not when height counted.
	assert(near(catalog.measure(solid(5, 32, 5)).reach, math.sqrt(16 + 16)))
end

-- Each way a schematic can be turned down.
do
	local function problem(measured_fields)
		local measured = {size = {x = 5, y = 5, z = 5}, blocks = 10, reach = 5, unknown = {}, no_item = {}}
		for key, value in pairs(measured_fields) do measured[key] = value end
		return catalog.problem_of(measured, 14)
	end
	assert(problem({}) == nil)
	assert(problem({unknown = {"a:b"}}).code == "unknown_nodes" and problem({unknown = {"a:b"}}).nodes[1] == "a:b")
	assert(problem({no_item = {"a:b"}}).code == "no_item")
	assert(problem({blocks = 0}).code == "empty")
	assert(problem({size = {x = 50, y = 20, z = 65}}).code == "too_big")
	assert(problem({size = {x = 5, y = 33, z = 5}}).code == "too_tall")
	assert(problem({size = {x = 5, y = 32, z = 5}}) == nil)
	assert(catalog.MAX_HEIGHT <= site.config.above, "the site search reads high enough")
	local far = problem({reach = 18.2})
	assert(far.code == "out_of_reach" and far.needs == 19 and far.reach == 14)
	assert(problem({reach = 14}) == nil)
end

-- Every stock building passes, on the nodes it really uses: the rules must not turn down
-- what a Builder already puts up. The fixtures only define the nodes inside schematics, not
-- every item those cost, so whether the items exist takes a run on the real engine.
minetest.registered_items = setmetatable({}, {__index = function() return {groups = {}} end})
for _, building in ipairs({
	"belltower", "blacksmith", "butcher", "church", "farm", "lamp", "large_house", "library",
	"medium_house", "small_house", "tavern", "well",
}) do
	local fixture = dofile("tests/fixtures/buildings/" .. building .. ".lua")
	local data = {}
	for i, id in ipairs(fixture.ids) do data[i] = {name = fixture.names[id + 1], prob = 254} end
	local measured = catalog.measure({size = fixture.size, data = data})
	local problem = catalog.problem_of(measured, site.config.reach)
	assert(problem == nil, building .. ": " .. (problem and problem.code or "") .. " "
		.. table.concat(problem and problem.nodes or {tostring(problem and problem.needs)}, ", "))
end

minetest.registered_items = nil

-- A scan: weights from the manifest, shares over what can be built.
add(DIR, "cottage", solid(3, 2, 3))
add(DIR, "tower", solid(2, 3, 2))
add(DIR, "shed", solid(2, 2, 2))
add(DIR, "broken", solid(2, 2, 2, "nope:gone"))
add(DIR, "banned", solid(1, 2, 1))
files[DIR .. "/garbage.mts"] = "garbage"
files[DIR .. "/throwing.mts"] = "throwing"
schematics.throwing = "throws"
files[DIR .. "/" .. catalog.MANIFEST] = minetest.write_json({version = 1, projects = {
	cottage = {weight = 3}, tower = {weight = 2}, banned = {weight = 0},
	broken = {weight = 50}, removed = {weight = 9},
}})
do
	local result = catalog.scan(catalog.SCHEMEDIT)
	assert(result.directory == DIR and result.manifest_problem == nil)
	assert(#result.entries == 7)
	assert(result.entries[1].name == "banned" and result.entries[7].name == "tower")
	local cottage, tower, shed = entry_of(result, "cottage"), entry_of(result, "tower"), entry_of(result, "shed")
	assert(cottage.weight == 3 and near(cottage.share, 0.5))
	assert(tower.weight == 2 and near(tower.share, 2 / 6))
	assert(shed.weight == catalog.DEFAULT_WEIGHT and near(shed.share, 1 / 6))
	assert(cottage.measured.blocks == 18 and cottage.hash == "sha:" .. DIR .. "/cottage")
	-- Weight 0 keeps its row with no share; what cannot be built keeps its weight, without a share.
	local banned = entry_of(result, "banned")
	assert(banned.weight == 0 and banned.share == 0 and banned.problem == nil)
	local broken = entry_of(result, "broken")
	assert(broken.weight == 50 and broken.share == 0 and broken.problem.code == "unknown_nodes")
	-- Junk is a row saying so, not an error.
	assert(entry_of(result, "garbage").problem.code == "unreadable")
	assert(entry_of(result, "throwing").problem.code == "unreadable")
end

-- The reach setting decides, on the same measurement.
do
	add(DIR, "wide", solid(31, 2, 31))
	assert(entry_of(catalog.scan(catalog.SCHEMEDIT), "wide").problem.code == "out_of_reach")
	settings.living_villages_builder_reach = "18"
	assert(entry_of(catalog.scan(catalog.SCHEMEDIT), "wide").problem == nil)
	settings.living_villages_builder_reach = nil
	files[DIR .. "/wide.mts"] = nil
end

-- An unchanged file is parsed once; a changed one is read again under the same name.
do
	local reads = 0
	local real = minetest.read_schematic
	minetest.read_schematic = function(path)
		reads = reads + 1
		return real(path)
	end
	add(DIR, "edited", solid(2, 2, 2))
	catalog.scan(catalog.SCHEMEDIT)
	local after_first = reads
	catalog.scan(catalog.SCHEMEDIT)
	assert(reads == after_first, "nothing is parsed twice, the files that failed included")
	files[DIR .. "/edited.mts"] = "edited, version two"
	schematics["edited, version two"] = solid(3, 3, 3)
	assert(entry_of(catalog.scan(catalog.SCHEMEDIT), "edited").measured.blocks == 27)
	minetest.read_schematic = real
	files[DIR .. "/edited.mts"] = nil
end

-- A file over the limit is not read at all.
do
	files[DIR .. "/huge.mts"] = string.rep("x", catalog.MAX_FILE_BYTES + 1)
	assert(entry_of(catalog.scan(catalog.SCHEMEDIT), "huge").problem.code == "file_too_big")
	files[DIR .. "/huge.mts"] = nil
end

-- Bad weights in a manifest read as the default.
do
	local manifest = {projects = {
		cottage = {weight = -1}, tower = {weight = "lots"}, shed = {weight = 1e9}, banned = "three",
	}}
	files[DIR .. "/" .. catalog.MANIFEST] = minetest.write_json(manifest)
	local result = catalog.scan(catalog.SCHEMEDIT)
	for _, name in ipairs({"cottage", "tower", "shed", "banned"}) do
		assert(entry_of(result, name).weight == catalog.DEFAULT_WEIGHT, name)
	end
end

-- A picture beside a schematic, whatever the case of its suffix. PNG beats JPEG.
do
	files[DIR .. "/cottage.jpeg"], files[DIR .. "/cottage.PNG"] = "x", "x"
	files[DIR .. "/tower.JPG"] = "x"
	files[DIR .. "/stray.png"], files[DIR .. "/shed.txt"] = "x", "x"
	local result = catalog.scan(catalog.SCHEMEDIT)
	assert(entry_of(result, "cottage").image == "cottage.PNG")
	assert(entry_of(result, "tower").image == "tower.JPG")
	assert(entry_of(result, "shed").image == nil and entry_of(result, "stray") == nil)
	files[DIR .. "/cottage.jpeg"], files[DIR .. "/cottage.PNG"], files[DIR .. "/tower.JPG"] = nil, nil, nil
	files[DIR .. "/stray.png"], files[DIR .. "/shed.txt"] = nil, nil
end

-- All weights 0: nothing to pick, and nothing divided by zero.
do
	local projects = {}
	for _, name in ipairs(catalog.list(DIR)) do projects[name] = {weight = 0} end
	files[DIR .. "/" .. catalog.MANIFEST] = minetest.write_json({projects = projects})
	for _, entry in ipairs(catalog.scan(catalog.SCHEMEDIT).entries) do assert(entry.share == 0) end
end

-- No manifest at all, and a directory with nothing in it.
do
	files[DIR .. "/" .. catalog.MANIFEST] = nil
	assert(near(entry_of(catalog.scan(catalog.SCHEMEDIT), "cottage").share, 1 / 4))
	local empty = catalog.scan(catalog.FOLDER)
	assert(#empty.entries == 0 and empty.manifest_problem == nil)
	assert(catalog.scan("stock") == nil)
end

-- Clean weights.
assert(catalog.clean_weight("3") == 3 and catalog.clean_weight(0) == 0 and catalog.clean_weight(0.5) == 0.5)
for _, bad in ipairs({-1, 1001, "many", 0 / 0, 1 / 0}) do assert(catalog.clean_weight(bad) == nil) end
assert(catalog.clean_weight(nil) == nil)

-- Setting a weight creates the manifest, then keeps what else is in it.
do
	assert(catalog.set_weight(DIR, "cottage", "4"))
	local path = DIR .. "/" .. catalog.MANIFEST
	assert(entry_of(catalog.scan(catalog.SCHEMEDIT), "cottage").weight == 4)
	local manifest = minetest.parse_json(files[path])
	manifest.note = "mine"
	manifest.projects.cottage.replace_materials = true
	files[path] = minetest.write_json(manifest)
	assert(catalog.set_weight(DIR, "cottage", 7))
	assert(catalog.set_weight(DIR, "tower", 0))
	manifest = minetest.parse_json(files[path])
	assert(manifest.note == "mine" and manifest.projects.cottage.replace_materials == true)
	assert(manifest.projects.cottage.weight == 7 and manifest.projects.tower.weight == 0)
end

-- What it refuses, leaving the file alone.
do
	local path = DIR .. "/" .. catalog.MANIFEST
	local before = files[path]
	local ok, why = catalog.set_weight(DIR, "cottage", "lots")
	assert(ok == false and why == "bad_weight")
	ok, why = catalog.set_weight(DIR, "../../secrets", 1)
	assert(ok == false and why == "no_file")
	assert(files[path] == before)
	write_ok = false
	ok, why = catalog.set_weight(DIR, "cottage", 2)
	assert(ok == false and why == "write_failed")
	write_ok = true
end

-- A manifest that cannot be read is reported, read as defaults and never written over.
for _, broken in ipairs({"{ not json", "number", "projects_not_table"}) do
	local path = DIR .. "/" .. catalog.MANIFEST
	stored.number = 5
	stored.projects_not_table = {projects = "nope"}
	files[path] = broken
	local result = catalog.scan(catalog.SCHEMEDIT)
	assert(result.manifest_problem == "malformed", broken)
	assert(entry_of(result, "cottage").weight == catalog.DEFAULT_WEIGHT)
	local ok, why = catalog.set_weight(DIR, "cottage", 5)
	assert(ok == false and why == "malformed", broken)
	assert(files[path] == broken)
end

print("builder_catalog: ok")
