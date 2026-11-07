-- Run with: lua tests/builder_away.lua
-- A Builder's pace while watched, and what its time away is worth (builder_away.lua).
local away = dofile("builder_away.lua")

local function close(a, b) return math.abs(a - b) < 1e-9 end

-- Seconds go to the next block placed, of whichever kind.
do
	local tally = away.new_tally()
	away.add_seconds(tally, 10)
	away.add_seconds(tally, -3)
	away.add_placed(tally, false)
	away.add_placed(tally, false)
	away.add_seconds(tally, 6)
	away.add_placed(tally, true)
	assert(tally.ground.seconds == 10 and tally.ground.placed == 2)
	assert(tally.high.seconds == 6 and tally.high.placed == 1 and tally.pending == 0)

	local kept = away.new_tally()
	away.add_seconds(kept, 4)
	away.merge(kept, tally)
	assert(kept.ground.placed == 2 and kept.high.seconds == 6 and kept.pending == 4)
end

local function tally_of(ground_seconds, ground_placed, high_seconds, high_placed, pending)
	return {
		ground = {seconds = ground_seconds, placed = ground_placed},
		high = {seconds = high_seconds or 0, placed = high_placed or 0}, pending = pending or 0,
	}
end

-- Too little seen: no pace, so nothing while away.
assert(away.rates(nil) == nil)
assert(away.rates(away.new_tally()) == nil)
assert(away.rates(tally_of(299, 100)) == nil, "not long enough")
assert(away.rates(tally_of(1000, 31)) == nil, "not enough blocks")
assert(away.rates(tally_of(1000, 0, 0, 0, 1000)) == nil, "waited the whole time")

-- The ground's pace, and the scaffolding's guessed from it until enough is seen.
do
	local rates = away.rates(tally_of(300, 150))
	assert(close(rates.ground, 0.5) and close(rates.high, 0.5 / away.HIGH_SLOWER))
	rates = away.rates(tally_of(300, 150, 70, 7))
	assert(close(rates.high, 0.5 / away.HIGH_SLOWER), "seven high blocks are too few")
	rates = away.rates(tally_of(300, 150, 80, 8))
	assert(close(rates.high, 0.1), "eight are enough: " .. rates.high)
	-- Time not yet put down to a block slows the ground.
	rates = away.rates(tally_of(300, 150, 0, 0, 300))
	assert(close(rates.ground, 0.25))
	-- Only high blocks seen: the ground is guessed from them.
	rates = away.rates(tally_of(0, 0, 400, 40))
	assert(close(rates.high, 0.1) and close(rates.ground, 0.1 * away.HIGH_SLOWER))
end

-- The fraction kept: the default, the setting, and never all of it.
assert(away.factor(nil) == away.DEFAULT_FACTOR and away.DEFAULT_FACTOR < 1)
assert(away.factor("0.3") == 0.3)
assert(away.factor("1") == away.MAX_FACTOR and away.MAX_FACTOR < 1, "staying is always quicker")
assert(away.factor("-1") == 0 and away.factor("junk") == away.DEFAULT_FACTOR)

-- What a block costs in time away: slower than it was watched, and slower again up high.
do
	local rates = {ground = 0.5, high = 0.1}
	assert(close(away.cost(rates, 0.5, false), 4))
	assert(close(away.cost(rates, 0.5, true), 20))
	assert(away.cost(rates, 0, false) == math.huge, "a factor of 0 turns it off")
	-- Whatever the pace and the factor, the same work takes longer away than watched.
	for _, factor in ipairs({0.1, 0.5, away.factor("5")}) do
		assert(away.cost(rates, factor, false) > 1 / rates.ground)
		assert(away.cost(rates, factor, true) > 1 / rates.high)
	end
end

print("builder_away: ok")
