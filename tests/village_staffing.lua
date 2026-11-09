-- Run with: luajit tests/village_staffing.lua
local nodes, metas, objects, afters, logs = {}, {}, {}, {}, {}
local settings = {}
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
local BED, COMPOSTER, BARREL = "mcl_beds:bed_red_bottom", "mcl_composters:composter", "mcl_barrels:barrel_closed"
local BENCH, JUKEBOX, LOOM = "living_villages:builder_block", "mcl_jukebox:jukebox", "mcl_loom:loom"

local function distance(a, b)
	local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(x * x + y * y + z * z)
end

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return 0 end,
	get_timeofday = function() return 0.4 end,
	settings = {get = function(_, name) return settings[name] end},
	registered_nodes = {},
	log = function(level, text) table.insert(logs, level .. " " .. text) end,
	pos_to_string = key,
	string_to_pos = function(text)
		local x, y, z = text:match("(-?%d+),(-?%d+),(-?%d+)")
		return x and {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
	end,
	get_item_group = function() return 0 end,
	after = function(seconds, fn) table.insert(afters, {seconds = seconds, fn = fn}) end,
	get_node_or_nil = function(pos)
		local name = nodes[key(pos)]
		return name and {name = name} or nil
	end,
	get_meta = function(pos)
		local k = key(pos)
		return {
			get_string = function(_, field) return metas[k] and metas[k][field] or "" end,
			set_string = function(_, field, value)
				metas[k] = metas[k] or {}
				metas[k][field] = value
			end,
		}
	end,
	find_nodes_in_area = function(minp, maxp, names)
		local wanted = {}
		for _, name in ipairs(names) do wanted[name] = true end
		local found = {}
		for k, name in pairs(nodes) do
			local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
			x, y, z = tonumber(x), tonumber(y), tonumber(z)
			if wanted[name] and x >= minp.x and x <= maxp.x and y >= minp.y and y <= maxp.y
					and z >= minp.z and z <= maxp.z then
				table.insert(found, {x = x, y = y, z = z})
			end
		end
		return found
	end,
	get_objects_inside_radius = function(pos, radius)
		local found = {}
		for _, entity in ipairs(objects) do
			if distance(entity.pos, pos) <= radius then
				table.insert(found, {get_luaentity = function() return entity end})
			end
		end
		return found
	end,
}
vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = distance,
}
mcl_mobs = {mob_class = {}}

local job_blocks = dofile("job_blocks.lua")
local staffing = dofile("village_staffing.lua")

local function count_logs(pattern)
	local n = 0
	for _, line in ipairs(logs) do if line:find(pattern) then n = n + 1 end end
	return n
end

