-- The alchemist (docs/villager-economy-design.md, ticket 20): a villager who claims an
-- alchemist's stand (alchemy_stand.lua) and turns stone and logs, which few buy, into
-- iron, flint, glass and gold, which no village makes. It neither eats nor wants
-- comforts, and works through the hours the others spend at the tavern and the church.
--
-- VoxeLibre cannot be given a new profession (keeper.lua says why), so the alchemist is a
-- role layered on the cleric, whose vanilla jobsite is the brewing stand:
--
-- - The stand is claimed through the node meta `villager`, as vanilla claims a
--   workstation. Vanilla's validate_jobsite checks only that meta, never the node, so
--   vanilla keeps the jobsite and commutes to it like any other.
-- - `_villages_alchemist` marks the role (saved), recovered on activation for a cleric
--   whose claimed jobsite is a stand. An alchemist whose stand is gone, or no longer
--   names it, goes back to being unemployed, so it looks for work again. An unloaded
--   stand is not taken for a gone one.
-- - Every module that treats a cleric specially asks the flag first: its timetables
--   (common.lua), food that never falls (food.lua), no comforts or wants, no donations or
--   alms (alms.lua), its ledger by role (possessions.trade_key), and its robe (init.lua).
--
-- job_blocks.lua hands stands out to a villager out of work (job_seek.lua); a new village
-- is never staffed with one (village_staffing.lua), since none is ever generated.
local core = minetest

local BLOCK = "living_villages:alchemy_stand"
local PROFESSION = "cleric"
local FLAG = "_villages_alchemist"
-- The cleric's robe, recoloured, as keeper.lua recolours the butcher's apron.
local OVERLAY = "(living_villages_villager_profession_cleric.png^[multiply:#4fb3a0)"

local M = {BLOCK = BLOCK, PROFESSION = PROFESSION, FLAG = FLAG, OVERLAY = OVERLAY}

local function pos_string(pos)
	if not pos then return "?" end
	return string.format("(%d,%d,%d)", pos.x, pos.y, pos.z)
end

local function is_block(pos)
	local node = pos and core.get_node_or_nil(pos)
	return node ~= nil and node.name == BLOCK
end

-- Its stand, if it holds one: the jobsite, a stand naming it.
function M.claimed_block(self)
	local pos = self._jobsite
	return is_block(pos) and core.get_meta(pos):get_string("villager") == self._id and pos or nil
end

-- Whether it works as an alchemist now.
function M.is_alchemist(self)
	return self[FLAG] == true and not self.child and self._profession == PROFESSION and M.claimed_block(self) ~= nil
end

-- Whether it has lost its stand: the stand's node is loaded and is no stand naming it, or
-- it no longer has the profession or a jobsite.
local function lost(self)
	if self.child or self._profession ~= PROFESSION or not self._jobsite then return true end
	if not core.get_node_or_nil(self._jobsite) then return false end
	return M.claimed_block(self) == nil
end

-- Who may take one: an adult out of work, as for any job block (job_blocks.eligible).
local function eligible(self)
	return not self.child and self._id ~= nil and not self._jobsite and self._profession == "unemployed"
		and not self._villages_left_unemployed
end

-- Claims the stand at pos. Returns whether it did.
function M.employ(self, pos)
	if not is_block(pos) or core.get_meta(pos):get_string("villager") ~= "" or not eligible(self) then return false end
	core.get_meta(pos):set_string("villager", self._id)
	self._jobsite = {x = pos.x, y = pos.y, z = pos.z}
	self._profession = PROFESSION
	self[FLAG] = true
	-- Whatever it did as a labourer is over; what it carries stays its own. It is fed for good.
	self._villages_labour, self._villages_peddle, self._villages_farm_seek = nil, nil, nil
	self._villages_starving = nil
	core.log("action", string.format("[living_villages] villager %s became alchemist at the stand at %s",
		tostring(self._id), pos_string(pos)))
	return true
end

-- Its stand gone or taken: unemployed again, to look for work.
function M.release(self)
	self[FLAG] = nil
	if self._profession == PROFESSION then
		self._profession = "unemployed"
		self._jobsite = nil
	end
	core.log("action", string.format("[living_villages] villager %s is no longer an alchemist", tostring(self._id)))
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
		if self[FLAG] and lost(self) then M.release(self) end
		return result
	end
end

-- One line for the inspector.
function M.status(self)
	if not self[FLAG] then return "not an alchemist" end
	local block = M.claimed_block(self)
	return block and string.format("alchemist at the stand at %s", pos_string(block)) or "alchemist, stand not loaded"
end

return M
