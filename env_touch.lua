-- Lava (or fire, or water) a villager only touches does not burn it.
--
-- mcl_mobs' environment check (physics.lua, get_env_hits) asks find_nodes_in_area for
-- lava over the mob's whole collision box. A villager pressed against a wall has its box
-- edge exactly on the cell boundary, and the engine rounds that edge (x.5, plus float
-- error) into the next cell: a lava cell diagonal to it, past the corner of the wall it
-- leans on, counts as touched, and it burns standing still. Two quarriers died so at
-- the user's cobble generator in ColonyFood (2026-11-19), the second after the generator
-- had let it go, wedged in the corner of the stand cell in front of the cobble.
--
-- For the check alone the box is drawn in by INSET on each side across, so only lava it
-- overlaps counts. Its height, which also gives the feet the check reads, is unchanged.
local INSET = 0.05

return function(def)
	local function inset(box)
		return {
			math.min(box[1] + INSET, 0), box[2], math.min(box[3] + INSET, 0),
			math.max(box[4] - INSET, 0), box[5], math.max(box[6] - INSET, 0),
		}
	end
	-- The def's own, or mcl_mobs' mob_class one through its metatable.
	local original = def.do_env_damage
	if not original then return end
	def.do_env_damage = function(self, ...)
		local own = rawget(self, "base_colbox")
		local box = own or self.base_colbox or self.initial_properties.collisionbox
		self.base_colbox = inset(box)
		local ok, result = pcall(original, self, ...)
		self.base_colbox = own
		if not ok then error(result, 0) end
		return result
	end
end
