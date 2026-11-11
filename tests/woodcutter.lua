-- Run with: lua tests/woodcutter.lua
local nodes, metas, logs, registered = {}, {}, {}, {}
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end

vector = {
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
}

table.copy = table.copy or function(t)
	local out = {}
	for k, v in pairs(t) do out[k] = type(v) == "table" and table.copy(v) or v end
	return out
end

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return 0 end,
	get_item_group = function() return 0 end,
	settings = {get = function() return nil end, get_bool = function(_, _, default) return default end},
	registered_nodes = {
		["mcl_core:tree"] = {
			description = "Oak Wood", tiles = {"default_tree_top.png", "default_tree_top.png", "default_tree.png"},
			groups = {handy = 1, axey = 1, tree = 1, flammable = 2}, paramtype2 = "facedir",
			on_place = function() end, after_destruct = function() end, _mcl_stripped_variant = "mcl_core:stripped_oak",
		},
	},
	register_node = function(name, def) registered[name] = def end,
	register_craft = function(recipe) registered[#registered + 1] = recipe end,
	log = function(_, message) logs[#logs + 1] = message end,
	get_node_or_nil = function(pos) return {name = nodes[key(pos)] or "air"} end,
	get_meta = function(pos)
		local k = key(pos)
		metas[k] = metas[k] or {}
		return {
			get_string = function(_, field) return metas[k][field] or "" end,
			set_string = function(_, field, value) metas[k][field] = value end,
		}
	end,
}

-- The block: a stump that is no log, crafted from a log and a stone axe.
local NAME = dofile("chopping_block.lua")
local block_def = registered[NAME]
assert(NAME == "living_villages:chopping_block" and block_def and block_def.description == "Chopping Block")
assert(block_def.groups.tree == nil and block_def.groups.axey == 1, "not a log, still an axe's to dig")
assert(block_def._mcl_stripped_variant == nil and block_def.after_destruct == nil and block_def.drop == NAME)
assert(minetest.registered_nodes["mcl_core:tree"].groups.tree == 1, "the log's own groups untouched")
local crafted = false
for _, recipe in ipairs(registered) do
	if recipe.output == NAME then
		crafted = recipe.recipe[1] == "group:tree" and recipe.recipe[2] == "mcl_tools:axe_stone"
	end
end
assert(crafted, "a log and a stone axe")

local woodcutter = dofile("woodcutter.lua")
local job_blocks = dofile("job_blocks.lua")
local roles = {woodcutter = woodcutter}
local block = {x = 5, y = 1, z = 5}
nodes[key(block)] = NAME

-- job_blocks knows it, and hands it to a villager out of work.
assert(job_blocks.kind(NAME, roles) == "chopping" and job_blocks.kind(NAME, {}) == nil)
local found = false
for _, name in ipairs(job_blocks.search_nodes(roles)) do found = found or name == NAME end
assert(found and job_blocks.is_free(block, roles))
local left_out = {_id = "lo", _profession = "unemployed", _villages_left_unemployed = true}
assert(not job_blocks.claim(left_out, block, roles), "one left out of work stays out")
local farmer = {_id = "fa", _profession = "farmer", _jobsite = {x = 0, y = 0, z = 0}}
assert(not woodcutter.employ(farmer, block), "one with a job keeps it")
local will = {_id = "will", _profession = "unemployed", _villages_labour = {day = 1, activity = "porter"},
	_villages_peddle = {item = "x"}}
assert(job_blocks.claim(will, block, roles))
assert(will._profession == "nitwit" and will._villages_woodcutter and will._jobsite.x == 5)
assert(metas[key(block)].villager == "will" and not will._villages_labour and not will._villages_peddle)
assert(logs[#logs]:find("became woodcutter"))
assert(woodcutter.is_woodcutter(will) and not job_blocks.is_free(block, roles))
assert(not woodcutter.employ({_id = "other", _profession = "unemployed"}, block), "taken")
assert(woodcutter.status(will):find("woodcutter at the chopping block"))

-- Through the work stage it answers "chop", so vanilla leaves it at its grove.
assert(woodcutter.activity_override(will, "work") == "chop")
assert(woodcutter.activity_override(will, "home") == nil)
assert(woodcutter.activity_override({_profession = "nitwit"}, "work") == nil, "a plain nitwit")

-- Installed: the role is recovered on activation, and lost with the block.
local def = {on_activate = function() end, do_custom = function() return true end}
woodcutter.install(def)
local again = {_id = "will", _profession = "nitwit", _jobsite = block}
def.on_activate(again, "", 0)
assert(again._villages_woodcutter, "recovered")
local nitwit = {_id = "nw", _profession = "nitwit"}
def.on_activate(nitwit, "", 0)
assert(not nitwit._villages_woodcutter, "a nitwit with no block is none")
assert(def.do_custom(will, 0.1) == true and will._villages_woodcutter)
nodes[key(block)] = nil
def.do_custom(will, 0.1)
assert(not will._villages_woodcutter and will._profession == "unemployed" and not will._jobsite)
assert(logs[#logs]:find("no longer a woodcutter"))

print("woodcutter.lua: ok")
