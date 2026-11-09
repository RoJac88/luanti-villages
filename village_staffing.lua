-- A generated village is staffed the moment it is placed, not by a race for job
-- blocks (design doc, Staffing a new village).
--
-- settlements.place_schematics places each building through
-- mcl_structures.place_schematic, which lands it later, from emerge_area, and then
-- runs its after-placement callback: VoxeLibre's spawns a villager on each red bed
-- near the building (mcl_villages/buildings.lua spawn_villagers), with `_bed` and
-- the bed's meta `villager` set. While the original place_schematics runs,
-- place_schematic is wrapped so each callback is counted and its box kept; when the
-- last one has run, every bed, job block and villager of the village exists, and
-- staffing runs once. A callback that never comes (a building that failed to place)
-- holds it up for TIMEOUT seconds at most.
--
-- Staffing pairs the village's free job blocks (job_blocks.lua) with its new
-- villagers greedily, the closest block and bed first (the bench and the jukebox
-- before the rest), and claims each pair the way that block is claimed. `living_villages_spawn_unemployed` villagers are left out of
-- work: greedy pairing stops short by that many, so they are those whose beds are
-- furthest from any block still free. They carry `_villages_left_unemployed` and no job
-- module gives them a block later (job_blocks.eligible); they are the labour pool.
-- Until staffing a new villager is held back from every job module
-- (`M.install_villager`), so none takes a block on its own first.
-- A village generated before this keeps the jobs its villagers took.
local core = minetest
local job_blocks = dofile(core.get_modpath("living_villages") .. "/job_blocks.lua")

local M = {}

M.SETTING = "living_villages_spawn_unemployed"
M.DEFAULT_UNEMPLOYED = 0
M.TIMEOUT = 120
local RED_BED = "mcl_beds:bed_red_bottom"
-- How far a villager may have wandered from its bed before staffing finds it.
local FIND_RADIUS = 8

-- Villager ids whose village is still being placed.
local awaiting = {}

-- How many of a new village's villagers are left without a job.
function M.unemployed(engine)
	engine = engine or core
	local value = tonumber(engine.settings and engine.settings:get(M.SETTING))
	if not value or value ~= value or value == math.huge then return M.DEFAULT_UNEMPLOYED end
	return math.max(0, math.floor(value))
end

function M.awaiting(self)
	return self._id ~= nil and awaiting[self._id] == true
end

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function by_position(a, b)
	if a.x ~= b.x then return a.x < b.x end
	if a.y ~= b.y then return a.y < b.y end
	return a.z < b.z
end

local function find_villager(id, bed)
	for _, object in ipairs(core.get_objects_inside_radius(bed, FIND_RADIUS)) do
		local entity = object:get_luaentity()
		if entity and entity.name == "mobs_mc:villager" and entity._id == id then return entity end
	end
end

-- The beds of a placed building whose villager is set, into batch.beds by id.
local function note_beds(batch, p1, p2)
	for _, bed in ipairs(core.find_nodes_in_area(p1, p2, {RED_BED})) do
		local id = core.get_meta(bed):get_string("villager")
		if id ~= "" and not batch.beds[id] then
			batch.beds[id] = bed
			awaiting[id] = true
		end
	end
end

