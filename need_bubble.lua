-- A villager's most urgent need, shown over its head to a player looking at it
-- (docs/villager-economy-design.md, What the player sees, Visibility; ticket 10).
--
-- Every INTERVAL seconds, for each player, a ray from its eye along its look reaches
-- RANGE (8) nodes; the first object it meets, if it is an adult villager, gets a bubble:
-- one particle above its head, seen only by that player, of the item it needs most by
-- worth (its ledger's needs, ledger.top by value), lasting until the next look. A node
-- in the way, or another object, hides it. A villager with no need shows nothing. A
-- villager's need is read at most once in NEED_SECONDS, since a player may stare.
--
-- The picture is the item's inventory image, or its wield image, or for a node drawn
-- as a cube (no inventory image) a cube of its tiles. Off with the economy.
local core = minetest
local clock = dofile(core.get_modpath("living_villages") .. "/economy_clock.lua")
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")

local RANGE = 8
local INTERVAL = 1
local NEED_SECONDS = 5
local DEFAULT_EYE = 1.625
-- Above a villager's head (its collision box is about 1.95 tall).
local ABOVE = 2.4
local SIZE = 5
local VILLAGER = "mobs_mc:villager"

local M = {RANGE = RANGE, INTERVAL = INTERVAL}

local function tile_name(tile)
	if type(tile) == "table" then tile = tile.name or tile.image end
	return type(tile) == "string" and tile ~= "" and tile or nil
end

-- A texture for the item, or nil.
function M.texture(item)
	local def = core.registered_items and core.registered_items[item]
	if not def then return nil end
	if def.inventory_image and def.inventory_image ~= "" then return def.inventory_image end
	if def.wield_image and def.wield_image ~= "" then return def.wield_image end
	local tiles = def.tiles
	if type(tiles) ~= "table" or not tile_name(tiles[1]) then return nil end
	local top = tile_name(tiles[1])
	local side = tile_name(tiles[3]) or tile_name(tiles[#tiles]) or top
	if core.inventorycube then return core.inventorycube(top, side, side) end
	return top
end

local cache = setmetatable({}, {__mode = "k"})

-- The item the villager needs most, or nil.
function M.need(self, now)
	local cached = cache[self]
	if cached and now < cached.until_time then return cached.item end
	local view = possessions.assess(self)
	local top = ledger.top(view.needs, view.value, 1)[1]
	local item = top and top.item or nil
	cache[self] = {item = item, until_time = now + NEED_SECONDS}
	return item
end

-- The adult villager the player looks at within RANGE, or nil.
function M.looked_at(player)
	local pos = player:get_pos()
	if not pos then return nil end
	local properties = player.get_properties and player:get_properties()
	local eye = vector.add(pos, {x = 0, y = properties and properties.eye_height or DEFAULT_EYE, z = 0})
	local look = player:get_look_dir()
	local ray = core.raycast(eye, vector.add(eye, vector.multiply(look, RANGE)), true, false)
	for pointed in ray do
		if pointed.type == "node" then return nil end
		if pointed.type == "object" and pointed.ref ~= player then
			local entity = pointed.ref:get_luaentity()
			if entity and entity.name == VILLAGER and not entity.child and entity._id then return entity end
			return nil
		end
	end
	return nil
end

-- Shows the bubble to one player, if it looks at a villager with a need. Returns the item.
function M.show(player, now)
	local villager = M.looked_at(player)
	if not villager then return nil end
	local item = M.need(villager, now)
	local texture = item and M.texture(item)
	local at = texture and villager.object:get_pos()
	if not at then return nil end
	core.add_particle({
		pos = {x = at.x, y = at.y + ABOVE, z = at.z},
		velocity = {x = 0, y = 0, z = 0},
		expirationtime = INTERVAL + 0.1,
		size = SIZE,
		texture = texture,
		playername = player:get_player_name(),
		glow = 10,
	})
	return item
end

function M.install()
	if not clock.enabled() or not core.register_globalstep then return end
	local timer = 0
	core.register_globalstep(function(dtime)
		timer = timer + dtime
		if timer < INTERVAL then return end
		timer = 0
		local now = core.get_gametime()
		for _, player in ipairs(core.get_connected_players()) do M.show(player, now) end
	end)
end

return M
