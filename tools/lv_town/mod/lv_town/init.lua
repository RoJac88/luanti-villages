-- The standard test village (tools/lv_town/README.md). A world mod kept in the template:
--
-- * Always: VoxeLibre generates no village of its own (settlements.create_site_plan
--   declines), so the test village is the only one, however far the world grows.
-- * Once, with lv_town_setup = true and no setup.done in the world folder (build.sh):
--   builds the village at spawn on a flat world through the same code a generated
--   village uses, fills in every trade, adds what the economy needs around it, takes a
--   census and shuts the server down.
--
-- Setup, in order:
--   1. forceload and emerge AREA around spawn; fail unless the ground there is grass
--   2. dig a pond, so the planner can place the fisherman's hut
--   3. plan, terraform and place the village with PseudoRandom(lv_town_seed), as
--      mcl_villages' build_a_settlement does; living_villages' planner, buildings,
--      stash chests and staffing all apply
--   4. after staffing, a job block on open ground for each trade nobody has, and tower
--      houses for more villagers if too few are out of work (LABOUR stay out of work)
--   5. two chickens by the butcher's smoker, an oak grove, sugar cane on a channel,
--      poppies, the quarry (a cobblestone generator), a chest by any bed without a stash
--   6. census.json, lvw.conf (lv_keep's centre, the spawn point) and setup.done
local core = minetest

local WORLD = core.get_worldpath()
local DONE, FAILED = WORLD .. "/setup.done", WORLD .. "/setup.failed"
local SEED = tonumber(core.settings:get("lv_town_seed")) or 1
local SETUP = core.settings:get_bool("lv_town_setup", false)
local AREA = 112
local LABOUR = 2
local GRASS = "mcl_core:dirt_with_grass"
local WATER = "mcl_core:water_source"

-- Every trade the village must have, and the block that makes one.
local REQUIRED = {
	farmer = "mcl_composters:composter",
	fisherman = "mcl_barrels:barrel_closed",
	fletcher = "mcl_fletching_table:fletching_table",
	shepherd = "mcl_loom:loom",
	librarian = "mcl_lectern:lectern",
	cartographer = "mcl_cartography_table:cartography_table",
	armorer = "mcl_blast_furnace:blast_furnace",
	butcher = "mcl_smoker:smoker",
	weapon_smith = "mcl_grindstone:grindstone",
	tool_smith = "mcl_smithing_table:table",
	cleric = "mcl_brewing:stand_000",
	mason = "mcl_stonecutter:stonecutter",
	leatherworker = "mcl_cauldrons:cauldron",
	keeper = "mcl_jukebox:jukebox",
	builder = "living_villages:builder_block",
	woodcutter = "living_villages:chopping_block",
	alchemist = "living_villages:alchemy_stand",
}
-- Trades whose block is no use without its building (the tavern's pantry, the Builder's
-- house, the church, the greenhouse's field): missing one fails the build.
local STRUCTURAL = {keeper = true, builder = true, cleric = true, farmer = true}
-- The keeper and the Builder sleep within 6 of their jukebox and bench, where every chest
-- is a work chest (possessions.is_work_chest): the pantry, the workshop. They keep their
-- goods there and never claim a stash; each needs a chest within WORK_CHEST of its block.
local WORK_CHEST = {keeper = 6, builder = 6}

local function log(fmt, ...)
	core.log("action", "[lv_town] " .. string.format(fmt, ...))
end

local function exists(path)
	local f = io.open(path, "r")
	if f then f:close() return true end
	return false
end

local function write(path, text)
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
end

-- Only the setup's own village is planned.
local building = false
core.register_on_mods_loaded(function()
	if not rawget(_G, "settlements") or not settlements.create_site_plan then return end
	local plan = settlements.create_site_plan
	settlements.create_site_plan = function(maxp, minp, ...)
		if building then return plan(maxp, minp, ...) end
		log("declined a generated village at %s", core.pos_to_string(minp))
		return false
	end
end)

if not SETUP or exists(DONE) or exists(FAILED) then return end

-- With no player on, villagers would stand still: they count as near one during setup,
-- as lv_keep makes them in a run, so they claim stashes and walk to their jobs.
core.register_on_mods_loaded(function()
	local class = mcl_mobs.mob_class
	local original = class.player_in_active_range
	class.player_in_active_range = function(self, ...)
		if self.name == "mobs_mc:villager" or self.name == "mobs_mc:chicken" then return true end
		return original(self, ...)
	end
end)

local G -- the ground's y: the top node of the flat world
local pr = PseudoRandom(SEED)
local reserved = {} -- boxes the setup has used, {x, z, w, d}
local report = {seed = SEED, placed = {}}

local function node(pos) return core.get_node(pos).name end

local function finish(ok, why)
	report.ok = ok
	report.why = why
	write(WORLD .. "/census.json", core.write_json(report, true))
	write(ok and DONE or FAILED, (why or "ok") .. "\n")
	log("%s%s", ok and "SETUP DONE" or "SETUP FAILED: ", why or "")
	core.request_shutdown("lv_town setup " .. (ok and "done" or "failed"), false, 3)
end

local function villagers()
	local list = {}
	for _, e in pairs(core.luaentities) do
		if e.name == "mobs_mc:villager" and not e.child and e._id then list[#list + 1] = e end
	end
	table.sort(list, function(a, b) return a._id < b._id end)
	return list
end

local function trade_of(e)
	if e._villages_keeper then return "keeper" end
	if e._villages_builder then return "builder" end
	if e._villages_woodcutter then return "woodcutter" end
	if e._villages_alchemist then return "alchemist" end
	local p = e._profession
	if not p or p == "" or p == "unemployed" or p == "nitwit" then return "unemployed" end
	return p
end

local function overlaps(x, z, w, d)
	for _, b in ipairs(reserved) do
		if x < b[1] + b[3] and b[1] < x + w and z < b[2] + b[4] and b[2] < z + d then return true end
	end
	return false
end

-- Whether a w by d patch at (x, z), and `margin` round it, is open grass with nothing
-- standing on it.
local function open(x, z, w, d, margin)
	if overlaps(x - margin, z - margin, w + 2 * margin, d + 2 * margin) then return false end
	for px = x - margin, x + w - 1 + margin do
		for pz = z - margin, z + d - 1 + margin do
			if node({x = px, y = G, z = pz}) ~= GRASS then return false end
			for y = G + 1, G + 6 do
				if node({x = px, y = y, z = pz}) ~= "air" then return false end
			end
		end
	end
	return true
end

-- The first open patch on rings round spawn, from rmin out; reserved once found.
local function spot(w, d, rmin, rmax, margin)
	margin = margin or 3
	for r = rmin, rmax, 3 do
		for a = 0, 350, 10 do
			local x = math.floor(r * math.cos(math.rad(a)) - w / 2 + 0.5)
			local z = math.floor(r * math.sin(math.rad(a)) - d / 2 + 0.5)
			if open(x, z, w, d, margin) then
				reserved[#reserved + 1] = {x - margin, z - margin, w + 2 * margin, d + 2 * margin}
				return {x = x, y = G, z = z}
			end
		end
	end
	return nil
end

local function place(what, pos, name, param2)
	core.set_node(pos, {name = name, param2 = param2 or 0})
	report.placed[#report.placed + 1] = {what = what, name = name, pos = core.pos_to_string(pos)}
end

local function census()
	local by_trade, list, no_stash = {}, {}, {}
	for _, e in ipairs(villagers()) do
		local trade = trade_of(e)
		by_trade[trade] = (by_trade[trade] or 0) + 1
		list[#list + 1] = {id = e._id:sub(1, 6), trade = trade,
			bed = e._bed and core.pos_to_string(e._bed) or nil,
			stash = e._villages_stash and core.pos_to_string(e._villages_stash) or nil,
			jobsite = e._jobsite and core.pos_to_string(e._jobsite) or nil}
		local radius = WORK_CHEST[trade]
		if radius then
			local chests = e._jobsite and core.find_nodes_in_area(vector.subtract(e._jobsite, radius),
				vector.add(e._jobsite, radius), {"mcl_chests:chest_small", "mcl_chests:chest"}) or {}
			list[#list].work_chests = #chests
			if #chests == 0 then no_stash[#no_stash + 1] = e end
		elseif e._bed and not e._villages_stash then
			no_stash[#no_stash + 1] = e
		end
	end
	local missing = {}
	for trade in pairs(REQUIRED) do
		if not by_trade[trade] then missing[#missing + 1] = trade end
	end
	table.sort(missing)
	return by_trade, list, missing, no_stash
end

local function count_nodes(names, radius)
	local found = core.find_nodes_in_area({x = -radius, y = G - 8, z = -radius},
		{x = radius, y = G + 24, z = radius}, names)
	return #found
end

-- 6. The census, and done.
local function phase_census()
	local by_trade, list, missing, no_stash = census()
	report.villagers, report.by_trade, report.missing = list, by_trade, missing
	report.adults = #list
	report.no_stash = #no_stash
	local butcher
	for _, e in ipairs(villagers()) do
		if trade_of(e) == "butcher" and e._jobsite then butcher = e end
	end
	local chickens = 0
	if butcher then
		for _, obj in ipairs(core.get_objects_inside_radius(butcher._jobsite, 12)) do
			local l = obj:get_luaentity()
			if l and l.name == "mobs_mc:chicken" then chickens = chickens + 1 end
		end
	end
	report.chickens_by_smoker = chickens
	report.reeds = count_nodes({"mcl_core:reeds"}, AREA)
	report.poppies = count_nodes({"mcl_flowers:poppy"}, AREA)
	report.oak_logs = count_nodes({"mcl_core:tree"}, AREA)
	report.bells = count_nodes({"mcl_bells:bell"}, AREA)
	report.lava = count_nodes({"mcl_core:lava_source"}, AREA)
	write(WORLD .. "/lvw.conf", string.format(
		"lv_keep_center = 0,%d,0\nlv_keep_radius = 96\nstatic_spawnpoint = 0,%d,0\n", G, G + 20))
	local shape = {}
	for trade, n in pairs(by_trade) do shape[#shape + 1] = trade .. "=" .. n end
	table.sort(shape)
	log("census: %d adults: %s", #list, table.concat(shape, " "))
	log("census: missing [%s], without stash %d, chickens %d, reeds %d, poppies %d, oak logs %d, bells %d, lava %d",
		table.concat(missing, " "), #no_stash, chickens, report.reeds, report.poppies, report.oak_logs,
		report.bells, report.lava)
	if #missing > 0 then return finish(false, "missing trades: " .. table.concat(missing, " ")) end
	if #no_stash > 0 then return finish(false, #no_stash .. " villagers without a stash or work chest") end
	if chickens < 2 then return finish(false, "chickens by the smoker: " .. chickens) end
	if report.bells ~= 1 then return finish(false, "bells: " .. report.bells .. " (another village?)") end
	finish(true)
end

-- A chest on the floor beside a bed, for a villager that found no stash.
local function chest_by(bed)
	for r = 1, 3 do
		for dx = -r, r do
			for dz = -r, r do
				local p = {x = bed.x + dx, y = bed.y, z = bed.z + dz}
				local below = core.registered_nodes[node({x = p.x, y = p.y - 1, z = p.z})]
				if node(p) == "air" and below and below.walkable and not node(p):find("bed") then
					place("stash chest", p, "mcl_chests:chest_small")
					return true
				end
			end
		end
	end
	return false
end

-- 5. What the economy needs round the village.
local function phase_extras()
	local butcher
	for _, e in ipairs(villagers()) do
		if trade_of(e) == "butcher" and e._jobsite then butcher = e end
	end
	if butcher then
		local j = butcher._jobsite
		local n = 0
		for dx = -2, 2 do
			for dz = -2, 2 do
				local p = {x = j.x + dx, y = j.y, z = j.z + dz}
				if n < 2 and node(p) == "air" and node({x = p.x, y = p.y + 1, z = p.z}) == "air" then
					core.add_entity(p, "mobs_mc:chicken")
					n = n + 1
					report.placed[#report.placed + 1] = {what = "chicken", pos = core.pos_to_string(p)}
				end
			end
		end
	end
	local grove = spot(15, 15, 30, 95)
	if grove then
		for i = 0, 2 do
			for k = 0, 2 do
				local p = {x = grove.x + 2 + 5 * i, y = G + 1, z = grove.z + 2 + 5 * k}
				mcl_core.generate_oak_tree(p)
			end
		end
		report.placed[#report.placed + 1] = {what = "oak grove", pos = core.pos_to_string(grove)}
	end
	local cane = spot(14, 3, 25, 95)
	if cane then
		for k = 1, 12 do
			core.set_node({x = cane.x + k, y = G, z = cane.z + 1}, {name = WATER})
			core.set_node({x = cane.x + k, y = G + 1, z = cane.z}, {name = "mcl_core:reeds"})
			core.set_node({x = cane.x + k, y = G + 1, z = cane.z + 2}, {name = "mcl_core:reeds"})
		end
		report.placed[#report.placed + 1] = {what = "cane channel", pos = core.pos_to_string(cane)}
	end
	local flowers = spot(8, 8, 20, 95)
	if flowers then
		for i = 0, 7 do
			for k = 0, 7 do
				if (i + k) % 2 == 0 then
					core.set_node({x = flowers.x + i, y = G + 1, z = flowers.z + k}, {name = "mcl_flowers:poppy"})
				end
			end
		end
		report.placed[#report.placed + 1] = {what = "poppies", pos = core.pos_to_string(flowers)}
	end
	local quarry = spot(9, 8, 25, 95)
	if quarry then
		settlements.place_schematics({{pos = {x = quarry.x + 1, y = G, z = quarry.z + 1}, name = "quarry",
			rotat = "0", surface_mat = GRASS}}, PseudoRandom(SEED + 2))
		report.placed[#report.placed + 1] = {what = "quarry", pos = core.pos_to_string(quarry)}
	end
	local _, _, _, no_stash = census()
	for _, e in ipairs(no_stash) do
		if WORK_CHEST[trade_of(e)] then
			chest_by(e._jobsite)
		else
			chest_by(e._bed)
		end
	end
	log("extras: grove %s, cane %s, poppies %s, quarry %s, %d stash chests added",
		tostring(grove ~= nil), tostring(cane ~= nil), tostring(flowers ~= nil), tostring(quarry ~= nil), #no_stash)
	core.after(90, phase_census)
end

-- 4. A job block for each missing trade, and more villagers if too few are free.
local function phase_fill()
	local by_trade, _, missing = census()
	local free = by_trade.unemployed or 0
	report.first_census = {by_trade = by_trade, missing = missing}
	log("after staffing: %d adults, missing [%s], %d out of work", #villagers(), table.concat(missing, " "), free)
	for _, trade in ipairs(missing) do
		if STRUCTURAL[trade] then
			return finish(false, "no " .. trade .. ": its building was not placed (try another lv_town_seed)")
		end
	end
	for _, trade in ipairs(missing) do
		local name = REQUIRED[trade]
		if not core.registered_nodes[name] then return finish(false, "unknown node " .. name) end
		local at
		if trade == "fisherman" and report.pond then
			at = spot(3, 3, report.pond.r, report.pond.r + 15, 1)
		end
		at = at or spot(3, 3, 12, 95, 2)
		if not at then return finish(false, "no room for the " .. trade .. "'s block") end
		place(trade .. " block", {x = at.x + 1, y = G + 1, z = at.z + 1}, name)
		if trade == "woodcutter" then
			place("woodcutter chest", {x = at.x + 2, y = G + 1, z = at.z + 1}, "mcl_chests:chest_small")
		end
	end
	local houses = {}
	for _ = 1, math.max(#missing + LABOUR - free, 0) do
		local at = spot(10, 10, 20, 95, 3)
		if not at then return finish(false, "no room for another house") end
		houses[#houses + 1] = {pos = at, name = "tower_house", rotat = "0", surface_mat = GRASS}
	end
	if #houses > 0 then
		settlements.place_schematics(houses, PseudoRandom(SEED + 1))
		report.placed[#report.placed + 1] = {what = #houses .. " tower houses"}
	end
	log("filled %d trades, %d more houses", #missing, #houses)
	core.after(200, phase_extras)
end

-- 2 and 3. The pond, then the village.
local function phase_village()
	local surface
	for y = 60, -40, -1 do
		local name = node({x = 0, y = y, z = 0})
		if name ~= "air" and name ~= "ignore" then G, surface = y, name break end
	end
	if not G then return finish(false, "no ground at spawn") end
	local biome = core.get_biome_data and core.get_biome_name(core.get_biome_data({x = 0, y = G, z = 0}).biome)
	report.ground, report.biome = G, biome
	if surface ~= GRASS then
		return finish(false, string.format("ground at spawn is %s (%s); try another lv_town_seed", surface, tostring(biome)))
	end
	-- The pond: the fisherman's hut is only planned with water in reach (site_planner.lua).
	local px, pz = 22, 18
	for x = px, px + 5 do
		for z = pz, pz + 7 do
			core.set_node({x = x, y = G, z = z}, {name = WATER})
			core.set_node({x = x, y = G - 1, z = z}, {name = WATER})
		end
	end
	report.pond = {x = px, z = pz, r = math.floor(math.sqrt(px * px + pz * pz))}
	reserved[#reserved + 1] = {px - 2, pz - 2, 10, 12}
	building = true
	local minp, maxp = {x = -40, y = G - 40, z = -40}, {x = 39, y = G + 39, z = 39}
	local ok, info = pcall(settlements.create_site_plan, maxp, minp, pr)
	building = false
	if not ok or not info then return finish(false, "no village plan: " .. tostring(info)) end
	local names = {}
	for _, b in ipairs(info) do names[#names + 1] = b.name end
	report.plan = names
	log("planned %d buildings: %s", #info, table.concat(names, " "))
	settlements.terraform(info, pr)
	settlements.paths(info)
	settlements.place_schematics(info, pr)
	core.after(150, phase_fill)
end

-- 1. Load the area.
core.after(3, function()
	core.set_timeofday(0.3)
	local n = 0
	for bx = -AREA, AREA, 16 do
		for bz = -AREA, AREA, 16 do
			for by = -32, 48, 16 do
				core.forceload_block({x = bx, y = by, z = bz}, true)
				n = n + 1
			end
		end
	end
	log("setup with seed %d: forceloaded %d blocks, emerging", SEED, n)
	core.emerge_area({x = -AREA, y = -32, z = -AREA}, {x = AREA, y = 63, z = AREA}, function(_, _, remaining)
		if remaining == 0 then core.after(2, phase_village) end
	end)
end)