-- Pairs and claims. Returns the summary it logs.
function M.staff(batch, roles, unemployed)
	local villagers = {}
	for id, bed in pairs(batch.beds) do
		local entity = find_villager(id, bed)
		if entity and job_blocks.eligible(entity) then
			table.insert(villagers, {id = id, bed = bed, entity = entity})
		end
	end
	table.sort(villagers, function(a, b) return by_position(a.bed, b.bed) end)
	local blocks, seen = {}, {}
	local names = job_blocks.search_nodes(roles)
	for _, box in ipairs(batch.boxes) do
		for _, pos in ipairs(core.find_nodes_in_area(box[1], box[2], names)) do
			if not seen[key(pos)] and job_blocks.is_free(pos, roles) then
				seen[key(pos)] = true
				table.insert(blocks, pos)
			end
		end
	end
	table.sort(blocks, by_position)
	local limit = math.max(0, #villagers - unemployed)
	local function try(v, block) return job_blocks.claim(v.entity, block, roles) end
	-- The bench and the jukebox first: a village wants its Builder and its keeper, and a
	-- tavern often stands apart from every bed, so closest-first would leave it to
	-- keeper.lua's evening take-over, which moves someone off a job on the first day.
	local first, rest = {}, {}
	for _, pos in ipairs(blocks) do
		local kind = job_blocks.kind(core.get_node_or_nil(pos).name, roles)
		table.insert((kind == "bench" or kind == "jukebox") and first or rest, pos)
	end
	local taken = job_blocks.pair(villagers, first, limit, try)
	local placed = {}
	for _, pair in ipairs(taken) do placed[pair.villager] = true end
	local others = {}
	for _, v in ipairs(villagers) do if not placed[v] then table.insert(others, v) end end
	for _, pair in ipairs(job_blocks.pair(others, rest, limit - #taken, try)) do table.insert(taken, pair) end
	-- Left out by the setting, not for want of a block: they stay the labour pool. Those
	-- that found no block take one built later (job_seek.lua).
	if #taken == limit and limit < #villagers then
		local employed = {}
		for _, pair in ipairs(taken) do employed[pair.villager] = true end
		for _, v in ipairs(villagers) do
			if not employed[v] then v.entity[job_blocks.LEFT_UNEMPLOYED] = true end
		end
	end
	local summary = {villagers = #villagers, blocks = #blocks, employed = #taken,
		unemployed = #villagers - #taken, free = #blocks - #taken}
	core.log("action", string.format("[living_villages] staffed a new village: %d villagers, %d job blocks, "
		.. "%d employed, %d left unemployed, %d blocks free", summary.villagers, summary.blocks,
		summary.employed, summary.unemployed, summary.free))
	return summary
end

local function finish(batch, roles, engine)
	if batch.done then return end
	batch.done = true
	local ok, err = pcall(M.staff, batch, roles, M.unemployed(engine))
	for id in pairs(batch.beds) do awaiting[id] = nil end
	if not ok then core.log("error", "[living_villages] staffing a new village failed: " .. tostring(err)) end
end

local function maybe_finish(batch, roles, engine)
	if batch.closed and batch.outstanding == 0 then finish(batch, roles, engine) end
end

local wrappers = setmetatable({}, {__mode = "k"})

-- Wraps settlements.place_schematics; install it outside every other wrapper, so
-- one batch covers the whole village. Returns true if installed (or already is).
function M.install(settlements, structures, roles, engine)
	engine = engine or core
	if type(settlements) == "table" and wrappers[settlements.place_schematics] then return true end
	if type(settlements) ~= "table" or type(settlements.place_schematics) ~= "function"
			or type(structures) ~= "table" or type(structures.place_schematic) ~= "function" then
		return false
	end
	local original = settlements.place_schematics
	local wrapper = function(...)
		local batch = {outstanding = 0, boxes = {}, beds = {}}
		local place = structures.place_schematic
		structures.place_schematic = function(pos, schematic, rotation, replacements, force, flags, callback, ...)
			if type(callback) ~= "function" then
				return place(pos, schematic, rotation, replacements, force, flags, callback, ...)
			end
			local ran = false
			local function counted(p1, p2, ...)
				ran = true
				local ok, err = pcall(callback, p1, p2, ...)
				if p1 and p2 then
					table.insert(batch.boxes, {vector.new(p1), vector.new(p2)})
					note_beds(batch, p1, p2)
				end
				batch.outstanding = batch.outstanding - 1
				maybe_finish(batch, roles, engine)
				if not ok then error(err, 0) end
			end
			batch.outstanding = batch.outstanding + 1
			local result = place(pos, schematic, rotation, replacements, force, flags, counted, ...)
			-- No placement under way: no callback will come.
			if not result and not ran then batch.outstanding = batch.outstanding - 1 end
			return result
		end
		local results = {pcall(original, ...)}
		structures.place_schematic = place
		batch.closed = true
		maybe_finish(batch, roles, engine)
		if not batch.done then
			engine.after(M.TIMEOUT, function()
				if not batch.done then
					core.log("warning", string.format("[living_villages] %d buildings of a new village never "
						.. "finished placing; staffing it with what is there", batch.outstanding))
					finish(batch, roles, engine)
				end
			end)
		end
		if not results[1] then error(results[2], 0) end
		return unpack(results, 2)
	end
	wrappers[wrapper] = true
	settlements.place_schematics = wrapper
	return true
end

-- Holds a villager whose village is still being placed back from every job module
-- inside this wrapper: it gets its job from staffing.
function M.install_villager(def)
	local original_custom = def.do_custom
	def.do_custom = function(self, dtime)
		if M.awaiting(self) then return end
		return original_custom(self, dtime)
	end
end

return M
