-- Run with: lua tests/theft.lua
local now = 100
local settings, logs, metas, objects = {}, {}, {}, {}
local blocked = false
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end

vector = {
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	subtract = function(a, n) return {x = a.x - n, y = a.y - n, z = a.z - n} end,
	add = function(a, n) return {x = a.x + n, y = a.y + n, z = a.z + n} end,
}

local serialized = {}
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
	log = function(_, message) logs[#logs + 1] = message end,
	pos_to_string = function(p) return "(" .. key(p) .. ")" end,
	line_of_sight = function() return not blocked end,
	get_node_or_nil = function() return {name = "mcl_chests:chest_small"} end,
	serialize = function(v)
		serialized[#serialized + 1] = v
		return "#" .. #serialized
	end,
	deserialize = function(text) return serialized[tonumber((text or ""):match("^#(%d+)$") or -1)] end,
	get_meta = function(pos)
		local fields = metas[key(pos)] or {}
		metas[key(pos)] = fields
		return {
			get_string = function(_, k) return fields[k] or "" end,
			set_string = function(_, k, v) fields[k] = v ~= "" and v or nil end,
		}
	end,
	get_objects_inside_radius = function(pos, radius)
		local found = {}
		for _, object in ipairs(objects) do
			if vector.distance(object:get_pos(), pos) <= radius then found[#found + 1] = object end
		end
		return found
	end,
	registered_nodes = {},
	override_item = function(name, fields)
		for k, v in pairs(fields) do minetest.registered_nodes[name][k] = v end
	end,
}

local theft = dofile("theft.lua")
local noted = {}
local gossip = {add = function(villager, name, kind) noted[#noted + 1] = {villager._id, name, kind} end}

local function villager(id, pos, fields)
	local self = {name = "mobs_mc:villager", _id = id}
	for k, v in pairs(fields or {}) do self[k] = v end
	self.object = {get_pos = function() return pos end, get_luaentity = function() return self end}
	objects[#objects + 1] = self.object
	return self
end
local function player(name, pos)
	return {
		is_player = function() return true end,
		get_player_name = function() return name end,
		get_pos = function() return pos end,
	}
end
local function stack(name, count)
	return {is_empty = function() return count == 0 end, get_name = function() return name end, get_count = function() return count end}
end

local chest = {x = 0, y = 0, z = 0}
metas[key(chest)] = {villages_owner = "olga-owner"}
local olga = villager("olga-owner", {x = 30, y = 0, z = 0}, {_villages_stash = chest})
local wit = villager("wit", {x = 5, y = 0, z = 0})
villager("far", {x = 20, y = 0, z = 0})
villager("dozy", {x = 2, y = 0, z = 0}, {_villages_sleeping = true})
local pat = player("pat", {x = 1, y = 0, z = 0})

-- A take from a stash in sight: the awake villager within 16 notes it.
local seen = theft.taken(gossip, chest, stack("mcl_farming:bread", 3), pat)
assert(#seen == 1 and seen[1] == wit and #noted == 1)
assert(noted[1][2] == "pat" and noted[1][3] == "minor_negative")
assert(logs[#logs]:find("pat took 3 mcl_farming:bread") and logs[#logs]:find("seen by 1"))
-- The next stack inside a minute is the same theft.
theft.taken(gossip, chest, stack("mcl_core:emerald", 2), pat)
assert(#noted == 1, "one theft per witness a minute")
now = now + theft.COOLDOWN
-- Behind a wall nobody sees.
blocked = true
assert(#theft.taken(gossip, chest, stack("mcl_farming:bread", 1), pat) == 0)
blocked = false

-- The owner finds what went, once.
local found = theft.discover(olga)
assert(found["mcl_farming:bread"] == 4 and found["mcl_core:emerald"] == 2)
assert(logs[#logs]:find("found 2 mcl_core:emerald, 4 mcl_farming:bread gone from its stash"), logs[#logs])
assert(theft.discover(olga) == nil)

-- An unclaimed chest, or no player: nothing.
local plain = {x = 50, y = 0, z = 0}
assert(#theft.taken(gossip, plain, stack("mcl_farming:bread", 1), pat) == 0 and metas[key(plain)].villages_missing == nil)
assert(#theft.taken(gossip, chest, stack("mcl_farming:bread", 1), nil) == 0)

-- install wraps the chests' take callback and keeps vanilla's.
local vanilla_called = false
for _, name in ipairs({"mcl_chests:chest", "mcl_chests:chest_small", "mcl_chests:chest_left", "mcl_chests:chest_right"}) do
	minetest.registered_nodes[name] = {on_metadata_inventory_take = function() vanilla_called = true end}
end
local def = {do_custom = function() return "vanilla" end}
theft.install(gossip, def)
now = now + theft.COOLDOWN
minetest.registered_nodes["mcl_chests:chest_small"].on_metadata_inventory_take(chest, "main", 1, stack("mcl_core:stick", 1), pat)
assert(vanilla_called and #noted == 2)
assert(def.do_custom(olga, 0.1) == "vanilla")
assert(metas[key(chest)].villages_missing == nil, "the owner looked")

-- Off with the economy.
settings.living_villages_economy = false
assert(#theft.taken(gossip, chest, stack("mcl_farming:bread", 1), pat) == 0)

print("theft.lua: ok")
