-- The woodcutter (docs/villager-economy-design.md, ticket 16): a villager who claims a
-- chopping block (chopping_block.lua) and cuts wood for the village every work stage.
-- Before it, only a villager with no job cut wood (labour.lua), so the more job blocks a
-- village had, the less wood: the Markets world had one labourer among 16 adults.
--
-- VoxeLibre cannot be given a new profession (keeper.lua says why), so the woodcutter is
-- a role layered on the nitwit, the one vanilla profession with no trades and no
-- workstation of its own:
--
-- - The block is claimed through the node meta `villager`, as vanilla claims a
--   workstation. Vanilla's validate_jobsite checks only that meta, never the node, so
--   vanilla keeps the jobsite; a nitwit is never handed another job by get_a_job.
-- - `_villages_woodcutter` marks the role (saved), recovered on activation for a nitwit
--   whose claimed jobsite is a chopping block. A woodcutter whose block is gone, or no
--   longer names it, goes back to being unemployed, so it looks for work again.
-- - Its work is labour.lua's woodcutter activity, every day, with no choice: a grove
--   around the block (not its bed), felled and replanted, logs past what it keeps burned
--   to charcoal, logs sold as planks when a villager asks (goods.lua). Its grove holds up
--   to labour.lua's GROVE_MAX_JOB trees.
-- - Through the work stage get_activity answers "chop" for it (common.activity_override),
--   so vanilla does not call it back to the block between trees.
--
-- job_blocks.lua hands blocks out like any other: village_staffing.lua when a village is
-- placed, job_seek.lua to a villager out of work. With the economy off the block is
-- still claimed but no wood is cut, as labour.lua does nothing then.
local core = minetest

local BLOCK = "living_villages:chopping_block"
local PROFESSION = "nitwit"
local FLAG = "_villages_woodcutter"

local M = {BLOCK = BLOCK, PROFESSION = PROFESSION, FLAG = FLAG}

local function pos_string(pos)
	if not pos then return "?" end
	return string.format("(%d,%d,%d)", pos.x, pos.y, pos.z)
end

local function is_block(pos)
	local node = pos and core.get_node_or_nil(pos)
	return node ~= nil and node.name == BLOCK
end

-- Its chopping block, if it holds one: the jobsite, a chopping block naming it.
function M.claimed_block(self)
	local pos = self._jobsite
	return is_block(pos) and core.get_meta(pos):get_string("villager") == self._id and pos or nil
end

-- Whether it works as a woodcutter now.
function M.is_woodcutter(self)
	return self[FLAG] == true and not self.child and self._profession == PROFESSION and M.claimed_block(self) ~= nil
end

-- Who may take one: an adult out of work, as for any job block (job_blocks.eligible).
local function eligible(self)
	return not self.child and self._id ~= nil and not self._jobsite and self._profession == "unemployed"
		and not self._villages_left_unemployed
end

-- Claims the chopping block at pos. Returns whether it did.
function M.employ(self, pos)
	if not is_block(pos) or core.get_meta(pos):get_string("villager") ~= "" or not eligible(self) then return false end
	core.get_meta(pos):set_string("villager", self._id)
	self._jobsite = {x = pos.x, y = pos.y, z = pos.z}
	self._profession = PROFESSION
	self[FLAG] = true
	-- Whatever it did as a labourer is over; what it carries stays its own.
	self._villages_labour, self._villages_peddle, self._villages_farm_seek = nil, nil, nil
	core.log("action", string.format("[living_villages] villager %s became woodcutter at the chopping block at %s",
		tostring(self._id), pos_string(pos)))
	return true
end

-- Its block gone or taken: unemployed again, to look for work.
function M.release(self)
	self[FLAG] = nil
	if self._profession == PROFESSION then
		self._profession = "unemployed"
		self._jobsite = nil
	end
	core.log("action", string.format("[living_villages] villager %s is no longer a woodcutter", tostring(self._id)))
end

-- Through the work stage, out at its grove, not called back to the block.
function M.activity_override(villager, stage)
	if stage == "work" and villager[FLAG] then return "chop" end
	return nil
end

function M.install(def)
	local original_activate = def.on_activate
	local original_custom = def.do_custom
	def.on_activate = function(self, staticdata, dtime)
		local result = original_activate(self, staticdata, dtime)
		if not self.child and self._profession == PROFESSION and self._id and M.claimed_block(self) then
			self[FLAG] = true
		end
		return result
	end
	def.do_custom = function(self, dtime)
		local result = original_custom(self, dtime)
		if self[FLAG] and not M.is_woodcutter(self) then M.release(self) end
		return result
	end
end

-- One line for the inspector.
function M.status(self)
	if not self[FLAG] then return "not a woodcutter" end
	local block = M.claimed_block(self)
	return block and string.format("woodcutter at the chopping block at %s, grove of %d", pos_string(block),
		#(self._villages_grove or {})) or "woodcutter with no block"
end

return M
