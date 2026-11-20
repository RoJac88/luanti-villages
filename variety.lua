-- Variety in meals (docs/villager-economy-design.md, ticket 34). A villager tires of a
-- food it ate a lot of lately: the food is worth less to it, so it buys, eats and dines on
-- others first, and a tavern that serves one dish only sees guests turn it down.
--
-- A record is {[day] = {[item] = count}} over the last WEEK days: an adult's meals
-- (`_villages_meals`, written by food.receive), or the dishes a keeper served
-- (`_villages_served_dishes`, meal.lua). A meal weighs (WEEK - age) / WEEK: today's 1, one
-- six days ago 1/7. An item's share is its weight over all the weight plus PRIOR meals, so
-- one meal is not a whole diet, and its factor 1 - DEPTH × share: 1 for a food not eaten
-- lately, never under 1 - DEPTH. Bread every day for a week gives about 0.71; two dishes
-- in turn about 0.85 each. Nutrition does not change, only what a food is worth.
--
-- Pure: it reads and writes only the record it is handed.
local WEEK = 7
local PRIOR = 3
local DEPTH = 0.5

local M = {WEEK = WEEK, PRIOR = PRIOR, DEPTH = DEPTH}

-- Notes `count` (1 unset) of `item` eaten on `day` in `record` (nil for a new one), drops
-- days past the week, and returns the record.
function M.note(record, item, day, count)
	record = record or {}
	for past in pairs(record) do
		if day - past >= WEEK or past > day then record[past] = nil end
	end
	local today = record[day] or {}
	today[item] = (today[item] or 0) + (count or 1)
	record[day] = today
	return record
end

-- The weight of `item`'s meals in `record` on `day`, and of all of them.
local function weights(record, item, day)
	local mine, all = 0, 0
	for past, meals in pairs(record or {}) do
		local age = day - past
		if age >= 0 and age < WEEK then
			local weight = (WEEK - age) / WEEK
			for eaten, count in pairs(meals) do
				all = all + weight * count
				if eaten == item then mine = mine + weight * count end
			end
		end
	end
	return mine, all
end

-- What `item` is worth to the eater, as a factor from 1 - DEPTH to 1.
function M.factor(record, item, day)
	local mine, all = weights(record, item, day)
	if mine <= 0 then return 1 end
	return 1 - DEPTH * mine / (all + PRIOR)
end

-- The item of `items` with the highest factor, `pick(n)` choosing among `n` tied (the
-- first unset); nil for none.
function M.best(record, items, day, pick)
	local top, tied = nil, {}
	for _, item in ipairs(items) do
		local factor = M.factor(record, item, day)
		if not top or factor > top + 1e-9 then
			top, tied = factor, {item}
		elseif factor > top - 1e-9 then
			tied[#tied + 1] = item
		end
	end
	if #tied == 0 then return nil end
	return tied[pick and pick(#tied) or 1]
end

return M