-- Pairing is greedy, closest first, and stops at the limit.
do
	local villagers = {{bed = {x = 0, y = 0, z = 0}}, {bed = {x = 10, y = 0, z = 0}}, {bed = {x = 100, y = 0, z = 0}}}
	local blocks = {{x = 9, y = 0, z = 0}, {x = 2, y = 0, z = 0}}
	local taken = job_blocks.pair(villagers, blocks, 3)
	assert(#taken == 2)
	assert(taken[1].villager == villagers[2] and taken[1].block.x == 9)
	assert(taken[2].villager == villagers[1] and taken[2].block.x == 2)
	-- Closest first is not each villager's nearest: the bed at 4 is nearest the block at 6,
	-- but the bed at 7 is nearer still, so it takes 6 and the bed at 4 takes 0.
	villagers = {{bed = {x = 4, y = 0, z = 0}}, {bed = {x = 7, y = 0, z = 0}}}
	blocks = {{x = 0, y = 0, z = 0}, {x = 6, y = 0, z = 0}}
	taken = job_blocks.pair(villagers, blocks, 2)
	assert(taken[1].villager == villagers[2] and taken[1].block.x == 6)
	assert(taken[2].villager == villagers[1] and taken[2].block.x == 0)
	-- The limit leaves out the villager furthest from what is left.
	villagers = {{bed = {x = 0, y = 0, z = 0}}, {bed = {x = 50, y = 0, z = 0}}, {bed = {x = 3, y = 0, z = 0}}}
	blocks = {{x = 1, y = 0, z = 0}, {x = 4, y = 0, z = 0}, {x = 60, y = 0, z = 0}}
	taken = job_blocks.pair(villagers, blocks, 2)
	assert(#taken == 2 and taken[1].villager ~= villagers[2] and taken[2].villager ~= villagers[2])
	-- A failed claim passes the block over, not the villager.
	villagers = {{bed = {x = 0, y = 0, z = 0}}}
	blocks = {{x = 1, y = 0, z = 0}, {x = 5, y = 0, z = 0}}
	taken = job_blocks.pair(villagers, blocks, 1, function(_, block) return block.x == 5 end)
	assert(#taken == 1 and taken[1].block.x == 5)
end

-- The setting.
do
	assert(staffing.unemployed() == 0)
	settings[staffing.SETTING] = "2"
	assert(staffing.unemployed() == 2)
	settings[staffing.SETTING] = "-3"
	assert(staffing.unemployed() == 0)
	settings[staffing.SETTING] = "nan"
	assert(staffing.unemployed() == 0)
	settings[staffing.SETTING] = nil
end

-- A village: buildings land later, each spawning villagers on its beds; staffing
-- waits for the last one, then pairs.
local placed -- callbacks waiting to "emerge", in order
local structures = {place_schematic = function(pos, schematic, rotation, replacements, force, flags, callback)
	if schematic == "missing" then return nil end
	table.insert(placed, {pos = pos, schematic = schematic, callback = callback})
	return true
end}
local settlements = {}
-- Each building is {beds = {...}, blocks = {[pos] = name}} at its own box.
settlements.place_schematics = function(info)
	for _, building in ipairs(info) do
		structures.place_schematic(building.pos, building.schematic, 0, nil, true, nil, function(p1, p2)
			for _, bed in ipairs(building.beds or {}) do
				local id = "v" .. key(bed)
				nodes[key(bed)] = BED
				metas[key(bed)] = {villager = id}
				table.insert(building.asleep or objects, {name = "mobs_mc:villager", _id = id, _bed = bed,
					_profession = building.profession or "unemployed", pos = {x = bed.x, y = bed.y, z = bed.z + 1}})
			end
			if building.fail then error("boom") end
		end)
	end
	return "placed"
end
local roles = {
	builder = {BENCH = BENCH, employ = function(self, pos)
		if not job_blocks.eligible(self) then return false end
		metas[key(pos)] = {villager = self._id}
		self._jobsite, self._profession, self._villages_builder = pos, "mason", true
		return true
	end},
	keeper = {employ = function(self, pos)
		if self._villages_farm_seek then return false end
		metas[key(pos)] = {villager = self._id}
		self._jobsite, self._profession, self._villages_keeper = pos, "farmer", true
		return true
	end},
}
local stored = {}
local storage = {
	get_string = function(_, k) return stored[k] or "" end,
	set_string = function(_, k, v) stored[k] = v ~= "" and v or nil end,
}
assert(staffing.install(settlements, structures, roles, minetest, storage))
assert(staffing.install(settlements, structures, roles), "a second install is a no-op")
local wrapped = settlements.place_schematics

local function reset()
	nodes, metas, objects, afters, logs, placed = {}, {}, {}, {}, {}, {}
end
local function land(i)
	local p = placed[i]
	local box = p.schematic
	p.callback(box[1], box[2], {x = 1, y = 1, z = 1}, 0, nil)
end
local function villager(id)
	for _, entity in ipairs(objects) do if entity._id == id then return entity end end
end

do
	reset()
	local house = {{x = 0, y = 0, z = 0}, {x = 9, y = 5, z = 9}}
	local tavern = {{x = 20, y = 0, z = 0}, {x = 29, y = 5, z = 9}}
	local workshop = {{x = 40, y = 0, z = 0}, {x = 49, y = 5, z = 9}}
	nodes[key({x = 2, y = 1, z = 2})] = COMPOSTER
	nodes[key({x = 8, y = 1, z = 8})] = BARREL
	nodes[key({x = 22, y = 1, z = 2})] = JUKEBOX
	nodes[key({x = 42, y = 1, z = 2})] = BENCH
	nodes[key({x = 47, y = 1, z = 7})] = LOOM
	metas[key({x = 47, y = 1, z = 7})] = {villager = "an older claim"}
	local result = wrapped({
		{pos = house[1], schematic = house, beds = {{x = 1, y = 1, z = 1}, {x = 8, y = 1, z = 6}}},
		{pos = tavern[1], schematic = tavern, beds = {{x = 23, y = 1, z = 3}}},
		{pos = workshop[1], schematic = workshop, beds = {{x = 43, y = 1, z = 3}}},
		{pos = {x = 0, y = 0, z = 99}, schematic = "missing"},
	})
	assert(result == "placed", "the original's result comes back")
	assert(structures.place_schematic ~= nil and #placed == 3)
	assert(#afters == 1 and afters[1].seconds == staffing.TIMEOUT)
	land(1)
	local first = villager("v1,1,1")
	assert(first and staffing.awaiting(first), "a new villager waits for staffing")
	assert(not first._jobsite)
	-- Held back from every job module meanwhile.
	local inner_ran = false
	local def = {do_custom = function() inner_ran = true end}
	staffing.install_villager(def)
	assert(def.do_custom(first, 0.1) == nil and not inner_ran)
	land(2)
	assert(not first._jobsite, "not until the last building")
	land(3)
	assert(not staffing.awaiting(first))
	def.do_custom(first, 0.1)
	assert(inner_ran)
	-- Each took the block nearest its bed.
	assert(first._profession == "farmer" and first._jobsite.x == 2)
	assert(villager("v8,1,6")._profession == "fisherman")
	assert(villager("v23,1,3")._villages_keeper)
	assert(villager("v43,1,3")._villages_builder)
	assert(metas[key({x = 47, y = 1, z = 7})].villager == "an older claim", "a claimed block is left alone")
	assert(count_logs("staffed a new village: 4 villagers, 4 job blocks, 4 employed, 0 left unemployed") == 1)
	-- The timeout comes to nothing once staffed.
	afters[1].fn()
	assert(count_logs("staffed a new village") == 1)
end

-- Some left unemployed: those furthest from a free block.
do
	reset()
	settings[staffing.SETTING] = "1"
	local house = {{x = 0, y = 0, z = 0}, {x = 30, y = 5, z = 9}}
	nodes[key({x = 2, y = 1, z = 2})] = COMPOSTER
	nodes[key({x = 6, y = 1, z = 2})] = BARREL
	wrapped({{pos = house[1], schematic = house,
		beds = {{x = 1, y = 1, z = 1}, {x = 7, y = 1, z = 1}, {x = 30, y = 1, z = 1}}}})
	land(1)
	assert(villager("v1,1,1")._profession == "farmer")
	assert(villager("v7,1,1")._profession == "fisherman")
	assert(villager("v30,1,1")._profession == "unemployed")
	assert(villager("v30,1,1")._villages_left_unemployed, "left out on purpose, it stays out")
	assert(not villager("v1,1,1")._villages_left_unemployed)
	assert(not job_blocks.eligible(villager("v30,1,1")))
	assert(count_logs("1 left unemployed") == 1)
	settings[staffing.SETTING] = nil
end

-- The jukebox is filled first, even far from every bed, so the tavern has its keeper on day one.
do
	reset()
	local house = {{x = 0, y = 0, z = 0}, {x = 9, y = 5, z = 9}}
	local tavern = {{x = 40, y = 0, z = 0}, {x = 49, y = 5, z = 9}}
	nodes[key({x = 2, y = 1, z = 2})] = COMPOSTER
	nodes[key({x = 3, y = 1, z = 2})] = BARREL
	nodes[key({x = 45, y = 1, z = 5})] = JUKEBOX
	wrapped({
		{pos = house[1], schematic = house, beds = {{x = 1, y = 1, z = 1}, {x = 4, y = 1, z = 1}}},
		{pos = tavern[1], schematic = tavern},
	})
	land(1)
	land(2)
	assert(villager("v4,1,1")._villages_keeper, "the bed nearest the jukebox keeps the tavern")
	assert(villager("v1,1,1")._profession == "farmer")
	assert(count_logs("2 employed") == 1)
end

-- A villager not loaded when its village is staffed is paired by its bed; its block is
-- held under its id, and the job is finished when it loads.
do
	reset()
	settings[staffing.SETTING] = "1"
	local house = {{x = 0, y = 0, z = 0}, {x = 30, y = 5, z = 9}}
	nodes[key({x = 2, y = 1, z = 2})] = COMPOSTER
	nodes[key({x = 6, y = 1, z = 2})] = JUKEBOX
	-- Spawned, but their mapblocks are not active.
	local asleep = {}
	wrapped({{pos = house[1], schematic = house, asleep = asleep,
		beds = {{x = 1, y = 1, z = 1}, {x = 7, y = 1, z = 1}, {x = 30, y = 1, z = 1}}}})
	land(1)
	assert(#objects == 0 and #asleep == 3)
	assert(metas[key({x = 2, y = 1, z = 2})].villager == "v1,1,1", "held under its id")
	assert(metas[key({x = 6, y = 1, z = 2})].villager == "v7,1,1")
	assert(stored["staffing:v30,1,1"] == "unemployed")
	local by_id = {}
	for _, e in ipairs(asleep) do by_id[e._id] = e end
	staffing.apply_pending(by_id["v1,1,1"], roles)
	assert(by_id["v1,1,1"]._profession == "farmer" and by_id["v1,1,1"]._jobsite.x == 2)
	assert(metas[key({x = 2, y = 1, z = 2})].villager == "v1,1,1")
	staffing.apply_pending(by_id["v7,1,1"], roles)
	assert(by_id["v7,1,1"]._villages_keeper, "the jukebox through the keeper's own claim")
	staffing.apply_pending(by_id["v30,1,1"], roles)
	assert(by_id["v30,1,1"]._villages_left_unemployed)
	assert(next(stored) == nil, "nothing left pending")
	-- A block someone else took meanwhile is not taken from them.
	stored["staffing:late"] = key({x = 2, y = 1, z = 2})
	local late = {_id = "late", _profession = "unemployed"}
	staffing.apply_pending(late, roles)
	assert(not late._jobsite and metas[key({x = 2, y = 1, z = 2})].villager == "v1,1,1")
	settings[staffing.SETTING] = nil
end

-- Never more than half left out: one villager alone is staffed whatever the setting.
do
	reset()
	settings[staffing.SETTING] = "5"
	local house = {{x = 0, y = 0, z = 0}, {x = 9, y = 5, z = 9}}
	nodes[key({x = 2, y = 1, z = 2})] = COMPOSTER
	wrapped({{pos = house[1], schematic = house, beds = {{x = 1, y = 1, z = 1}}}})
	land(1)
	assert(villager("v1,1,1")._profession == "farmer" and not villager("v1,1,1")._villages_left_unemployed)
	-- Five villagers, five blocks: two left out, not five.
	reset()
	local row = {{x = 0, y = 0, z = 0}, {x = 60, y = 5, z = 9}}
	local beds = {}
	for i = 0, 4 do
		table.insert(beds, {x = i * 12, y = 1, z = 1})
		nodes[key({x = i * 12 + 1, y = 1, z = 2})] = BARREL
	end
	wrapped({{pos = row[1], schematic = row, beds = beds}})
	land(1)
	assert(count_logs("3 employed, 2 left unemployed") == 1)
	settings[staffing.SETTING] = nil
end

-- Too few blocks: those without one are not held out of work, so a block built later is theirs.
do
	reset()
	settings[staffing.SETTING] = "1"
	local house = {{x = 0, y = 0, z = 0}, {x = 30, y = 5, z = 9}}
	nodes[key({x = 2, y = 1, z = 2})] = COMPOSTER
	wrapped({{pos = house[1], schematic = house,
		beds = {{x = 1, y = 1, z = 1}, {x = 7, y = 1, z = 1}, {x = 30, y = 1, z = 1}}}})
	land(1)
	assert(villager("v1,1,1")._profession == "farmer")
	assert(not villager("v7,1,1")._villages_left_unemployed and not villager("v30,1,1")._villages_left_unemployed)
	settings[staffing.SETTING] = nil
end

-- A nitwit is not staffed; a building that never lands holds staffing up only until the timeout.
do
	reset()
	local house = {{x = 0, y = 0, z = 0}, {x = 9, y = 5, z = 9}}
	local lost = {{x = 100, y = 0, z = 0}, {x = 109, y = 5, z = 9}}
	nodes[key({x = 2, y = 1, z = 2})] = COMPOSTER
	nodes[key({x = 3, y = 1, z = 2})] = BARREL
	wrapped({
		{pos = house[1], schematic = house, beds = {{x = 1, y = 1, z = 1}}},
		{pos = {x = 0, y = 0, z = 10}, schematic = {{x = 0, y = 0, z = 10}, {x = 9, y = 5, z = 19}},
			beds = {{x = 2, y = 1, z = 12}}, profession = "nitwit"},
		{pos = lost[1], schematic = lost},
	})
	land(1)
	land(2)
	assert(villager("v1,1,1")._profession == "unemployed" and staffing.awaiting(villager("v1,1,1")))
	afters[1].fn()
	assert(count_logs("never finished placing") == 1)
	assert(villager("v1,1,1")._profession == "farmer")
	assert(villager("v2,1,12")._profession == "nitwit")
	assert(not villager("v2,1,12")._villages_left_unemployed)
	assert(not staffing.awaiting(villager("v1,1,1")))
end

-- An error in a callback still counts it, and is raised.
do
	reset()
	local house = {{x = 0, y = 0, z = 0}, {x = 9, y = 5, z = 9}}
	nodes[key({x = 2, y = 1, z = 2})] = COMPOSTER
	wrapped({{pos = house[1], schematic = house, beds = {{x = 1, y = 1, z = 1}}, fail = true}})
	local ok, err = pcall(land, 1)
	assert(not ok and tostring(err):find("boom"))
	assert(villager("v1,1,1")._profession == "farmer")
end

-- Without the APIs it is not installed.
assert(not staffing.install({}, structures, roles))
assert(not staffing.install({place_schematics = function() end}, {}, roles))

print("village_staffing.lua: ok")
