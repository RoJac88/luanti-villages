-- A picture of a building, for the bench's window: a PNG or JPEG next to its schematic with the
-- same name. Clients only have the media a server sends, so a picture goes to the player looking
-- at it, under a name made from its content, and an edited file is simply a new picture. The
-- window names it only once that client has it, as a texture named too soon shows as a broken
-- one. Until then, or if it never arrives, the window has its list of materials to show.
--
-- The engine accepts any bytes as media, so a file is looked at first.
local core = minetest

local M = {}

M.MAX_BYTES = 2 * 1024 * 1024
local PNG_MAGIC = "\137PNG\r\n\26\n"

local function u16(content, at)
	return content:byte(at) * 256 + content:byte(at + 1)
end

local function u32(content, at)
	return u16(content, at) * 65536 + u16(content, at + 2)
end

-- A JPEG's size is in its start-of-frame segment, past however many others.
local function jpeg_size(content)
	local at = 3
	while at + 8 <= #content do
		if content:byte(at) ~= 0xFF then return nil end
		local marker = content:byte(at + 1)
		-- Start-of-frame markers, less the three that are not (DHT, JPG, DAC).
		if marker >= 0xC0 and marker <= 0xCF and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC then
			return u16(content, at + 7), u16(content, at + 5)
		end
		at = at + 2 + u16(content, at + 2)
	end
	return nil
end

-- "png" or "jpg" with a picture's width and height, or nil for what is not one.
function M.identify(content)
	local kind, width, height
	if content:sub(1, 8) == PNG_MAGIC and #content >= 24 then
		kind, width, height = "png", u32(content, 17), u32(content, 21)
	elseif content:sub(1, 2) == "\255\216" then
		kind = "jpg"
		width, height = jpeg_size(content)
	end
	if not (kind and width and height and width > 0 and height > 0) then return nil end
	return kind, width, height
end

-- player name -> media name -> "sending" or "arrived"
local sent = {}

-- The picture at `path` for a player: {texture, width, height} once the client has it, else nil.
-- `on_arrival` is called when it does, for the window to be shown again.
function M.request(player, path, on_arrival, engine)
	engine = engine or core
	local file = io.open(path, "rb")
	if not file then return nil end
	local bytes = file:seek("end")
	if bytes > M.MAX_BYTES then
		file:close()
		return nil
	end
	file:seek("set", 0)
	local content = file:read("*a")
	file:close()
	local kind, width, height = M.identify(content)
	if not kind then return nil end

	local media = "living_villages_preview_" .. engine.sha1(content) .. "." .. kind
	local states = sent[player] or {}
	sent[player] = states
	if states[media] == "arrived" then return {texture = media, width = width, height = height} end
	if states[media] == "sending" then return nil end
	states[media] = "sending"
	local accepted = engine.dynamic_add_media({filepath = path, filename = media, to_player = player}, function()
		states[media] = "arrived"
		on_arrival()
	end)
	if not accepted then states[media] = nil end
	return nil
end

-- A client forgets what it was sent when it leaves.
function M.forget(player)
	sent[player] = nil
end

-- A picture's size to fit a box, keeping its shape.
function M.fit(width, height, box_width, box_height)
	local scale = math.min(box_width / width, box_height / height)
	return width * scale, height * scale
end

return M
