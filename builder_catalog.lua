-- The buildings a bench can draw on besides the stock ones: the .mts files of a directory,
-- with a weight for each from that directory's builder_projects.json, and whether a Builder
-- could actually put each one up. schemedit has no API and always exports to <world>/schems,
-- so all that integrating with it takes is reading that directory.
--
-- Mod security only lets a mod list and read inside the world and loaded mods, and refuses
-- symlinks out, so the project folder is a path inside the world. It comes from a setting and
-- never from a player.
--
-- A player's schematic has had none of the checks a stock building has, so nothing is taken on
-- trust. An unknown node would silently place as air, and a block nobody can supply would keep
-- a Builder waiting for ever.
local core = minetest
local materials = dofile(core.get_modpath("living_villages") .. "/builder_materials.lua")
local site = dofile(core.get_modpath("living_villages") .. "/builder_site.lua")

local M = {}

M.SCHEMEDIT, M.FOLDER = "schemedit", "folder"
M.MANIFEST = "builder_projects.json"
M.DEFAULT_FOLDER = "builder_schems"
M.DEFAULT_WEIGHT = 1
M.MAX_WEIGHT = 1000
M.MAX_FILE_BYTES = 1024 * 1024
-- Every cell becomes a table in a Builder's plan, on the main thread.
M.MAX_VOLUME = 64000

local DEFAULT_REACH = 14

local function setting_number(engine, name, default)
	return tonumber(engine.settings and engine.settings:get(name)) or default
end

-- A relative path of plain names, so it cannot climb out of the world.
function M.valid_folder(path)
	if type(path) ~= "string" or path == "" then return false end
	for part in (path .. "/"):gmatch("(.-)/") do
		if not part:match("^[%w_%-]+$") then return false end
	end
	return true
end

-- The directory of a source, or nil for one that has none, such as the stock buildings.
function M.directory(source, engine)
	engine = engine or core
	if source == M.SCHEMEDIT then return engine.get_worldpath() .. "/schems" end
	if source ~= M.FOLDER then return nil end
	local folder = engine.settings and engine.settings:get("living_villages_builder_schem_dir")
	if folder == nil or folder == "" then
		folder = M.DEFAULT_FOLDER
	elseif not M.valid_folder(folder) then
		engine.log("warning", "[living_villages] living_villages_builder_schem_dir must be a path inside the world; using "
			.. M.DEFAULT_FOLDER)
		folder = M.DEFAULT_FOLDER
	end
	return engine.get_worldpath() .. "/" .. folder
end

-- The schematics of a directory, as names without the suffix, sorted. Missing is empty.
function M.list(directory, engine)
	engine = engine or core
	local names = {}
	for _, file in ipairs(engine.get_dir_list(directory, false) or {}) do
		local name = file:match("^(.+)%.[mM][tT][sS]$")
		if name then names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

-- The manifest as a table, empty if there is none. nil and "malformed" for a file that is
-- there but cannot be read, which must not be written over: it is a player's work.
function M.read_manifest(directory, engine)
	engine = engine or core
	local file = io.open(directory .. "/" .. M.MANIFEST, "rb")
	if not file then return {} end
	local text = file:read("*a")
	file:close()
	local manifest = engine.parse_json(text)
	if type(manifest) ~= "table" then return nil, "malformed" end
	if manifest.projects ~= nil and type(manifest.projects) ~= "table" then return nil, "malformed" end
	return manifest
end

-- A weight as given, or nil for what is not one. NaN fails both comparisons.
function M.clean_weight(value)
	local weight = tonumber(value)
	if not weight or not (weight >= 0 and weight <= M.MAX_WEIGHT) then return nil end
	return weight
end

local function weight_of(manifest, name)
	local entry = manifest.projects and manifest.projects[name]
	return type(entry) == "table" and M.clean_weight(entry.weight) or M.DEFAULT_WEIGHT
end

-- Sets one building's weight. Returns true, or false and "bad_weight", "no_file", "malformed"
-- or "write_failed". Other fields of the manifest are kept.
function M.set_weight(directory, name, value, engine)
	engine = engine or core
	local weight = M.clean_weight(value)
	if not weight then return false, "bad_weight" end
	local known = false
	for _, listed in ipairs(M.list(directory, engine)) do known = known or listed == name end
	if not known then return false, "no_file" end
	local manifest, problem = M.read_manifest(directory, engine)
	if not manifest then return false, problem end
	manifest.version = manifest.version or 1
	manifest.projects = manifest.projects or {}
	if type(manifest.projects[name]) ~= "table" then manifest.projects[name] = {} end
	manifest.projects[name].weight = weight
	if not engine.safe_file_write(directory .. "/" .. M.MANIFEST, engine.write_json(manifest, true)) then
		return false, "write_failed"
	end
	return true
end

local function sorted_keys(set)
	local keys = {}
	for key in pairs(set) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

