-- A small stub of the engine for the farm tests: nodes in a table, node metadata
-- with inventories, and the handful of node definitions a farm uses. Each test
-- calls new() first, which installs the stubs as globals.
local M = {}

local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end

local function parse(item)
	if type(item) == "table" then return item end
	local name, count = (item or ""):match("^(%S+)%s*(%d*)")
	return {name = name or "", count = tonumber(count) or (name and 1 or 0)}
end

function M.stack(item)
	local stack = parse(item)
	stack = {name = stack.name, count = stack.count}
	function stack:get_name() return self.name end
	function stack:get_count() return self.count end
	function stack:is_empty() return self.count == 0 end
	function stack:to_string() return self.name .. " " .. self.count end
	function stack:take_item(count)
		local taken = math.min(count or 1, self.count)
		self.count = self.count - taken
		if self.count == 0 then self.name = "" end
		return M.stack(self.name .. " " .. taken)
	end
	return stack
end

local function inventory()
	local lists = {}
	local inv = {lists = lists}
	function inv:get_size(list) return lists[list] and #lists[list] or 0 end
	function inv:set_size(list, size)
		lists[list] = lists[list] or {}
		for i = #lists[list] + 1, size do lists[list][i] = M.stack("") end
	end
	function inv:get_stack(list, index) return lists[list][index] end
	function inv:set_stack(list, index, item) lists[list][index] = M.stack(item) end
	function inv:get_list(list) return lists[list] end
	function inv:add_item(list, item)
		local stack = M.stack(item)
		for _, slot in ipairs(lists[list] or {}) do
			if stack.count == 0 then break end
			if slot.name == stack.name or slot.count == 0 then
				local moved = math.min(64 - slot.count, stack.count)
				slot.name, slot.count = stack.name, slot.count + moved
				stack.count = stack.count - moved
			end
		end
		return stack
	end
	function inv:room_for_item(list, item)
		local stack = M.stack(item)
		local room = 0
		for _, slot in ipairs(lists[list] or {}) do
			if slot.count == 0 then room = room + 64
			elseif slot.name == stack.name then room = room + 64 - slot.count end
		end
		return room >= stack.count
	end
	function inv:contains_item(list, item)
		local stack = M.stack(item)
		local held = 0
		for _, slot in ipairs(lists[list] or {}) do
			if slot.name == stack.name then held = held + slot.count end
		end
		return held >= stack.count
	end
	function inv:remove_item(list, item)
		local wanted = M.stack(item)
		local taken = 0
		for _, slot in ipairs(lists[list] or {}) do
			if slot.name == wanted.name and taken < wanted.count then
				local moved = math.min(slot.count, wanted.count - taken)
				slot.count = slot.count - moved
				taken = taken + moved
				if slot.count == 0 then slot.name = "" end
			end
		end
		return M.stack(wanted.name .. " " .. taken)
	end
	return inv
end

local function groups_of(defs, name)
	return defs[name] and defs[name].groups or {}
end

