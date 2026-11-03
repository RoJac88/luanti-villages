-- Run with: luajit tests/farm_jobs.lua
local nodes, metas, finds = {}, {}, {}
local now, time, settings = 100, 0.4, {}
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
local COMPOSTER, BARREL = "mcl_composters:composter", "mcl_barrels:barrel_closed"

local function round(pos)
	return {x = math.floor(pos.x + 0.5), y = math.floor(pos.y + 0.5), z = math.floor(pos.z + 0.5)}
end

minetest = {
	get_modpath = function() return "." end,
	get_timeofday = function() return time end,
	get_gametime = function() return now end,
	settings = {get = function(_, name) return settings[name] end},
	registered_nodes = {},
	log = function() end,
	pos_to_string = key,
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
		table.insert(finds, {minp = minp, maxp = maxp})
		local lo, hi, found = round(minp), round(maxp), {}
		for k, name in pairs(nodes) do
			local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
			x, y, z = tonumber(x), tonumber(y), tonumber(z)
			if name == names[1] and x >= lo.x and x <= hi.x and y >= lo.y and y <= hi.y and z >= lo.z and z <= hi.z then
				table.insert(found, {x = x, y = y, z = z})
			end
		end
		return found
	end,
}
vector = {
	add = function(a, n) return {x = a.x + n, y = a.y + n, z = a.z + n} end,
	subtract = function(a, n) return {x = a.x - n, y = a.y - n, z = a.z - n} end,
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	equals = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end,
	distance = function(a, b)
		local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
		return math.sqrt(x * x + y * y + z * z)
	end,
}
mcl_mobs = {mob_class = {}}

local common = dofile("common.lua")
local farm_jobs = dofile("farm_jobs.lua")

-- Vanilla's get_a_job as far as this needs it: an untraded villager beside any
-- workstation takes it. A traded-looking one, unemployed, has none to ask for.
local vanilla_seen
local def = {do_custom = function(self)
	vanilla_seen = self._trades
	if self._profession == "unemployed" and self._trades == nil and self._barrel_beside then
		metas[key(self._barrel_beside)] = {villager = self._id}
		self._jobsite, self._profession = self._barrel_beside, "fisherman"
	end
end}
local trips = {}
local navigation = {seek_composter = function(self, site, on_arrival)
	table.insert(trips, {self = self, site = site, on_arrival = on_arrival})
	return true
end}
farm_jobs.install(def, navigation)

local function villager(pos, extra)
	local entity = {
		_id = "v" .. tostring(math.random(1e9)), _profession = "unemployed", state = "stand",
		object = {get_pos = function() return pos end},
	}
	for k, v in pairs(extra or {}) do entity[k] = v end
	return entity
end
local function reset()
	nodes, metas, finds, trips = {}, {}, {}, {}
	now, time, settings = now + 1000, 0.4, {}
end

