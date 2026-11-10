-- Goods that wear out (docs/villager-economy-design.md, ticket 11d): goods that do a
-- villager good for a while and then are used up. Data as recipes.lua is, and the few
-- functions that read it; it touches no engine state but what it is handed.
--
-- Each good names its item, who wants it (a profession, or the labour activity of a
-- villager still labouring: labour.lua's `_villages_labour`), what wears it (`use`: one harvest,
-- felling or cobble mined is one use), how many uses it lasts and its rate: how much
-- faster that work goes with it. Every effect is a bonus over the rates without it.
--
-- A good in use is held in `_villages_wants` ({[key] = {item, left}}), apart from its
-- belongings; a worn-out one is gone. The ledger (possessions.assess) wants one when
-- none is in use or the one in use is nearly worn (NEARLY_WORN of its uses left), and
-- values it at most at what it brings over its life (`worth`): its uses, times the
-- goods one use yields at their price, times the rate's gain. Market news posts the
-- need, and conversations and trade trips buy it as any other.
local core = minetest
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")

local M = {}

M.GOODS = {
	{key = "hoe", item = "mcl_farming:hoe_stone", professions = {farmer = true}, use = "harvest",
		uses = 64, rate = 1.5, yields = {["mcl_farming:wheat_item"] = 1}},
	{key = "axe", item = "mcl_tools:axe_stone", activities = {woodcutter = true}, use = "fell",
		uses = 32, rate = 1.5, yields = {["mcl_core:tree"] = 5}},
	{key = "pickaxe", item = "mcl_tools:pick_stone", activities = {quarrier = true}, use = "mine",
		uses = 64, rate = 1.5, yields = {["mcl_core:cobble"] = 1}},
}
-- Of its uses, this share left and it wants the next one.
M.NEARLY_WORN = 1 / 8
-- Uses between the lines that log how fast the work goes.
M.LOG_EVERY = 16
-- A gap between two uses up to this long is work going on; a longer one is walking,
-- waiting for a crop or another stage, which the pace leaves out (run 48: 16 harvests
-- took 111 s one time and 2053 s the next, by hand).
M.BURST_GAP = 5

local function wanted_by(self, good)
	if self.child or not self._id then return false end
	if good.professions and good.professions[self._profession] then return true end
	-- A labour activity counts only while it labours: one that took a job that day still
	-- carries the morning's `_villages_labour` (run 45, a tool smith wanting an axe).
	local labours = self._profession == "nitwit" or (self._profession == "unemployed" and not self._jobsite)
	local labour = self._villages_labour
	return labours and good.activities ~= nil and labour ~= nil and good.activities[labour.activity] == true
end

-- The goods this villager wants, in M.GOODS order.
function M.goods(self)
	local list = {}
	for _, good in ipairs(M.GOODS) do
		if wanted_by(self, good) then table.insert(list, good) end
	end
	return list
end

function M.in_use(self, good)
	local held = self._villages_wants
	return held and held[good.key] or nil
end

-- What one good brings over its life, in emeralds.
function M.worth(good)
	local per_use = 0
	for item, count in pairs(good.yields) do per_use = per_use + count * (ledger.price(item) or 0) end
	return good.uses * per_use * (good.rate - 1)
end

-- For the ledger: {item = 1} for each good it should get, and {item = worth} for each it wants.
function M.targets(self)
	local targets, worth = {}, {}
	for _, good in ipairs(M.goods(self)) do
		local current = M.in_use(self, good)
		if not current or current.left <= good.uses * M.NEARLY_WORN then targets[good.item] = 1 end
		worth[good.item] = M.worth(good)
	end
	return targets, worth
end

-- Not saved: for the lines that log the pace.
local paces = setmetatable({}, {__mode = "k"})

-- Logs every LOG_EVERY uses: how long they took, and the seconds per use while working
-- (the gaps of at most BURST_GAP between one use and the next), which the rate divides.
local function note_pace(self, good, tool, now)
	local pace = paces[self]
	if not pace then
		pace = {}
		paces[self] = pace
	end
	local entry = pace[good.use]
	if not entry or entry.tool ~= tool then
		entry = {tool = tool, count = 0, since = now, busy = 0, gaps = 0}
		pace[good.use] = entry
	end
	if entry.last and now - entry.last <= M.BURST_GAP then
		entry.busy = entry.busy + (now - entry.last)
		entry.gaps = entry.gaps + 1
	end
	entry.last = now
	entry.count = entry.count + 1
	if entry.count >= M.LOG_EVERY then
		local each = entry.gaps > 0 and string.format("%.2f s each while working", entry.busy / entry.gaps) or "no run of work"
		core.log("action", string.format("[living_villages] villager %s: %d %s in %d s (%s) %s",
			tostring(self._id):sub(1, 6), entry.count, good.use, math.floor(now - entry.since + 0.5), each,
			tool and ("with a " .. tool) or "by hand"))
		pace[good.use] = {tool = tool, count = 0, since = now, busy = 0, gaps = 0, last = now}
	end
end

-- One `use` of work (harvest, fell, mine): wears the good in use, taking a new one from
-- what it holds through take(self, item, count) when it has none. Returns the rate to
-- divide the work's time by: the good's, or 1.
function M.use(self, use, take, now)
	for _, good in ipairs(M.goods(self)) do
		if good.use == use then
			self._villages_wants = self._villages_wants or {}
			local current = self._villages_wants[good.key]
			if not current and take and take(self, good.item, 1) > 0 then
				current = {item = good.item, left = good.uses}
				self._villages_wants[good.key] = current
				core.log("action", string.format("[living_villages] villager %s takes up a %s",
					tostring(self._id):sub(1, 6), good.item))
			end
			if not current then
				note_pace(self, good, nil, now or 0)
				if not next(self._villages_wants) then self._villages_wants = nil end
				return 1
			end
			current.left = current.left - 1
			note_pace(self, good, good.item, now or 0)
			if current.left <= 0 then
				self._villages_wants[good.key] = nil
				if not next(self._villages_wants) then self._villages_wants = nil end
				core.log("action", string.format("[living_villages] villager %s wore out its %s",
					tostring(self._id):sub(1, 6), good.item))
			end
			return good.rate
		end
	end
	return 1
end

-- One line for the inspector.
function M.status(self)
	local parts = {}
	for _, good in ipairs(M.GOODS) do
		local current = M.in_use(self, good)
		if current then table.insert(parts, string.format("%s, %d of %d uses left", current.item, current.left, good.uses)) end
	end
	return #parts > 0 and table.concat(parts, "; ") or "none"
end

return M
