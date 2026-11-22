-- tavern_duty.lua (ticket 48): the butcher's dishes for the keeper alone while a keeper
-- serves, and a keeper absent two dinners in a row leaves its jukebox vacant.
local metas = {}
local function key(pos) return pos.x .. "," .. pos.y .. "," .. pos.z end
local day, tod, now = 10, 0.5, 0
local jukeboxes = {}
minetest = {
	get_modpath = function() return "." end,
	get_day_count = function() return day end,
	get_timeofday = function() return tod end,
	get_gametime = function() return now end,
	get_meta = function(pos)
		local k = key(pos)
		metas[k] = metas[k] or {}
		local m = metas[k]
		return {
			get_string = function(_, name) return m[name] or "" end,
			set_string = function(_, name, value) m[name] = value end,
		}
	end,
	find_nodes_in_area = function(minp, maxp)
		local out = {}
		for _, pos in ipairs(jukeboxes) do
			if pos.x >= minp.x and pos.x <= maxp.x and pos.y >= minp.y and pos.y <= maxp.y
				and pos.z >= minp.z and pos.z <= maxp.z then out[#out + 1] = pos end
		end
		return out
	end,
}
core = minetest

local duty = dofile("tavern_duty.lua")

-- Missed dinners: today's counts once its service is over (18500 ticks).
assert(duty.missed(9, 10, false) == 0)
assert(duty.missed(9, 10, true) == 1)
assert(duty.missed(8, 10, false) == 1)
assert(duty.missed(8, 10, true) == 2)
assert(not duty.absent(9, 10, true) and not duty.absent(8, 10, false))
assert(duty.absent(8, 10, true) and duty.absent(7, 10, false))
assert(not duty.absent(nil, 10, true), "never noted: not absent")

-- A jukebox: unclaimed is vacant; claimed and staffed today is not; two dinners missed is.
local jukebox = {x = 0, y = 0, z = 0}
jukeboxes[1] = jukebox
assert(duty.vacant(jukebox))
minetest.get_meta(jukebox):set_string("villager", "keeper1")
assert(not duty.vacant(jukebox), "claimed, never noted")
local keeper = {_id = "keeper1", _villages_keeper = true}
duty.note(keeper, jukebox)
assert(keeper._villages_keeper_staffed == 10 and not duty.vacant(jukebox) and not duty.stale(jukebox))
day, tod = 12, 0.5
assert(not duty.vacant(jukebox), "missed day 11 only: today's service is still to come")
tod = 18600 / 24000
assert(duty.vacant(jukebox) and duty.stale(jukebox), "missed days 11 and 12")
day, tod = 12, 0.5

-- The butcher's dishes: for the keeper alone while a keeper serves near its bed.
local butcher = {_id = "b", _profession = "butcher", _bed = {x = 10, y = 0, z = 10}}
local diner = {_id = "d", _profession = "mason"}
duty.note(keeper, jukebox)
assert(duty.keeper_only(butcher, "mcl_mobitems:cooked_beef"))
assert(not duty.keeper_only(butcher, "mcl_mobitems:beef"), "raw meat sells to anyone")
assert(not duty.may_sell(butcher, diner, "mcl_mobitems:cooked_beef"))
assert(duty.may_sell(butcher, keeper, "mcl_mobitems:cooked_beef"))
assert(duty.may_sell({_id = "f", _profession = "farmer", _bed = butcher._bed}, diner, "mcl_farming:bread"),
	"a farmer's bread sells to anyone")
-- Far from any tavern: anyone buys.
local far = {_id = "far", _profession = "butcher", _bed = {x = 500, y = 0, z = 0}}
assert(duty.may_sell(far, diner, "mcl_mobitems:cooked_beef"))
-- Its keeper absent: the cached answer holds CHECK_SECONDS, then anyone buys.
tod = 18600 / 24000
day = 14
assert(duty.keeper_only(butcher, "mcl_mobitems:cooked_beef"), "cached")
now = now + duty.CHECK_SECONDS + 1
assert(not duty.keeper_only(butcher, "mcl_mobitems:cooked_beef"), "no keeper serving: anyone buys")

print("tavern_duty.lua: ok")
