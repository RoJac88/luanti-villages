-- Run with: lua tests/builder_materials.lua
-- Every node of every stock building, as this mod furnishes it and as the generator
-- swaps it for each surface, must have a cost or be left out on purpose.
local stock_world = dofile("tests/support/stock_world.lua")
stock_world.install(stock_world.new())

local materials = dofile("builder_materials.lua")
local template = dofile("building_template.lua")

local function one(cost)
	local item, count = next(cost)
	assert(next(cost, item) == nil, "more than one item")
	return item, count
end

local function costs(name, item, count)
	local got, n = one(assert(materials.cost(name), name .. " has no cost"))
	assert(got == item and n == (count or 1), name .. " costs " .. n .. " " .. got)
end

-- Shapes of one item cost that item.
costs("mcl_stairs:stair_cobble_outer", "mcl_stairs:stair_cobble")
costs("mcl_stairs:stair_wood_inner", "mcl_stairs:stair_wood")
costs("mcl_stairs:slab_wood_top", "mcl_stairs:slab_wood")
costs("mcl_stairs:slab_stone_double", "mcl_stairs:slab_stone", 2)
costs("mcl_walls:cobble_12", "mcl_walls:cobble")
costs("mcl_walls:stonebrick_0", "mcl_walls:stonebrick")
costs("mcl_torches:torch_wall", "mcl_torches:torch")
costs("mcl_doors:trapdoor_open", "mcl_doors:trapdoor")
costs("mcl_doors:iron_trapdoor_open", "mcl_doors:iron_trapdoor")
costs("mesecons_walllever:wall_lever_on", "mesecons_walllever:wall_lever_off")
costs("mesecons_pressureplates:pressure_plate_wood_off", "mesecons_pressureplates:pressure_plate_wood_off")
costs("mcl_villages:stonebrickcarved", "mcl_core:stonebrickcarved")
costs("xpanes:pane_natural_flat", "xpanes:pane_natural_flat")
costs("mcl_core:cobble", "mcl_core:cobble")
costs("mcl_chests:chest", "mcl_chests:chest")

-- Ground costs dirt, which grows the rest on its own.
costs("mcl_core:dirt_with_grass", "mcl_core:dirt")
costs("mcl_farming:soil_wet", "mcl_core:dirt")

-- Pairs cost one, on the first half.
costs("mcl_doors:wooden_door_b_1", "mcl_doors:wooden_door")
assert(materials.cost("mcl_doors:wooden_door_t_1") == nil)
costs("mcl_beds:bed_red_bottom", "mcl_beds:bed_red_bottom")
assert(materials.cost("mcl_beds:bed_red_top") == nil)

-- Crops cost what they grow from, and start young.
costs("mcl_farming:wheat", "mcl_farming:wheat_seeds")
costs("mcl_farming:carrot", "mcl_farming:carrot_item")
costs("mcl_farming:potato", "mcl_farming:potato_item")
assert(materials.placed("mcl_farming:wheat") == "mcl_farming:wheat_1")
assert(materials.identity("mcl_farming:wheat_1") == materials.identity("mcl_farming:wheat"))
assert(materials.identity("mcl_farming:wheat_5") == materials.identity("mcl_farming:wheat"))

-- Liquids cost a bucket, and hand the empty one back.
costs("mcl_core:water_source", "mcl_buckets:bucket_water")
costs("mcl_core:lava_source", "mcl_buckets:bucket_lava")
assert(materials.returns("mcl_core:water_source")[materials.EMPTY_BUCKET] == 1)
assert(materials.returns("mcl_core:cobble") == nil)

-- A potted flower takes the pot and the flower.
do
	local cost = materials.cost("mcl_flowerpots:flower_pot_allium")
	assert(cost["mcl_flowerpots:flower_pot"] == 1 and cost["mcl_flowers:allium"] == 1)
end

