-- The latest deaths, for the pulpit's parish register (ticket 48b). init.lua's on_die notes
-- each adult villager's death here: where, the day, its trade and how it died. It does not
-- wait for a cleric or a pulpit to be loaded, so a death seen by no one is still known.
-- The pulpit shows the latest within its radius (`latest`), only that one.
--
-- The list is kept in mod storage (KEY), newest last, at most KEEP. How it died is put in
-- words when it dies, from mcl_mobs' cmi_cause (`cause`): a punch names its mob or player,
-- `environment` names the node it stood in, which tells drowning from suffocation and fire.
local core = minetest

local KEY = "parish_deaths"
local KEEP = 32
local storage = core.get_mod_storage and core.get_mod_storage()

local M = {KEY = KEY, KEEP = KEEP}

local function short_name(name)
	return (tostring(name):gsub("^.*:", ""):gsub("_", " "))
end

-- How it died, in words, from mcl_mobs' cmi_cause. `starving`: it was when it died.
function M.cause(cmi_cause, starving)
	local kind = cmi_cause and cmi_cause.type
	local node = cmi_cause and type(cmi_cause.node) == "string" and cmi_cause.node or nil
	local text
	if kind == "punch" then
		local puncher = cmi_cause.puncher
		local entity = puncher and puncher.get_luaentity and puncher:get_luaentity()
		if puncher and puncher.is_player and puncher:is_player() then
			text = "was killed by " .. puncher:get_player_name()
		elseif entity and entity.name then
			text = "was killed by a " .. short_name(entity.name)
		else
			text = "was killed"
		end
	elseif kind == "fall" then
		text = "died in a fall"
	elseif kind == "fire" or kind == "light" then
		text = "burned to death"
	elseif kind == "environment" and node then
		if node:find("water") then
			text = "drowned"
		elseif node:find("lava") or node:find("fire") then
			text = "burned to death"
		elseif node:find("cactus") then
			text = "died on a cactus"
		else
			text = "suffocated in " .. short_name(node)
		end
	elseif kind == "cactus" then
		text = "died on a cactus"
	elseif starving then
		return "starved"
	else
		text = "died"
	end
	return starving and (text .. ", starving") or text
end

local function load()
	return storage and core.deserialize(storage:get_string(KEY)) or {}
end

-- Notes a death: {pos, day, id, trade, cause}.
function M.note(entry)
	if not storage or not entry.pos then return end
	local list = load()
	list[#list + 1] = {
		pos = {x = math.floor(entry.pos.x + 0.5), y = math.floor(entry.pos.y + 0.5), z = math.floor(entry.pos.z + 0.5)},
		day = entry.day, id = entry.id, trade = entry.trade, cause = entry.cause,
	}
	while #list > KEEP do table.remove(list, 1) end
	storage:set_string(KEY, core.serialize(list))
end

-- The latest death within radius of pos, or nil.
function M.latest(pos, radius)
	local list = load()
	for i = #list, 1, -1 do
		local entry = list[i]
		local dx, dy, dz = entry.pos.x - pos.x, entry.pos.y - pos.y, entry.pos.z - pos.z
		if dx * dx + dy * dy + dz * dz <= radius * radius then return entry end
	end
	return nil
end

return M
