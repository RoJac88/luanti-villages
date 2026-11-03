local time, now = 0.4, 100
local crop = {x = 2, y = 0, z = 0}
local crop_name, removed, replanted, path_target, arrived = "mcl_farming:wheat", nil, nil, nil, nil
local nearby_objects = {}
local existing_drop = {
	removed = false,
	get_luaentity = function() return {name = "__builtin:item", itemstring = "mcl_farming:potato_item"} end,
	remove = function(self) self.removed = true end,
}
local nearby_villager = {
	removed = false,
	get_luaentity = function() return {name = "mobs_mc:villager"} end,
	remove = function(self) self.removed = true end,
}

minetest = {
	get_modpath = function() return "." end,
	get_timeofday = function() return time end,
	get_gametime = function() return now end,
	get_item_group = function() return 0 end,
	get_node_or_nil = function(pos)
		if pos.x == 0 then return {name = "mcl_composters:composter"} end
		if pos.x == 2 then return {name = crop_name} end
		return {name = "air"}
	end,
	get_meta = function()
		return {get_string = function(_, name) return name == "villager" and "farmer-1" or "" end}
	end,
	find_nodes_in_area = function() return {crop} end,
	get_objects_inside_radius = function() return nearby_objects end,
	is_protected = function() return false end,
	remove_node = function(pos)
		removed = pos
		crop_name = "air"
	end,
	set_node = function(pos, node) replanted = {pos = pos, name = node.name}; crop_name = node.name end,
}
vector = {
	new = function(pos) return {x = pos.x, y = pos.y, z = pos.z} end,
	distance = function(a, b)
		local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
		return math.sqrt(x * x + y * y + z * z)
	end,
}

local def = {
	do_custom = function() end,
}
dofile("farmer.lua").install(def)
local farmer = {
	_id = "farmer-1", _profession = "farmer", _jobsite = {x = 0, y = 0, z = 0}, state = "stand",
	object = {get_pos = function() return {x = 1, y = 0, z = 0} end},
	gopath = function(_, target, callback)
		path_target, arrived = target, callback
		return true
	end,
}

nearby_objects = {existing_drop, nearby_villager}
def.do_custom(farmer, 0.1)
assert(path_target and path_target.x == crop.x)
assert(farmer._villages_farm_target)
arrived(farmer)
assert(removed and removed.x == crop.x)
assert(replanted and replanted.name == "mcl_farming:wheat_1")
assert(not farmer._villages_farm_target)
assert(not existing_drop.removed, "farmers should not collect pre-existing ground items")
assert(not nearby_villager.removed, "farmers must not target nearby villagers")

time = 0.7
path_target = nil
farmer._villages_farm_next = nil
def.do_custom(farmer, 0.1)
assert(not path_target)

-- Compost in the composter does not end the job: each fill level is the same
-- jobsite, and stays out of the job search, since vanilla's employ cannot take it.
local common = dofile("common.lua")
for _, name in ipairs({"mcl_composters:composter_1", "mcl_composters:composter_7", "mcl_composters:composter_ready"}) do
	assert(common.is_composter_node(name) and common.is_workstation_node(name))
	assert(common.workstation_profession(name) == "farmer")
	for _, searched in ipairs(common.workstation_search_nodes()) do assert(searched ~= name) end
end
local searched_empty = false
for _, searched in ipairs(common.workstation_search_nodes()) do
	searched_empty = searched_empty or searched == "mcl_composters:composter"
end
assert(searched_empty)
assert(not common.is_composter_node("mcl_barrels:barrel_closed"))

print("farmer.lua: ok")
