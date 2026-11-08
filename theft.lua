-- Taking from a villager's stash (docs/villager-economy-design.md, Possessions, Theft;
-- ticket 9). Nothing is locked: a player may open any chest. But a player who takes
-- from a claimed stash (possessions.lua's `villages_owner` meta) within WITNESS_RADIUS
-- (16) of a villager that can see it, awake, gives that villager `minor_negative`
-- gossip about the player (gossip.lua), as a hit does, which the villager then passes
-- on in conversation. One theft per witness and player counts once in COOLDOWN seconds,
-- so emptying a chest stack by stack is one theft, not a dozen.
--
-- What was taken is written in the chest's meta (`villages_missing`). The owner finds
-- it when it next looks, once a minute (its own do_custom wrapper here), and logs the loss;
-- its ledger already counts the stash, so whatever it needed of what went missing it
-- now needs more, and says so in market news (market_news.lua).
--
-- Chests' on_metadata_inventory_take (mcl_chests/api.lua, which only logs) is wrapped,
-- for every chest node a stash can be. Off with the economy.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local stock = dofile(core.get_modpath("living_villages") .. "/farm_stock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")

local WITNESS_RADIUS = 16
local EYE = 1.5
local COOLDOWN = 60
local VILLAGER = "mobs_mc:villager"
local MISSING = "villages_missing"

local M = {WITNESS_RADIUS = WITNESS_RADIUS, COOLDOWN = COOLDOWN, MISSING = MISSING}

local noted = {}

local function sees(a, b)
	if not core.line_of_sight then return true end
	return core.line_of_sight({x = a.x, y = a.y + EYE, z = a.z}, {x = b.x, y = b.y + EYE, z = b.z}) ~= false
end

local function add_missing(pos, name, count)
	local meta = core.get_meta(pos)
	local missing = core.deserialize(meta:get_string(MISSING)) or {}
	missing[name] = (missing[name] or 0) + count
	meta:set_string(MISSING, core.serialize(missing))
end

-- A player took `stack` from the chest at pos. Returns the witnesses who noted it.
function M.taken(gossip, pos, stack, player)
	if not clock.enabled() or not player or not player.is_player or not player:is_player() then return {} end
	local owner = core.get_meta(pos):get_string(possessions.OWNER)
	if owner == "" or stack:is_empty() then return {} end
	add_missing(pos, stack:get_name(), stack:get_count())
	local name = player:get_player_name()
	local seen_from = player:get_pos() or pos
	local now = core.get_gametime()
	local witnesses = {}
	for _, object in ipairs(core.get_objects_inside_radius(seen_from, WITNESS_RADIUS)) do
		local villager = object:get_luaentity()
		local at = villager and villager.name == VILLAGER and not villager._villages_sleeping and object:get_pos()
		if at and sees(at, seen_from) then
			local key = tostring(villager._id) .. "|" .. name
			if not noted[key] or now - noted[key] >= COOLDOWN then
				noted[key] = now
				gossip.add(villager, name, "minor_negative")
				witnesses[#witnesses + 1] = villager
			end
		end
	end
	core.log("action", string.format("[living_villages] theft: %s took %d %s from %s's stash at %s, seen by %d",
		name, stack:get_count(), stack:get_name(), owner:sub(1, 6), core.pos_to_string(pos), #witnesses))
	return witnesses
end

-- What has gone from the villager's stash since it last looked, cleared as it reads.
function M.discover(self)
	local stash = self._villages_stash
	if not stash or core.get_meta(stash):get_string(possessions.OWNER) ~= self._id then return nil end
	local found
	for _, half in ipairs(possessions.halves(stash)) do
		local meta = core.get_meta(half)
		local missing = core.deserialize(meta:get_string(MISSING))
		if missing then
			meta:set_string(MISSING, "")
			found = found or {}
			for item, count in pairs(missing) do found[item] = (found[item] or 0) + count end
		end
	end
	if found then
		local parts = {}
		for item, count in pairs(found) do parts[#parts + 1] = count .. " " .. item end
		table.sort(parts)
		core.log("action", string.format("[living_villages] villager %s found %s gone from its stash",
			tostring(self._id):sub(1, 6), table.concat(parts, ", ")))
	end
	return found
end

function M.install(gossip, def)
	if not clock.enabled() then return end
	for _, node in ipairs(stock.CHEST_NODES) do
		local registered = core.registered_nodes[node]
		if registered then
			local original = registered.on_metadata_inventory_take
			core.override_item(node, {
				on_metadata_inventory_take = function(pos, listname, index, stack, player)
					if original then original(pos, listname, index, stack, player) end
					M.taken(gossip, pos, stack, player)
				end,
			})
		end
	end
	local original_custom = def.do_custom
	local next_look = setmetatable({}, {__mode = "k"})
	def.do_custom = function(self, dtime)
		local now = core.get_gametime()
		if not self.child and now >= (next_look[self] or 0) then
			next_look[self] = now + possessions.CLAIM_SECONDS
			M.discover(self)
		end
		return original_custom(self, dtime)
	end
end

return M
