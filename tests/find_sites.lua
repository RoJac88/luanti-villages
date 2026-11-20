-- Run with: lua tests/find_sites.lua
local now, searches = 100, 0
local nodes = {}
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	get_timeofday = function() return 0.5 end,
	get_item_group = function() return 0 end,
	get_node_or_nil = function(pos) return {name = nodes[key(pos)] or "air"} end,
	find_nodes_in_area = function(minp, maxp, names)
		searches = searches + 1
		local found = {}
		for k, name in pairs(nodes) do
			local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
			x, y, z = tonumber(x), tonumber(y), tonumber(z)
			if name == names[1] and x >= minp.x and x <= maxp.x and y >= minp.y and y <= maxp.y
				and z >= minp.z and z <= maxp.z then
				found[#found + 1] = {x = x, y = y, z = z}
			end
		end
		return found
	end,
}
local common = dofile("common.lua")
local BELL = "mcl_bells:bell"

nodes[key({x = 40, y = 5, z = 0})] = BELL
nodes[key({x = 90, y = 5, z = 0})] = BELL

-- Two villagers in one 16-node cell share a search; each sees only its own box.
local a = common.find_sites({BELL}, {x = 1, y = 0, z = 1}, 80, 32)
local b = common.find_sites({BELL}, {x = 14, y = 0, z = 3}, 80, 32)
assert(searches == 1, "one search for the cell")
assert(#a == 1 and a[1].x == 40, "the bell 89 away is outside the first villager's box")
assert(#b == 2, "and inside the second's")

-- Another cell searches for itself.
common.find_sites({BELL}, {x = 200, y = 0, z = 0}, 80, 32)
assert(searches == 2)

-- A bell taken down is not handed out from the shared search; another is found at once.
nodes[key({x = 40, y = 5, z = 0})] = nil
nodes[key({x = 30, y = 5, z = 0})] = BELL
a = common.find_sites({BELL}, {x = 1, y = 0, z = 1}, 80, 32)
assert(#a == 1 and a[1].x == 30 and searches == 3, "none left in the cache, so it searched again")

-- The shared search lasts SITE_SECONDS.
common.find_sites({BELL}, {x = 2, y = 0, z = 2}, 80, 32)
assert(searches == 3)
now = now + 10
common.find_sites({BELL}, {x = 2, y = 0, z = 2}, 80, 32)
assert(searches == 4, "an old search is done again")

print("find_sites tests passed")
