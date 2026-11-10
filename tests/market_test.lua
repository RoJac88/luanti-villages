-- Run with: lua tests/market_test.lua
local day, time = 9, 0.3
local settings, logs, command = {}, {}, nil

vector = {
	new = function(a) return {x = a.x, y = a.y, z = a.z} end,
	distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
}

minetest = {
	get_modpath = function() return "." end,
	get_gametime = function() return 1000 end,
	get_day_count = function() return day end,
	get_timeofday = function() return time end,
	set_timeofday = function(t) time = t end,
	settings = {
		get = function(_, name) return settings[name] end,
		set = function(_, name, value) settings[name] = value end,
		get_bool = function(_, name, default)
			if settings[name] == nil then return default end
			return settings[name]
		end,
	},
	log = function(_, message) logs[#logs + 1] = message end,
	registered_items = {},
	registered_nodes = {},
	register_chatcommand = function(name, def) assert(name == "living_villages_market") command = def end,
	luaentities = {},
}

local test = dofile("market_test.lua")
local common = dofile("common.lua")
test.install()
assert(command and command.privs.server)

local nina = {name = "mobs_mc:villager", _id = "nina", _profession = "nitwit", _villages_food = 12,
	_villages_labour = {day = day, activity = "forager"}, _villages_market_stock_day = day,
	_villages_market_attempted = true, _villages_belongings = {["mcl_core:emerald"] = 640},
	_villages_market_news = {
		{item = "mcl_core:coal_lump", kind = "has", price = 256, count = 10, who = "cole", heard = 1000, hops = 1},
		{item = "mcl_core:coal_lump", kind = "needs", price = 640, count = 6, who = "smith", heard = 1000, hops = 1},
	}}
local smith = {name = "mobs_mc:villager", _id = "smith", _profession = "tool_smith", _villages_market_stock_day = day}
minetest.luaentities = {nina, smith, {name = "mobs_mc:cow"}}

-- Open: today is a holiday, the bell stage has begun, and everyone may set up again.
local ok, reply = command.func("tester", "open")
assert(ok and reply:find("holiday", 1, true))
assert(common.is_holiday() and not common.is_holiday(1), "today only")
assert(common.schedule_stage(nil, smith) == "bell")
assert(nina._villages_market_stock_day == nil and not nina._villages_market_attempted and smith._villages_market_stock_day == nil)

-- Work: a working day, the work stage, and labour chosen afresh, with the deal it heard.
ok, reply = command.func("tester", "work")
assert(ok and not common.is_holiday() and common.schedule_stage(nil, smith) == "work")
assert(nina._villages_labour == nil, "chooses again")
assert(reply:find("nina", 1, true) and reply:find("best deal", 1, true) and not reply:find("smith", 1, true))

-- Clear: the override goes; another day is never overridden.
day = day + 1
settings.living_villages_holiday_override = (day - 1) .. ":holiday"
assert(common.is_holiday() == (day % 4 == 0), "the override is for its own day")
command.func("tester", "clear")
assert(settings.living_villages_holiday_override == "")
assert(command.func("tester", "nonsense") == false)

print("market_test.lua: ok")
