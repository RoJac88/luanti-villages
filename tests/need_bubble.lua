-- Run with: lua tests/need_bubble.lua
local settings, particles, steps, hits, players = {}, {}, {}, {}, {}
local now = 0
vector = {
	add = function(a, b) return {x = a.x + b.x, y = a.y + b.y, z = a.z + b.z} end,
	multiply = function(a, n) return {x = a.x * n, y = a.y * n, z = a.z * n} end,
	distance = function() return 0 end,
}
local cast
minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return now end,
	settings = {
		get = function(_, name) return settings[name] end,
		get_bool = function(_, name, default)
			if settings[name] == nil then return default end
			return settings[name]
		end,
	},
	log = function() end,
	registered_items = {
		["mcl_core:coal_lump"] = {inventory_image = "coal.png"},
		["mcl_core:cobble"] = {inventory_image = "", tiles = {"cobble.png"}},
		["mcl_core:stone"] = {tiles = {{name = "top.png"}, "bottom.png", "side.png"}},
		["no:picture"] = {},
	},
	inventorycube = function(a, b, c) return "cube:" .. a .. "," .. b .. "," .. c end,
	raycast = function(from, to, objects, liquids)
		cast = {from = from, to = to, objects = objects, liquids = liquids}
		local i = 0
		return function()
			i = i + 1
			return hits[i]
		end
	end,
	add_particle = function(def) particles[#particles + 1] = def end,
	register_globalstep = function(fn) steps[#steps + 1] = fn end,
	get_connected_players = function() return players end,
}

local bubble = dofile("need_bubble.lua")

-- Textures: the inventory image, else a cube of the tiles.
assert(bubble.texture("mcl_core:coal_lump") == "coal.png")
assert(bubble.texture("mcl_core:cobble") == "cube:cobble.png,cobble.png,cobble.png")
assert(bubble.texture("mcl_core:stone") == "cube:top.png,side.png,side.png")
assert(bubble.texture("no:picture") == nil and bubble.texture("no:thing") == nil)

local player = {
	get_pos = function() return {x = 0, y = 0, z = 0} end,
	get_properties = function() return {eye_height = 1.5} end,
	get_look_dir = function() return {x = 1, y = 0, z = 0} end,
	get_player_name = function() return "pat" end,
}
players[1] = player
local smith = {name = "mobs_mc:villager", _id = "sam", _profession = "tool_smith", _max_trade_tier = 1,
	_villages_food = 20, _villages_belongings = {}}
smith.object = {get_pos = function() return {x = 4, y = 0, z = 0} end, get_luaentity = function() return smith end}
local cow = {get_luaentity = function() return {name = "mobs_mc:cow"} end}

-- Looking at the smith, within 8, from the eye.
hits = {{type = "object", ref = player}, {type = "object", ref = smith.object}}
assert(bubble.looked_at(player) == smith)
assert(cast.from.y == 1.5 and cast.to.x == bubble.RANGE and cast.objects == true and cast.liquids == false)
-- A wall or another creature first hides it; a child shows nothing.
hits = {{type = "node"}, {type = "object", ref = smith.object}}
assert(bubble.looked_at(player) == nil)
hits = {{type = "object", ref = cow}, {type = "object", ref = smith.object}}
assert(bubble.looked_at(player) == nil)
smith.child = true
hits = {{type = "object", ref = smith.object}}
assert(bubble.looked_at(player) == nil)
smith.child = nil

-- A smith with nothing needs what its recipes take; the bubble shows it to that player only.
hits = {{type = "object", ref = smith.object}}
bubble.install()
assert(#steps == 1)
steps[1](0.5)
assert(#particles == 0, "once a second")
steps[1](0.6)
assert(#particles == 1)
local shown = particles[1]
assert(shown.playername == "pat" and shown.pos.x == 4 and shown.pos.y > 2 and shown.expirationtime > bubble.INTERVAL)
local need = bubble.need(smith, now)
assert(need and shown.texture == bubble.texture(need), tostring(need))
-- The need is cached for a few seconds.
smith._villages_belongings = {["mcl_core:cobble"] = 500, ["mcl_core:stick"] = 500, ["mcl_core:coal_lump"] = 500}
assert(bubble.need(smith, now + 1) == need)
assert(bubble.need(smith, now + 10) ~= need)

-- Off with the economy.
settings.living_villages_economy = false
steps = {}
bubble.install()
assert(#steps == 0)

print("need_bubble.lua: ok")
