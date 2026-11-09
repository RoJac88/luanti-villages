-- Run with: lua tests/demand.lua
local settings = {}
minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return 0 end,
	settings = {
		get = function(_, name) return settings[name] end,
		get_bool = function(_, name, default)
			if settings[name] == nil then return default end
			return settings[name]
		end,
	},
	log = function() end,
}
vector = {distance = function() return 0 end}

local demand = dofile("demand.lua")
local ledger = dofile("ledger.lua")

local COAL, EMERALD = "mcl_core:coal_lump", "mcl_core:emerald"
local smith = {_id = "sam", _profession = "tool_smith"}
local function view(held)
	return ledger.assess({id = "sam", profession = "tool_smith", max_tier = 1, held = held})
end

-- Buying coal: out of it, the smith takes fewer lumps for its emerald (a scarce good's
-- price rises); with its target held, the base; with a glut, more.
local short = demand.count(smith, COAL, 15, EMERALD, 64, view({}), "fed")
assert(short == 9, short) -- 15 / sqrt(3)
assert(demand.count(smith, COAL, 15, EMERALD, 64, view({[COAL] = 15}), "fed") == 15)
local glut = demand.count(smith, COAL, 15, EMERALD, 64, view({[COAL] = 200}), "fed")
assert(glut > 15 and glut <= 22, glut)
-- Charcoal it holds counts as coal.
assert(demand.count(smith, COAL, 15, EMERALD, 64, view({["mcl_core:charcoal_lump"] = 15}), "fed") == 15)

-- Selling: a glut of what it sells comes cheaper; hunger makes it dearer.
local axes = view({["mcl_tools:axe_stone"] = 20})
assert(demand.count(smith, EMERALD, 10, "mcl_tools:axe_stone", 64, axes, "fed") < 10)
assert(demand.count(smith, EMERALD, 4, "mcl_tools:axe_stone", 64, view({}), "fed") == 4)
assert(demand.count(smith, EMERALD, 4, "mcl_tools:axe_stone", 64, view({}), "hungry") == 5)
assert(demand.count(smith, EMERALD, 4, "mcl_tools:axe_stone", 64, view({}), "starving") == 6)
-- Never below 1 or above a stack.
assert(demand.count(smith, EMERALD, 1, "mcl_tools:axe_stone", 64, axes, "fed") == 1)
assert(demand.count(smith, EMERALD, 60, "mcl_tools:axe_stone", 64, view({}), "starving") == 64)
-- An unpriced item: no demand term.
assert(demand.count(smith, "no:thing", 7, EMERALD, 64, view({}), "fed") == 7)

-- Off: the base count stands.
settings.living_villages_economy = false
assert(demand.count(smith, COAL, 15, EMERALD, 64, view({}), "fed") == 15)

print("demand.lua: ok")