function M.new()
	local world = {
		nodes = {}, metas = {}, dropped = {}, sounds = {}, particles = 0, protected = {},
		now = 100, time = 0.4, day = 10, settings = {}, objects = {}, random = 0,
	}
	local defs = {
		["air"] = {groups = {}},
		["mcl_core:dirt"] = {groups = {cultivatable = 2}},
		["mcl_core:dirt_with_grass"] = {groups = {cultivatable = 2}},
		["mcl_core:coarse_dirt"] = {groups = {cultivatable = 1}},
		["mcl_core:grass_path"] = {groups = {cultivatable = 2}},
		["mcl_core:water_source"] = {groups = {water = 3}},
		["mcl_core:stone"] = {groups = {}},
		["mcl_farming:soil"] = {groups = {soil = 2}},
		["mcl_farming:soil_wet"] = {groups = {soil = 3}},
		["mcl_composters:composter"] = {groups = {}},
		["mcl_chests:chest_small"] = {groups = {}},
		["mcl_chests:trapped_chest_small"] = {groups = {}},
	}
	local function crop(name, drops)
		defs[name] = {groups = {plant = 1}, place_param2 = 3, sounds = {dug = "dug", place = "place"}, test_drops = drops}
	end
	crop("mcl_farming:wheat", {"mcl_farming:wheat_seeds", "mcl_farming:wheat_seeds", "mcl_farming:wheat_item"})
	crop("mcl_farming:potato", {"mcl_farming:potato_item 2"})
	crop("mcl_farming:carrot", {"mcl_farming:carrot_item 2"})
	crop("mcl_farming:beetroot", {"mcl_farming:beetroot_item", "mcl_farming:beetroot_seeds"})
	for stage = 1, 7 do
		crop("mcl_farming:wheat_" .. stage, {"mcl_farming:wheat_seeds"})
		crop("mcl_farming:potato_" .. stage, {"mcl_farming:potato_item"})
		crop("mcl_farming:carrot_" .. stage, {"mcl_farming:carrot_item"})
		defs["mcl_composters:composter_" .. stage] = {groups = {}}
	end
	for stage = 0, 2 do crop("mcl_farming:beetroot_" .. stage, {"mcl_farming:beetroot_seeds"}) end
	defs["mcl_composters:composter_ready"] = {groups = {}}
	-- The composter's hook without its dice: every item raises the level.
	local function composter_push(pos)
		local inv = world.meta(pos).inv
		assert(inv:get_stack("src", 1):get_count() == 1)
		inv:set_stack("src", 1, "")
		local level = world.defs[world.name(pos)].level
		local name = level < 7 and ("mcl_composters:composter_" .. (level + 1)) or "mcl_composters:composter_ready"
		world.nodes[key(pos)] = {name = name}
		table.insert(world.composted, pos)
	end
	world.composted = {}
	for level = 0, 7 do
		local name = level == 0 and "mcl_composters:composter" or ("mcl_composters:composter_" .. level)
		defs[name] = {groups = {}, level = level, _mcl_hoppers_on_after_push = composter_push}
	end
	world.defs = defs

	function world.set(pos, name) world.nodes[key(pos)] = {name = name} end
	function world.name(pos)
		local node = world.nodes[key(pos)]
		return node and node.name or "air"
	end
	function world.node(pos) return world.nodes[key(pos)] end

	local function meta_of(pos)
		local k = key(pos)
		if not world.metas[k] then world.metas[k] = {fields = {}, inv = inventory()} end
		return world.metas[k]
	end
	world.meta = meta_of

	minetest = {
		registered_nodes = defs,
		registered_items = defs,
		get_modpath = function() return "." end,
		get_gametime = function() return world.now end,
		get_timeofday = function() return world.time end,
		get_day_count = function() return world.day end,
		log = function() end,
		settings = {
			get = function(_, name) return world.settings[name] end,
			get_bool = function(_, name, default)
				if world.settings[name] == nil then return default end
				return world.settings[name] == true or world.settings[name] == "true"
			end,
		},
		get_item_group = function(name, group) return groups_of(defs, name)[group] or 0 end,
		-- Unset cells read as air; a test marks one unloaded by naming it "ignore".
		get_node_or_nil = function(pos)
			local node = world.nodes[key(pos)]
			if node and node.name == "ignore" then return nil end
			return node or {name = "air"}
		end,
		get_node = function(pos) return world.nodes[key(pos)] or {name = "air"} end,
		set_node = function(pos, node) world.metas[key(pos)] = nil; world.nodes[key(pos)] = node end,
		swap_node = function(pos, node) world.nodes[key(pos)] = node end,
		remove_node = function(pos) world.metas[key(pos)] = nil; world.nodes[key(pos)] = nil end,
		is_protected = function(pos) return world.protected[key(pos)] == true end,
		get_node_drops = function(node) return defs[node.name].test_drops end,
		sound_play = function(sound) table.insert(world.sounds, sound) end,
		add_particle = function() world.particles = world.particles + 1 end,
		add_particlespawner = function() end,
		add_item = function(pos, item) table.insert(world.dropped, {pos = pos, item = item}) end,
		get_meta = function(pos)
			local meta = meta_of(pos)
			return {
				get_string = function(_, field) return meta.fields[field] or "" end,
				set_string = function(_, field, value) meta.fields[field] = value end,
				get_inventory = function() return meta.inv end,
			}
		end,
		get_inventory = function(location) return meta_of(location.pos).inv end,
		get_node_timer = function(pos)
			local meta = meta_of(pos)
			return {
				is_started = function() return meta.timer == true end,
				start = function() meta.timer = true end,
			}
		end,
		get_objects_inside_radius = function(pos, radius)
			local found = {}
			for _, object in ipairs(world.objects) do
				local at = object:get_pos()
				if at and vector.distance(pos, at) <= radius then table.insert(found, object) end
			end
			return found
		end,
		find_nodes_in_area = function(minp, maxp, names)
			local found = {}
			for k, node in pairs(world.nodes) do
				local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
				x, y, z = tonumber(x), tonumber(y), tonumber(z)
				if x >= minp.x and x <= maxp.x and y >= minp.y and y <= maxp.y and z >= minp.z and z <= maxp.z then
					for _, name in ipairs(names) do
						local group = name:match("^group:(.*)$")
						if name == node.name or (group and groups_of(defs, node.name)[group]) then
							table.insert(found, {x = x, y = y, z = z})
							break
						end
					end
				end
			end
			table.sort(found, function(a, b)
				if a.x ~= b.x then return a.x < b.x end
				if a.y ~= b.y then return a.y < b.y end
				return a.z < b.z
			end)
			return found
		end,
	}
	vector = {
		new = function(pos) return {x = pos.x, y = pos.y, z = pos.z} end,
		zero = function() return {x = 0, y = 0, z = 0} end,
		round = function(pos)
			return {x = math.floor(pos.x + 0.5), y = math.floor(pos.y + 0.5), z = math.floor(pos.z + 0.5)}
		end,
		offset = function(pos, x, y, z) return {x = pos.x + x, y = pos.y + y, z = pos.z + z} end,
		distance = function(a, b)
			local x, y, z = a.x - b.x, a.y - b.y, a.z - b.z
			return math.sqrt(x * x + y * y + z * z)
		end,
	}
	ItemStack = M.stack
	mcl_bone_meal = {
		use_bone_meal = function(itemstack, _, pointed)
			world.bone_mealed = pointed.under
			local node = world.nodes[key(pointed.under)]
			if node then
				local base, stage = node.name:match("^(.-_)(%d+)$")
				if base then
					local grown = base .. (tonumber(stage) + 1)
					world.nodes[key(pointed.under)] = {name = defs[grown] and grown or base:sub(1, -2)}
				end
			end
			itemstack:take_item()
			return itemstack
		end,
	}
	return world
