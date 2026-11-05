-- Run with: lua tests/builder_preview.lua
-- Telling a picture from what is not one, and when a client has it.
minetest = {get_modpath = function() return "." end}
local preview = dofile("builder_preview.lua")

local function bytes(...) return string.char(...) end
local function png(width, height)
	return "\137PNG\r\n\26\n\0\0\0\13IHDR"
		.. bytes(0, math.floor(width / 65536) % 256, math.floor(width / 256) % 256, width % 256)
		.. bytes(0, math.floor(height / 65536) % 256, math.floor(height / 256) % 256, height % 256)
end
-- SOI, an APP0 segment of `padding` bytes, then a frame header of the given marker.
local function jpeg(width, height, marker, padding)
	local length = padding + 2
	return "\255\216\255\224" .. bytes(math.floor(length / 256), length % 256) .. string.rep("x", padding)
		.. bytes(0xFF, marker, 0, 17, 8)
		.. bytes(math.floor(height / 256), height % 256, math.floor(width / 256), width % 256) .. "more"
end

-- Sizes read from each format, past a JPEG's other segments.
do
	local kind, width, height = preview.identify(png(1920, 1080))
	assert(kind == "png" and width == 1920 and height == 1080)
	kind, width, height = preview.identify(jpeg(640, 480, 0xC0, 16))
	assert(kind == "jpg" and width == 640 and height == 480)
	kind, width, height = preview.identify(jpeg(800, 600, 0xC2, 300))
	assert(kind == "jpg" and width == 800 and height == 600, "progressive")
	-- A Huffman table has a marker in the same range, and no size.
	assert(preview.identify(jpeg(1, 1, 0xC4, 16)) == nil)
end

-- What is not a picture, or claims to be of nothing.
for _, junk in ipairs({
	"", "text", "\137PNG\r\n\26\n", png(1, 1):sub(1, 20), png(0, 10), png(10, 0),
	"\255\216", "\255\216\255", jpeg(0, 10, 0xC0, 4), "\255\216nonsense and more of it",
}) do
	assert(preview.identify(junk) == nil, junk)
end

-- Fitting keeps the shape, both ways.
do
	local w, h = preview.fit(400, 200, 5, 2.7)
	assert(w == 5 and h == 2.5)
	w, h = preview.fit(100, 300, 5, 3)
	assert(w == 1 and h == 3)
end

-- A file over the limit is not read, nor sent.
do
	local real_open, sent = io.open, 0
	io.open = function()
		return {seek = function(_, whence) return whence == "end" and preview.MAX_BYTES + 1 or 0 end, close = function() end}
	end
	local engine = {dynamic_add_media = function() sent = sent + 1 return true end, sha1 = function() return "h" end}
	assert(preview.request("ann", "/x.png", function() end, engine) == nil and sent == 0)
	-- A file that has gone.
	io.open = function() return nil end
	assert(preview.request("ann", "/x.png", function() end, engine) == nil and sent == 0)
	-- Refused by the engine: tried again next time.
	local content = png(2, 2)
	io.open = function()
		return {
			seek = function(_, whence) return whence == "end" and #content or 0 end,
			read = function() return content end,
			close = function() end,
		}
	end
	engine.dynamic_add_media = function() sent = sent + 1 return false end
	preview.request("ann", "/x.png", function() end, engine)
	preview.request("ann", "/x.png", function() end, engine)
	assert(sent == 2)
	io.open = real_open
end

print("builder_preview: ok")
