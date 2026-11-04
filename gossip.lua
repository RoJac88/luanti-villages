-- Villagers gossip about players, as in Java Minecraft: each villager keeps its own
-- memory of each player, there is no village-wide score, and news travels only when
-- villagers finish a conversation (conversation.lua). Two villagers can rightly
-- disagree about the same player. A villager's reputation for a player moves the
-- first ingredient of its trades for that player and, at REPUTATION_HOSTILE, turns
-- iron golems on the player. There is no refusal to trade; Java has none either.
--
-- The numbers are Java's (minecraft.wiki, Villager and Trading). Java's demand and
-- Hero of the Village price terms are left out, since neither exists here, and its
-- per-trade price multiplier is approximated by whether the offered item stacks,
-- since VoxeLibre's trade tables have none.
--
-- Decay is worked out when the memory is next read, from the game time, so it costs
-- nothing per tick. Unlike Java it counts time the villager was unloaded: a villager
-- with no player within 48 nodes is suspended, so grudges would otherwise hardly fade.
--
-- Prices go in the player's detached "wanted" list, which is what vanilla charges and
-- draws from, never in _trades: other players see their own prices, and the fisherman's
-- restock (fisherman.lua) and market sellers still read the real trades.
local core = minetest

local TYPES = {
	trading = {gain = 4, decay = 2, cost = 20, max = 25, multiplier = 1},
	major_positive = {gain = 20, decay = 0, cost = 100, max = 20, multiplier = 5},
	minor_positive = {gain = 25, decay = 1, cost = 5, max = 25, multiplier = 1},
	minor_negative = {gain = 25, decay = 20, cost = 20, max = 200, multiplier = -1},
	major_negative = {gain = 25, decay = 10, cost = 10, max = 100, multiplier = -5},
}
local TYPE_ORDER = {"major_positive", "minor_positive", "trading", "minor_negative", "major_negative"}
-- Seconds of game time per decay step.
local DECAY_SECONDS = 1200
-- At most this many entries pass from one villager to another in one conversation.
local SHARE_ENTRIES = 10
local WITNESS_RADIUS = 16
local EYE = 1.5
local PRICE_MULTIPLIER = 0.05
local PRICE_MULTIPLIER_SINGLE = 0.2
local REPUTATION_HOSTILE = -100
-- A golem asks villagers in this box about it, and players it can see, this often.
local GOLEM_SCAN_SECONDS = 5
local GOLEM_BOX_XZ, GOLEM_BOX_Y = 10, 8
-- Enough to reach the corners of the box.
local GOLEM_SCAN_RADIUS = 17
local VILLAGER = "mobs_mc:villager"

local function enabled()
	return not core.settings or core.settings:get_bool("living_villages_gossip", true)
end

local function short_id(self)
	return tostring(self._id):sub(1, 6)
end

-- This villager's memory, decayed up to now, or nil if it remembers nothing.
local function memory(self)
	local remembered = self._villages_gossip
	if not remembered then return nil end
	local now = core.get_gametime()
	local last = self._villages_gossip_decayed or now
	local steps = math.floor((now - last) / DECAY_SECONDS)
	if steps >= 1 then
		self._villages_gossip_decayed = last + steps * DECAY_SECONDS
		for subject, entries in pairs(remembered) do
			for kind, value in pairs(entries) do
				local left = value - TYPES[kind].decay * steps
				entries[kind] = left > 0 and left or nil
			end
			if not next(entries) then remembered[subject] = nil end
		end
	else
		self._villages_gossip_decayed = last
	end
	if not next(remembered) then
		self._villages_gossip, self._villages_gossip_decayed = nil, nil
		return nil
	end
	return remembered
end

local function entries_for(self, subject)
	local remembered = memory(self)
	if not remembered then
		remembered = {}
		self._villages_gossip, self._villages_gossip_decayed = remembered, core.get_gametime()
	end
	remembered[subject] = remembered[subject] or {}
	return remembered[subject]
end

-- What self saw for itself: adds up to the type's maximum.
local function add(self, subject, kind)
	if not enabled() then return end
	local entries = entries_for(self, subject)
	local info = TYPES[kind]
	entries[kind] = math.min((entries[kind] or 0) + info.gain, info.max)
	core.log("action", string.format("[living_villages] gossip: villager %s noted %s %s (now %d)",
		short_id(self), subject, kind, entries[kind]))
