-- Each villager's economic clock (docs/villager-economy-design.md): seconds of game
-- time it has been economically active. Hunger reads it, and so will production
-- and crafting, so that all of them pause together. A village no player is near
-- is neither fed nor hungry, and is never found starving with full fields.
--
-- Active means loaded with a player within mcl_mobs' active range. mcl_mobs runs
-- do_custom for a suspended villager too (mcl_mobs/api.lua), so the range is asked
-- here. The clock advances in stamps every STAMP_SECONDS. A gap of AWAY_GAP or
-- more since the last stamp (unloaded, or suspended and stamped out) is not added.
-- This is builder.lua's stamp, used the other way round: the Builder pays for the
-- gap, the economy skips it.
--
-- A night skipped while it stays active (players sleeping, or a test world's lv_keep)
-- moves the time of day but not game time. Each stamp also notes where it fell in the
-- calendar (`_villages_econ_cal`, days); when the calendar ran further than game time
-- between two stamps, the clock adds the difference, up to one game day. Hunger and
-- rent then count calendar days, as dinner does, while a village that could not work
-- through the night (unloaded, or no player near) still neither hungers nor pays.
local core = minetest

local STAMP_SECONDS = 10
local AWAY_GAP = 120

local M = {STAMP_SECONDS = STAMP_SECONDS, AWAY_GAP = AWAY_GAP}

-- Seconds of game time in a game day, or nil while time stands still.
local function day_seconds()
	local speed = core.settings and core.settings.get and tonumber(core.settings:get("time_speed")) or 72
	if speed <= 0 then return nil end
	return 86400 / speed
end

-- Where in the calendar it is, in days, or nil where the engine does not say.
local function calendar()
	if not core.get_day_count or not core.get_timeofday then return nil end
	return core.get_day_count() + core.get_timeofday()
end

-- Seconds a skip added between two stamps `real` seconds apart: how far the calendar
-- ran past game time, within one day.
local function skipped(from, to, real)
	local day = day_seconds()
	if not from or not to or not day then return 0 end
	return math.min(math.max((to - from) * day - real, 0), day)
end

function M.enabled()
	return not core.settings or core.settings:get_bool("living_villages_economy", true)
end

function M.read(self)
	return self._villages_econ_clock or 0
end

local function active(self)
	return not self.player_in_active_range or self:player_in_active_range() and true or false
end

-- Moves the clock on to `now`, if a stamp is due. `is_active` defaults to asking
-- mcl_mobs. Returns the clock.
function M.advance(self, now, is_active)
	local stamp = self._villages_econ_stamp
	local clock = M.read(self)
	if stamp and now >= stamp and now - stamp < STAMP_SECONDS then return clock end
	if is_active == nil then is_active = active(self) end
	local cal = calendar()
	if is_active then
		if stamp and now >= stamp and now - stamp < AWAY_GAP then
			clock = clock + (now - stamp) + skipped(self._villages_econ_cal, cal, now - stamp)
		end
		self._villages_econ_stamp = now
		self._villages_econ_cal = cal
		self._villages_econ_clock = clock
	else
		self._villages_econ_stamp, self._villages_econ_cal = nil, nil
	end
	return clock
end

-- Outermost do_custom wrapper, so the clock runs whatever an inner one returns.
function M.install(def)
	if not M.enabled() then return end
	local original = def.do_custom
	def.do_custom = function(self, dtime)
		M.advance(self, core.get_gametime())
		if original then return original(self, dtime) end
	end
end

return M
