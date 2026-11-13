-- The buildings a player can order at a bench (builder_bench_menu.lua's Select schematic tab):
-- the .mts files of <world>/schems, a picture of each from a PNG or JPEG of the same name, and
-- whether a Builder could actually put each one up. schemedit has no API and always exports
-- to <world>/schems, so all that integrating with it takes is reading that directory.
--
-- A player's schematic has had none of the checks a stock building has, so nothing is taken on
-- trust. An unknown node would silently place as air, and a block nobody can supply would keep
-- a Builder waiting for ever.
local core = minetest
local materials = dofile(core.get_modpath("living_villages") .. "/builder_materials.lua")
local site = dofile(core.get_modpath("living_villages") .. "/builder_site.lua")

local M = {}

M.MAX_FILE_BYTES = 1024 * 1024
-- Every cell becomes a table in a Builder's plan, on the main thread.
M.MAX_VOLUME = 64000
-- Layers, the ground layer included. builder_site.lua reads the map high enough for this.
M.MAX_HEIGHT = 32

local function setting_number(engine, name, default)
	return tonumber(engine.settings and engine.settings:get(name)) or default
end

-- The one directory a player's schematics come from: where schemedit exports.
function M.directory(engine)
	engine = engine or core
	return engine.get_worldpath() .. "/schems"
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

-- The picture beside each schematic of a directory, name -> file. PNG beats JPEG.
local IMAGE_ORDER = {png = 1, jpg = 2, jpeg = 3}
local function images_in(directory, engine)
	local images, ranks = {}, {}
	for _, file in ipairs(engine.get_dir_list(directory, false) or {}) do
		local name, suffix = file:match("^(.+)%.(%w+)$")
		local rank = suffix and IMAGE_ORDER[suffix:lower()]
		if rank and (not ranks[name] or rank < ranks[name]) then
			images[name], ranks[name] = file, rank
		end
	end
	return images
end

-- An item -> count table as a list, most-used first, then by name.
function M.sorted_materials(bill)
	local list = {}
	for item, count in pairs(bill) do list[#list + 1] = {item = item, count = count} end
	table.sort(list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.item < b.item
	end)
	return list
end

local function sorted_keys(set)
	local keys = {}
	for key in pairs(set) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

-- The facts of a schematic table (read_schematic's: x fastest, then y, then z; a prob of 0
-- is a void, which places nothing). Cells that may place count, however unlikely.
-- `reach` is how far a Builder must reach for its worst block: a low one from the ring's outer
-- row, standing on the ground, and a high one (above `scaffold_height`) from a column on the
-- ring's inner row, standing level with it (builder.lua).
function M.measure(schematic, engine, scaffold_height)
	engine = engine or core
	scaffold_height = scaffold_height or site.config.scaffold_height
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
					local depth = math.min(x, size.x - 1 - x, z, size.z - 1 - z)
					if y > scaffold_height then
						reach = math.max(reach, depth + 1)
					else
						-- It stands on the ground at y 1, in the ring's outer row.
						local across = depth + ring
						reach = math.max(reach, math.sqrt(across * across + (y - 1) * (y - 1)))
					end
				end
			end
		end
	end
	return {
		size = {x = size.x, y = size.y, z = size.z}, blocks = blocks, reach = reach,
		materials = M.sorted_materials(bill),
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
	if size.y > M.MAX_HEIGHT then return {code = "too_tall", limit = M.MAX_HEIGHT} end
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
	-- What is high, and so its reach, depends on the scaffold height.
	local height = setting_number(engine, "living_villages_builder_scaffold_height", site.config.scaffold_height)
	local key = hash .. "|" .. height
	if measured_by_hash[key] == nil then
		-- Never place a directory's schematic by path: the engine would then keep serving
		-- that copy for the path, whatever the file later becomes.
		local ok, schematic = pcall(engine.read_schematic, path, {})
		measured_by_hash[key] = ok and schematic and schematic.data and M.measure(schematic, engine, height) or false
	end
	if not measured_by_hash[key] then return nil, {code = "unreadable"}, hash end
	return measured_by_hash[key], nil, hash
end

-- A project builds from its own copy, named for its content, so re-exporting or deleting the
-- file cannot change a building half up. Copies are never removed: a bench in an unloaded block
-- may still need one, and they are small.
function M.snapshot_path(hash, engine)
	engine = engine or core
	return engine.get_worldpath() .. "/living_villages/project_schems/" .. hash .. ".mts"
end

-- Copies a schematic for a project. Returns the hash of what was copied, which is what the
-- project must name, or nil if it could not be.
function M.take_snapshot(directory, name, engine)
	engine = engine or core
	local file = io.open(directory .. "/" .. name .. ".mts", "rb")
	if not file then return nil end
	local content = file:read("*a")
	file:close()
	local hash = engine.sha1(content)
	engine.mkdir(engine.get_worldpath() .. "/living_villages/project_schems")
	if not engine.safe_file_write(M.snapshot_path(hash, engine), content) then return nil end
	return hash
end

-- Everything the bench's window shows of the directory: {directory, entries}. An entry is
-- {name, hash, measured, problem, image}, sorted by name.
function M.scan(engine)
	engine = engine or core
	local directory = M.directory(engine)
	local reach = setting_number(engine, "living_villages_builder_reach", site.config.reach)
	local images = images_in(directory, engine)
	local entries = {}
	for _, name in ipairs(M.list(directory, engine)) do
		local measured, problem, hash = examine(directory .. "/" .. name .. ".mts", engine)
		problem = problem or M.problem_of(measured, reach)
		entries[#entries + 1] = {name = name, hash = hash, measured = measured, problem = problem, image = images[name]}
	end
	return {directory = directory, entries = entries}
end

return M
