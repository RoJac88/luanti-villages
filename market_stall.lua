-- The market's economy (docs/villager-economy-design.md, ticket 12): what a seller puts
-- on its stall, the banner it flies, and the browsers that buy. market.lua calls it once
-- init.lua hands it over (market.use_economy), only with the economy on; with it off a
-- stall shows market.lua's fixed goods and nothing is sold.
--
-- Goods. A seller's stall shows its top STALL_ITEMS spare goods (its ledger's surplus,
-- possessions.assess), by value, of those it carries: what it really has to sell. A
-- villager with nothing spare falls back to market.lua's fixed pair for its profession,
-- or, with none (a nitwit), stays a browser. A peddler (labour.lua) sells its stock here.
--
-- Banners. Opening a stall flies a banner (the cartographer's, recipes.lua): one taken
-- from the seller's belongings lasts BANNER_MARKETS market days (`_villages_banner_left`).
-- A villager that kept a stall in the last BANNER_DAYS days and has no banner flying
-- wants one (M.wants, read by possessions.assess), worth no more than its price, so
-- buying one is no urgent matter. A stall opens without a banner too.
--
-- Browsers. While the stall is open, every SERVE_SECONDS the seller offers its stall
-- goods to the adult villagers within SERVE_RADIUS: exchange.lua's end-of-conversation
-- trade for those items alone (exchange.offer's `only`), each browser once a stall day.
local core = minetest
local possessions = dofile(core.get_modpath("living_villages") .. "/possessions.lua")
local ledger = dofile(core.get_modpath("living_villages") .. "/ledger.lua")
local exchange = dofile(core.get_modpath("living_villages") .. "/exchange.lua")

local STALL_ITEMS = 2
local BANNER = "mcl_banners:banner_item_white"
local BANNER_MARKETS = 4
local BANNER_DAYS = 3
local SERVE_SECONDS = 5
local SERVE_RADIUS = 6
local VILLAGER = "mobs_mc:villager"

local M = {
	STALL_ITEMS = STALL_ITEMS, BANNER = BANNER, BANNER_MARKETS = BANNER_MARKETS, BANNER_DAYS = BANNER_DAYS,
	SERVE_SECONDS = SERVE_SECONDS, SERVE_RADIUS = SERVE_RADIUS,
}

local function short_id(id)
	return tostring(id):sub(1, 6)
end

-- Its top spare goods that it carries, by value, at most STALL_ITEMS, or nil.
function M.goods(villager)
	local view = possessions.assess(villager)
	local carried = {}
	for item, count in pairs(view.surplus) do
		local spare = math.min(count, possessions.count(villager, item))
		if spare > 0 then carried[item] = spare end
	end
	local list = {}
	for _, top in ipairs(ledger.top(carried, view.value, STALL_ITEMS)) do list[#list + 1] = top.item end
	return #list > 0 and list or nil
end

-- Flies a banner on opening a stall on `day`. Returns whether one flies.
function M.open(villager, day)
	villager._villages_stall_day = day
	local left = villager._villages_banner_left or 0
	if left > 0 then
		villager._villages_banner_left = left - 1 > 0 and left - 1 or nil
		return true
	end
	if possessions.count(villager, BANNER) < 1 then return false end
	possessions.take(villager, BANNER, 1)
	villager._villages_banner_left = BANNER_MARKETS - 1
	core.log("action", string.format("[living_villages] market: villager %s hung a new banner at its stall",
		short_id(villager._id)))
	return true
end

-- What a villager wants for its stall, for possessions.assess: extra, worth.
function M.wants(villager, day)
	local stall_day = villager._villages_stall_day
	if not stall_day or not day or day - stall_day > BANNER_DAYS then return nil end
	if (villager._villages_banner_left or 0) > 0 then return nil end
	return BANNER, 1, ledger.price(BANNER)
end

local next_serve = setmetatable({}, {__mode = "k"})
-- Seller -> {browser id -> day it was served}.
local served = setmetatable({}, {__mode = "k"})

-- Sells the stall's `items` to one browser. Returns the trade made, or nil.
function M.sell(seller, browser, items)
	local seller_view, browser_view = possessions.assess(seller), possessions.assess(browser)
	local best
	local seen = {}
	for _, item in ipairs(items) do
		if not seen[item] then
			seen[item] = true
			local offer = exchange.offer(seller, seller_view, browser, browser_view, item)
			if offer and (not best or offer.gain > best.gain) then best = offer end
		end
	end
	if best and exchange.settle(best) then
		core.log("action", string.format("[living_villages] market: villager %s bought %d %s at %s's stall",
			short_id(browser._id), best.count, best.item, short_id(seller._id)))
		return best
	end
	return nil
end

-- Offers the stall goods to the browsers near, every SERVE_SECONDS. Returns the trades.
function M.serve(seller, items, now, day)
	if not items or now < (next_serve[seller] or 0) then return {} end
	next_serve[seller] = now + SERVE_SECONDS
	local pos = seller.object and seller.object:get_pos()
	if not pos then return {} end
	local list = served[seller] or {}
	served[seller] = list
	local made = {}
	for _, object in ipairs(core.get_objects_inside_radius(pos, SERVE_RADIUS)) do
		local browser = object:get_luaentity()
		if browser and browser ~= seller and browser.name == VILLAGER and browser._id and not browser.child
			and not browser._villages_market_session and list[browser._id] ~= day then
			list[browser._id] = day
			local trade = M.sell(seller, browser, items)
			if trade then made[#made + 1] = trade end
		end
	end
	return made
end

return M
