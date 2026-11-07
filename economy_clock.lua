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
local core = minetest

local STAMP_SECONDS = 10
local AWAY_GAP = 120

local M = {STAMP_SECONDS = STAMP_SECONDS, AWAY_GAP = AWAY_GAP}

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
	if is_active then
		if stamp and now >= stamp and now - stamp < AWAY_GAP then clock = clock + (now - stamp) end
		self._villages_econ_stamp = now
		self._villages_econ_clock = clock
	else
		self._villages_econ_stamp = nil
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