-- What a building was placed as still counts as itself in another state.
assert(materials.identity("mcl_doors:wooden_door_b_2") == materials.identity("mcl_doors:wooden_door_b_1"))
assert(materials.identity("mcl_doors:wooden_door_t_2") == materials.identity("mcl_doors:wooden_door_t_1"))
assert(materials.identity("mcl_doors:wooden_door_t_1") ~= materials.identity("mcl_doors:wooden_door_b_1"))
assert(materials.identity("mcl_furnaces:furnace_active") == materials.identity("mcl_furnaces:furnace"))
assert(materials.identity("mcl_fences:fence_gate_open") == materials.identity("mcl_fences:fence_gate"))
assert(materials.identity("mcl_chests:chest_small") == materials.identity("mcl_chests:chest"))
assert(materials.identity("mcl_chests:chest_left") == materials.identity("mcl_chests:chest"))
assert(materials.identity("mcl_stairs:stair_wood_outer") == materials.identity("mcl_stairs:stair_wood"))
assert(materials.identity("xpanes:pane_natural") == materials.identity("xpanes:pane_natural_flat"))
assert(materials.identity("mcl_farming:soil") == materials.identity("mcl_farming:soil_wet"))
assert(materials.identity("mcl_flowerpots:flower_pot_allium") ~= materials.identity("mcl_flowerpots:flower_pot_tulip_white"))
assert(materials.identity("mcl_core:cobble") ~= materials.identity("mcl_core:wood"))

-- A schematic's chest becomes one that has an inventory; a lever starts off.
assert(materials.placed("mcl_chests:chest") == "mcl_chests:chest_small")
assert(materials.placed("mesecons_walllever:wall_lever_on") == "mesecons_walllever:wall_lever_off")
assert(materials.placed("mcl_core:cobble") == "mcl_core:cobble")

-- Profession blocks are left out, the mod's own included.
for _, name in ipairs({
	"mcl_composters:composter", "mcl_barrels:barrel_closed", "mcl_fletching_table:fletching_table", "mcl_loom:loom",
	"mcl_lectern:lectern", "mcl_cartography_table:cartography_table", "mcl_blast_furnace:blast_furnace",
	"mcl_smoker:smoker", "mcl_brewing:stand_000", "mcl_cauldrons:cauldron", "mcl_jukebox:jukebox",
	"living_villages:pulpit", "living_villages:builder_block",
}) do
	assert(materials.excluded(name), name .. " is a profession block")
	assert(materials.cost(name) == nil, name .. " costs nothing")
end
for _, name in ipairs({"mcl_furnaces:furnace", "mcl_anvils:anvil", "mcl_chests:chest", "mcl_crafting_table:crafting_table"}) do
	assert(not materials.excluded(name), name .. " is no jobsite")
end

-- The dirt family, which is what a Builder may break for a site.
assert(materials.is_dirt("mcl_core:dirt") and materials.is_dirt("mcl_core:dirt_with_grass") and materials.is_dirt("mcl_core:podzol"))
assert(not materials.is_dirt("mcl_core:stone") and not materials.is_dirt("mcl_core:sand") and not materials.is_dirt("mcl_core:gravel"))

-- Everything on sale has a price in whole emeralds. The bell, sold by vanilla for 36,
-- is meant to be cheaper here, not free.
for item, price in pairs(materials.SALES) do
	assert(price >= 1 and price == math.floor(price), item)
end
assert(materials.SALES["mcl_bells:bell"] < 36)

-- Every stock node on every surface resolves. What it resolves to has to be real too,
-- which only a run on the real engine can tell: tools/lv_probe's LV_PROBE_BUILDER.
local BUILDINGS = {
	"belltower", "blacksmith", "butcher", "church", "farm", "lamp", "large_house", "library",
	"medium_house", "small_house", "tavern", "well",
}
local SURFACES = {
	"mcl_core:dirt_with_grass", "mcl_core:dirt_with_grass_snow", "mcl_core:podzol",
	"mcl_core:sand", "mcl_core:redsand", "mcl_core:snow",
}
for _, building in ipairs(BUILDINGS) do
	local fixture = dofile("tests/fixtures/buildings/" .. building .. ".lua")
	for _, surface in ipairs(SURFACES) do
		for _, id in ipairs(fixture.ids) do
			local name = template.swap_name(fixture.names[id + 1], surface, true)
			if name ~= "air" and not materials.excluded(name) and not materials.is_top_half(name) then
				local cost = materials.cost(name)
				assert(cost and next(cost), building .. ": no cost for " .. name)
				for item, count in pairs(cost) do
					assert(type(item) == "string" and count >= 1, name)
					assert(not item:find("_outer$") and not item:find("_inner$") and not item:find("_open$"), name .. " -> " .. item)
				end
			end
		end
	end
end

print("builder_materials: ok")
