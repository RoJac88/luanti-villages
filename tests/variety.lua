-- Run with: lua tests/variety.lua
minetest = {get_modpath = function() return "." end}
local variety = dofile("variety.lua")
local BREAD, FISH, STEW = "mcl_farming:bread", "mcl_fishing:fish_cooked", "mcl_mushrooms:mushroom_stew"
local function near(a, b, eps) return math.abs(a - b) < (eps or 1e-9) end

-- A food not eaten lately is worth its all.
assert(variety.factor(nil, BREAD, 10) == 1)
-- One meal is not a whole diet: 1 over 1 + PRIOR.
local record = variety.note(nil, BREAD, 10)
assert(near(variety.factor(record, BREAD, 10), 1 - variety.DEPTH * 1 / (1 + variety.PRIOR)))
assert(variety.factor(record, FISH, 10) == 1)

-- Bread every day for a week: about 0.71.
record = nil
for day = 1, 7 do record = variety.note(record, BREAD, day) end
local bread_only = variety.factor(record, BREAD, 7)
assert(near(bread_only, 1 - 0.5 * 4 / 7, 1e-6), bread_only)
-- Two dishes in turn: about 0.85 each, both better than one dish.
local turns
for day = 1, 7 do turns = variety.note(turns, day % 2 == 0 and BREAD or FISH, day) end
local a, b = variety.factor(turns, BREAD, 7), variety.factor(turns, FISH, 7)
assert(a > bread_only and b > bread_only and a > 0.8 and b > 0.8, a .. " " .. b)

-- Never under 1 - DEPTH, however much of one food.
local glut
for day = 1, 7 do glut = variety.note(glut, BREAD, day, 50) end
local floor = variety.factor(glut, BREAD, 7)
assert(floor >= 1 - variety.DEPTH and floor < 0.52, floor)

-- Recent meals weigh more: bread a week ago tires less than bread today.
local old = variety.note(nil, BREAD, 1)
local new = variety.note(nil, BREAD, 7)
assert(variety.factor(old, BREAD, 7) > variety.factor(new, BREAD, 7))
-- Days past the week drop out, read and written.
assert(variety.factor(old, BREAD, 8) == 1)
local trimmed = variety.note(variety.note(nil, BREAD, 1), FISH, 8)
assert(trimmed[1] == nil and trimmed[8][FISH] == 1)

-- The least tired-of dish; among equals, `pick` chooses, the first unset.
record = variety.note(variety.note(nil, BREAD, 5), BREAD, 6)
record = variety.note(record, FISH, 6)
assert(variety.best(record, {BREAD, FISH, STEW}, 6) == STEW)
assert(variety.best(record, {BREAD, FISH}, 6) == FISH)
assert(variety.best(nil, {BREAD, FISH}, 6) == BREAD)
assert(variety.best(nil, {BREAD, FISH}, 6, function(n) return n end) == FISH)
assert(variety.best(record, {}, 6) == nil)
print("variety.lua: ok")
