-- Materials a Builder takes in place of one another for a stock building. It still asks for
-- the item the schematic has, oak stairs say, but builds with any stairs of the family the
-- chests hold, birch or spruce, and sets the node of the item it used. A player's order is
-- built exactly as drawn: none of this applies to it (building_template.lua's `custom`).
--
-- A family is a list of items, each the same thing made of another wood, colour or stone.
-- An item's stem is the start that every node of it shares: a stair's corners, a door's
-- halves and a slab's top all begin with their item's name, and a pressure plate, a bed or a
-- pane drops its "_off", "_bottom" or "_flat". A potted flower's stem is the pot holding it,
-- since the pot is a node of its own for each flower. What follows the stem in a node's
-- name (`rest`) is the node's shape or state, and must be one of RESTS, so that no other
-- item that happens to start with a stem is taken for a member.
--
-- Pure data and functions. Members are VoxeLibre 0.92.3's (read from a headless server's
-- registered items); `variant` checks the node it names exists when given an engine.
local M = {}

-- Woods, each with its names for every shape. Bamboo has planks but no logs.
local WOODS = {
	{planks = "mcl_core:wood", stair = "mcl_stairs:stair_wood", slab = "mcl_stairs:slab_wood",
		fence = "mcl_fences:fence", gate = "mcl_fences:fence_gate", door = "mcl_doors:wooden_door",
		trapdoor = "mcl_doors:trapdoor", plate = "mesecons_pressureplates:pressure_plate_wood_off",
		button = "mesecons_button:button_wood_off", log = "mcl_core:tree", bark = "mcl_core:tree_bark",
		stripped = "mcl_core:stripped_oak", stripped_bark = "mcl_core:stripped_oak_bark"},
	{planks = "mcl_core:darkwood", stair = "mcl_stairs:stair_darkwood", slab = "mcl_stairs:slab_darkwood",
		fence = "mcl_fences:dark_oak_fence", gate = "mcl_fences:dark_oak_fence_gate", door = "mcl_doors:dark_oak_door",
		trapdoor = "mcl_doors:dark_oak_trapdoor", plate = "mesecons_pressureplates:pressure_plate_darkwood_off",
		button = "mesecons_button:button_darkwood_off", log = "mcl_core:darktree", bark = "mcl_core:darktree_bark",
		stripped = "mcl_core:stripped_dark_oak", stripped_bark = "mcl_core:stripped_dark_oak_bark"},
	{planks = "mcl_mangrove:mangrove_wood", stair = "mcl_stairs:stair_mangrove_wood",
		slab = "mcl_stairs:slab_mangrove_wood", fence = "mcl_mangrove:mangrove_wood_fence",
		gate = "mcl_mangrove:mangrove_wood_fence_gate", door = "mcl_mangrove:mangrove_door",
		trapdoor = "mcl_mangrove:mangrove_trapdoor", plate = "mesecons_pressureplates:pressure_plate_mangrove_wood_off",
		button = "mesecons_button:button_mangrove_wood_off", log = "mcl_mangrove:mangrove_tree",
		bark = "mcl_mangrove:mangrove_tree_bark", stripped = "mcl_mangrove:mangrove_stripped",
		stripped_bark = "mcl_mangrove:mangrove_stripped_bark"},
	{planks = "mcl_cherry_blossom:cherrywood", stair = "mcl_stairs:stair_cherrywood",
		slab = "mcl_stairs:slab_cherrywood", fence = "mcl_cherry_blossom:cherry_fence",
		gate = "mcl_cherry_blossom:cherry_fence_gate", door = "mcl_cherry_blossom:cherry_door",
		trapdoor = "mcl_cherry_blossom:cherry_trapdoor", plate = "mcl_cherry_blossom:pressure_plate_cherrywood_off",
		button = "mesecons_button:button_cherrywood_off", log = "mcl_cherry_blossom:cherrytree",
		bark = "mcl_cherry_blossom:cherrytree_bark", stripped = "mcl_cherry_blossom:stripped_cherrytree",
		stripped_bark = "mcl_cherry_blossom:stripped_cherrytree_bark"},
	{planks = "mcl_bamboo:bamboo_plank", stair = "mcl_stairs:stair_bamboo_plank",
		slab = "mcl_stairs:slab_bamboo_plank", fence = "mcl_bamboo:bamboo_fence",
		gate = "mcl_bamboo:bamboo_fence_gate", door = "mcl_bamboo:bamboo_door", trapdoor = "mcl_bamboo:bamboo_trapdoor",
		plate = "mcl_bamboo:pressure_plate_bamboo_wood_off", button = "mesecons_button:button_bamboo_off"},
}
-- Spruce, birch, jungle and acacia name every shape alike.
for _, species in ipairs({"spruce", "birch", "jungle", "acacia"}) do
	table.insert(WOODS, {
		planks = "mcl_core:" .. species .. "wood", stair = "mcl_stairs:stair_" .. species .. "wood",
		slab = "mcl_stairs:slab_" .. species .. "wood", fence = "mcl_fences:" .. species .. "_fence",
		gate = "mcl_fences:" .. species .. "_fence_gate", door = "mcl_doors:" .. species .. "_door",
		trapdoor = "mcl_doors:" .. species .. "_trapdoor",
		plate = "mesecons_pressureplates:pressure_plate_" .. species .. "wood_off",
		button = "mesecons_button:button_" .. species .. "wood_off", log = "mcl_core:" .. species .. "tree",
		bark = "mcl_core:" .. species .. "tree_bark", stripped = "mcl_core:stripped_" .. species,
		stripped_bark = "mcl_core:stripped_" .. species .. "_bark",
	})
