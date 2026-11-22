-- keeper_market.lua (ticket 51): on a market day the keeper goes round the stalls that show
-- food it wants, once each a day, and buys there.
local now, day, tod = 0, 4, 11000 / 24000
local objects = {}
vector = {
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
}
minetest = {
	get_modpath = function() return "." end,
	get_timeofday = function() return tod end,
	get_gametime = function() return now end,
	get_day_count = function() return day end,
	get_objects_inside_radius = function() return objects end,
	log = function() end,
	registered_items = nil,
}
core = minetest

local market = dofile("keeper_market.lua")

-- Market hours: a holiday, 10500 to 14500.
assert(market.open(true, 10500) and market.open(true, 14499))
assert(not market.open(true, 10499) and not market.open(true, 14500) and not market.open(false, 12000))

local function entity(id, pos, goods)
	local e = {_id = id}
	e.object = {get_pos = function() return pos end, get_luaentity = function() return e end}
	if goods then e._villages_market_session = {stall = {}, goods = goods} end
	return e
end
local keeper = entity("keeper", {x = 0, y = 0, z = 0})
local far_butcher = entity("butcher", {x = 20, y = 0, z = 0}, {"mcl_fishing:fish_cooked", "mcl_mobitems:feather"})
local near_farmer = entity("farmer", {x = 5, y = 0, z = 0}, {"mcl_farming:bread", "mcl_farming:wheat_seeds"})
local mason = entity("mason", {x = 2, y = 0, z = 0}, {"mcl_core:stonebrick"})
local walker = entity("walker", {x = 1, y = 0, z = 0})
objects = {far_butcher.object, near_farmer.object, mason.object, walker.object, keeper.object}

-- The stalls with food it wants, nearest first: only their food; none without food, nor a
-- villager keeping no stall.
local stalls = market.stalls(keeper, {x = 0, y = 0, z = 0}, day)
assert(#stalls == 2 and stalls[1].seller == near_farmer and stalls[2].seller == far_butcher)
assert(#stalls[1].items == 1 and stalls[1].items[1] == "mcl_farming:bread")
assert(#stalls[2].items == 1 and stalls[2].items[1] == "mcl_fishing:fish_cooked")

-- A step walks to the nearest; arriving, it marks the stall visited and trades there.
local walked
local step_go = function(self, target, arrive) walked = {target = target, arrive = arrive} end
assert(market.step(keeper, now, day, step_go))
assert(walked and walked.target.x == 5)
keeper.object.get_pos = function() return {x = 4, y = 0, z = 0} end
walked.arrive(keeper)
assert(keeper._villages_market_visited.farmer)
-- Next, the butcher; the farmer's stall is not visited again today.
now = now + market.CHECK_SECONDS
walked = nil
market.step(keeper, now, day, step_go)
assert(walked and walked.target.x == 20)
-- A new day: every stall again.
assert(#market.stalls(keeper, {x = 0, y = 0, z = 0}, day + 4) == 2)

print("keeper_market.lua: ok")
