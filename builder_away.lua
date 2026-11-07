-- What a Builder gets done while no player is near (builder.lua). Its villager is unloaded
-- then, so nothing happens until a player comes back; the time it was away is then turned into
-- blocks at a fraction of the pace it kept while it was watched, on this same project. That
-- pace is earned, not configured: it counts every second of work spent on the project,
-- chest trips, walks, waits and climbs included, so with the fraction under 1 staying near
-- is always quicker. A project that never got going has no pace and gets nothing. Pure.
local M = {}

-- The least it must have shown before its pace counts.
M.MIN_SECONDS = 300
M.MIN_PLACED = 32
-- A pace for blocks from the scaffolding needs this many of them; until then they are taken
-- to be this much slower than the ground's.
M.MIN_HIGH = 8
M.HIGH_SLOWER = 4
-- The fraction of its watched pace it keeps while away, unless the setting says otherwise.
M.DEFAULT_FACTOR = 0.5
M.MAX_FACTOR = 0.9

local function kind_of(high)
	return high and "high" or "ground"
end

-- The record a project keeps: seconds and blocks by kind, and seconds not yet put down to a
-- block.
function M.new_tally()
	return {ground = {seconds = 0, placed = 0}, high = {seconds = 0, placed = 0}, pending = 0}
end

-- Seconds of work go to the next block placed, whatever it is, so the trip that fetched a
-- column's blocks counts against the column.
function M.add_seconds(tally, seconds)
	if seconds > 0 then tally.pending = tally.pending + seconds end
end

function M.add_placed(tally, high)
	local kind = tally[kind_of(high)]
	kind.seconds = kind.seconds + tally.pending
	kind.placed = kind.placed + 1
	tally.pending = 0
end

-- Adds what a session counted to what the project kept.
function M.merge(into, from)
	for _, kind in ipairs({"ground", "high"}) do
		into[kind].seconds = into[kind].seconds + from[kind].seconds
		into[kind].placed = into[kind].placed + from[kind].placed
	end
	into.pending = into.pending + from.pending
end

-- Blocks a second, for the ground and for the scaffolding, or nil if too little was seen.
-- Seconds not yet put down to a block count against the ground, so a long wait lowers it.
function M.rates(tally)
	if not tally then return nil end
	local g, h = tally.ground, tally.high
	local seconds = g.seconds + h.seconds + tally.pending
	local placed = g.placed + h.placed
	if seconds < M.MIN_SECONDS or placed < M.MIN_PLACED then return nil end
	local ground_seconds = g.seconds + tally.pending
	local ground = g.placed > 0 and ground_seconds > 0 and g.placed / ground_seconds or nil
	local high = h.placed >= M.MIN_HIGH and h.seconds > 0 and h.placed / h.seconds or nil
	-- One kind only: the other is guessed from it, never quicker.
	ground = ground or (high and high * M.HIGH_SLOWER)
	high = high or (ground and ground / M.HIGH_SLOWER)
	if not ground or not high then return nil end
	return {ground = ground, high = high}
end

function M.factor(setting)
	local factor = tonumber(setting) or M.DEFAULT_FACTOR
	return math.max(0, math.min(M.MAX_FACTOR, factor))
end

-- Seconds of its time away a step takes.
function M.cost(rates, factor, high)
	local rate = rates[kind_of(high)] * factor
	if rate <= 0 then return math.huge end
	return 1 / rate
end

return M