end

-- A composter this farmer holds, as vanilla's employ leaves it.
function M.claim(world, pos, id, name)
	world.set(pos, name or "mcl_composters:composter")
	world.meta(pos).fields.villager = id
end

-- A chest with its inventory made, holding the items given.
function M.chest(world, pos, name, items)
	world.set(pos, name or "mcl_chests:chest_small")
	local inv = world.meta(pos).inv
	inv:set_size("main", 27)
	for _, item in ipairs(items or {}) do inv:add_item("main", item) end
	return inv
end

-- A farmer whose gopath walks it to the cell beside the target at once, as the
-- stock_buildings test covers real routes. fail_walks makes gopath refuse.
function M.farmer(world, pos, fields)
	local at = {x = pos.x, y = pos.y, z = pos.z}
	local entity = {
		name = "mobs_mc:villager", _id = "farmer-1", _profession = "farmer", state = "stand",
		health = 20, initial_properties = {hp_max = 20}, walks = {},
	}
	for field, value in pairs(fields or {}) do entity[field] = value end
	entity.object = {
		get_pos = function() return at end,
		set_pos = function(_, new) at = new end,
		set_velocity = function() end,
		get_luaentity = function() return entity end,
		set_hp = function(_, hp) entity.health = hp end,
	}
	table.insert(world.objects, entity.object)
	entity.gopath = function(self, target, arrived)
		table.insert(self.walks, target)
		if self.fail_walks then return false end
		at = {x = target.x + 1, y = target.y, z = target.z}
		if arrived then arrived(self, target) end
		return true
	end
	return entity
end

return M
