-- The Builder's house, a new building for the village generator. Every other building
-- is a stock schematic this mod edits; this one has no stock to start from, so it is
-- written out here as layers, readable and with no binary file to fall out of step.
-- site_planner.lua reserves one per village, as it does the church. Its max_num of 0
-- keeps it out of the random pick, and village_census.lua keeps it out of the mix a
-- Builder copies. Removing the mod would leave an unknown node, as with the pulpit.
--
-- It follows the stock small house's way in: the ground layer at y 0, the floor at y 1,
-- a cobble stair up to a door at y 2 in the wall two cells from the front. Inside are
-- the bed, which makes VoxeLibre spawn the villager who claims the bench nearest its
-- bed, the bench, and a double chest with its back to the wall (builder_block.lua).
local core = minetest

local M = {}

M.NAME = "builder_house"
M.SETTING = "living_villages_builder"

-- A character for each cell: its name and param2.
local LEGEND = {
	["."] = {"air"},
	["d"] = {"mcl_core:dirt"},
	["c"] = {"mcl_core:cobble"},
	["w"] = {"mcl_core:wood"},
	["t"] = {"mcl_core:tree"},
	["g"] = {"mcl_core:glass"},
	["s"] = {"mcl_stairs:stair_cobble", 0},
	["D"] = {"mcl_doors:wooden_door_b_1", 2},
	["U"] = {"mcl_doors:wooden_door_t_1", 2},
	["B"] = {"mcl_beds:bed_red_bottom", 0},
	["b"] = {"mcl_beds:bed_red_top", 0},
	["X"] = {"living_villages:builder_block", 2},
	-- Back to the +x wall, so facing -x: a chest's front is away from its param2.
	["C"] = {"mcl_chests:chest_small", 1},
	["T"] = {"mcl_crafting_table:crafting_table", 0},
	["i"] = {"mcl_torches:torch", 1},
	["_"] = {"mcl_stairs:slab_wood"},
}

-- Bottom layer first. In each layer the first row is z 0, the street side, and x runs
-- left to right.
local LAYERS = {
	{ -- y 0: the ground
		"ddddddddd",
		"ddddddddd",
		"ddddddddd",
		"ddddddddd",
		"ddddddddd",
		"ddddddddd",
		"ddddddddd",
		"ddddddddd",
		"ddddddddd",
		"ddddddddd",
	},
	{ -- y 1: the floor
		".........",
		"....s....",
		".ccccccc.",
		".ccccccc.",
		".ccccccc.",
		".ccccccc.",
		".ccccccc.",
		".ccccccc.",
		".ccccccc.",
		".ccccccc.",
	},
	{ -- y 2: where the villager stands
		".........",
		".........",
		".tccDcct.",
		".cT....c.",
		".c.....c.",
		".ci...Cc.",
		".c....Cc.",
		".cB....c.",
		".cb...Xc.",
		".tccccct.",
	},
	{ -- y 3
		".........",
		".........",
		".twwUwwt.",
		".w.....w.",
		".g.....g.",
		".g.....g.",
		".g.....g.",
		".w.....w.",
		".w.....w.",
		".twwwwwt.",
	},
	{ -- y 4
		".........",
		".........",
		".twwwwwt.",
		".w.....w.",
		".w.....w.",
		".w.....w.",
		".w.....w.",
		".w.....w.",
		".w.....w.",
		".twwwwwt.",
	},
	{ -- y 5: the eaves
		"_________",
		"_________",
		"_wwwwwww_",
		"_wwwwwww_",
		"_wwwwwww_",
		"_wwwwwww_",
		"_wwwwwww_",
		"_wwwwwww_",
		"_wwwwwww_",
		"_________",
	},
	{ -- y 6: the ridge
		".........",
		".........",
		".........",
		".._____..",
		".._____..",
		".._____..",
		".._____..",
		".._____..",
		".........",
		".........",
	},
}

-- The layers as a schematic, in the engine's order: x fastest, then y, then z.
function M.schematic()
	local width, depth, height = #LAYERS[1][1], #LAYERS[1], #LAYERS
	local data = {}
	for z = 1, depth do
		for y = 1, height do
			local row = LAYERS[y][z]
			for x = 1, width do
				local cell = assert(LEGEND[row:sub(x, x)], "no such cell in the builder's house")
				data[#data + 1] = {name = cell[1], prob = 255, param2 = cell[2] or 0}
			end
		end
	end
	return {size = {x = width, y = height, z = depth}, data = data}
end

function M.enabled(engine)
	engine = engine or core
	return not engine.settings or engine.settings:get_bool(M.SETTING, true)
end

-- Adds the house to the generator's list, last, so the belltower stays first. It takes
-- its pseudobiome rule from the stock houses. Returns the entry, or nil.
function M.install(settlements, engine)
	if not M.enabled(engine) then return nil end
	if type(settlements) ~= "table" or type(settlements.schematic_table) ~= "table" then return nil end
	local rplc
	for _, entry in ipairs(settlements.schematic_table) do
		if entry.name == M.NAME then return entry end
		if entry.name == "small_house" then rplc = entry.rplc end
	end
	local schematic = M.schematic()
	local entry = {
		name = M.NAME,
		mts = schematic,
		hwidth = schematic.size.x,
		hdepth = schematic.size.z,
		hheight = schematic.size.y,
		hsize = 13,
		max_num = 0,
		rplc = rplc,
	}
	table.insert(settlements.schematic_table, entry)
	return entry
end

return M
