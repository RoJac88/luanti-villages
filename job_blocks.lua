-- The job blocks a villager can take, and how each is claimed: every workstation
-- (common.lua's table, a composter at any fill level, a cauldron), the Builder's
-- bench, the tavern's jukebox and the church's pulpit. village_staffing.lua hands
-- them out when a village is placed; job_seek.lua sends a villager out of work to
-- the free one nearest its bed.
--
-- A workstation is claimed as VoxeLibre's employ (mobs_mc/villager.lua:1150) claims
-- one: the node's meta `villager`, `_jobsite` and `_profession`; init.lua's
-- tick_visual puts on the skin. The others go through their own module's claim, so
-- their saved state is what it would have been: `roles` is {builder = builder.lua,
-- keeper = keeper.lua, cleric = cleric.lua}, any of them missing, looked up at the
-- call (the Builder is installed later than the rest).
local core = minetest
local common = dofile(core.get_modpath("living_villages") .. "/common.lua")

local M = {}

local JUKEBOX = "mcl_jukebox:jukebox"
local PULPIT = "living_villages:pulpit"
local LEATHERWORKER = "leatherworker"

local composter_levels = {"mcl_composters:composter_ready"}
for level = 1, 7 do table.insert(composter_levels, "mcl_composters:composter_" .. level) end

local function bench_name(roles)
	return roles and roles.builder and roles.builder.BENCH
end

-- The node names to look for, for find_nodes_in_area.
function M.search_nodes(roles)
	local names = {}
	for _, name in ipairs(common.workstation_search_nodes()) do table.insert(names, name) end
	for _, name in ipairs(composter_levels) do table.insert(names, name) end
	table.insert(names, JUKEBOX)
	if roles and roles.cleric then table.insert(names, PULPIT) end
	local bench = bench_name(roles)
	if bench then table.insert(names, bench) end
	return names
end

-- "workstation", "bench", "jukebox", "pulpit", or nil for a node that is no job.
function M.kind(name, roles)
	if not name then return nil end
	if name == JUKEBOX then return roles and roles.keeper and "jukebox" or nil end
	if name == PULPIT then return roles and roles.cleric and "pulpit" or nil end
	if name == bench_name(roles) then return "bench" end
	if common.is_workstation_node(name) then return "workstation" end
	return nil
end

-- The profession a workstation makes.
function M.profession(name)
	return common.workstation_profession(name)
		or (core.get_item_group(name, "cauldron") > 0 and LEATHERWORKER or nil)
end

function M.is_free(pos, roles)
	local node = pos and core.get_node_or_nil(pos)
	return node ~= nil and M.kind(node.name, roles) ~= nil and core.get_meta(pos):get_string("villager") == ""
end

-- Saved on a villager a new village left out of work (village_staffing.lua): it stays
-- in the labour pool, and no job module gives it a block.
M.LEFT_UNEMPLOYED = "_villages_left_unemployed"

-- Who may take one: an adult out of work, with no jobsite, not left out of work on purpose.
function M.eligible(self)
	return not self.child and self._id ~= nil and not self._jobsite and self._profession == "unemployed"
		and not self[M.LEFT_UNEMPLOYED]
end

local function claim_workstation(self, pos, name)
	local profession = M.profession(name)
	if not profession then return false end
	core.get_meta(pos):set_string("villager", self._id)
	self._jobsite = {x = pos.x, y = pos.y, z = pos.z}
	self._profession = profession
	core.log("action", string.format("[living_villages] villager %s became %s at the %s at %s",
		tostring(self._id), profession, name, core.pos_to_string(pos)))
	return true
end

-- Claims the free job block at pos for self. Returns whether it did.
function M.claim(self, pos, roles)
	if not M.eligible(self) or not M.is_free(pos, roles) then return false end
	local name = core.get_node_or_nil(pos).name
	local kind = M.kind(name, roles)
	-- keeper.lua and cleric.lua stand aside for a villager on its way to a job; this is that job.
	local seeking = self._villages_farm_seek
	self._villages_farm_seek = nil
	local ok
	if kind == "workstation" then
		ok = claim_workstation(self, pos, name)
	elseif kind == "bench" then
		ok = roles.builder.employ(self, pos)
	elseif kind == "jukebox" then
		ok = roles.keeper.employ(self, pos)
	elseif kind == "pulpit" then
		ok = roles.cleric.employ(self, pos)
	end
	if not ok then self._villages_farm_seek = seeking end
	return ok == true
end

-- The free job block nearest `from` among `sites`, skipping any `skip` says to.
function M.nearest_free(from, sites, roles, skip)
	local best, best_distance
	for _, site in ipairs(sites) do
		if (not skip or not skip(site)) and M.is_free(site, roles) then
			local distance = vector.distance(from, site)
			if not best or distance < best_distance then best, best_distance = site, distance end
		end
	end
	return best
end

-- Greedy pairing: of every (villager, block) pair the closest bed and block go
-- first, then the closest of the rest, until `limit` villagers have a block or
-- either side runs out. `villagers` are {bed = pos, ...}, `blocks` positions.
-- `try(villager, block)`, if given, makes the claim; a block it fails on is passed
-- over and the villager goes on to its next nearest. Returns {{villager = v,
-- block = pos}, ...} in the order taken. Ties go to the lower index, so the result
-- is fixed for the same input.
function M.pair(villagers, blocks, limit, try)
	local pairs_by_distance = {}
	for vi, v in ipairs(villagers) do
		for bi, block in ipairs(blocks) do
			table.insert(pairs_by_distance, {vi = vi, bi = bi, distance = vector.distance(v.bed, block)})
		end
	end
	table.sort(pairs_by_distance, function(a, b)
		if a.distance ~= b.distance then return a.distance < b.distance end
		if a.vi ~= b.vi then return a.vi < b.vi end
		return a.bi < b.bi
	end)
	local taken_v, taken_b, result = {}, {}, {}
	limit = math.min(limit or #villagers, #villagers)
	for _, p in ipairs(pairs_by_distance) do
		if #result >= limit then break end
		if not taken_v[p.vi] and not taken_b[p.bi] then
			taken_b[p.bi] = true
			if not try or try(villagers[p.vi], blocks[p.bi]) then
				taken_v[p.vi] = true
				table.insert(result, {villager = villagers[p.vi], block = blocks[p.bi]})
			end
		end
	end
	return result
end

return M
