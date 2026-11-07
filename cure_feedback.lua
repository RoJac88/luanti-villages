-- Makes a zombie villager's cure visible. VoxeLibre's only sign of a cure is a roll of
-- sin(random walk) / 5, which often rests near its 11.5 degree peak for 20 s and more, so
-- the zombie seems to stop and lean while it goes on walking and attacking. The apple
-- also comes back, so nothing tells a player the click worked. This adds Java's cues:
-- a sound and particles when the cure starts, particles and a steady shake while it runs,
-- and a sound and particles when the villager appears. A click with a golden apple on a
-- zombie already curing puffs particles, since vanilla ignores it.
--
-- Nothing is saved: the shake's phase and the particle timer live in a weak table, and
-- whether a zombie is curing is vanilla's own _curing, which is saved with it.
local core = minetest

local APPLE = "mcl_core:apple_gold"
-- Java's regeneration colour for the cure, its happy villager green for the conversion.
local CURE_TEXTURE = "mcl_particles_effect.png^[colorize:#cd5cab:200"
local DONE_TEXTURE = "mcl_particles_bonemeal.png^[colorize:#00ee00:125"
local START_SOUND = "mobs_mc_zombie_growl"
local DONE_SOUND = "mcl_brewing_complete"
local HEAR = 16
-- The shake: radians and cycles per second. Vanilla's peak is 0.2 rad.
local SHAKE_ROLL = 0.12
local SHAKE_HZ = 2.5
local PARTICLE_SECONDS = 1
-- The zombie's collision box is 1.94 tall; particles rise from its body.
local BODY_LOW, BODY_HIGH = 0.4, 1.8

local state = setmetatable({}, {__mode = "k"})

local function burst(at, attached, texture, amount, seconds)
	if not core.add_particlespawner then return end
	core.add_particlespawner({
		amount = amount,
		time = seconds,
		attached = attached,
		minpos = {x = at.x - 0.4, y = at.y + BODY_LOW, z = at.z - 0.4},
		maxpos = {x = at.x + 0.4, y = at.y + BODY_HIGH, z = at.z + 0.4},
		minvel = {x = -0.2, y = 0.3, z = -0.2},
		maxvel = {x = 0.2, y = 0.8, z = 0.2},
		minexptime = 0.6,
		maxexptime = 1.2,
		minsize = 1,
		maxsize = 2,
		texture = texture,
		glow = 8,
	})
end

-- Around the zombie: positions are relative to it when the spawner is attached.
local function body_burst(self, texture, amount, seconds)
	burst({x = 0, y = 0, z = 0}, self.object, texture, amount, seconds)
end

local function sound(name, spec, pitch)
	if not core.sound_play then return end
	spec.gain = 1
	spec.pitch = pitch
	spec.max_hear_distance = HEAR
	core.sound_play(name, spec, true)
end

local function wielded_name(clicker)
	if not (clicker and clicker.is_player and clicker:is_player() and clicker.get_wielded_item) then return nil end
	return clicker:get_wielded_item():get_name()
end

local function shake(self, dtime)
	local s = state[self]
	if not s then
		s = {phase = 0, particles = 0}
		state[self] = s
	end
	s.phase = (s.phase + dtime * SHAKE_HZ) % 1
	-- After vanilla's own roll this step, which this replaces; pitch and yaw are kept.
	if self.shaking and self.object.get_rotation then
		local rot = self.object:get_rotation()
		if rot then
			rot.z = math.sin(s.phase * 2 * math.pi) * SHAKE_ROLL
			self.object:set_rotation(rot)
		end
	end
	s.particles = s.particles - dtime
	if s.particles <= 0 then
		s.particles = PARTICLE_SECONDS
		body_burst(self, CURE_TEXTURE, 4, PARTICLE_SECONDS)
	end
end

local function install(zombie_def)
	local original_rightclick = zombie_def.on_rightclick
	zombie_def.on_rightclick = function(self, clicker)
		local was_curing = self._curing
		local held = wielded_name(clicker)
		local result = original_rightclick(self, clicker)
		if self._curing and not was_curing then
			sound(START_SOUND, {object = self.object}, 1.4)
			body_burst(self, CURE_TEXTURE, 24, 0.5)
		elseif was_curing and held == APPLE then
			body_burst(self, CURE_TEXTURE, 8, 0.3)
		end
		return result
	end

	local original_custom = zombie_def.do_custom
	zombie_def.do_custom = function(self, dtime)
		local was_curing = self._curing
		local pos = was_curing and self.object:get_pos()
		local result = original_custom(self, dtime)
		if was_curing and self._curing == nil then
			-- Vanilla clears _curing only as it swaps the zombie for the villager.
			state[self] = nil
			if pos then
				sound(DONE_SOUND, {pos = pos}, 1)
				burst(pos, nil, DONE_TEXTURE, 30, 0.6)
			end
		elseif self._curing then
			shake(self, dtime)
		end
		return result
	end
end

return {install = install}
