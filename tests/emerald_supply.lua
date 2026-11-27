-- Run with: lua tests/emerald_supply.lua
local economy = true

local function stack(name, count)
	local self = {name = name or "", count = name and name ~= "" and (count or 1) or 0}
	function self:get_name() return self.count > 0 and self.name or "" end
	function self:get_count() return self.count end
	function self:set_count(n) self.count = n end
	function self:is_empty() return self.count == 0 end
	return self
end
ItemStack = function(from)
	if type(from) == "table" then return stack(from.name, from.count) end
	if not from or from == "" then return stack() end
	local name, count = from:match("^(%S+)%s*(%d*)$")
	return stack(name, tonumber(count) or 1)
end

local crafts, cleared, predicts, on_crafts, mods_loaded, overridden = {}, {}, {}, {}, {}, {}
local nodes, added = {}, {}
minetest = {
	get_modpath = function() return "." end,
	settings = {get_bool = function(_, name)
		assert(name == "living_villages_economy")
		return economy
	end},
	registered_nodes = {["mcl_core:stone_with_emerald"] = {}, ["mcl_deepslate:deepslate_with_emerald"] = {}},
	registered_items = {["mcl_core:emeraldblock"] = {}},
	clear_craft = function(def) cleared[#cleared + 1] = def end,
	register_craft = function(def) crafts[#crafts + 1] = def end,
	register_craft_predict = function(f) predicts[#predicts + 1] = f end,
	register_on_craft = function(f) on_crafts[#on_crafts + 1] = f end,
	register_on_mods_loaded = function(f) mods_loaded[#mods_loaded + 1] = f end,
	override_item = function(name, def) overridden[name] = def end,
	get_node = function(pos) return {name = nodes[pos.x] or "air"} end,
	add_item = function(pos, item)
		local s = type(item) == "string" and ItemStack(item) or item
		added[#added + 1] = {name = s:get_name(), count = s:get_count()}
	end,
}

local supply = dofile("emerald_supply.lua")
local SCALE = supply.SCALE
assert(SCALE == 64, "the economy's scale")

-- Off with the economy.
economy = false
assert(supply.install() == false and #crafts == 0 and #cleared == 0, "nothing changes with the economy off")
economy = true
assert(supply.install() == true, "installs with the economy on")

-- Recipes: every emerald recipe cleared, made again scaled.
assert(#cleared == 1 and cleared[1].output == "mcl_core:emerald", "the emerald recipes are cleared")
local block_out, cooked = nil, {}
for _, def in ipairs(crafts) do
	if def.type == "shapeless" then block_out = def.output end
	if def.type == "cooking" then cooked[def.recipe] = def.output end
end
assert(block_out == "mcl_core:emerald " .. 9 * SCALE, "a block breaks into 576")
assert(cooked["mcl_core:stone_with_emerald"] == "mcl_core:emerald 64", "smelting ore gives 64")
assert(cooked["mcl_deepslate:deepslate_with_emerald"] == "mcl_core:emerald 64", "and deepslate ore")
assert(overridden["mcl_core:emeraldblock"]._doc_items_usagehelp:find("64"), "the block says what it takes")

-- The block's craft.
local function grid(count, other)
	local g = {}
	for i = 1, 9 do g[i] = ItemStack("mcl_core:emerald " .. count) end
	if other then g[5] = ItemStack(other) end
	return g
end
local function craft_inv(g)
	local inv = {list = {}}
	for i, s in ipairs(g) do inv.list[i] = ItemStack({name = s:get_name(), count = s:get_count()}) end
	function inv:set_stack(_, i, s) self.list[i] = s end
	function inv:set_list(_, l) self.list = l end
	return inv
end
local block = ItemStack("mcl_core:emeraldblock")
assert(predicts[1](block, nil, grid(64)) == nil, "a full grid shows the block")
assert(predicts[1](block, nil, grid(63)):is_empty(), "63 in a slot shows nothing")
assert(predicts[1](ItemStack("mcl_core:stone"), nil, grid(1)) == nil, "other crafts are left alone")

-- The engine took one from each slot of a grid of 100: on_craft leaves 36.
local old = grid(100)
local inv = craft_inv(grid(99))
assert(on_crafts[1](block, nil, old, inv) == nil, "the block is kept")
for i = 1, 9 do assert(inv.list[i]:get_count() == 36, "64 taken from each slot") end
-- Short in a slot: the grid comes back and no block.
old = grid(64)
old[3] = ItemStack("mcl_core:emerald 10")
inv = craft_inv(grid(63))
assert(on_crafts[1](block, nil, old, inv):is_empty(), "no block for a short grid")
assert(inv.list[3]:get_count() == 10 and inv.list[1]:get_count() == 64, "the grid is put back")

-- Drops: an emerald ore's emeralds come 64 to an entity, others untouched.
assert(#mods_loaded == 1)
local original_add = minetest.add_item
minetest.handle_node_drops = function(pos, drops)
	for _, item in ipairs(drops) do
		local s = ItemStack(item)
		for _ = 1, s:get_count() do minetest.add_item(pos, s:get_name()) end
	end
end
mods_loaded[1]()
nodes[1] = "mcl_core:stone_with_emerald"
nodes[2] = "mcl_core:stone"
nodes[3] = "mcl_deepslate:deepslate_with_emerald"
minetest.handle_node_drops({x = 1}, {"mcl_core:emerald 2"})
assert(#added == 2 and added[1].count == 64 and added[2].count == 64, "Fortune's 2 become two lumps of 64")
assert(minetest.add_item == original_add, "add_item is put back")
added = {}
minetest.handle_node_drops({x = 2}, {"mcl_core:emerald"})
assert(#added == 1 and added[1].count == 1, "an emerald from elsewhere stays 1")
added = {}
minetest.handle_node_drops({x = 3}, {"mcl_deepslate:deepslate_with_emerald"})
assert(#added == 1 and added[1].count == 1 and added[1].name == "mcl_deepslate:deepslate_with_emerald",
	"silk touch gives the ore itself")
added = {}
minetest.handle_node_drops({x = 3}, {"mcl_core:emerald"})
assert(#added == 1 and added[1].count == 64, "deepslate ore gives 64")

-- An error in the drops still puts add_item back.
minetest.handle_node_drops = supply.wrap_drops(function() error("boom") end)
assert(not pcall(minetest.handle_node_drops, {x = 1}, {}), "the error is raised")
assert(minetest.add_item == original_add, "add_item is put back after an error")

print("emerald_supply tests passed")