end
-- The nether's stems: planks shapes and logs, no boats or saplings.
for _, stem in ipairs({"crimson", "warped"}) do
	table.insert(WOODS, {
		planks = "mcl_crimson:" .. stem .. "_hyphae_wood", stair = "mcl_stairs:stair_" .. stem .. "_hyphae_wood",
		slab = "mcl_stairs:slab_" .. stem .. "_hyphae_wood", fence = "mcl_crimson:" .. stem .. "_fence",
		gate = "mcl_crimson:" .. stem .. "_fence_gate", door = "mcl_crimson:" .. stem .. "_door",
		trapdoor = "mcl_crimson:" .. stem .. "_trapdoor",
		plate = "mesecons_pressureplates:pressure_plate_" .. stem .. "_hyphae_wood_off",
		button = "mesecons_button:button_" .. stem .. "_hyphae_wood_off", log = "mcl_crimson:" .. stem .. "_hyphae",
		bark = "mcl_crimson:" .. stem .. "_hyphae_bark", stripped = "mcl_crimson:stripped_" .. stem .. "_hyphae",
		stripped_bark = "mcl_crimson:stripped_" .. stem .. "_hyphae_bark",
	})
end
local WOOD_SHAPES = {"planks", "stair", "slab", "fence", "gate", "door", "trapdoor", "plate", "button", "log", "bark",
	"stripped", "stripped_bark"}

-- Wool's colours, and glass's, which says gray where wool says grey.
local COLOURS = {"white", "grey", "silver", "black", "red", "yellow", "green", "cyan", "blue", "magenta", "orange",
	"purple", "brown", "pink", "lime", "light_blue"}
local function glass_colour(colour)
	return colour == "grey" and "gray" or colour
end

-- Potted flowers: the small flowers a pot takes, each a pot node of its own.
local FLOWERS = {"allium", "azure_bluet", "blue_orchid", "cornflower", "dandelion", "lily_of_the_valley",
	"oxeye_daisy", "poppy", "tulip_orange", "tulip_pink", "tulip_red", "tulip_white"}

