-- Run with: lua tests/economy_report.lua
local day, objects = 10, {}
minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return 0 end,
	get_day_count = function() return day end,
	settings = {get = function() return nil end, get_bool = function(_, _, default) return default end},
	log = function() end,
	get_objects_inside_radius = function() return objects end,
}
vector = {distance = function() return 0 end}

local report = dofile("economy_report.lua")
local tally = dofile("economy_tally.lua")

-- The tally: today and yesterday, older days dropped.
do
	local v = {}
	tally.note(v, {["mcl_core:stick"] = 4}, {["mcl_core:tree"] = 1}, 8)
	tally.note(v, {["mcl_core:stick"] = 4}, nil, 9)
	tally.note(v, {["mcl_core:stick"] = 2, ["mcl_core:paper"] = 3}, {["mcl_core:reeds"] = 3}, 9)
	local made, used = tally.on(v, 9)
	assert(made["mcl_core:stick"] == 6 and made["mcl_core:paper"] == 3 and used["mcl_core:reeds"] == 3)
	assert(tally.on(v, 8)["mcl_core:stick"] == 4, "yesterday")
	tally.note(v, nil, {["mcl_farming:bread"] = 1}, 10)
	assert(tally.on(v, 8) == nil, "two days back is gone")
	assert(tally.on(v, 9)["mcl_core:stick"] == 6, "yesterday is kept")
	assert(select(2, tally.on(v, 10))["mcl_farming:bread"] == 1)
	assert(tally.status(v, 10) == "made nothing; used 1 bread", tally.status(v, 10))
	tally.note(v, {["mcl_core:stick"] = 1}, nil, 13)
	assert(tally.on(v, 12) == nil and tally.on(v, 13)["mcl_core:stick"] == 1, "a gap of days keeps nothing old")
end

-- Shortages and gluts sum the Builder's news by item, worthiest first.
local heard = {
	{item = "mcl_core:coal_lump", who = "a", kind = "needs", count = 10, price = 0.2},
	{item = "mcl_core:coal_lump", who = "b", kind = "needs", count = 5, price = 0.3},
	{item = "mcl_books:book", who = "a", kind = "needs", count = 1, price = 1},
	{item = "mcl_farming:wheat_item", who = "c", kind = "has", count = 20, price = 0.05},
}
local shortages = report.shortages(heard)
assert(#shortages == 2 and shortages[1].item == "mcl_core:coal_lump")
assert(shortages[1].count == 15 and shortages[1].villagers == 2 and math.abs(shortages[1].worth - 3.5) < 1e-9)
assert(report.gluts(heard)[1].item == "mcl_farming:wheat_item")

-- Gaps: a profession that makes what the village is short of, when none of its
-- producers are here. Books come from the librarian.
do
	local gaps = report.gaps({{item = "mcl_books:book", count = 2, worth = 2}}, {farmer = 3})
	assert(gaps[1].profession == "librarian" and gaps[1].score == 2 and gaps[1].items[1] == "mcl_books:book")
	assert(#report.gaps({{item = "mcl_books:book", count = 2, worth = 2}}, {librarian = 1}) == 0, "a producer is here")
	-- The worst gap's buildings are favoured; a profession no stock building houses, none.
	assert(report.favoured(gaps).library and not report.favoured(gaps).farm)
	assert(report.favoured({}) == nil)
	assert(report.buildings_for("fisherman").tavern and report.buildings_for("fisherman").medium_house)
	assert(report.buildings_for("tool_smith") == nil)
	-- The keeper's bread is no building's work.
	for _, gap in ipairs(report.gaps({{item = "mcl_farming:bread", count = 9, worth = 9}}, {})) do
		assert(gap.profession ~= "keeper")
	end
end

-- The whole report, from villagers around the bench.
do
	local function villager(fields)
		local self = {name = "mobs_mc:villager", _id = fields.id}
		for k, v in pairs(fields) do self[k] = v end
		objects[#objects + 1] = {get_luaentity = function() return self end}
		return self
	end
	local smith = villager({id = "smith1", _profession = "armorer"})
	villager({id = "bob", _profession = "mason", _villages_builder = true})
	villager({id = "kip", _profession = "farmer", _villages_keeper = true})
	villager({id = "nit", _profession = "nitwit", _villages_labour = {day = day, activity = "forager"}})
	villager({id = "lazy", _profession = "unemployed", _villages_labour = {day = day - 1, activity = "woodcutter"}})
	villager({id = "kid", _profession = "unemployed", child = true})
	objects[#objects + 1] = {get_luaentity = function() return {name = "mobs_mc:cow"} end}
	tally.note(smith, {["mcl_armor:boots_iron"] = 1}, {["mcl_core:iron_ingot"] = 4, ["mcl_core:charcoal_lump"] = 1}, day)
	local around = report.around({x = 0, y = 0, z = 0}, 64)
	assert(#around == 5, "adults only, villagers only")
	local r = report.build(heard, around, day)
	assert(r.heard and r.present.armorer == 1 and r.present.builder == 1 and r.present.keeper == 1)
	assert(r.present.mason == nil and r.present.farmer == nil, "the Builder and the keeper by their roles")
	assert(#r.idle == 2 and r.idle[1].id == "lazy" and r.idle[1].activity == nil and r.idle[2].activity == "forager")
	assert(r.today.made[1].item == "mcl_armor:boots_iron" and r.today.used[1].item == "mcl_core:iron_ingot")
	assert(#r.yesterday.made == 0)
	assert(r.gaps[1].profession == "librarian", r.gaps[1].profession)
	-- Without a Builder near, nothing heard.
	local quiet = report.build(nil, around, day)
	assert(not quiet.heard and quiet.shortages == nil and quiet.gaps == nil and quiet.present.armorer == 1)
end

print("economy_report.lua: ok")
