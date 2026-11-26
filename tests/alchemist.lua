-- Run with: lua tests/alchemist.lua
local nodes, metas, logs, registered = {}, {}, {}, {}
local unloaded = {}
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
local time, day = 0, 1

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
	get_timeofday = function() return time end,
	get_day_count = function() return day end,
	get_item_group = function() return 0 end,
	settings = {get = function() return nil end, get_bool = function(_, _, default) return default end},
	registered_nodes = {
		["mcl_brewing:stand_000"] = {
			description = "Brewing Stand", groups = {pickaxey = 1, container = 2, brewitem = 1},
			tiles = {"mcl_brewing_top.png", "mcl_brewing_base.png", "mcl_brewing_side.png^[transformFX"},
			drawtype = "nodebox", drop = "mcl_brewing:stand",
			on_construct = function() end, on_timer = function() end, on_receive_fields = function() end,
			allow_metadata_inventory_put = function() end, _mcl_hoppers_on_try_push = function() end,
		},
	},
	register_node = function(name, def) registered[name] = def end,
	register_craft = function(recipe) registered[#registered + 1] = recipe end,
	log = function(_, message) logs[#logs + 1] = message end,
	get_node_or_nil = function(pos)
		if unloaded[key(pos)] then return nil end
		return {name = nodes[key(pos)] or "air"}
	end,
	get_meta = function(pos)
		local k = key(pos)
		metas[k] = metas[k] or {}
		return {
			get_string = function(_, field) return metas[k][field] or "" end,
			set_string = function(_, field, value) metas[k][field] = value end,
		}
	end,
}
core = minetest

-- The stand: a brewing stand in shape, with nothing of one's brewing.
local NAME = dofile("alchemy_stand.lua")
local stand = registered[NAME]
assert(NAME == "living_villages:alchemy_stand" and stand and stand.description == "Alchemist's Stand")
assert(stand.drawtype == "nodebox" and stand.drop == NAME)
assert(stand.on_construct == nil and stand.on_timer == nil and stand.on_receive_fields == nil
	and stand.allow_metadata_inventory_put == nil and stand._mcl_hoppers_on_try_push == nil, "brews nothing")
assert(stand.groups.container == nil and stand.groups.brewitem == nil and stand.groups.pickaxey == 1)
assert(minetest.registered_nodes["mcl_brewing:stand_000"].groups.container == 2, "the brewing stand untouched")
assert(stand.tiles[1] ~= "mcl_brewing_top.png" and stand.tiles[1]:find("mcl_brewing_top.png", 1, true), "recoloured")

-- Its recipe: air north, water east, earth south, fire west, the centre empty.
local recipe, replacements
for _, craft in ipairs(registered) do
	if craft.output == NAME then recipe, replacements = craft.recipe, craft.replacements end
end
assert(recipe, "craftable")
assert(recipe[1][1] == "" and recipe[1][2] == "mcl_mobitems:feather" and recipe[1][3] == "")
assert(recipe[2][1] == "mcl_mobitems:blaze_rod" and recipe[2][2] == "" and recipe[2][3] == "mcl_potions:water")
assert(recipe[3][1] == "" and recipe[3][2] == "group:cobble" and recipe[3][3] == "")
assert(replacements and replacements[1][1] == "mcl_potions:water" and replacements[1][2] == "mcl_potions:glass_bottle",
	"the bottle comes back empty")

-- Without mcl_brewing nothing is registered, and the name is still returned.
do
	local saved = minetest.registered_nodes["mcl_brewing:stand_000"]
	minetest.registered_nodes["mcl_brewing:stand_000"] = nil
	registered[NAME] = nil
	assert(dofile("alchemy_stand.lua") == NAME and registered[NAME] == nil)
	assert(logs[#logs]:find("alchemist's stand was not registered", 1, true))
	minetest.registered_nodes["mcl_brewing:stand_000"] = saved
	registered[NAME] = stand
end

local alchemist = dofile("alchemist.lua")
local job_blocks = dofile("job_blocks.lua")
local roles = {alchemist = alchemist}
local block = {x = 5, y = 1, z = 5}
nodes[key(block)] = NAME

-- job_blocks knows it, and hands it to a villager out of work.
assert(alchemist.BLOCK == NAME)
assert(job_blocks.kind(NAME, roles) == "alchemy" and job_blocks.kind(NAME, {}) == nil)
local found = false
for _, name in ipairs(job_blocks.search_nodes(roles)) do found = found or name == NAME end
assert(found and job_blocks.is_free(block, roles))
local left_out = {_id = "lo", _profession = "unemployed", _villages_left_unemployed = true}
assert(not job_blocks.claim(left_out, block, roles), "one left out of work stays out")
local farmer = {_id = "fa", _profession = "farmer", _jobsite = {x = 0, y = 0, z = 0}}
assert(not alchemist.employ(farmer, block), "one with a job keeps it")
assert(not alchemist.employ({_id = "kid", _profession = "unemployed", child = true}, block), "no child")
local ada = {_id = "ada", _profession = "unemployed", _villages_labour = {day = 1, activity = "porter"},
	_villages_peddle = {item = "x"}, _villages_starving = true}
assert(job_blocks.claim(ada, block, roles))
assert(ada._profession == "cleric" and ada._villages_alchemist == true and ada._jobsite.x == 5)
assert(metas[key(block)].villager == "ada" and not ada._villages_labour and not ada._villages_peddle)
assert(not ada._villages_starving, "fed for good")
assert(logs[#logs]:find("became alchemist at the stand", 1, true))
assert(alchemist.is_alchemist(ada) and not job_blocks.is_free(block, roles))
assert(not alchemist.employ({_id = "other", _profession = "unemployed"}, block), "taken")
assert(alchemist.status(ada):find("alchemist at the stand at (5,1,5)", 1, true))
assert(alchemist.status({_profession = "cleric"}) == "not an alchemist")

-- Installed: the role is recovered on activation, kept while the stand is unloaded, and
-- lost with the stand.
local def = {on_activate = function() end, do_custom = function() return true end}
alchemist.install(def)
local again = {_id = "ada", _profession = "cleric", _jobsite = block}
def.on_activate(again, "", 0)
assert(again._villages_alchemist, "recovered")
local priest = {_id = "pr", _profession = "cleric", _jobsite = {x = 9, y = 9, z = 9}}
def.on_activate(priest, "", 0)
assert(not priest._villages_alchemist, "a cleric at a pulpit is none")
assert(def.do_custom(ada, 0.1) == true and ada._villages_alchemist)
unloaded[key(block)] = true
def.do_custom(ada, 0.1)
assert(ada._villages_alchemist and ada._profession == "cleric", "an unloaded stand is not a lost one")
assert(alchemist.status(ada) == "alchemist, stand not loaded")
unloaded[key(block)] = nil
metas[key(block)].villager = "someone else"
def.do_custom(ada, 0.1)
assert(not ada._villages_alchemist and ada._profession == "unemployed" and not ada._jobsite)
assert(logs[#logs]:find("no longer an alchemist", 1, true))
metas[key(block)].villager = ""

-- Its timetables: no tavern and no church; work from 7000 to 17500, and on a holiday the
-- bell from 10500 to 15000.
local common = dofile("common.lua")
local function at(ticks) return ticks / 24000 end
local alch = {_id = "al", _profession = "cleric", _villages_alchemist = true}
local cleric = {_id = "cl", _profession = "cleric"}
day = 1
for _, case in ipairs({
	{5499, "sleep"}, {5500, "putter"}, {6999, "putter"}, {7000, "work"}, {15500, "work"},
	{17499, "work"}, {17500, "home"}, {18500, "sleep"},
}) do
	local stage = common.schedule_stage(at(case[1]), alch)
	assert(stage == case[2], ("ordinary %d: expected %s, got %s"):format(case[1], case[2], stage))
end
assert(common.schedule_stage(at(16000), cleric) == "tavern", "a cleric still dines")
day = 4
for _, case in ipairs({
	{5500, "putter"}, {7000, "work"}, {10249, "work"}, {10250, "work"}, {10500, "bell"},
	{14999, "bell"}, {15000, "work"}, {17499, "work"}, {17500, "home"},
}) do
	local stage = common.schedule_stage(at(case[1]), alch)
	assert(stage == case[2], ("holiday %d: expected %s, got %s"):format(case[1], case[2], stage))
end
assert(common.schedule_stage(at(7000), cleric) == "service", "a cleric still holds the service")

-- A whole ordinary day's work is 10500 ticks: 525 s at time_speed 72.
day, time = 1, at(23999)
local worked = common.work_seconds(1199.95, alch)
assert(math.abs(worked - 525) < 1e-6, worked)

-- Its jobsite counts as a claimed one, so vanilla's commute to it is planned.
local mine = {_id = "me", _jobsite = block}
metas[key(block)].villager = "me"
assert(common.has_claimed_jobsite(mine))

print("alchemist.lua: ok")
