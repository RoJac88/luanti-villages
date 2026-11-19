-- Run with: luajit tests/env_touch.lua
-- A stand-in for mcl_mobs' do_env_damage: the lava cells its box reaches, rounded the
-- way find_nodes_in_area rounds a position (half away from zero), as get_env_hits does.
local lava = {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function round(v) return v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5) end
local seen_box
local def = {initial_properties = {collisionbox = {-0.3, -0.01, -0.3, 0.3, 1.94, 0.3}}}
def.do_env_damage = function(self)
	local cb = self.base_colbox or self.initial_properties.collisionbox
	seen_box = cb
	local p = self.pos
	for x = round(p.x + cb[1]), round(p.x + cb[4]) do
		for y = round(p.y + cb[2]), round(p.y + cb[5]) do
			for z = round(p.z + cb[3]), round(p.z + cb[6]) do
				if lava[key(x, y, z)] then self.burnt = true; return "burnt" end
			end
		end
	end
end
dofile("env_touch.lua")(def)

local function villager(x, y, z)
	return setmetatable({pos = {x = x, y = y, z = z}, base_colbox = {-0.3, -0.01, -0.3, 0.3, 1.94, 0.3}},
		{__index = def})
end

-- The ColonyFood generator: lava at (-143, 6, -19), diagonal to the stand cell
-- (-144, 6, -20). Wedged in its corner, the box's edges lie on x -143.5 and z -19.5;
-- float error puts them a hair inside the lava's cell.
lava[key(-143, 6, -19)] = true
lava[key(-143, 7, -19)] = true
local v = villager(-143.8 + 1e-9, 5.51, -19.8 + 1e-9)
assert(v:do_env_damage() == nil and not v.burnt, "a villager only touching the lava's corner is not burnt")
assert(v.base_colbox[1] == -0.3 and v.base_colbox[4] == 0.3, "its box is given back after the check")
assert(seen_box[1] == -0.25 and seen_box[4] == 0.25 and seen_box[2] == -0.01 and seen_box[5] == 1.94,
	"the check sees the box drawn in across, not in height")
-- Stepped a little into the lava's cell, it burns.
v = villager(-143.6, 5.51, -19.6)
assert(v:do_env_damage() == "burnt" and v.burnt, "a villager overlapping lava is burnt")
-- Its own box absent, the def's is drawn in, and none is left on the villager.
v = villager(-143.6, 5.51, -19.6)
v.base_colbox = nil
assert(v:do_env_damage() == "burnt")
assert(rawget(v, "base_colbox") == nil, "no box is left on a villager that had none")
assert(seen_box[1] == -0.25)
print("env_touch tests passed")