-- The facts of a schematic table (read_schematic's: x fastest, then y, then z; a prob of 0
-- is a void, which places nothing). Cells that may place count, however unlikely.
-- `reach` is how far a Builder must reach, from the ring it works from, for its worst block.
function M.measure(schematic, engine)
	engine = engine or core
	local size = schematic.size
	local ring = site.config.ring
	local unknown, no_item, bill = {}, {}, {}
	local blocks, reach = 0, 0
	for i, cell in ipairs(schematic.data) do
		local name = cell.name
		if name ~= "air" and name ~= "ignore" and (cell.prob or 255) > 0 then
			if not engine.registered_nodes[name] then
				unknown[name] = true
			else
				local cost, problem = materials.custom_cost(name, engine)
				if problem then no_item[name] = true end
				if cost then
					blocks = blocks + 1
					for item, count in pairs(cost) do bill[item] = (bill[item] or 0) + count end
					local x = (i - 1) % size.x
					local y = math.floor((i - 1) / size.x) % size.y
					local z = math.floor((i - 1) / (size.x * size.y))
					-- It stands on the ground at y 1, in the ring's outer row.
					local across = math.min(x, size.x - 1 - x, z, size.z - 1 - z) + ring
					reach = math.max(reach, math.sqrt(across * across + (y - 1) * (y - 1)))
				end
			end
		end
	end
	local materials_list = {}
	for item, count in pairs(bill) do materials_list[#materials_list + 1] = {item = item, count = count} end
	table.sort(materials_list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.item < b.item
	end)
	return {
		size = {x = size.x, y = size.y, z = size.z}, blocks = blocks, reach = reach, materials = materials_list,
		unknown = sorted_keys(unknown), no_item = sorted_keys(no_item),
	}
end

-- Why a measured schematic cannot be built, as {code, ...}, or nil if it can.
function M.problem_of(measured, reach)
	if #measured.unknown > 0 then return {code = "unknown_nodes", nodes = measured.unknown} end
	if #measured.no_item > 0 then return {code = "no_item", nodes = measured.no_item} end
	if measured.blocks == 0 then return {code = "empty"} end
	local size = measured.size
	if size.x * size.y * size.z > M.MAX_VOLUME then return {code = "too_big", limit = M.MAX_VOLUME} end
	-- builder_site.lua reads the map this far above the bench, and turns down anything taller.
	if size.y > site.config.above then return {code = "too_tall", limit = site.config.above} end
	if measured.reach > reach then return {code = "out_of_reach", needs = math.ceil(measured.reach), reach = reach} end
	return nil
end

-- A file's content is what is measured, so an edit needs no restart and an unchanged file
-- is not parsed again each time a menu opens.
local measured_by_hash = {}

local function examine(path, engine)
	local file = io.open(path, "rb")
	if not file then return nil, {code = "unreadable"} end
	local bytes = file:seek("end")
	if bytes > M.MAX_FILE_BYTES then
		file:close()
		return nil, {code = "file_too_big", limit = M.MAX_FILE_BYTES}
	end
	file:seek("set", 0)
	local content = file:read("*a")
	file:close()
	local hash = engine.sha1(content)
	if measured_by_hash[hash] == nil then
		-- Never place a directory's schematic by path: the engine would then keep serving
		-- that copy for the path, whatever the file later becomes.
		local ok, schematic = pcall(engine.read_schematic, path, {})
		measured_by_hash[hash] = ok and schematic and schematic.data and M.measure(schematic, engine) or false
	end
	if not measured_by_hash[hash] then return nil, {code = "unreadable"}, hash end
	return measured_by_hash[hash], nil, hash
end

-- Everything a menu shows of a source: {directory, entries, manifest_problem}. An entry is
-- {name, weight, share, hash, measured, problem}, sorted by name. Shares sum to 1 over what
-- can be built; a building that cannot be built, or has weight 0, has a share of 0.
function M.scan(source, engine)
	engine = engine or core
	local directory = M.directory(source, engine)
	if not directory then return nil end
	local manifest, manifest_problem = M.read_manifest(directory, engine)
	manifest = manifest or {}
	local reach = setting_number(engine, "living_villages_builder_reach", DEFAULT_REACH)
	local entries, total = {}, 0
	for _, name in ipairs(M.list(directory, engine)) do
		local measured, problem, hash = examine(directory .. "/" .. name .. ".mts", engine)
		problem = problem or M.problem_of(measured, reach)
		local entry = {
			name = name, weight = weight_of(manifest, name), share = 0, hash = hash, measured = measured, problem = problem,
		}
		if not problem then total = total + entry.weight end
		entries[#entries + 1] = entry
	end
	if total > 0 then
		for _, entry in ipairs(entries) do
			if not entry.problem then entry.share = entry.weight / total end
		end
	end
	return {directory = directory, entries = entries, manifest_problem = manifest_problem}
end

return M