-- family key -> list of {item, stem}.
local families = {}
local function add(key, items, strip)
	local list = {}
	for _, item in ipairs(items) do
		list[#list + 1] = {item = item, stem = strip and item:gsub(strip .. "$", "") or item}
	end
	families[key] = list
end

for _, shape in ipairs(WOOD_SHAPES) do
	local items = {}
	for _, wood in ipairs(WOODS) do
		if wood[shape] then items[#items + 1] = wood[shape] end
	end
	add("wood_" .. shape, items, (shape == "plate" or shape == "button") and "_off" or nil)
end

local function coloured(make)
	local items = {}
	for _, colour in ipairs(COLOURS) do items[#items + 1] = make(colour) end
	return items
end
add("wool", coloured(function(c) return "mcl_wool:" .. c end))
add("carpet", coloured(function(c) return "mcl_wool:" .. c .. "_carpet" end))
add("bed", coloured(function(c) return "mcl_beds:bed_" .. c .. "_bottom" end), "_bottom")
-- Clear glass stays clear: only stained glass and panes take another colour.
add("stained_glass", coloured(function(c) return "mcl_core:glass_" .. glass_colour(c) end))
add("stained_pane", coloured(function(c) return "xpanes:pane_" .. glass_colour(c) .. "_flat" end), "_flat")
local terracotta = coloured(function(c) return "mcl_colorblocks:hardened_clay_" .. c end)
table.insert(terracotta, 1, "mcl_colorblocks:hardened_clay")
add("terracotta", terracotta)
add("concrete", coloured(function(c) return "mcl_colorblocks:concrete_" .. c end))

add("cobble", {"mcl_core:cobble", "mcl_deepslate:deepslate_cobbled"})
add("cobble_stair", {"mcl_stairs:stair_cobble", "mcl_stairs:stair_deepslate_cobbled"})
add("cobble_slab", {"mcl_stairs:slab_cobble", "mcl_stairs:slab_deepslate_cobbled"})
add("cobble_wall", {"mcl_walls:cobble", "mcl_deepslate:deepslatecobbledwall"})
-- Plain, mossy and cracked stone bricks: a village looks worn anyway. Carved ones are exact.
add("stonebrick", {"mcl_core:stonebrick", "mcl_core:stonebrickmossy", "mcl_core:stonebrickcracked"})
add("stonebrick_stair", {"mcl_stairs:stair_stonebrick", "mcl_stairs:stair_stonebrickmossy",
	"mcl_stairs:stair_stonebrickcracked"})
add("stonebrick_slab", {"mcl_stairs:slab_stonebrick", "mcl_stairs:slab_stonebrickmossy",
	"mcl_stairs:slab_stonebrickcracked"})
add("stonebrick_wall", {"mcl_walls:stonebrick", "mcl_walls:stonebrickmossy"})
add("sand", {"mcl_core:sand", "mcl_core:redsand"})
add("sandstone", {"mcl_core:sandstone", "mcl_core:redsandstone"})
add("sandstone_smooth", {"mcl_core:sandstonesmooth", "mcl_core:redsandstonesmooth"})
add("sandstone_smooth2", {"mcl_core:sandstonesmooth2", "mcl_core:redsandstonesmooth2"})
add("sandstone_carved", {"mcl_core:sandstonecarved", "mcl_core:redsandstonecarved"})
add("sandstone_stair", {"mcl_stairs:stair_sandstone", "mcl_stairs:stair_redsandstone"})
add("sandstone_slab", {"mcl_stairs:slab_sandstone", "mcl_stairs:slab_redsandstone"})
add("sandstone_smooth2_stair", {"mcl_stairs:stair_sandstonesmooth2", "mcl_stairs:stair_redsandstonesmooth2"})
add("sandstone_smooth2_slab", {"mcl_stairs:slab_sandstonesmooth2", "mcl_stairs:slab_redsandstonesmooth2"})
add("sandstone_wall", {"mcl_walls:sandstone", "mcl_walls:redsandstone"})

do
	local list = {}
	for _, flower in ipairs(FLOWERS) do
		list[#list + 1] = {item = "mcl_flowers:" .. flower, stem = "mcl_flowerpots:flower_pot_" .. flower}
	end
	families.potted_flower = list
end

-- item -> member, stem -> member; a member is {item, stem, family}.
local by_item, by_stem = {}, {}
for key, list in pairs(families) do
	for _, member in ipairs(list) do
		member.family = key
		assert(not by_item[member.item], member.item .. " is in two families")
		by_item[member.item] = member
		assert(not by_stem[member.stem], member.stem .. " is two items' stem")
		by_stem[member.stem] = member
	end
end

-- What may follow a stem: a node's shape or state, or the identity's own endings
-- (builder_materials.identity: a door's ":top", an item's "_off").
local RESTS = {"^$", "^_top$", "^_bottom$", "^_double$", "^_outer$", "^_inner$", "^_open$", "^_on$", "^_off$",
	"^_flat$", "^_[bt]_%d+$", "^:top$", "^_%d+$"}
local function is_rest(rest)
	for _, pattern in ipairs(RESTS) do
		if rest:match(pattern) then return true end
	end
	return false
end

-- The member a node or item name is made of, and what follows its stem, or nil. The
-- longest stem wins: a tree's bark is no tree.
function M.lookup(name)
	local stem = name
	while true do
		local member = by_stem[stem]
		if member then
			local rest = name:sub(#stem + 1)
			if is_rest(rest) then return member, rest end
		end
		local cut = stem:match("^(.*)[_:][^_:]*$")
		if not cut or cut == "" then return nil end
		stem = cut
	end
end

-- The member record of an item, or nil when it has no family.
function M.member(item)
	return by_item[item]
end

-- The items of an item's family, itself first, or just itself when it has none.
function M.members(item)
	local member = by_item[item]
	if not member then return {item} end
	local list = {item}
	for _, other in ipairs(families[member.family]) do
		if other.item ~= item then list[#list + 1] = other.item end
	end
	return list
end

-- What makes two identities the same thing built, family aside: birch stairs stand for oak.
function M.kind(identity)
	local member, rest = M.lookup(identity)
	if member then return "family:" .. member.family .. rest end
	return identity
end

-- The same node made of `supplied` instead: a birch stair's corner for an oak one's. Nil
-- when `name` has no family or `supplied` is not in it, or, given an engine, when there is
-- no such node.
function M.variant(name, supplied, engine)
	local member, rest = M.lookup(name)
	local other = by_item[supplied]
	if not member or not other or other.family ~= member.family then return nil end
	local result = other.stem .. rest
	if engine and engine.registered_nodes and not engine.registered_nodes[result] then return nil end
	return result
end

-- The order to use a family's items in for `item`: itself, then the one the project took
-- before (`prefer`, family -> item), then the others, most held first. `count(item)` says
-- how many are at hand.
function M.order(item, prefer, count)
	local list = M.members(item)
	local member = by_item[item]
	local chosen = member and prefer and prefer[member.family]
	local first = {item}
	if chosen and chosen ~= item then first[2] = chosen end
	local rest = {}
	for i = 2, #list do
		if list[i] ~= chosen then rest[#rest + 1] = list[i] end
	end
	local counts = {}
	for _, other in ipairs(rest) do counts[other] = count(other) end
	table.sort(rest, function(a, b)
		if counts[a] ~= counts[b] then return counts[a] > counts[b] end
		return a < b
	end)
	for _, other in ipairs(rest) do first[#first + 1] = other end
	return first
end

-- Every item worth counting for a bill: the billed items and, for those that may be
-- swapped, the rest of their families.
function M.related(bill, swappable)
	local set = {}
	for item in pairs(bill) do
		if swappable[item] then
			for _, other in ipairs(M.members(item)) do set[other] = true end
		else
			set[item] = true
		end
	end
	return set
end

local function sorted_keys(map)
	local keys = {}
	for key in pairs(map) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

-- How much of each billed item what is at hand covers: its own first, then, for one that
-- may be swapped, the rest of its family, the project's choice and the most held first.
-- bill and have are item -> count, swappable item -> true. Returns covered (item ->
-- count) and used (what of `have` it took, item -> count).
function M.cover(bill, swappable, have, prefer)
	local left, covered, used = {}, {}, {}
	for item, count in pairs(have) do left[item] = count end
	local items = sorted_keys(bill)
	for _, item in ipairs(items) do
		local own = math.min(bill[item], left[item] or 0)
		covered[item] = own
		if own > 0 then
			left[item] = left[item] - own
			used[item] = (used[item] or 0) + own
		end
	end
	for _, item in ipairs(items) do
		if swappable[item] then
			local order = M.order(item, prefer, function(other) return left[other] or 0 end)
			for i = 2, #order do
				local short = bill[item] - covered[item]
				if short <= 0 then break end
				local other = order[i]
				local take = math.min(short, left[other] or 0)
				if take > 0 then
					covered[item] = covered[item] + take
					left[other] = left[other] - take
					used[other] = (used[other] or 0) + take
				end
			end
		end
	end
	return covered, used
end

M.FAMILIES = families
return M