-- Nothing free: vanilla's search runs as ever, with no stand-in, and the wide scan is throttled.
do
	reset()
	local v = villager({x = 0, y = 0, z = 0})
	def.do_custom(v, 0.1)
	assert(vanilla_seen == nil and not v._villages_farm_seek and #trips == 0)
	assert(#finds == 1)
	def.do_custom(v, 0.1)
	assert(#finds == 1, "the scan must not run every tick")
	now = now + 31
	def.do_custom(v, 0.1)
	assert(#finds == 2)
end

-- A free composter beyond vanilla's 48 nodes is sought, while vanilla's own search asks for nothing.
do
	reset()
	local far = {x = 90, y = 0, z = 0}
	nodes[key(far)] = COMPOSTER
	local v = villager({x = 0, y = 0, z = 0}, {_trades = "own"})
	def.do_custom(v, 0.1)
	assert(vanilla_seen:find("traded_once", 1, true), "vanilla must see a traded-looking list")
	assert(v._trades == "own", "the real list comes back")
	assert(v._villages_farm_seek.x == 90)
	assert(#trips == 1 and trips[1].site.x == 90)
	local minp, maxp = common.farm_job_box({x = 0, y = 0, z = 0})
	assert(maxp.x == 96 and minp.y == -24)
	-- A far one past the setting is not seen.
	reset()
	nodes[key(far)] = COMPOSTER
	settings.living_villages_farm_job_radius = "64"
	local near_only = villager({x = 0, y = 0, z = 0})
	def.do_custom(near_only, 0.1)
	assert(not near_only._villages_farm_seek and #trips == 0)
	-- The engine's limit on a box holds at the setting's largest.
	settings.living_villages_farm_job_radius = "9999"
	minp, maxp = common.farm_job_box({x = 0, y = 0, z = 0})
	assert((maxp.x - minp.x + 1) * (maxp.y - minp.y + 1) * (maxp.z - minp.z + 1) <= 4096000)
end

-- A barrel right beside it does not win: the composter comes first.
do
	reset()
	local barrel = {x = 1, y = 0, z = 0}
	nodes[key(barrel)] = BARREL
	nodes[key({x = 30, y = 0, z = 0})] = COMPOSTER
	local v = villager({x = 0, y = 0, z = 0}, {_barrel_beside = barrel})
	def.do_custom(v, 0.1)
	assert(v._profession == "unemployed" and not v._jobsite, "the barrel must not be claimed")
	assert(not (metas[key(barrel)] and metas[key(barrel)].villager))
	-- Arriving beside the composter makes a farmer of it, and keeps the claim.
	local site = {x = 30, y = 0, z = 0}
	local arrived = villager({x = 29, y = 0, z = 0})
	trips[1].on_arrival(arrived)
	assert(arrived._profession == "farmer" and arrived._jobsite.x == 30)
	assert(metas[key(site)].villager == arrived._id)
	assert(not arrived._villages_farm_seek)
end

-- Already beside one: claims it without a trip.
do
	reset()
	nodes[key({x = 1, y = 0, z = 0})] = COMPOSTER
	local v = villager({x = 0, y = 0, z = 0})
	def.do_custom(v, 0.1)
	assert(v._profession == "farmer" and #trips == 0)
end

-- A claimed composter, or one with a fill level no search can claim, is no reason to wait.
do
	reset()
	local claimed = {x = 5, y = 0, z = 0}
	nodes[key(claimed)] = COMPOSTER
	metas[key(claimed)] = {villager = "someone"}
	nodes[key({x = 6, y = 0, z = 0})] = "mcl_composters:composter_3"
	local v = villager({x = 0, y = 0, z = 0})
	def.do_custom(v, 0.1)
	assert(vanilla_seen == nil and not v._villages_farm_seek)
end

-- Someone else takes it: the next tick looks again, and with nothing left vanilla has it back.
do
	reset()
	local one, two = {x = 10, y = 0, z = 0}, {x = 20, y = 0, z = 0}
	nodes[key(one)] = COMPOSTER
	nodes[key(two)] = COMPOSTER
	local v = villager({x = 0, y = 0, z = 0})
	def.do_custom(v, 0.1)
	assert(v._villages_farm_seek.x == 10)
	metas[key(one)] = {villager = "someone"}
	def.do_custom(v, 0.1)
	assert(v._villages_farm_seek.x == 20, "another free composter must be found at once")
	metas[key(two)] = {villager = "someone"}
	def.do_custom(v, 0.1)
	assert(not v._villages_farm_seek and vanilla_seen == nil)
end

-- None it can reach: the other jobs are open again for a while, without waiting on the route's backoff.
do
	reset()
	nodes[key({x = 10, y = 0, z = 0})] = COMPOSTER
	local v = villager({x = 0, y = 0, z = 0})
	def.do_custom(v, 0.1)
	assert(#trips == 1)
	now = now + 2
	v._villages_job_search_route = {status = "retry", reason = "no reachable unclaimed workstation", retry_at = now + 30}
	def.do_custom(v, 0.1)
	assert(not v._villages_farm_seek and not v._villages_job_search_route)
	def.do_custom(v, 0.1)
	assert(vanilla_seen == nil, "vanilla's search is back")
	now = now + 301
	def.do_custom(v, 0.1)
	assert(v._villages_farm_seek, "and the composter is tried again later")
end

-- A failure from before the search, or a pathfinder pause, says nothing about the composter.
do
	reset()
	nodes[key({x = 10, y = 0, z = 0})] = COMPOSTER
	local v = villager({x = 0, y = 0, z = 0}, {
		_villages_job_search_route = {status = "retry", reason = "no reachable unclaimed workstation", retry_at = now + 30},
	})
	def.do_custom(v, 0.1)
	assert(v._villages_farm_seek and #trips == 1, "an older failure must not count against this composter")
	now = now + 6
	v._villages_job_search_route = {status = "retry", reason = "pathfinder cooldown", retry_at = now + 20}
	def.do_custom(v, 0.1)
	assert(v._villages_farm_seek and #trips == 1)
	now = now + 21
	def.do_custom(v, 0.1)
	assert(v._villages_farm_seek and #trips == 2)
end

-- Off work it holds the job open but goes nowhere; on a walk, it is left to finish.
do
	reset()
	nodes[key({x = 10, y = 0, z = 0})] = COMPOSTER
	time = 0 -- night
	local v = villager({x = 0, y = 0, z = 0})
	def.do_custom(v, 0.1)
	assert(v._villages_farm_seek and vanilla_seen and #trips == 0)
	time = 0.4
	v.state = "gowp"
	def.do_custom(v, 0.1)
	assert(#trips == 0)
end

-- Anyone with a job, a child, a nitwit: left alone, and a stale mark is dropped.
do
	reset()
	nodes[key({x = 10, y = 0, z = 0})] = COMPOSTER
	for _, extra in ipairs({
		{_profession = "mason", _villages_farm_seek = {x = 1, y = 1, z = 1}},
		{child = true},
		{_profession = "nitwit"},
		{_profession = "fisherman", _jobsite = {x = 0, y = 0, z = 1}},
	}) do
		local v = villager({x = 0, y = 0, z = 0}, extra)
		def.do_custom(v, 0.1)
		assert(not v._villages_farm_seek and #trips == 0 and vanilla_seen == v._trades)
	end
end

print("farm_jobs.lua: ok")