end

local function reputation(self, subject)
	local remembered = memory(self)
	local entries = remembered and remembered[subject]
	if not entries then return 0 end
	local total = 0
	for kind, value in pairs(entries) do total = total + value * TYPES[kind].multiplier end
	return total
end

-- What from can pass on: entries still worth something after the sharing cost.
local function shareable(from)
	local list, total = {}, 0
	for subject, entries in pairs(memory(from) or {}) do
		for kind, value in pairs(entries) do
			local info = TYPES[kind]
			if value > info.cost then
				local weight = value * math.abs(info.multiplier)
				list[#list + 1] = {subject = subject, kind = kind, value = value - info.cost, weight = weight}
				total = total + weight
			end
		end
	end
	return list, total
end

-- from tells to up to SHARE_ENTRIES things, the strongest likeliest. Hearsay does not
-- pile up: to keeps the larger of what it had and what it heard, and what it heard
-- cost something, so it can never come back larger than it went out. Returns how many.
local function share(from, to)
	local list, total = shareable(from)
	local told = 0
	while #list > 0 and told < SHARE_ENTRIES do
		local roll, chosen = math.random() * total, #list
		for i, candidate in ipairs(list) do
			roll = roll - candidate.weight
			if roll <= 0 then chosen = i break end
		end
		local entry = table.remove(list, chosen)
		total = total - entry.weight
		local entries = entries_for(to, entry.subject)
		entries[entry.kind] = math.max(entries[entry.kind] or 0, math.min(entry.value, TYPES[entry.kind].max))
		told = told + 1
	end
	return told
end

-- Everyone in a finished conversation tells everyone else, both ways.
local function exchange(members)
	if not enabled() then return end
	local told = 0
	for _, from in ipairs(members) do
		for _, to in ipairs(members) do
			if from ~= to then told = told + share(from, to) end
		end
	end
	if told > 0 then
		local ids = {}
		for _, member in ipairs(members) do ids[#ids + 1] = short_id(member) end
		core.log("action", string.format("[living_villages] gossip: villagers %s shared %d entries",
			table.concat(ids, " "), told))
	end
end

-- Java's price with demand and hero left out. r is negative for a disliked player, whose
-- price rises; floor makes even -1 cost one more, as in Java.
local function price(base, r, multiplier, stack_max)
	return math.min(math.max(base - math.floor(multiplier * r), 1), stack_max)
end

local function price_multiplier(offered)
	return offered:get_stack_max() == 1 and PRICE_MULTIPLIER_SINGLE or PRICE_MULTIPLIER
end

local function status(self)
	local remembered = memory(self)
	if not remembered then return "knows of nobody" end
	local names = {}
	for name in pairs(remembered) do names[#names + 1] = name end
	table.sort(names)
	local parts = {}
	for _, name in ipairs(names) do
		local kinds = {}
		for _, kind in ipairs(TYPE_ORDER) do
			local value = remembered[name][kind]
			if value then kinds[#kinds + 1] = kind .. " " .. value end
		end
		parts[#parts + 1] = string.format("%s %d (%s)", name, reputation(self, name), table.concat(kinds, ", "))
	end
	return table.concat(parts, "; ")
end

-- The player answerable for a hit: the puncher or the owner of its projectile, whose
-- _owner is the player's name (vl_projectile, via mcl_util.get_entity_id). Mobs and
-- the environment answer to nobody.
local function responsible_player(puncher)
	if not puncher then return nil end
	if puncher.is_player and puncher:is_player() then return puncher:get_player_name() end
	local entity = puncher.get_luaentity and puncher:get_luaentity()
	local owner = entity and entity._owner
	if type(owner) == "string" and core.get_player_by_name(owner) then return owner end
	return nil
end

local function sees(a, b)
	if not core.line_of_sight then return true end
	return core.line_of_sight({x = a.x, y = a.y + EYE, z = a.z}, {x = b.x, y = b.y + EYE, z = b.z}) ~= false
end

local function tell_witnesses(self, pos, killer)
	for _, object in ipairs(core.get_objects_inside_radius(pos, WITNESS_RADIUS)) do
		local other = object:get_luaentity()
		local other_pos = other and other ~= self and other.name == VILLAGER and object:get_pos()
		if other_pos and sees(pos, other_pos) then add(other, killer, "major_negative") end
	end
end

-- Reprice the trade vanilla just put in the player's wanted list, and draw that price.
-- The list is changed only once the drawing is sure to change with it, so what the
-- window shows and what it charges cannot disagree if VoxeLibre's formspec moves.
local function priced_form(trader, player_name, formname, formspec)
	local inv = core.get_inventory({type = "detached", name = formname})
	local base = inv and inv:get_stack("wanted", 1)
	if not base or base:is_empty() then return formspec end
	local count = price(base:get_count(), reputation(trader, player_name),
		price_multiplier(inv:get_stack("offered", 1)), base:get_stack_max())
	if count == base:get_count() then return formspec end
	local priced = ItemStack(base)
	priced:set_count(count)
	local first, last = formspec:find("item_image[2,1;1,1;" .. base:to_string() .. "]", 1, true)
	if not first then
		core.log("warning", "[living_villages] gossip: the trade window has changed, prices stay as they are")
		return formspec
	end
	inv:set_stack("wanted", 1, priced)
	-- Paging judges items already in the input slots before the show, at the base price.
	local callbacks = core.detached_inventories and core.detached_inventories[formname]
	if callbacks and callbacks.on_put and not inv:is_empty("input") then
		callbacks.on_put(inv, "input", 1, ItemStack(""), core.get_player_by_name(player_name))
	end
	return formspec:sub(1, first - 1) .. "item_image[2,1;1,1;" .. priced:to_string() .. "]" .. formspec:sub(last + 1)
end

local function install_prices(def)
	local sessions, taking = {}, {}
	local original_rightclick = def.on_rightclick
	def.on_rightclick = function(self, clicker)
		local name = clicker and clicker.is_player and clicker:is_player() and clicker:get_player_name()
		if name then sessions[name] = self end
		return original_rightclick(self, clicker)
	end

	-- Vanilla shows the window after it sets a trade (opening, paging) and, with the list
	-- already priced, after a tier-up or lock in on_take, which must not be priced twice.
	local original_show = core.show_formspec
	core.show_formspec = function(player_name, formname, formspec)
		local trader = sessions[player_name]
		if trader and not taking[player_name] and formname == "mobs_mc:trade_" .. player_name and enabled() then
			formspec = priced_form(trader, player_name, formname, formspec)
		end
		return original_show(player_name, formname, formspec)
	end

	-- Vanilla's own join callback makes the inventory and is registered first. It keeps
	-- the inventory across a rejoin, so wrap it once.
	local function wrap_inventory(name)
		local callbacks = core.detached_inventories and core.detached_inventories["mobs_mc:trade_" .. name]
		if not callbacks or callbacks._villages_gossip then return end
		callbacks._villages_gossip = true
		local original_take = callbacks.on_take
		callbacks.on_take = function(inv, listname, index, stack, player)
			taking[name] = true
			local result = original_take(inv, listname, index, stack, player)
			taking[name] = nil
			local trader = sessions[name]
			if listname == "output" and trader then add(trader, name, "trading") end
			return result
		end
	end
	if core.register_on_joinplayer then
		core.register_on_joinplayer(function(player) wrap_inventory(player:get_player_name()) end)
	end
	if core.register_on_leaveplayer then
		core.register_on_leaveplayer(function(player) sessions[player:get_player_name()] = nil end)
	end
end

-- Whether a villager in the golem's box thinks this badly of the player.
local function hated(golem_pos, nearby, name)
	for _, object in ipairs(nearby) do
		local other = object:get_luaentity()
		local pos = other and other.name == VILLAGER and object:get_pos()
		if pos and math.abs(pos.x - golem_pos.x) <= GOLEM_BOX_XZ and math.abs(pos.z - golem_pos.z) <= GOLEM_BOX_XZ
			and math.abs(pos.y - golem_pos.y) <= GOLEM_BOX_Y and reputation(other, name) <= REPUTATION_HOSTILE then
			return true
		end
	end
	return false
end

local function hated_player(self, pos)
	local nearby = core.get_objects_inside_radius(pos, GOLEM_SCAN_RADIUS)
	local range = self.view_range or GOLEM_SCAN_RADIUS
	for _, object in ipairs(nearby) do
		if object.is_player and object:is_player() and vector.distance(pos, object:get_pos()) <= range then
			local name = object:get_player_name()
			local invisible = mcl_mobs and mcl_mobs.invis and mcl_mobs.invis[name]
			if not invisible and not core.is_creative_enabled(name) and hated(pos, nearby, name) then
				return object
			end
		end
	end
	return nil
end

-- Java spares golems players built. Only the pumpkin check makes those, with add_entity,
-- which activates the entity before it returns. Golems already built count as the village's.
local function install_golem(golem_def)
	local building = false
	local original_summon = mobs_mc and mobs_mc.check_iron_golem_summon
	if original_summon then
		mobs_mc.check_iron_golem_summon = function(...)
			building = true
			local result = original_summon(...)
			building = false
			return result
		end
	end
	local original_activate = golem_def.on_activate
	golem_def.on_activate = function(self, staticdata, dtime)
		local result = original_activate(self, staticdata, dtime)
		if building then self._villages_player_built = true end
		return result
	end
	local original_custom = golem_def.do_custom
	golem_def.do_custom = function(self, dtime)
		local result = original_custom and original_custom(self, dtime)
		self._villages_gossip_scan = (self._villages_gossip_scan or math.random() * GOLEM_SCAN_SECONDS) - dtime
		if self._villages_gossip_scan > 0 then return result end
		self._villages_gossip_scan = GOLEM_SCAN_SECONDS
		if self._villages_player_built or self.state == "attack" or not enabled() then return result end
		local pos = self.object:get_pos()
		local target = pos and hated_player(self, pos)
		if target then
			core.log("action", string.format("[living_villages] gossip: a golem turns on %s", target:get_player_name()))
			-- As vanilla's alert to a punched villager does: gives up once the player is gone.
			self._aggro = true
			self:do_attack(target)
		end
		return result
	end
end

-- The cure makes the new villager with add_entity inside the zombie's do_custom, and
-- records nobody; note who fed the apple and credit the villager activated meanwhile.
local function install_cure(def, zombie_def)
	local curing_by
	local original_rightclick = zombie_def.on_rightclick
	zombie_def.on_rightclick = function(self, clicker)
		local was_curing = self._curing
		local result = original_rightclick(self, clicker)
		if self._curing and not was_curing and clicker and clicker.is_player and clicker:is_player() then
			self._villages_curer = clicker:get_player_name()
		end
		return result
	end
	local original_custom = zombie_def.do_custom
	zombie_def.do_custom = function(self, dtime)
		curing_by = self._villages_curer
		local result = original_custom(self, dtime)
		curing_by = nil
		return result
	end
	local original_activate = def.on_activate
	def.on_activate = function(self, staticdata, dtime)
		local result = original_activate(self, staticdata, dtime)
		if curing_by then
			add(self, curing_by, "major_positive")
			add(self, curing_by, "minor_positive")
		end
		return result
	end
end

local function install(def, golem_def, zombie_def)
	local original_punch = def.on_punch or (mcl_mobs and mcl_mobs.mob_class and mcl_mobs.mob_class.on_punch)
	if original_punch then
		def.on_punch = function(self, hitter, ...)
			local health = self.health
			local result = original_punch(self, hitter, ...)
			-- Vanilla refuses a hit inside the invulnerability window, out of reach or protected.
			if self.health and health and self.health < health then
				local name = responsible_player(hitter)
				if name then add(self, name, "minor_negative") end
			end
			return result
		end
	end

	local original_die = def.on_die
	def.on_die = function(self, pos, cmi_cause)
		local killer = cmi_cause and responsible_player(cmi_cause.puncher)
		local at = pos or self.object:get_pos()
		if killer and at and enabled() then tell_witnesses(self, at, killer) end
		if original_die then return original_die(self, pos, cmi_cause) end
	end

	install_prices(def)
	if golem_def then install_golem(golem_def) end
	if zombie_def then install_cure(def, zombie_def) end
end

return {
	install = install,
	add = add,
	reputation = reputation,
	share = share,
	exchange = exchange,
	price = price,
	status = status,
	-- Exposed for tests.
	TYPES = TYPES,
	DECAY_SECONDS = DECAY_SECONDS,
	SHARE_ENTRIES = SHARE_ENTRIES,
	WITNESS_RADIUS = WITNESS_RADIUS,
	REPUTATION_HOSTILE = REPUTATION_HOSTILE,
	GOLEM_SCAN_SECONDS = GOLEM_SCAN_SECONDS,
}
