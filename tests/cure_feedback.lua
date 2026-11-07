-- Run with: lua tests/cure_feedback.lua
local sounds, spawners = {}, {}

minetest = {
	get_modpath = function() return "." end,
	sound_play = function(name, spec) sounds[#sounds + 1] = {name = name, spec = spec} end,
	add_particlespawner = function(def) spawners[#spawners + 1] = def end,
}

local cure_feedback = dofile("cure_feedback.lua")

local function expect(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
	end
end

local function clear()
	for i = #sounds, 1, -1 do sounds[i] = nil end
	for i = #spawners, 1, -1 do spawners[i] = nil end
end

local function player(item)
	return {
		is_player = function() return true end,
		get_wielded_item = function() return {get_name = function() return item end} end,
	}
end

local function object()
	local o = {rot = {x = 0, y = 1, z = 0.2}, pos = {x = 1, y = 2, z = 3}}
	function o:get_rotation() return {x = self.rot.x, y = self.rot.y, z = self.rot.z} end
	function o:set_rotation(r) self.rot = r end
	function o:get_pos() return self.pos end
	return o
end

-- Vanilla's handlers, as in mobs_mc/villager_zombie.lua: the apple starts a cure, which
-- ends by swapping the zombie for a villager.
local converted = 0
local zombie_def = {
	on_rightclick = function(self, clicker)
		if not self._curing and clicker:get_wielded_item():get_name() == "mcl_core:apple_gold" then
			self._curing = 200
			self.shaking = true
		end
	end,
	do_custom = function(self, dtime)
		if self._curing then
			self._curing = self._curing - dtime
			if self._curing <= 0 then
				self._curing = nil
				converted = converted + 1
				return false
			end
		end
	end,
}
cure_feedback.install(zombie_def)

local function zombie() return {object = object()} end

-- The cure starts: a sound on the zombie and a burst attached to it.
do
	clear()
	local z = zombie()
	zombie_def.on_rightclick(z, player("mcl_core:apple_gold"))
	expect(z._curing, 200, "vanilla still starts the cure")
	expect(#sounds, 1, "one sound")
	expect(sounds[1].name, "mobs_mc_zombie_growl", "the start sound")
	expect(sounds[1].spec.object, z.object, "played on the zombie")
	expect(#spawners, 1, "one burst")
	expect(spawners[1].attached, z.object, "attached to the zombie")
end

-- Anything else does nothing; vanilla ignores it too.
do
	clear()
	local z = zombie()
	zombie_def.on_rightclick(z, player("mcl_core:apple"))
	expect(z._curing, nil, "no cure from a plain apple")
	expect(#sounds + #spawners, 0, "and no feedback")
end

-- An apple on a zombie already curing: a small puff, no sound, the timer untouched.
do
	clear()
	local z = zombie()
	z._curing = 50
	zombie_def.on_rightclick(z, player("mcl_core:apple_gold"))
	expect(z._curing, 50, "vanilla leaves the timer alone")
	expect(#sounds, 0, "no sound")
	expect(#spawners, 1, "a puff")
	clear()
	zombie_def.on_rightclick(z, player("mcl_core:bread"))
	expect(#spawners, 0, "but not for another item")
end

-- While curing: a steady shake that replaces vanilla's roll, and particles every second.
do
	clear()
	local z = zombie()
	z._curing, z.shaking = 100, true
	local rolls = {}
	for i = 1, 20 do
		z.object.rot.z = 0.2 -- vanilla's roll at its peak, set earlier in the step
		zombie_def.do_custom(z, 0.1)
		rolls[i] = z.object.rot.z
	end
	local lo, hi = math.huge, -math.huge
	for _, r in ipairs(rolls) do lo, hi = math.min(lo, r), math.max(hi, r) end
	assert(hi - lo > 0.2, "the zombie sways from side to side")
	assert(hi <= 0.12 + 1e-9 and lo >= -0.12 - 1e-9, "within the shake's roll")
	expect(z.object.rot.y, 1, "the yaw is kept")
	expect(#spawners, 2, "a spawner a second over two seconds")
	expect(#sounds, 0, "and no sound")
end

-- Without vanilla's shaking flag the rotation is left alone.
do
	clear()
	local z = zombie()
	z._curing = 100
	zombie_def.do_custom(z, 0.1)
	expect(z.object.rot.z, 0.2, "roll untouched")
end

-- The conversion: a sound and a burst where the zombie stood, unattached.
do
	clear()
	local z = zombie()
	z._curing, z.shaking = 0.05, true
	local result = zombie_def.do_custom(z, 0.1)
	expect(result, false, "vanilla's result passes through")
	expect(converted, 1, "vanilla converts")
	expect(#sounds, 1, "one sound")
	expect(sounds[1].name, "mcl_brewing_complete", "the done sound")
	expect(sounds[1].spec.pos, z.object.pos, "at the zombie's place")
	expect(#spawners, 1, "one burst")
	expect(spawners[1].attached, nil, "not attached to the removed zombie")
	expect(spawners[1].minpos.x, 1 - 0.4, "around that place")
end

-- A zombie that is not curing gets nothing.
do
	clear()
	local z = zombie()
	zombie_def.do_custom(z, 1)
	expect(#sounds + #spawners, 0, "nothing")
	expect(z.object.rot.z, 0.2, "roll untouched")
end

print("cure_feedback tests passed")
