# Villager economy

Engineering design for the villager economy: villagers with needs, belongings and
the ability to trade with each other, so that a village's economy emerges from
individual villagers rather than from a village-wide script. This document records
the agreed gameplay and divides implementation into small, ordered tickets. The
fork has issues disabled, so the tickets live here (see [Tickets](#tickets)).
Numerical defaults are initial engineering choices to verify in playtesting.

Trade between villages is out of scope, but the design leaves room for it: the
peddler (ticket 12) is the first villager who carries goods from one place to
another.

## Goals

- Every villager has needs (food, its work's inputs, comforts for its savings), belongings
  (a pouch, a home chest, emeralds) and a sense of what things are worth to it.
- Villagers learn what others need and have spare through the gossip they already
  exchange in conversations, and trade with each other when both gain.
- Goods enter the village only through work or from players, and leave it only by
  being eaten, built with or crafted into something else. Trading moves goods and
  never creates them.
- The player has a reason to balance the professions in a village, and can see how
  well it is balanced.
- The VoxeLibre core loop is untouched: explore, gather, craft, build, and trade with
  villagers through the ordinary trade window, at vanilla stock levels.

## Non-goals

- No starvation deaths, departures or collapse. An unbalanced village stagnates.
- No village-wide store, bank or score. As with gossip, each villager knows only
  what it has seen or been told.
- Few new nodes. Every site is an ordinary VoxeLibre node except the mod's own job
  blocks: the pulpit, the builder's bench, the chopping block and the alchemist's
  stand (ticket 20).
- No change to how jobsites are claimed or how traded villagers are locked into
  their profession. The roles (keeper, Builder, alchemist) are the only professions
  added, each over a vanilla one.
- No villager takes from a player's inventory.

## Decisions

| Question | Decision |
|---|---|
| Does a villager's own emerald stock limit player trades? | No. Player trades keep vanilla's unlimited stock; the player is the economy's open edge (its "mint") |
| Do food points fall? | Yes, gradually, by about one loaf a day |
| Can villagers starve to death? | No. Hunger lowers output and stops births, never health below what it is |
| What happens while a villager is unloaded? | Its economic clock pauses: hunger, production and crafting stop together |
| Do players pay for tavern meals? | Yes, a villager's dinner price (18 emeralds, `ledger.DINNER`), and the meal comes out of the pantry |
| Does the farmer still give food away? | Yes to its own household, and one item to a villager at 0 points; everyone else buys |
| Do nitwits take part? | Yes, as gatherers, porters and peddlers, choosing work by what they hear pays |
| Do unemployed villagers do nitwit work? | Yes, while they wait for a jobsite. Vanilla's job claim still comes first |
| Can a village's own supply raise trade tiers? | Yes, alongside vanilla's player-trade progression, not instead of it |

## Player experience

A new village looks as it does today, except that people are carrying things.
Each villager started with a small stock suited to its profession. The farmer
sells bread to its neighbours and the keeper buys crops for the pantry. At dinner,
guests pay for their plates. When the tavern runs dry the guests still sit and
talk, but the plates stay empty, and over the next few days the villagers get
hungry.

A hungry villager works at half pace and charges the player more. Villagers that
are well fed have children; hungry villages stop growing. Nothing dies.

The nitwits and the unemployed are no longer idle. In the morning they pick up work
according to what they have heard is scarce: foraging berries and flowers, cutting
the trees of a grove they planted, working a cobblestone generator a player built,
carrying goods for a fee. When wood gets expensive more of them cut wood; when it
gets cheap they drift to other work.

Each profession needs things other villagers make, and some only players can
supply. A toolsmith with no coal or charcoal, no sticks and no cobble produces
nothing, restocks slowly and stays at a low tier. A village whose woodcutters make
charcoal, whose quarrier makes cobble and whose foragers bring sticks keeps its
smith supplied. That smith restocks reliably, climbs to master tier without the
player trading every tier up, and sells cheaply. A village short of something pays
the player well for it.

The Builder's bench gets an Economy tab: what the village makes and uses, what is
short and what is in glut, and what the idle hands are doing, as heard by the
bench's Builder. The Builder also leans its next project toward the village's worst
gap, which the player can override as today.

## Principles

1. **The player is the open edge.** Inside the village, goods are conserved: made by
   work, used up by eating, building and crafting, moved by trade. Player trades
   keep vanilla's unlimited stock and money, but what a player sells goes into the
   villager's belongings and the emeralds a player pays go to the villager.
2. **One clock, paused when unloaded.** Hunger, production and crafting all run on
   each villager's own economic clock, which advances only while the villager is
   active (see [The economic clock](#the-economic-clock)). Nothing is caught up over
   unloaded time, so a village is never found starving with full fields.
3. **Decentralized.** No village-wide state. Two villagers can disagree about a
   price, and that difference is what trade lives on.
4. **Lazy.** Work is computed from elapsed clock time when a villager acts or is
   looked at, never per tick per item.
5. **Removable.** State is in `_villages_*` entity fields and node metadata; goods
   are real items in real chests; a pouch drops on death (as the farmer's does).
   Removing the mod leaves vanilla villagers and chests full of ordinary items.
6. **Every profession has village demand.** Each profession sells something other
   villagers want, even when players are its bigger market; goods only a player uses
   are fine, a profession only players buy from is not (see
   [Village demand by profession](#village-demand-by-profession)). A villager's want
   for another's goods is a bonus over its plain rate, never a penalty below it, so a
   village that lacks the seller works as it does without the economy.

## The economic clock

`economy_clock.lua`. Each villager keeps `_villages_econ_clock`, seconds of game
time it has been economically active, and `_villages_econ_stamp`, the game time it
last advanced it. Every `STAMP_SECONDS` (10) of game time, while a player is within
mcl_mobs' active range (mcl_mobs runs `do_custom` for a suspended villager too, so the
range is asked), the clock advances by the time since the stamp. A gap of `AWAY_GAP` (120 s) or more since the last stamp (the villager was
unloaded or suspended) is not added. This is `builder_away.lua`'s stamp, used for the
opposite purpose: the Builder pays for the gap, the economy skips it.

Hunger, jobsite crafting, news freshness for a villager's own entries, and nitwit
gathering rates read the economic clock. Gossip decay and news decay for hearsay
keep using game time, since they describe the world rather than the villager's
work. `builder_away.lua` is unchanged: the Builder keeps its own paid catch-up.

Real production loops (the farmer's field, the fisherman's line, the shepherd's
shears) already only run while the villager is active, so they pause with it.

## Hunger

`food.lua` gains a falling rate: `living_villages_hunger_per_day` points per game
day of economic clock (default 4, one loaf). The cap stays 12. Points fall lazily
when read, like gossip decay.

| Points | State | Effect |
|---|---|---|
| 12 | Full | May become a parent (unchanged rule; a birth still spends 12) |
| 4 to 11 | Fed | None |
| 1 to 3 | Hungry | Production and gathering at half rate; prices to players include a hunger term; seeks food before puttering |
| 0 | Starving | No production, no health regeneration, no restocking |

A villager eats when its points are at or below `FULL - 4` and it has food: from its
belongings, and then from its stash when it stands within 4 of it (`possessions.eat`,
checked once a minute). Tavern dinner is the other
place it eats (see [The tavern](#the-tavern)). Eating uses `food.receive` and
`food.show_handover`'s eating sound; food never goes on the ground.

An adult never fed (`_villages_food` unset) starts at 8 points, fed but not full, so
a new village is not found starving with nothing made and nothing restocked, and
births still wait on the farm (ticket 8, found when the first crafting probe made
nothing).

Children do not get hungry. Their household feeds them once a day, as now
(`_villages_fed_day`), and they take no part in trade.

## Possessions

`possessions.lua`.

- **Belongings.** `_villages_belongings`, item name to count, carried, dropped where
  the villager dies. It is kept apart from the work pouch (`_villages_farm_pouch`,
  `farm_stock.lua`), which the farmer, the Builder and the keeper treat as goods for
  their job: they empty it into work chests, wait for it to be empty, and drop it when
  the job goes. A shared pouch would have sent a farmer's emeralds into its farm chest
  and kept a Builder from ever finishing. The pouch stays the job's; belongings are
  the villager's.
- **Emeralds.** Held in the belongings as `mcl_core:emerald`.
- **Stash.** The chest nearest the villager's bed, within
  `living_villages_stash_radius` (8), claimed in the chest's meta: `villages_owner`
  (the villager's `_id`) and `villages_owner_bed` (the bed it was claimed from); both
  halves of a double chest. Generated chests and chests a player placed are eligible.
  Work chests never are: a tavern's pantry (within 6 of a jukebox), a farm's chest
  (beside a composter), a Builder's (within 6 of its bench). `farm_stock.find_chests`
  leaves stashes out, so farmers, Builders and keepers never take from one.
- **Succession.** A stash belongs to the bed. A villager whose bed is the one a chest
  was claimed from, and whose owner no longer holds that bed (vanilla's `villager` bed
  meta names someone else or no one), takes the chest and what is in it. A villager
  that moves to another bed gives up its old chest.
- **Starting stock.** 3 to 6 emeralds when a villager is first seen as an adult
  (`_villages_endowed`), and a kit (`KITS`: a farmer some seeds and bread, a smith a
  few coal and ingots) the first time it has a profession that has one
  (`_villages_kit`), once in its life, so taking a job away and back cannot mint more.
  A villager born in the village gets the same when it grows up: births are a source
  of emeralds, limited by food.
- **Theft.** A player who takes from a claimed stash within sight of a villager
  (gossip's witness rule: 16 nodes, line of sight, and awake) gives that villager
  `minor_negative` gossip, once a minute per witness and player however many stacks
  are taken (`theft.lua`, ticket 9). What was taken is written in the chest's meta
  (`villages_missing`); the owner finds it when it next looks, once a minute, and logs
  it. Its ledger counts the stash, so what it needed of the missing goods it now needs
  more, and market news carries that as "needs". Nothing is locked.

## Ledger and prices

`ledger.lua`, pure: no engine calls beyond what is passed in.

**Base prices.** `trade_tables.lua` is a checked-in copy of VoxeLibre's profession
trade tables, extracted by `tools/extract_trades/`. The tables are a `local` in
`mobs_mc/villager.lua` and are not exposed, so the tool cuts that block out and
evaluates it with stubs; it is rerun when the supported VoxeLibre version changes,
and `tests/trade_tables.lua` fails when the installed VoxeLibre no longer matches.
`ledger.lua` derives prices from the raw trades when first asked. A buy offer of N
items for E emeralds prices an item at E/N; a sell offer of N items for E emeralds
(and perhaps a second ingredient, at its own price) at the same. Where an item has
both, the base is their geometric mean. Items in no table (logs, cobble, saplings, sticks' sources)
get a short hand-written table in `ledger.lua`, consistent with their crafting
yield (planks at a quarter of a log, and so on).

**Targets.** Each villager has a target stock per item: what it wants to hold.

| Layer | Source |
|---|---|
| Food | Enough food points for 3 days |
| Work inputs | Its profession's recipe inputs for a day's production (see [Production](#production)); the Builder's `requires_materials` |
| Preferences | 1 or 2 items from a short list (flowers, books, a wool colour, cake), chosen by a hash of `_id`, wanted in small numbers |

**Need and surplus.** Need = target − held; surplus = held − target − reserve, where
the reserve is a quarter of the target, so a villager never sells down to nothing.

**Value.** What an item is worth to one villager: base price × urgency, where urgency
rises from 1 (no need) toward 3 as the need approaches the whole target, and falls
toward 0.5 for surplus. A villager will buy below its value and sell above it.

Ticket 21 replaces how prices and values are formed: see [Price discovery](#price-discovery).

## Production

Every good in the village has a source in this section or comes from a player.

### Real loops

| Profession | Change |
|---|---|
| Farmer | Unchanged: crops into the pouch |
| Fisherman | One completed cycle in four (`fisherman.lua`, which before only restocked) lands a fish by vanilla's fishing odds: cod in its barrel, up to 16, for the keeper to buy; anything else in its belongings, up to 8 of a kind |
| Shepherd | Every 90 s of the work stage shears a flock sheep within 4 that has its wool (`flock.lua`), 1 to 3 wool of its colour into its belongings, up to 16 a colour. Wool grows back when the sheep eats grass, as on vanilla sheep |
| Keeper | Cooks raw pantry ingredients into menu items (see [The tavern](#the-tavern)) |

### Jobsite crafting

Professions with no work loop craft at their jobsite (ticket 8). `recipes.lua` holds
one recipe list per profession, pure data that `ledger.lua` also reads: outputs from
that profession's sell offers, or inputs of its own recipes (paper and books for the
librarian's bookshelves), inputs from the real crafting recipe. A test checks every
output against the profession's trade table in `trade_tables.lua`. `production.lua`
does the making. Over work-stage economic clock time spent within 3 of its jobsite, a
villager banks seconds (`_villages_craft`) and makes a recipe's outputs at
`living_villages_craft_seconds` per item (default 120), taking the inputs from its
belongings and then its stash, wherever it stands. With no inputs it makes nothing and
banks nothing. A hungry villager works at half the rate, a starving one not at all.

It makes the recipe that adds most by its own values (the output's value less the
inputs' and the fuel's), among those it has inputs and fuel for and whose output it
holds fewer than its target plus 16 of. A surplus output's value falls, so a smith
moves from one tool to the next. Smelted goods take one furnace smelt each, and the
smiths one per ingot they forge. A coal or charcoal lump is 8 smelts, and the smelts
left over are kept (`_villages_fuel`). A crafting profession's ledger targets 4 crafts of
each recipe input, and 4 lumps of coal where its recipes smelt.

| Profession | Makes | From |
|---|---|---|
| Tool smith | Stone pickaxe, axe, shovel, hoe | Cobble, sticks |
| Weapon smith | Iron axe | Iron, sticks, fuel |
| Armorer | Iron helmet, chestplate, leggings, boots | Iron, fuel |
| Butcher | Cooked porkchop, cooked chicken | Raw meat, fuel |
| Fletcher | Arrows; flint; bows | Flint, sticks, feathers; gravel; sticks, string |
| Librarian | Paper; books; planks; bookshelves; glass | Sugar cane; paper, leather; oak logs; planks, books; sand, fuel |
| Leatherworker | Leather armour | Leather |
| Mason | Bricks; chiselled stone bricks; polished andesite, granite, diorite | Clay, fuel; stone; the raw stone |

The farmer, fisherman and shepherd make their goods in their own loops. The cleric's
goods have no recipe, and the cartographer's map needs a compass a village cannot make,
so these five restock as vanilla does. Enchanted goods are never made. Kits were
topped up so each crafting profession can make its first goods: feathers for the
fletcher, leather for the librarian, cobble for the tool smith, a fourth ingot for the
armorer and sticks for the weapon smith.

Charcoal counts wherever vanilla's tables ask for coal: the ledger counts the two
together toward one target, and fuel burns either, charcoal first. So a village can
supply its smiths from its own woodcutters, who burn charcoal (see below). The butcher's
cooked meat became food (porkchop 6, chicken 5).

### Nitwit and unemployed labour

`labour.lua`. Each morning (putter stage) a nitwit, or an unemployed villager with
no jobsite in sight, chooses an activity for the day: the one with the best expected
income, which is the price it has heard for the activity's goods × the rate it can
gather them, with a small bias to yesterday's choice so villagers do not all switch
at once. With no news it picks at random among the activities it has a site for.
Vanilla's job claim always wins over this for the unemployed. `nitwit.lua`'s demotion
guard is untouched.

| Activity | Site | Rule |
|---|---|---|
| Forager | Wild plants within 32 of its bed | Sweet berry bushes (`mcl_farming:sweet_berry_bush_*`) at their last stage, apples from the ground (dropped by leaves), mushrooms, flowers, sugar cane above its bottom block. Only what grows back |
| Woodcutter | A grove near its bed | Plants saplings, fells only trees grown from saplings it planted (positions kept on the villager, `_villages_grove`, at most 8), replants each one, and burns some logs into charcoal. Wild trees are never cut |
| Quarrier | A cobblestone generator within 32 | Mines cobble a player's water-and-lava machine makes (`mcl_core`'s "Lava cooling" ABM). Never digs terrain |
| Porter | Stashes of villagers who hire it | Carries goods for a buyer's trade trip, for a fee |
| Peddler | The village | Buys surplus below the going price and sells where it has heard of need, keeping the margin (ticket 12) |

Ticket 7 builds `labour.lua` with the forager and the woodcutter. The choice is made at
the first work tick of each game day (`_villages_labour`), from the best price heard
asked (market news "needs" entries) for each activity's goods times its rate (forager
12 a day: berries, apples, cane; woodcutter 10: logs, saplings); yesterday's counts
1.25 times. Foragers leave flowers and mushrooms, which do not come back once picked.
A woodcutter's grove spot is open grass 8 to 20 from its bed, with a clear 7 x 7 x 7
box above, no path, door or bed within 3, and 5 from its other trees; it takes its
first sapling from under a wild oak, at most once a day, and never cuts a wild tree.
Every species that grows from one sapling counts (oak, birch, spruce, jungle,
acacia), so a savanna village cuts acacia; a wild tree is told from a house's logs by
its own leaves above it. A trip to a tree ends on an open cell beside the trunk, and
a target it could not reach is passed over for 5 minutes.
From ticket 8, after each felling it burns 8 of the logs it carries past 16 into 7
charcoal, up to 32: eight logs smelted with one lump of the charcoal as fuel, in a clamp
by the grove rather than a furnace. Trips stay within 50 of the bed, so
`far_trips.lua` is not needed, and labour leaves `activity_override` alone: a nitwit's
work stage has no jobsite for vanilla to send it to. Apples (3 points) and sweet
berries (1) became food.

Ticket 11 adds the quarrier and the porter. A quarrier's cobble is a generator's when
lava and water both touch it from the side or above, which is where VoxeLibre's Lava
cooling ABM puts it; it mines within 32 of its bed, up to 64 (a Builder wants cobble by
the hundred), at a rate of 32 a day for the choice. A porter is open when the villager
has heard of a trade waiting (an item one villager needs and another has); its income
for the choice is 2, a fee or two; its work is the trips it is hired for.

## Market news

An extension of `gossip.lua`. A second memory, `_villages_market_news`, a list of at
most `NEWS_ENTRIES` (24) entries:

```lua
{item = "mcl_core:coal_lump", who = "<villager _id>", kind = "has" | "needs",
	count = 12, price = 0.07, home = <bed pos>, heard = <game time>, hops = 1}
```

- A villager's own top three needs and surpluses from its ledger are always
  shareable, with `hops = 0`.
- When a conversation runs its full time, `conversation.lua` already calls
  `gossip.exchange(members)`. Exchange also shares up to `NEWS_SHARE` (6) news
  entries each way, chosen by the **listener's** interest: an item the listener needs
  or has spare weighs more, fresher and fewer hops weigh more. Hearsay costs a hop.
  The listener keeps the freshest entry per (item, who, kind).
- Entries older than `NEWS_DAYS` (2) game days are forgotten. When the cap is
  reached, the least interesting entry goes.

This makes the well, the bell, the church social and the tavern the village's
market-information network. A villager who talks a lot finds trades sooner.

`market_news.lua` holds it; `conversation.lua` calls its `exchange` beside
`gossip.exchange`, so gossip's own setting does not turn the market off. Each
listener's ledger view is worked out once per conversation. What each member knows is
fixed before anyone speaks, so news crosses one hop per conversation. An item it needs
offered, or has spare wanted, weighs 4 times more; freshness falls linearly over
`NEWS_DAYS` to a floor of a tenth; each hop divides the weight by one more. From
ticket 11 an entry that completes a trade the listener has heard of (an offer of what
it heard someone needs, or a want of what it heard someone has) weighs 4 times too:
probe runs showed a quarrier's cobble never reaching a Builder through villagers who
wanted neither.

## Exchange between villagers

`exchange.lua`. A trade happens when the buyer's value for the goods is at least the
seller's ask (`asks.lua`, see [17. The food loop](#17-the-food-loop)). It settles at the
ask, in emeralds, or in goods when the buyer is out of emeralds and the seller needs
something it has. An item with no base price has no ask and settles at the midpoint of
the two values, as all trades did before ticket 17. Goods pass pouch to pouch
with `food.show_handover`'s animation. Three channels, in order:

1. **End of conversation.** After news is exchanged, each member checks the others
   for a trade it now knows of. They are standing together and loaded, so this
   needs no navigation. At most one trade per pair per conversation.
2. **Trade trips.** A villager with an urgent need (urgency above 2) and news of a
   seller walks to the seller, or to the seller's stash if the seller is not home,
   in its putter stage, through `navigation.lua`, with `far_trips.lua` covering the
   distance from home. A porter can be hired instead. The Builder buys its missing
   materials this way.
3. **Holiday market.** `market.lua` stalls show the seller's real surplus instead of
   its profession's two fixed goods, and browsers buy at stalls.

Ticket 6 settles the first channel (`exchange.lua`). Each pair makes the one trade
that gains the two of them most, buyer's value less seller's, over the goods the buyer
needs and the seller has spare and carries (a stash is not at hand). Emerald
payments are whole: a sale worth under one emerald grows to the fewest items that make
one, if the seller has them spare, and either payment goes through only when the buyer
values what it gets at no less than it pays and the seller at no more. Barter pays in
the one good the seller needs that leaves the buyer the most. The views are worked out
afresh for each pair, so a trade earlier in the same conversation counts.

Ticket 11 settles the second (`trade_trips.lua`). A need is urgent at a value 2 times
its price or more. The buyer picks, of the sellers it has heard have the item spare at
a value under its own and live within 64 of its bed, the need worth most, then the
nearest. It walks to the seller's bed: a seller within 8 sells in person, from its
belongings, as at the end of a conversation. A seller away from home carries its goods,
so a loaded one within 64 of its bed is followed, up to 3 walks; failing that the buyer
walks on to the seller's claimed stash and buys from the chest at the price it heard
(the seller's ask, ticket 17), whole emeralds into the chest. Either way it buys no more
than its emeralds pay for, and with none it plans no trip. Own trips run in the putter
stage, and the Builder's in its work stage too while short. A trip is dropped when the
day turns; a seller that came to nothing is passed over for 10 minutes.

A porter is hired when a conversation ends, after its trades: by a member with a
job (a jobsite, the keeper or the Builder), an urgent need with a known seller,
somewhere to deliver (its stash, the Builder's nearest bench chest) and 2 emeralds
or more. It gets a purse of up to 8, buys at its client's value in its work stage,
delivers the goods and the change, and keeps a fee of 1 if it bought anything. A
failed trip brings the whole purse back, the next day if need be.

The Builder (`builder_market.lua`), while short in `requires_materials`, puts its
missing priced materials in its ledger as `extra`, so its news posts them and it values
them urgently; unpriced ones (stone bricks, sand) only a player brings. It moves what
it bought into its pouch, where the bill counts it, and tops its purse up to 8 from
emeralds left in its bench chests.

## The farmer's food

From ticket 17 `farmer.lua`'s `hand_over` gives food only to children, free (a child's
growth waits on it). Adults eat at the tavern, or their own food at dinner, or alms
when broke. The farmer's surplus goes:

- wheat to its belongings up to 8 and bread up to 4, for its own dinner and to sell to
  villagers at its ask;
- the rest to its chest, where the keeper buys it (see [The tavern](#the-tavern)); the
  farmer collects the emeralds left there when it next stores its surplus.

Before ticket 17 it also fed its household free, sold a bundle (as many as vanilla
sells for one emerald) to anyone with an emerald and no food, and gave a starving
villager one item. That left the keeper's chest bare: the Colony run of 2026-11-13 saw
the farmers give away what the tavern should have bought.

With the economy off it feeds everyone free, as before.

## The tavern

- **Pantry.** The chests within 6 of the keeper's jukebox; the stock tavern's chest
  stands 3 behind it. The keeper fetches food for it from the farms' chests and the
  fishermen's barrels, and from ticket 4 buys it: it takes up to 8 emeralds from the
  pantry and leaves in the work chest what the food will sell for as dinners, one
  dinner's price per meal it makes (a loaf, a potato or a cod is one, wheat a third;
  ticket 11b). The tavern keeps no margin, so dinner money passes through the pantry
  to the food producers; the keeper's wage is its household's free dinners. What it
  cannot pay in whole emeralds, a fraction or a short purse, it owes in the chest's
  meta and pays first next time, up to 8, past which it is forgiven. It takes the food
  even when it cannot pay. Ticket 4 paid vanilla's prices, rounded: a probe run showed 8
  wheat paying nothing while each dinner made from it took an emerald, and the
  village's money piling up in the pantry.
- **Cooking.** The keeper turns raw pantry items into its menu items over its shift:
  bread from wheat, baked potatoes from potatoes, cooked fish from raw fish.
- **Dinner.** `meal.lua` serves a guest only when the pantry has a menu item: it
  takes the item, the guest gains its food points and pays one emerald from its
  belongings into the pantry (from ticket 8). The keeper and its household (beds in
  the same house, `possessions.same_house`) eat free. A guest is served only at or
  below 8 points, the mark at which it eats what it carries, so one fed from home
  keeps its emeralds; one that cannot pay is not served. With an empty pantry the
  guest is seated and nothing is served. From ticket 11b every payment is logged:
  diner, price and pantry.
- **Player meals.** `player_meals.lua` takes the meal from the pantry and charges
  the player one emerald from their inventory before serving. A player with no
  emerald, or a tavern with an empty pantry, is not served and the log says which.
- **Player trades.** The keeper's menu trades stay vanilla (unlimited). A low pantry
  raises the player's price through the demand term.

## Rent

Ticket 11b. Longer probe runs of ticket 11 showed money going one way. Every villager
pays the tavern for dinner, and a villager whose goods no one needs urgently, the
Builder above all, loses an emerald a day until it can buy nothing. In one run a
Builder bought 34 cobble from a quarrier for 2 emeralds, had none left for the last 8,
and never finished the house. The first run with rent showed the dinner money did not
even reach the food producers: the keeper paid vanilla's prices for raw food, rounded,
which is nothing for a load of wheat, so it piled up in the pantry. Now the keeper pays
what the food sells for (The tavern), so the food producers earn what the village spends
on dinner, and rent takes part of that to the Builder, which spends it on materials,
which quarriers and woodcutters spend at the tavern. The Builder grows richer as the
village grows.

- **Landlord.** Rent is owed to a Builder's bench, not to the villager holding it, so a
  new Builder inherits the income. Paid by errand, it goes in the bench chests, from which
  `builder_market.lua` already tops up the Builder's purse. A village with no claimed
  bench collects none.
- **Tenants.** A villager whose bed is in a house the Builder built: `finish_building`
  writes the bench's position as `villages_landlord` into the meta of every bed in the
  footprint. In a generated village farmers and fishermen pay as well, as if their
  houses had been built for them, so money starts flowing out of the food producers.
  Their landlord is the nearest claimed bench within `VILLAGE_RADIUS` (128) of the bed.
  The Builder, the keeper and its household (`possessions.same_house`) and children pay
  nothing.
- **How much.** `RENT` (1) emerald every `RENT_DAYS` (2) days of economic clock, so a
  villager away from players owes nothing for that time. Both numbers are guesses for
  probe runs to settle.
- **Arrears.** Rent not paid stays owing, up to `RENT_CAP` (3) emeralds; past that it
  is forgiven. No one is evicted. A tenant pays only from emeralds above the price of a
  dinner, so it eats first and pays when it next has money.
- **Paying.** At the end of a conversation with its landlord's Builder, before trades, a
  tenant hands over what it owes, from belongings to belongings, as `exchange.lua`
  settles a trade. Otherwise, owing anything it can pay, it goes by errand (kept from
  `far_trips.lua`'s walk home) in its putter stage to the bench's nearest chest, where
  it leaves the emeralds. The first design waited for the cap before the errand; a
  probe run showed conversations with the Builder too rare and too often cut short.
- **Where it goes.** The Builder pays for materials and dinner as before, from its
  belongings and its purse top-up. While the census has a building to put up it keeps
  buying; with none, rent piles up on the bench, and the census below shows it.
- **Observability.** Dinner payments are logged (The tavern), and so is every rent
  payment (tenant, amount, bench, at a conversation or by errand) and arrears forgiven.
  The probe census records each villager's emeralds, the pantry's and each bench
  chest's, so a run shows where money sits day by day. The inspector gets a `Rent`
  line: landlord, owed, last paid.

## Village demand by profession

Food is the one constant demand: everyone eats every day. Without more, money ends with
whoever sells food and every other profession lives on its starting emeralds (Principle
6). Where each profession's village demand comes from:

| Profession | Sells to villagers | Buyer and why | Ticket |
|---|---|---|---|
| Farmer, fisherman | Food | The keeper, for dinners | 4, 11b |
| Mason | Bricks, smooth stone | The Builder, as materials | 11 |
| Shepherd | Wool | The Builder (beds); banners | 11, 12 |
| Tool smith | Stone hoe, axe, pickaxe | Farmers, woodcutters, quarriers: a tool wears out | 11d |
| Librarian | Books; glass | Everyone: reading speeds work for a while; the Builder | 11e, 11 |
| Leatherworker | Leather, from a cow herd | The librarian, for books | 11e |
| Butcher | Cooked meat | The keeper: a second dish | 11e |
| Fletcher | Bows, arrows | Warriors: arrows are spent, bows wear | To do (warriors) |
| Cleric | Its blessing | Donations at the holiday service, which it passes on as alms | 11c |
| Cartographer | Banners | Villagers decorating for the holiday market | 12 |
| Weapon smith, armorer | Swords, axes; armor, shields | Warriors; iron from the alchemist (20) | To do (warriors) |
| Alchemist | Iron, flint, glass, gold | The smiths and the armorer (iron), the fletcher (flint), the Builder (glass); players | 20 |

## Donations and alms

Ticket 11c. A safety net for villagers who run out of money, and the cleric's income.

- **Donating.** At the end of the holiday service (`church.lua`), each attendee with
  more than `SAVINGS` (8) emeralds gives the cleric at the pulpit a tenth of the excess,
  at least 1. The rich give most, so money comes from where it piles up.
- **Good gossip.** `gossip.lua` keys its memory by a subject string, so a villager's id
  serves as one: each attendee that sees a donation records `minor_positive` about the
  donor (`major_positive` for 5 emeralds or more), which decays and spreads in
  conversation like gossip about players. Villager subjects get their own share of the
  entries passed in a conversation, so they do not crowd out gossip about players.
- **What standing buys.** In `exchange.lua`, a trader that thinks well of the other
  moves the price toward it, by up to a tenth: generous villagers trade a little
  cheaper, and the donation pays back over time.
- **Alms.** The cleric keeps a tenth of what it is given as its own (half until ticket
  19). In the social stage after the service, which keeps villagers about the pulpit, it
  tops up every villager there with less than two dinners' worth to two dinners, from
  the rest. What is left
  waits for the next holiday.

Money goes food producers → donations → cleric → alms → poor villagers → tavern → food
producers. Donations, alms and standing are logged; the inspector gets a `Standing` line.

## Goods that wear out

Ticket 11d. `wants.lua` is data, as `recipes.lua` is: goods that do a villager good for
a while and then are used up. Each entry names the item (or a choice of items), who
wants it (professions or labour activities), how long it lasts (uses or days of
economic clock) and its effect: a rate multiplier on that villager's work. The ledger
reads it: a villager without the good, or with one nearly used up, needs it, valued at
the extra income it brings over its life, so its market news posts the need and trades
and trade trips buy it. Its work loops read the multiplier. Every effect is a bonus over
today's rates (Principle 6).

First entries, whose supply already exists (cobble from quarriers, sticks from
woodcutters, the tool smith's recipes):

| Good | Wanted by | Lasts | Effect |
|---|---|---|---|
| Stone hoe | Farmers | 64 harvests | Harvests 1.5 times as fast |
| Stone axe | Woodcutters | 32 fellings | Fells 1.5 times as fast |
| Stone pickaxe | Quarriers | 64 cobble | Mines 1.5 times as fast |

A good in use is held in `_villages_wants` (item, uses or clock left); a worn-out tool
is gone. The numbers are guesses for probe runs.

## Leather

Ticket 11e. No villager makes leather: the only leather is the librarian's and the
leatherworker's starting kits and what players sell, so books stop after about two.
Cows drop 1 to 3 beef and 0 to 2 leather (`mobs_mc/cow+mooshroom.lua`).

- **Herding.** The leatherworker keeps a herd of cows by its cauldron, as `flock.lua`'s
  shepherds keep sheep (ordinary `mobs_mc:cow`, marked with the villager's id, up to a
  herd size). Cows breed on wheat (their `follow`), which it buys from farmers; past
  the herd size it slaughters one, keeping the leather and selling the beef to the
  butcher.
- **Books.** Reading joins `wants.lua`: every adult wants a book every few days, and
  one read speeds its work by a fifth for that time, then is used up.
- **Cooked meat.** The butcher cooks beef too, and the keeper buys cooked meat as a
  second dish, at one dinner a piece.

How mobs_mc's cows breed and can be slaughtered under a villager's hand needs reading
before it is designed further.

## Warriors (to do)

Not scheduled: combat would be the hardest behaviour in the mod, so it waits. Noted here
because three professions' village demand depends on it (Principle 6).

- **Roles.** An archer (ranged) and a guard (melee), roles over a post block as the
  Builder's is over its bench, taken by unemployed adults, a few per village.
- **Defense first.** A hostile mob near the village, or a player its own gossip holds at
  or below `REPUTATION_HOSTILE` (as iron golems already treat players, `gossip.lua`),
  is a threat, and answering it overrides every schedule stage. Never villagers or
  golems; an archer holds its shot while a villager is in the way.
- **Archers** stand where they can hit: in bow range, in line of sight, on high ground
  if there is any, and shoot real arrows (`mcl_bows.shoot_arrow` takes a shooter
  object). **Guards** close in and strike with the weapon they carry; armor lessens what
  they take.
- **Hunting** fills their time when nothing threatens: wild cows, pigs, chickens and
  rabbits, never a leatherworker's herd, for leather, meat and feathers they sell.
- **Demand.** Arrows (spent) and bows from the fletcher, swords from the tool smith and
  the weapon smith, armor from the leatherworker and the armorer. The iron goods still
  need a village source of iron.
- **Open:** whether threats wake warriors at night or a watch keeps one awake; whether
  guards use the armor stand as their post.

## The alchemist

Ticket 20. Stone and logs have few buyers, and nobody in a village makes iron, flint,
glass or gold. The alchemist turns the first two into the rest. No village is generated
with one: a player crafts its stand. It neither eats nor wants comforts, and it works
through the hours others spend at the tavern and the church, so what it earns goes back
to the villagers who sell it stone and logs.

### The stand

- `living_villages:alchemy_stand`, "Alchemist's stand": the brewing stand's shape and
  textures, recoloured (`mcl_brewing`'s stand mesh with a tint of its own). It has no
  formspec and brews nothing. It is not an `mcl_brewing` node, so vanilla clerics never
  look for it. It is the mod's fourth node: remove the mod and a placed stand becomes
  an unknown node, and its alchemist loses its job, as with the bench and the pulpit.
- Recipe, shaped, with the top of the grid read as north: a feather (air) north, a
  nautilus shell (water) east, any stone-tier block (earth, `group:cobble`: cobble,
  cobbled deepslate, blackstone, as stone tools take) south and a blaze rod (fire,
  `mcl_mobitems:blaze_rod`, an alias of `flaming_rod`) west. The centre is empty.

  ```
  .            feather         .
  blaze rod    .               nautilus shell
  .            group:cobble    .
  ```

- Never generated. `village_staffing.lua` never places or hands one out. A placed stand
  is a job block like any other (`job_blocks.lua` kind `alchemy`), so an adult out of
  work takes the nearest free one (`job_seek.lua`).

### The role

A role over a vanilla cleric, as the Builder is over a mason and the keeper over a
butcher. The brewing stand is the vanilla cleric's jobsite and its robe suits the role.
The robe is tinted so an alchemist is told from a cleric at a glance. `alchemist.lua`
claims the stand through the node's `villager` meta, which is all vanilla's
`validate_jobsite` checks, and sets `_villages_alchemist`. It has no `_trades`. Every
check for a cleric asks the flag first: `common.lua`'s `schedule_of`, `church.lua`,
`alms.lua`, `cleric.lua`'s pulpit seek and `economy_report.lua`.

- **Timetable.** Ordinary day: putter from 5500, work 7000 to 17500 (the others' work
  and tavern hours), then home and sleep. Holiday: putter, work 7000 to 10500 (service
  and social), bell 10500 to 15000, work 15000 to 17500. So it meets the village at the
  morning bell and the well, and at the holiday bell, where it keeps a stall and may buy
  a banner like any seller (`market_stall.lua`).
- **No food.** Its food points never fall. It is never hungry or starving, so it always
  works at full rate. It never eats, is never served and never wants food. Births treat
  it as fed.
- **No comforts or wants.** `comforts.lua` gives it no slots and `wants.lua` gives it no
  goods that wear out (books, tools). Its ledger wants only its inputs and a banner for
  its stall.
- **No church.** It never attends, so it never donates and never gets alms or a stake.
  `alms.lua` also skips it by the flag, in case it is standing near the pulpit.
- **Everything else as usual.** Conversations, market news, trade trips in the putter
  stage, hiring porters (it has a jobsite), rent if its bed is in a house the Builder
  built, and its stash.

### What it makes

At its stand, within `production.lua`'s jobsite reach, from its belongings and then its
stash. The times are shares of its work day, which is 10500 ticks: 525 s of economic
clock at the default `time_speed` (72), worked out from `time_speed` and the timetable.

| Makes | From | Share of a work day | Default | A whole day on it | Stops |
|---|---|---|---|---|---|
| Iron nugget | 4 stone or cobble | 1/18 | 29.2 s | 18 nuggets (72 stone) | Never |
| Flint | 4 logs, any species | 1/6 | 87.5 s | 6 flint (24 logs) | At 32 flint |
| Glass | 2 stone | 1/36 | 14.6 s | 36 glass (72 stone) | Past 12 glass |

Glass takes stone at the nugget's pace. A holiday has 6000 work ticks, about 57% of a
day. It picks by order, not by value: glass while it holds 12 or fewer, then flint while
it holds fewer than 32 and has the logs, then nuggets. At cost-based prices the three
recipes add about the same value, so a choice by value would be arbitrary. `production`'s
stock cap (target plus `STOCK`) does not apply to the nuggets.

### What it buys

- **Logs**, while it holds fewer than 32 flint: 4 logs for each flint short, at most
  `INPUT_CAP` (32) at a time, as the `log` category.
- **Stone**, always: a new `stone` category (stone and cobble, one unit each) for the
  nuggets, a day's 72 wanted. `prices.balance` already counts a need only as far as its
  villager can pay, so it buys stone for as long as it has the money. Glass takes plain
  stone only, so both the mason's smelted stone and the quarrier's cobble sell.
- It values its inputs at their base price and never more: urgency for stone and logs is
  held at 1 or under. So it never pays more for an input than the output returns, and a
  seller whose ask has risen above base waits until the ask falls.

### What it sells

Its nuggets, flint and glass are all spare, since it targets none of them. A few more
goods come from them at sale, through the conversions every job uses (`goods.lua`,
ticket 15):

| From | To | Takes | Gives | Only past |
|---|---|---|---|---|
| Iron nugget | Iron ingot | 9 | 1 | — |
| Iron nugget | Gold nugget | 18 (2 ingots) | 1 | 108 nuggets |
| Iron nugget | Gold ingot | 162 (9 gold nuggets) | 1 | 108 nuggets |
| Glass | Glass pane | 1 | 1 | — |

A conversion gets a new `reserve` field: it spends only the source held past that many.
So gold shows in news, at its stall and in trades only while it holds more than 108
nuggets (12 ingots' worth), and it is paid for from the excess alone: a gold ingot needs
270 nuggets held. A pane counts as one glass, so both come from 2 stone. Its ask never
falls below its reference value (below): `asks.lua`'s glut discount stops there.

### Cost-based prices

Its reference value for each output is what the inputs cost at base prices (stone 3.2,
a log 16). These become the village's base prices too, so a smith values iron at a price
the alchemist can sell at:

| Item | Base price now | Cost-based |
|---|---|---|
| Iron nugget | — | 12.8 |
| Iron ingot | 16 | 115.2 |
| Gold nugget | — | 230.4 |
| Gold ingot | 21.3 | 2073.6 |
| Flint | 2.4 | 64 |
| Glass | 16 | 6.4 |
| Glass pane | 5.8 | 6.4 |

A good made from iron, gold or flint (`recipes.lua`) is priced at no less than 1.25 times
its inputs and fuel at these prices, so the smiths, the armorer and the fletcher still
gain on each craft:

| Item | Now | With the cost floor |
|---|---|---|
| Iron helmet | 320 | 724 |
| Iron chestplate | 576 | 1158 |
| Iron leggings | 448 | 1013 |
| Iron boots | 256 | 579 |
| Iron axe | 192 | 439 |
| Arrow | 4 | 21.5 |

What follows from this:

- Players pay about twice as much for iron gear and about five times as much for arrows.
- A player selling iron to a smith gets up to 0.9 × 115 an ingot, out of that smith's
  emeralds.
- Glass gets cheaper, and so do the Builder's houses.
- A vanilla trade's want for iron, gold or flint counts only where the profession's own
  recipes take it. That drops the cleric's gold ingots (at 2073 it would pay players out of
  the alms fund), the tool smith's iron and flint, and the leatherworker's and weapon
  smith's flint, which none of them uses. The armorer, the weapon smith (iron) and the
  fletcher (flint) keep theirs.
- The alchemist cannot lose money trading with villagers: it buys at base or below and
  sells at base or above.

### Trading with players

It is the only villager whose player trades use conversions. In `trade_window.lua` it
treats the player as it would a villager, with its own margins:

- **It sells** at 1.5 times its reference value (others: 1.25 times their value). The
  window lists what it holds spare and what its conversions can make: an iron ingot
  while it holds 9 nuggets, gold only past the reserve, a pane for each glass. Buying an
  ingot takes 9 nuggets from its pouch and puts the emeralds in it.
- **It buys** iron and gold, as nuggets or ingots, at any time; flint while it holds
  fewer than 32; and glass or panes while it holds 12 or fewer. It pays half its
  reference value (others: 0.9), from the emeralds in its pouch. What it buys goes into
  its belongings as it is, and it sells a held ingot before converting new nuggets.
- Reputation moves both prices, as with everyone else.

### Saved state and observability

- `_villages_alchemist` on the villager, and the `villager` meta on its stand. Its craft
  bank is the existing `_villages_craft`.
- Logs: `became alchemist at the stand at <pos>`, each craft as `production.lua` logs
  it, and conversions as `exchange.lua` logs them now.
- Inspector line `Alchemy`: nuggets held (and whether gold is on sale), flint out of 32,
  glass out of 12, and what it made today.

## Prices and the money supply

At VoxeLibre's prices an emerald is worth 32 sticks or 20 wheat, so most sales between
villagers come to a fraction of one, and trades in whole emeralds cannot happen: runs 34
to 36 saw trade trips for a few coal or a spare loaf come to 0.3 to 0.5 of an emerald.
Rather than credit or change, every price and every emerald amount is multiplied by
one factor, `ledger.SCALE` = 64, so the cheapest goods (sticks, rotten flesh, 1/32 of
an emerald today) are worth 2 and a whole-emerald price is within a quarter of the
value of even one of them. This first step changes no price relative to another;
rebalancing what goods are worth against each other is later tuning (see Open
questions).

**What scales.**

| Amount | Today | Scaled |
|---|---|---|
| Base prices (`ledger.lua`, derived and hand-written) | stick 1/32, wheat 1/20, bread about 1/7, bell 36 | stick 2, wheat 3.2, bread about 9, bell 2304 |
| A new adult's emeralds (`possessions.endow`) | 3 to 6 | 192 to 384 |
| Rent, its cap, the dinner a villager must keep (`rent.lua`) | 1, 3, 1 | 64, 192, 18 (the dinner price, below) |
| A villager's dinner (`meal.lua`), the keeper's dinner credit | 1 | 18 (`ledger.DINNER`, set after 11h) |
| A player's tavern meal (`living_villages_player_meal_price`) | 1 | 18 |
| Purses: the keeper's, the Builder's, a porter's | 8 | 512 |
| The keeper's tab cap; a porter's fee | 8; 1 | 512; 64 |
| The Builder's sales to players (`builder_materials.SALES`) | 1 to 16 | 64 to 1024 |
| Player trades (below) | vanilla | emeralds times 64 |

`exchange.lua`'s smallest sale stays one emerald, now half a stick. The farmer's food
sale keeps its bundle (as many as vanilla sells for one emerald, six loaves), now for
64 emeralds.

**Player trades.** The emeralds in each trade the player sees are multiplied by
`SCALE` in the player's detached trade lists, where `gossip.lua` already sets the
price (both wanted slots and the offered slot, so selling 20 wheat pays 64 emeralds
and 6 bread cost 64), before the demand and reputation terms move it; the reputation
discount scales with it. `_trades` keeps vanilla's counts, so the fisherman's restock
and the market still read real trades, and removing the mod restores vanilla prices.
The emerald's `stack_max` goes from 64 to 4096 (`core.override_item`), so a
price up to 4096 fits one slot; prices already clamp to `stack_max`. With the economy
off nothing scales and the stack stays at 64.

**Existing worlds.** A villager endowed before the change (`_villages_endowed` with no
`_villages_emerald_scale`) has the emeralds in its belongings multiplied once and is
marked. Chests are left alone. Stacks over 64 outlive the mod as ordinary oversized
stacks.

## Price discovery

Ticket 21. This section replaces how a price is formed. [Ledger and
prices](#ledger-and-prices), [Prices and the money supply](#prices-and-the-money-supply)
and tickets 13 and 14 describe the system it replaces, which stays in place until each
part lands. The aim is a decentralised market in the Austrian sense:

- No price is set from outside. Base prices only seed what a villager first believes.
- Each villager values goods subjectively: by its own needs, its own money, and what
  the goods let it make.
- A price is learnt from trades and offers, and it changes what gets made and bought.
- The player is one more trader whose trades move prices like anyone's.

With 20 to 30 villagers, a market seldom has more than one seller and a few buyers, so
every rule has to work in a thin market.

### What the alchemist showed (ColonyFood, 2026-11-15)

The alchemist took its stand on day 246. By day 285:

- It had bought about 300 emeralds of logs and cobble, and sold nothing to a villager.
- It held 30 flint, 17 iron nuggets and 8 gold nuggets, with 1 emerald left.
- The armorer wanted 32 ingots, valued at 366 each, and held 46 emeralds.
- The weapon smith wanted 11 ingots at 326 and held 0. The fletcher wanted 23 flint at
  157 and held 1.
- Two farmers and the mason held 3940 of the village's roughly 4700 emeralds.
- The mason wanted 8 panes at 51 and could pay, but the alchemist made no glass. Glass
  takes stone, and it was offered only cobble.

The old rules could not settle this, for six reasons:

1. **Prices were tied to fixed base prices, with narrow bands.** An ask stayed between
   0.5 and 2 times its base price (the alchemist's never below it), and a belief
   between 1/8 and 8 times it. No allowed ask reached a buyer with 1 emerald.
2. **Value ignored the villager's own money.** A smith with no emeralds valued an ingot
   at 326. A farmer with 3110 valued everything at the same base prices as anyone, so it
   bought almost nothing and money stopped moving.
3. **Demand and supply did not answer to price.** A need was a fixed target, so a dearer
   good was wanted just as much. Production followed fixed ranks with no thought of
   whether the goods sold, so the alchemist kept making flint nobody could pay for.
4. **Prices were never learnt from trades.** Beliefs moved only on counts of needs and
   offers heard in the news, never on prices paid, and asks moved only on whether a good
   sold. The two loops shared nothing.
5. **Producer goods were valued by their own base price, not by what they make.** The
   armorer valued iron by an ingot's base price even though nobody could buy armour.
6. **Player trades stood outside the market.** The window priced off a villager's value
   with fixed margins and moved no ask and no belief, so a player could not shift a
   price by trading.

### Reference prices

Each villager keeps a reference price in emeralds per item: what it thinks the item
trades for. This replaces ticket 13's multipliers.

**Storage.** A reference price is kept as a factor on the item's base price, in ticket
13's `_villages_prices` (`{[key] = factor}`). The base price is only the seed. A key
absent from it is at the base price. A category's members (food, fuel, logs, planks,
wool, stone) share one factor under `group:<category>`, the first category in
`goods.ORDER` the item belongs to (`goods.category_of`), so a loaf and a potato stay in
line with each other. A villager keeps at most KEEP (64) keys, those furthest from 1.
Saves from before 21b kept a factor per item: at the first day's move, a category's
members are folded into its key at their geometric mean (`prices.migrate`).

**Bounds.** A factor stays within SPAN (64) either side of 1. This is a safety rail,
not a working range. Counts alone (the imbalance below) take a factor no further than
COUNT_SPAN (4) either way.

**Learning.** A reference price moves in log space toward evidence. There is no pull
back toward the base price: with no evidence, a price stays where it is.

| Evidence | Moves the price toward | Share |
|---|---|---|
| A trade it made, as buyer or seller, with a villager or a player | the price paid per item | LEARN_TRADE 0.3 |
| A price signal heard in the news (an entry's `ref`, below) | their geometric mean, each weighted 1 / (1 + hops) | LEARN_NEWS 0.1, times the weight, at most 0.1 |
| A buy it passed up because the ask was over its value | the dearest such ask that day, if above its price | LEARN_MISS 0.05 |
| A finished conversation | the members' geometric mean, as ticket 13's SHARE | SHARE 0.25 |

**News carries prices.** A `has` entry carries the seller's ask, as it does today. A
`needs` entry carries the needer's bid: its value, capped at its emeralds. Peddlers,
porters and trade trips act on these. Each entry also carries `ref`, the teller's own
price signal:
- for what it has, its reference price times its ask factor, so a glut shows;
- for what it needs, its reference price.

Reference prices learn from `ref`, never from `price`. A need's price has urgency and
the money factor in it. In the simulation, learning from it ran an untraded good to
the rail: each villager's bid raised the next one's reference price, and with it that
villager's own bid.

Counts and budgets still go into the market's demand and supply. Ticket 13's imbalance
rule becomes a small extra term on top of the learning above: one day of full imbalance
moves a price by IMBALANCE_DAY (1.15), and never past COUNT_SPAN. In the simulation, a
need nobody could meet (the fletcher's planks) ran to the rail on counts alone. Heard
prices carry most of the weight.

### The money factor

What a villager pays in emeralds depends on how many emeralds it holds. Each villager
has a marginal value for an emerald, `λ`:

```
λ = clamp((CUSHION / max(emeralds, 1)) ^ GAMMA, 1/LAMBDA_SPAN, LAMBDA_SPAN)
value = reference price × urgency / λ
```

- CUSHION is 4 dinners at the villager's reference price for a dinner (see [A dinner
  that floats](#a-dinner-that-floats)), 72 emeralds at today's price.
- GAMMA is 0.5 and LAMBDA_SPAN is 8.
- At CUSHION, `λ` is 1 and value is as today.
- A villager with 1 emerald has `λ` of 8: everything is worth an eighth as much to it,
  so it sells cheap and bids low. That bid is still capped at its emeralds.
- The farmer with 3110 emeralds has `λ` of about 0.15: it pays up to six or seven times
  a reference price for what it wants.

This one factor:

- moves money from the rich to whoever sells what they want;
- makes a broke seller's goods cheap;
- largely replaces comforts' fixed WORTH caps: a comfort is worth its reference price
  over `λ`. Comforts keep their slots, the quantity side.

**Exceptions.**
- What is left of a porter's purse is its client's money, not the porter's.
- The keeper's values are left as they are (`λ` of 1): its emeralds are a float topped
  up from the pantry, so they say nothing about how rich it is.
- Goods against goods are reckoned with no money in them (the view's `real`). Two broke
  villagers still swap at what the goods are worth to them.

### Producer goods and production by margin

**Imputed values.** An input is worth what it makes. For a crafter, an input's value is
capped by its imputed value:

```
imputed = (output price × output count − other inputs at reference prices) / this input's count
```

The output price is the crafter's reference price for the output. It counts the best
recipe that uses the input. So when armour stops selling:

1. the armorer's armour asks fall;
2. its reference price for armour follows them down;
3. its bid for iron follows that.

**Choosing what to make.** A producer makes the recipe that pays most per second of
work:

```
(output price × count − inputs at reference prices) / production.cost
```

It skips any recipe that doesn't pay. When nothing pays, it does what an idle crafter
does today: labours (ticket 19b). It wants only the inputs of recipes that pay.

- An unsold stock pulls its own price down, so it stops itself. The alchemist's fixed
  stops (`upto` 12 glass and 32 flint) and its ranks give way to margins.
- STORE_CAP (64) stays as a hard limit on any one made good held.
- The real loops (field, fishing line, shears, herd) keep running regardless, as they
  are tied to a place and a job.

**Cost floors.** These go:
- The alchemist's ask floor (`asks.lua`), its input `worth` caps and its goods' `least`
  floors (`alchemist.targets`).
- COST_FLOOR, as a price rule (ledger.lua).

A seller may sell below what its inputs cost, since they are spent; it just stops making
more. COST_PRICED stays, as the seed for the alchemist's goods' reference prices.

**What it gives the alchemist.** If flint doesn't sell, the alchemist stops buying logs
for it. If the mason bids for panes, its bid for stone rises, the mason (who makes stone
from cobble) sells it some, and it makes glass.

### Asks

A seller asks its reference price times its ask factor:

```
ask = reference price × factor
```

The factor is a short-term term, between ASK_MIN 0.25 and ASK_MAX 4:

- A sale moves the reference price toward the price paid (LEARN_TRADE). It also pulls
  the factor back toward 1 by the same share, so a lasting rise is carried by the
  reference price rather than counted twice.
- Each sale raises the factor by MARKUP (1.05), as today.
- A slow day lowers it by MARKDOWN (0.9), as today. On a slow day when the seller's
  emeralds are under CUSHION, it falls by MARKDOWN once more: a seller short of money
  cuts its price faster.

An ask never falls below the seller's own value for one held past its target and
reserve. That value is already low for one with a glut or no money. A peddler still
never asks under its bid.

### Players

The player trades at the villager's own prices. The window's rows are:

| Row | Price |
|---|---|
| The villager sells to the player | its ask |
| The villager buys from the player | its bid: value, capped at its emeralds |

- Reputation moves both by up to REP_MAX, as today.
- MARKUP, BID_SHARE and the alchemist's ALCHEMY_MARKUP and ALCHEMY_BID go. A villager
  never both needs and has spare of the same item, so it offers no spread for a player
  to arbitrage against itself. Arbitrage between villagers is the player's part in the
  market.
- A player trade is settled like a villager's: `asks.sold` for the seller, and learning
  from the price on the villager's side. A player who buys up a good raises its price;
  one who floods a good lowers it.
- Conversions in the window stay with the alchemist.

**Giving emeralds.** A player can put money back into the economy in two ways:

- **A gift in the window.** A "Give" field gives the villager emeralds outright. A gift
  of at least GIFT_GOSSIP (a dinner) is `minor_positive` gossip, and one of 8 dinners
  or more is `major_positive`. The villager thinks better of the giver, so it gives the
  player better prices.
- **The stash.** Emeralds left in a villager's stash are collected (`possessions.
  collect_stash_emeralds`). On 2026-11-15, emeralds left in two chests did nothing:
  - The first chest was a trapped chest, and `farm_stock.CHEST_NODES` doesn't include
    trapped chests.
  - The other chest was nobody's stash.
  - A stash only pays out when its villager comes within STASH_REACH (4) of it, so a
    chest at the edge of the 8-node claim radius is seldom reached.

  21a adds trapped chests, names the owner of a stash in the chest's infotext, logs each
  collection, and has a villager collect from its stash when it rises from bed.

### A dinner that floats

The keeper prices dinner as a seller prices any good. Nothing in the economy is a fixed
price any more except rent, a new adult's emeralds, purses and a porter's fee (see Open
questions).

- **Food cost.** The keeper keeps a reference price for a meal's food. It learns it from
  what it pays for food. Fetching from a farm chest, it pays its own reference price for
  the food it takes, not DINNER per meal. It also learns from the food asks it hears.
- **The dinner price.** This is the food cost per meal times the keeper's dinner factor.
  The factor is set from each evening:
  - It falls by MARKDOWN if guests were turned away because they couldn't pay while the
    pantry still had food.
  - It rises by MARKUP if the pantry ran out.
  - It stays between ASK_MIN and ASK_MAX.
  - The price is posted in the tavern's meta and carried in the news as an ask for the
    pseudo-item `living_villages:dinner`.
- **Who dines.** A villager dines when the dinner price is no more than its value for a
  meal: a meal's food points at its reference price for food, times its urgency, over
  `λ`. Otherwise it eats from its pouch or buys food from a farmer, so the tavern
  competes with the farmers' stalls. The raw plate for the broke stays at BROKE_PRICE.
- **Players** pay the posted dinner price unless the server sets
  `living_villages_player_meal_price`.
- **Amounts counted in dinners** follow the villager's reference price for a dinner,
  so they scale with prices: savings, the craftsman's stake, the comfort step, what a
  tenant keeps back from rent, and CUSHION. `ledger.DINNER` remains only as the seed
  for that reference price.

### Stability

A thin market can swing, spiral or stall. Each part:

- **Learns in small steps in log space.** No single trade moves a price by more than
  LEARN_TRADE.
- **Keeps the safety rails.** These are REF_SPAN, ASK_MIN and ASK_MAX, and LAMBDA_SPAN.
- **Comes with a pure simulation test** (`tests/price_sim.lua`). It runs a handful of
  stub villagers through days and checks four things:
  - one seller and one buyer settle on a price between their values;
  - a glut's price falls until it sells;
  - a rich buyer's money spreads to several sellers;
  - nothing runs to a rail in 60 days of steady state.
- **Is checked in ColonyFood** with lv_keep's summary. It adds each traded item's median
  reference price, its trades and their prices per day, and the share of emeralds held
  by the richest three.

## Staffing a new village

A generated village is staffed the moment it is placed, not by a race for workstations.
Every unemployed villager today takes the nearest free job block, so on the first day
they all crowd the composters (`farm_jobs.lua` puts farming first), a villager can end
up working across the village from its bed, and a probe run spends its first day
waiting for jobs to settle.

- **When.** `settlements.place_schematics` places a village's buildings, but each one
  lands later, through `emerge_area`, and VoxeLibre spawns a villager on each red bed
  in that building's after-placement callback (`mcl_villages/buildings.lua`
  `spawn_villagers`), with `_bed` and the bed's meta set. While the original runs,
  `mcl_structures.place_schematic` is wrapped to count those callbacks; when the last
  one has run, every bed, job block and villager exists, and staffing runs once.
- **Who gets what.** The job blocks are every workstation in the village area
  (`common.lua`'s workstation table), the Builder's bench and the tavern's jukebox. The
  villagers are those just spawned, each on its own bed. Pairs are taken greedily, the
  closest job block and bed first, until one side runs out. Each pair is claimed as
  VoxeLibre's `employ` claims one: the block's meta `villager`, `_jobsite`,
  `_profession` and the texture (`init.lua`'s mirror of `set_textures`); the bench and
  the jukebox through `builder.lua`'s and `keeper.lua`'s own claims, so their
  saved state is what it would have been. Beds stay as spawned, so each villager works at
  the job nearest its bed.
- **Left unemployed.** `living_villages_spawn_unemployed` villagers are left without a
  job: those whose beds are furthest from any block still free. They are the labour pool
  (forager, woodcutter, quarrier); the probe's `lv_probe_nitwits` stays for nitwits.
- **Later job seekers.** A child grown up or a villager who loses its job takes the free
  job block nearest its bed, of any kind, in place of VoxeLibre's nearest to where it
  stands. This replaces `farm_jobs.lua`'s farming first: a composter no longer comes
  ahead of other jobs. `child_jobs.lua` still keeps children from taking any.
- **Scope.** New villages only. A village generated before this keeps the jobs its
  villagers took.

## What the player sees

**Prices.** Java's demand term, which `gossip.lua` left out "since neither exists
here", now exists (`demand.lua`, ticket 9). The ledger's urgency for an offer's item
moves the first ingredient of that trade for every player, through the same `wanted`
list wrapper reputation uses, combined with reputation in one place: the demand term
moves the base count first, then reputation moves that. The urgency (the trader's
value over the base price, 0.5 to 3) moves the price by its square root, so a full
need is about 1.7 times. A villager short of what it buys pays more for it, asking
fewer items for its emerald (a smith out of coal takes 9 lumps, not 15); one with a
glut of what it sells sells cheaper. A hungry villager charges 1.25 times for what it
sells and a starving one 1.5 times: it works slower, so its goods are scarcer.
Counts stay between 1 and a stack. With gossip off the demand term still applies;
with the economy off only reputation does.

**Restocking.** Vanilla restocks a villager's locked trades in `unlock_trades` when
it arrives at its jobsite (`mobs_mc/villager.lua`, `do_work`). Both are local to
VoxeLibre's file, so `production.lua` wraps `do_custom` instead: when a call turns the
order to "work" and changes `_trades`, it puts `_trades` back for a starving villager,
and for a crafting profession that cannot make one craft from what its belongings and
stash hold. It tries again on its next arrival. The fisherman's per-cycle restock is
unchanged.

**Tiers.** Vanilla raises `_max_trade_tier` when a player first uses a trade at
the top tier, or with a 1 in 5 chance on a freshly restocked one. In addition, a
villager that has crafted on `living_villages_tier_supply_days` (3) separate days at
its current tier, entirely from inputs it bought from villagers or produced itself,
goes up one tier, up to 5. Both routes run; the faster one wins. `production.lua`
counts a craft as village supply when its inputs and fuel all came from belongings:
belongings fill only from the kit, the villager's own work and trades with villagers,
while a stash may hold what a player left. The kit counts, as the village's start.
The days are kept in `_villages_tier_supply` ({tier, days, day}). Going up sets
`_max_trade_tier`, `_max_tradenum` and the badge, mirroring vanilla's file-local
`update_max_tradenum` and `set_textures`.

**Visibility.**

- **Economy tab** on the Builder's bench (`builder_bench_menu.lua`, from
  `economy_report.lua` through `builder.economy`), in two labelled halves. *Heard by
  the Builder*: shortages and gluts, its market news (own and hearsay) summed by item
  with how many villagers and items, and the missing professions: those that make
  what the village is short of when none of that item's producers is present, worst
  (most worth answered) first. *Seen around the bench*: the loaded adult villagers
  within 128: professions present (the keeper and the Builder by role), nitwits and
  the unemployed with today's activity, and goods made and used today and yesterday.
  Made and used come from each villager's tally (`economy_tally.lua`,
  `_villages_tally`): crafts with their inputs and lumps, gathering and charcoal,
  meals. With no Builder loaded nothing is heard; with the economy off it says so.
- **Need bubble** (`need_bubble.lua`). Once a second, a ray from each player's eye
  along its look, 8 nodes; the first object, if an adult villager, shows that player
  a particle of its top need by worth (the first of its ledger's needs, as the
  inspector's Needs line orders them) over its head. A node or another object in the
  way hides it.
- **Census.** `village_census.lua`'s pick takes a `favoured` set whose shares count
  double in the deficit: the stock buildings holding the worst gap's jobsite
  (`economy_report.BUILDINGS`, read from VoxeLibre's schematics: farm, tavern and
  medium house, small house, large house, blacksmith, library, butcher, church; none
  holds a weapon smith's, tool smith's or mason's). The bench menu's choice of a
  schematic source still overrides it. The Builder logs the gap with its choice.
- **Inspector.** `diagnostic.lua` shows a villager's food, clock, belongings, stash,
  needs, surplus, news, labour and crafting, and now its trade tier with the days of
  village supply toward the next and what it made and used today.

## Profession dependencies (VoxeLibre 0.92.3)

From `mobs_mc/villager.lua`'s trade tables. "Buys" are a profession's inputs in this
design; whether the village can supply them decides how well it works without a
player.

| Profession | Buys (inputs) | Village source | Sells (outputs) |
|---|---|---|---|
| Farmer | Wheat, potato, carrot, beetroot, pumpkin, melon | Its own fields | Bread, pie, apple, cookie, cake, stew |
| Fisherman | String, coal, raw fish, raw salmon, boats | Own line; charcoal | Cooked fish, campfire, rod |
| Shepherd | Wool, dyes | Own flock; foraged flowers for dyes | Wool, carpet, beds, banners, shears |
| Fletcher | Sticks, flint, string, feathers | Woodcutter; quarrier's gravel; player | Arrows, flint, bows, crossbows |
| Librarian | Paper, books, ink sacs, writable books | Forager's sugar cane; player | Enchanted books, bookshelves, lanterns, glass, clock, compass |
| Cartographer | Paper, glass panes, compass | Forager; librarian | Maps, frames, banners |
| Armorer | Coal, iron, lava bucket, diamond | Charcoal; **player** | Iron and chain armour, bell, shield |
| Weapon smith | Coal, iron, flint, diamond | Charcoal; **player** | Iron axes, enchanted swords, bell |
| Tool smith | Coal, iron, flint, diamond | Charcoal, quarrier; **player** | Stone and iron tools, bell |
| Leatherworker | Leather, flint, leather pieces | Butcher; **player** | Leather armour, saddle |
| Butcher | Chicken, pork, rabbit, coal, mutton, beef, dried kelp, sweet berries | Forager; charcoal; **player** | Cooked meat, stew |
| Cleric | Rotten flesh, gold, rabbit foot, glass bottle, nether wart | **player** | Redstone, lapis, glowstone, pearls |
| Mason | Clay, stone, granite, andesite, diorite, quartz | Quarrier; **player** | Bricks, polished stone, terracotta |

The renewable core of a village is farmer, fisherman, shepherd, keeper and the
nitwit activities. Smiths, cleric and the iron, gold and diamond side of every
profession depend on the player, which is the core loop: the player mines, the
village turns raw materials into goods.

## Existing code and integration decisions

| Existing code | Use/change |
|---|---|
| `food.lua` | Falling points on the economic clock; eating from pouch and stash; hunger states |
| `farm_stock.lua` | Pouch functions move to `possessions.lua`; chest transfers stay |
| `farmer.lua` | `hand_over` limited to household, children, handout and paying buyers |
| `fisherman.lua` | A catch one cycle in four: cod into its barrel, other fish into its belongings |
| `flock.lua` | Shearing during the work stage |
| `keeper.lua`, `meal.lua`, `player_meals.lua` | Pantry, cooking, paid dinners, paid player meals |
| `gossip.lua` | Market news memory and exchange; demand and hunger terms beside reputation in the `wanted` wrapper |
| `conversation.lua` | No change beyond the exchange it already calls; end-of-conversation trade runs from there |
| `births.lua` | No change; hunger makes its food rule bite |
| `nitwit.lua` | No change; `labour.lua` gives nitwits work through `activity_override`, as the farmer and shepherd do |
| `common.lua` | `activity_override` answers for labour activities |
| `far_trips.lua` | Trade trips and labour sites count as errands |
| `builder.lua`, `builder_status.lua` | Builder posts its missing materials as news and buys them on trade trips; Buy buttons unchanged |
| `builder_bench_menu.lua` | Economy tab |
| `village_census.lua` | Economic weight in the building choice |
| `market.lua`, `bell.lua` | Stalls sell real surplus (ticket 12) |
| `diagnostic.lua` | Shows the economy fields |
| `builder_away.lua` | Unchanged; its stamp pattern is reused by `economy_clock.lua` |

## Saved state

New `_villages_*` entity fields, never to be renamed once released:

| Field | Holds |
|---|---|
| `_villages_econ_clock`, `_villages_econ_stamp` | Economic clock |
| `_villages_food_at` | Clock reading at which food points were last decayed |
| `_villages_belongings` | What a villager owns and carries, emeralds included |
| `_villages_endowed` | Emeralds given |
| `_villages_kit` | The profession whose kit it was given |
| `_villages_stash` | Its stash chest's position (the claim itself is in the chest's meta) |
| `_villages_market_news` | Market news list |
| `_villages_labour` | Today's activity and the day it was chosen |
| `_villages_grove` | Positions of saplings a woodcutter planted |
| `_villages_sapling_day` | The day a woodcutter last took a sapling from under a wild oak |
| `_villages_craft` | Work seconds banked toward the next crafted item |
| `_villages_fuel` | Furnace smelts left from the last coal or charcoal lump burned |
| `_villages_tier_supply` | Days crafted from village supply at the current tier |
| `_villages_tally` | What it made and used today, and yesterday |
| `_villages_trade_trip` | A trade trip under way: item, seller, legs, a porter's client and purse |
| `_villages_builder_wants`, `_villages_builder_drop` | A short Builder's missing priced materials, and its delivery chest |
| `_villages_rent` | Rent owed, the clock reading it was last charged at, the bench, and the last payment |
| `_villages_rent_errand` | A rent errand under way: the bench chest it walks to |

Existing fields reused: `_villages_food`, `_villages_fed_day`. Node metadata:
`villages_owner` and `villages_owner_bed` on stash chests, and `villages_missing`
(what a player took, until the owner looks). From ticket 11b, `villages_landlord` on
beds the Builder built: the bench they owe rent to; and `villages_keeper_tab` on work
chests and barrels: what the keeper still owes there for food.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `living_villages_economy` | true | Turns the whole economy off; villagers behave as before this design |
| `living_villages_hunger_per_day` | 4 | Food points lost per game day of economic clock; 0 turns hunger off |
| `living_villages_stash_radius` | 8 | How far from its bed a villager's stash may be |
| `living_villages_craft_seconds` | 120 | Work seconds per crafted item |
| `living_villages_tier_supply_days` | 3 | Days of village-supplied crafting per tier |
| `living_villages_player_meal_price` | 1 | Emeralds a player pays for a tavern meal; 0 makes them free |
| `living_villages_spawn_unemployed` | 0 | Villagers of a new village left without a job at generation |

## Performance

- The clock stamp is one comparison per `do_custom` call and one write every 10 s.
- Ledgers are computed on demand, over a few dozen items, and cached per clock
  stamp.
- News is capped at 24 entries and shared only when a conversation ends.
- Stash reads touch one chest's inventory, only when a villager eats, crafts or
  trades.
- Labour site searches (berry bushes, generators) run on the route queue, once per
  morning, with the result cached on the villager for the day.

## Testing

Each new module gets a test in `tests/` that stubs the engine, as the existing ones
do. `ledger.lua`, `production.lua`'s recipes, `economy_clock.lua`'s gap rule and
`exchange.lua`'s settlement are pure and tested directly. A test checks every
recipe output against `trade_tables.lua`. `tools/lv_probe` gains an `LV_PROBE_ECONOMY`
mode that runs a village for several game days and logs per-day production,
consumption, trades, news spread and food levels, so pacing can be tuned on real
villages. `docs/economy-scenarios.md` holds manual in-game checks for what neither
can prove: the paid meal, theft gossip, the Economy tab and need bubbles.

## Tickets

Each ticket is one PR against the fork's `main`, on a `feature/economy-<n>-<slug>`
branch, and each leaves the game playable with `living_villages_economy` on or off.

| # | Ticket | Depends on |
|---|---|---|
| 1 | Economic clock, hunger, pantry dinners, paid player meals, the keeper's supply trips and cooking | — |
| 2 | `possessions.lua`: pouch for every villager, emeralds, stash claim and succession, starting stock | — |
| 3 | `tools/extract_trades/`, `trade_tables.lua`, `ledger.lua` (pure) | 2 |
| 4 | Farmer's distribution rules; fisherman's fish; shepherd's shearing | 1, 2, 3 |
| 5 | Market news in gossip | 3 |
| 6 | End-of-conversation exchange | 4, 5 |
| 7 | `labour.lua`: activity choice from news; forager and woodcutter | 5 |
| 8 | `production.lua`: jobsite crafting; restock tied to working | 3 |
| 9 | Demand and hunger price terms; tier advancement from village supply; theft gossip | 3, 8 |
| 10 | Economy tab, need bubble, inspector fields, census weight | 5 |
| 11 | Quarrier, porter, trade trips; the Builder buys from villagers | 6, 7 |
| 11b | Rent to the Builder's bench; dinner and rent logging; emeralds in the probe census | 1, 11 |
| 11c | Donations at the holiday service, alms, gossip about villagers | 6, 11b |
| 11d | `wants.lua`: goods that wear out; stone tools | 3, 8 |
| 11e | Leather: the leatherworker's cow herd, books, cooked meat | 4, 11d |
| 11f | Staffing a new village: every job and bed assigned at generation | — |
| 11g | Trade trips that finish: on into the work stage, sellers that can make up an emerald, chasing a seller that moves | 11b |
| 11h | Prices and the money supply times 64; player trades scaled; emeralds stack to 4096 | 11g |
| 12 | Peddler; holiday market sells real surplus | 6, 11 |
| 12b | Market fixes: stall walks after the bell walk, stalls that show wanted goods, empty stashes remembered, peddlers that get chosen | 12 |
| 13 | Prices that move with supply and demand, each villager its own | 12b |
| 14 | The mod's own trade window in place of vanilla's trades | 13 |
| 15 | Needs by purpose (food, fuel, logs, planks), a few conversions at sale, the butcher cooks fish | 14 |
| 16 | The woodcutter: a chopping block, generated and craftable, and a grove that grows | 15 |
| 17 | The food loop: keeper's supply, food targets, the butcher's sales | 16 |
| 18 | Farm output: hoes multiply the harvest, tending, sowing for the village | 17 |
| 19 | Money that circulates: comforts for savings and the cleric's share (19a), idle crafters labour (19b), new goods from existing professions (19c), quarries players build (19d) | 18 |
| 20 | The alchemist: its stand and role (20a), cost-based prices (20b), alchemy at the stand (20c), trades with players (20d) | 19 |
| 21 | Price discovery: the money factor and gifts (21a), reference prices that learn (21b), players at the villagers' prices (21c), production by margin (21d), a dinner that floats (21e) | 20 |

### 1. Clock, hunger and the tavern

`economy_clock.lua`; falling points and hunger states in `food.lua`;
`tavern_pantry.lua` (the chests within 6 of the jukebox); `meal.lua` serves only what
the pantry holds and feeds the villager guest; `player_meals.lua` charges the player
into the pantry. Villagers have no emeralds before ticket 2, so they eat from the
pantry free. Hunger only sets the state here: its effects come with the tickets that
add what they act on (production in 4 and 8, prices and restocks in 8 and 9).

Every generated tavern already has a pantry: the stock schematic's chest stands 3
behind the jukebox, filled with ordinary village loot. So the pantry's supply lands
in the same ticket, or existing taverns would stop serving. `keeper_supply.lua`: in its
free hours, while the pantry holds fewer than 12 meals, the keeper walks to the work
chest of a farmer within 48 of the jukebox and carries back up to 24 bread, potatoes
and wheat; on shift it cooks one dish every 10 s (three wheat to a loaf, a potato
baked, a cod cooked); and a newly generated tavern's chest gets a starting stock on top
of its loot. Ticket 4 later turns the fetching into buying. A tavern with no chest (a
player's own) serves as before: a display that feeds no one and costs nothing.

Done when the tests show points falling with the clock and not without it, a pantry
dinner feeding its guest and emptying the pantry, an empty pantry serving nothing, a
player paying into the pantry or not being served, and the keeper fetching, delivering
and cooking; and a probe run shows a generated tavern's pantry stocked.

### 2. Possessions

`possessions.lua`: belongings apart from the work pouch, emeralds, kits, the stash
claim with its work-chest exclusions and succession, drop on death; stashes left out of
`farm_stock.find_chests`. `keeper.lua`'s `take_over` drops the old job's pouch instead
of deleting it. Villagers still eat at the tavern free: with no income before tickets 4
and 6, paying for dinner would only run their emeralds out. Done when every villager
owns its emeralds and kit after first activation, claims a stash by its bed that no
work chest is, and drops its belongings on death.

### 3. Prices and ledger

The extraction tool, the generated table, the hand table for unlisted items, and
`ledger.lua`'s targets, need, surplus and value. Pure; no behaviour change yet,
beyond the inspector showing each villager's top needs and surplus
(`possessions.assess`, from its belongings, stash and food).

### 4. Food distribution and real goods

`farmer.lua` household, handout and selling; the keeper buying at work chests and
barrels; eating from belongings and stash; fish per cycle into the barrel; shearing.
Villagers still dine at the tavern free: only farmers and fishermen earn yet, so
paying would run everyone else's emeralds out before ticket 8 gives them something to sell.
Done when a farmer sells bread to a neighbour for emeralds, the keeper pays for what
it fetches, and a farmer still feeds its children free.

### 5. Market news

`_villages_market_news`, its exchange in `gossip.exchange`, listener-weighted
choice, decay. Done when a probe run shows a need spreading from one villager to
most of a village within two game days.

### 6. Exchange

`exchange.lua` settlement; end-of-conversation trades. Done when two villagers who
meet trade goods both value and their pouches show it. Villagers still dine at the
tavern free: trading moves goods between them, but most professions make nothing to
sell until ticket 8, so paying for dinner waits for that ticket.

### 7. Labour

`labour.lua` choice and the forager and woodcutter activities. Done when nitwits and
the unemployed gather and sell, and the share choosing wood falls after its price does.

### 8. Jobsite crafting

`production.lua` recipes and crafting over the clock; restock wrapper. Done when a
toolsmith without inputs stops restocking and one with inputs makes tools.

Landed with it: `recipes.lua`, read by the ledger too, so crafting professions want
and buy their inputs; charcoal counted as coal and burned by woodcutters; cooked meat
as food; the kits topped up; and villagers paying an emerald for tavern dinners, now
that every crafting profession has goods to sell.

### 9. Player-facing prices and tiers

Demand and hunger terms in the `wanted` wrapper; tier advancement from supply;
theft gossip. Done when a player sees a scarce good's price rise and a supplied smith
climbs a tier with no player trade.

Landed as `demand.lua` (applied in `gossip.lua`'s priced window), the tier count in
`production.lua`, and `theft.lua` (wrapping the chests' take callback).

### 10. Visibility

Economy tab, need bubble, inspector, census weight.

Landed as `economy_tally.lua`, `economy_report.lua` (read by `builder.economy` for the
tab and the census), `need_bubble.lua`, the tab in `builder_bench_menu.lua`, `pick`'s
`favoured` in `village_census.lua`, and the inspector's `Trade tier` and `Today` lines.
The Builder, a mason to vanilla, no longer crafts or wants as one. `docs/economy-scenarios.md`
holds the manual checks.

### 11. Trade trips and the Builder

Quarrier and porter activities; trade trips through `navigation.lua`; the Builder
posting and buying materials. Done when a Builder in `requires_materials` gets cobble
from a quarrier without a player.

Landed as the quarrier and porter in `labour.lua`, `trade_trips.lua` (installed in
`init.lua`, which also hands it the end of each conversation for hiring),
`builder_market.lua`, `exchange.offer`'s single-item form, the trade trip as a
`far_trips.lua` errand and a busy field for `conversation.lua`, and the inspector's
`Trade trip` and `Builder wants` lines.

### 11b. Rent

Rent owed to the Builder's bench by the tenants of its houses and, in a generated
village, by farmers and fishermen; paid at the end of a conversation with the Builder,
or by errand to the bench chest. The keeper pays for food what it sells for as
dinners, with a tab for fractions. Dinner and rent payments logged; the probe census
records the emeralds of each villager, the pantry and each bench chest; the
inspector's `Rent` line. Done when a probe run of six game days,
with ticket 11's staging (a small house and a cobble generator), shows rent reaching the
bench from farmers and fishermen and the Builder spending it on materials without a
player, and the census shows where the village's emeralds sit on each day. (Finishing
the house was dropped: it also needs planks, logs, glass panes, carved stone brick and a
bed, which no villager sells yet; see Open questions.)

Landed as `rent.lua` (installed in `init.lua`, settled at the end of each conversation
before the exchange), `builder.lua` marking a finished building's beds, the keeper's
dinner pricing and tab in `keeper_supply.lua`, dinner logging in `meal.lua`,
`possessions.is_food_chest` keeping farm and pantry emeralds out of rent and the
Builder's purse, the keeper delivering at its jukebox, and the probe census's daily
emerald line (`farms` for chests beside a composter). Rent errands and trade trips go on
once they stand where their walk was headed, since `navigation.lua` could drop a walk's
arrival callback when another mover took the villager over. It no longer does: a walk
taken over where it was going counts as arrived, and any other walk that ends short
(taken over, canceled, superseded, or with no route found) calls the `lost` handler of a
gopath callback given as `{arrived = fn, lost = fn}`. Both errands walk again at once on
a lost walk, rather than waiting out their timeout. Run 32 (seed 2007, chunk
208,768) showed farmers paying rent on days 5, 6 and 7, the Builder taking it from the
bench chest each time and buying 28 and then 15 cobble from the nitwit with it.

### 11c. Donations and alms

Donations to the cleric at the end of the holiday service, from attendees with savings;
good gossip about the donor, using villager ids as gossip subjects, with their own share
of what passes in a conversation; standing moving `exchange.lua`'s price by up to a
tenth; alms to attendees who cannot pay for a dinner. Done when a probe run over a
holiday shows a farmer donating, the cleric keeping half, a broke villager getting alms
and then buying a dinner, and the donor's standing spreading in conversation.

Landed as `alms.lua` (installed in `init.lua` after `gossip.lua`), villager subjects in
`gossip.lua` (`villager_subject`, with their own `VILLAGER_SHARE_ENTRIES` share) and
`exchange.unit_price`. Merged on tests and an engine load check, without a probe run.
Choices the design left open:

* The cleric does it all, every second of the social stage, among the villagers within
  12 of its pulpit (church.lua's social radius): donations first, so a gift can go out
  as alms the same day. Anyone there counts as an attendee.
* `SAVINGS` is 8 dinners (144) and a major gift 2 dinners (36): the design's 8 and 5
  emeralds came before ticket 11h scaled money by 64.
* Witnesses note `minor_positive` for every gift, and `major_positive` too for a major
  one. As in Java, `major_positive` costs more to share than it can hold, so only the
  minor entry spreads.
* Standing moves the midpoint by up to a tenth at a reputation of 100, the buyer's
  liking raising it and the seller's lowering it, never past either side's value.

### 11d. Goods that wear out

`wants.lua` and its reading in the ledger and the work loops; stone hoe, axe and
pickaxe. Done when a probe run shows a farmer, woodcutter or quarrier buying a stone
tool from the tool smith, working faster with it, and buying another once it wears out.

Landed as `wants.lua`, read by `possessions.assess`, `labour.lua` and `farmer.lua`, with
changes in `ledger.lua`, `production.lua`, `market_news.lua` and `trade_trips.lua`. Probe
runs 44 to 48 (seed 2007, chunk 208,768) showed a farmer taking a trade trip for a stone
hoe, buying it for 67, harvesting with it and wearing it out; the second purchase is not
yet shown. Choices from those runs:

* Only a villager still labouring wants a labour tool (run 45).
* A heard ask counts as at least its price when the tool smith chooses what to make, and
  a crafter makes an output nobody asks for and it has no target for only while it holds
  none (runs 46 and 48), so its sticks go to the hoe.
* A trade trip reads the uncapped urgency: a tool's value is capped at its worth, which
  kept urgency below the trip threshold (run 46).
* Market news always tells a surplus someone has asked for (run 47).
* News also passes at the tavern (`meal.lua`): once an evening a seated villager swaps
  market news with the keeper on duty, served or not, so the keeper carries one diner's
  need to another's supply. In run 50 the farmer had four conversations in three hours
  and never heard of the tool smith's hoe, which it posted as a need all along. The
  cleric does the same for its congregation once a holiday (`alms.church_news`), in the
  pass after the service: the service allows no conversations, and the social stage
  after it lasts seconds.

### 11e. Leather

The leatherworker's cow herd, books in `wants.lua`, cooked meat on the tavern menu.
Done when a probe run shows leather reaching the librarian from a herd, a book made
from it bought and read, and beef reaching the butcher and, cooked, the tavern.

Landed as `herd.lua` (installed in `init.lua` after `production.lua`), the book in
`wants.lua` (`BOOK`, `reading_rate`), the butcher's cooked beef in `recipes.lua`, a
keeper input and menu dish, and `keeper_supply.shelve`. Merged on tests and an engine
check of the herd (seeded, a calf bred, one slaughtered), without a probe run. Choices
the design left open:

* The herd is kept, not led: up to 4 adults within 32 of the leatherworker's jobsite,
  wild adults within 16 taken on, 2 cows seeded once for a herd that never had one, and
  a stray past 24 that no player sees set back. No following, unlike `flock.lua`.
* Breeding does not wait for vanilla's mating: every 300 s of the work stage two wheat
  make a calf (`mcl_mobs.spawn_child`) while the herd has room; past 4 adults it
  slaughters one instead, its drops (1 to 3 beef, 0 to 2 leather) going into belongings.
  The leatherworker wants 4 wheat held, which it buys like any need.
* The leatherworker's armour recipes are gone: they held a batch of 32 leather back from
  the librarian for armour no villager wears. Its player trades need no stock.
* A book lasts 3 days of game time from when it is opened, at its owner's next work, and
  speeds harvesting, labour and crafting by a fifth. Every adult wants one; its worth is
  that fifth of four dinners a day.
* The keeper buys cooked beef as a need (up to 6) and shelves it in the pantry on its
  shift; it is on the menu at 2 for an emerald. It is priced at the ledger's value, not
  one dinner a piece. It pays with the tavern's money: on shift it tops its own emeralds
  up to 8 dinners from the pantry (`keeper_supply.float`), where dinner money goes.

### 11f. Staffing a new village

`village_staffing.lua`: staffing at generation (see Staffing a new village), the
`living_villages_spawn_unemployed` setting, the nearest-to-bed rule for later job seekers
in place of `farm_jobs.lua`. Done when a probe run on
seed 2007 chunk 208,768 shows, before the first morning, every job block claimed by
the villager whose bed is nearest it, the Builder and the keeper among them, the set
number left unemployed, and no villager changing job on day 1; and when a grown child
takes the free block nearest its bed.

Landed as `village_staffing.lua`, `job_blocks.lua` (the block kinds, their claims and the
greedy pairing) and `job_seek.lua` (in place of `farm_jobs.lua`, with
`navigation.seek_job` planning only to the chosen block). Choices the design left open,
most from probe runs 38 to 42 (seed 2007, chunk 208,768):

* The bench and the jukebox are paired first, then the rest closest-first. In run 38 the
  tavern stood apart from every bed, so closest-first left the jukebox free, and that
  evening `keeper.lua`'s take-over moved the fletcher off its table. The cost: a keeper
  may not be the bed nearest its jukebox (run 42's second village, rank 3 of 7).
* The villagers the setting leaves out carry `_villages_left_unemployed`. No job module
  gives them a block later (`job_blocks.eligible`, and the bench, jukebox and pulpit
  checks); otherwise they would take a free one within seconds. Those left without a
  block only because blocks ran out are not marked, and take one built later. The
  setting leaves at most half a village out: run 40's one-villager village was left
  with no one working.
* A villager not loaded when its village is staffed is paired by its bed's meta id: its
  block's meta holds its id and mod storage the rest, finished when it loads
  (`apply_pending`). In run 40 a village placed during a 21 s lag spike was staffed
  with 1 of its 8 villagers, and its Builder then took the bench on its own.
* `job_seek.lua` measures only from the bed. Vanilla clears `_bed` for a while in
  places, and in run 39 a grown child scanned from where it stood and took the block
  beside it. A villager without a bed now waits up to a game day before it looks from
  where it stands, and a block chosen so is dropped once the bed is back.
* The pulpit is a job block too, claimed through `cleric.lua`.
* One composter, the one nearest any new villager's bed, is paired first with the bench
  and the jukebox. After 11f seed 2007's village had no farmer, since every bed had a
  nearer block, and its food comes from farmers.

Runs 39 to 42 each staffed the village at generation: 9 of 11 villagers, each owner's
bed the nearest of the 11 to its block, the Builder and the keeper among them, 2 left
unemployed, and no villager changing job on day 1. In runs 40 to 42 a child, staged with
a fletching table by its bed and a stonecutter beside where it was born, grew up and
took the fletching table. Run 42 also generated a second village with no one near and
staffed all 8 of its villagers.

### 11g. Trade trips that finish

Runs 33 and 34 (seed 2007, chunk 208,768) showed trade trips rarely ending in a sale,
for three reasons, and this ticket answers each in `trade_trips.lua`:

* Too little time. An ordinary villager travels only in the putter stage, about 75 s of
  real time, and a trip from an earlier day is dropped: every bread trip in run 34 was
  dropped unfinished the next evening and planned again. A trip already under way now
  goes on in the next work stage too, with `trade_trips.activity_override` keeping
  vanilla from calling the villager back to its jobsite, and is dropped only once the
  day after the one it was planned on is over. New trips are still planned only in the
  putter stage (the Builder and porters as before).
* Sellers that cannot make up an emerald. A sale must come to a whole emerald that both
  sides gain by (`exchange.lua`); in run 34 a wool trip reached a seller with 1 spare,
  worth 0.42 at the midpoint, and could not buy. A trip is now planned only from news
  whose count, at the midpoint of the two values, meets `M.terms` with the buyer's
  emeralds: the rule a stash sale already uses. A seller passed over is logged once a
  day with the count heard and what it carries now. Run 35 then planned no trips at all,
  and run 36 showed why: heard counts matched what sellers carried (4 coal heard, 4
  carried), but at today's prices such sales come to under an emerald (4 coal at 0.13
  each, 1 spare loaf at 0.32). The check is right; prices are too small for whole
  emeralds, which ticket 11h's rebalance answers.
* A seller that moves. In run 33 the Builder chased a nitwit gathering cobble and timed
  out walking to where it had stood. While chasing, a walk is aimed afresh, counting as
  a chase, once the seller has moved more than `SELLER_REACH` from its target.

Done when tests show a trip planned in the putter stage going on in the next work stage
and dropped the day after, sellers too small for a sale passed over, and a chase
re-aimed; and a probe run on seed 2007 chunk 208,768 shows no trip ending "no offer"
for want of a whole emerald. Trips that buy cheap goods wait on ticket 11h.

### 11h. Prices and the money supply

`ledger.SCALE` and every amount in Prices and the money supply; the player trade
scaling in `gossip.lua`'s pricing step; the emerald's `stack_max`; the farmer's food
sale by price; the one-time top-up of existing villagers. Done when the tests pass at
the new scale (a stick worth 2, a new adult holding 192 to 384), a test shows a player
trade window charging 64 times vanilla's emeralds and an emerald stack of 4096, and a
probe run on seed 2007 chunk 208,768 shows trade trips for coal or bread buying in
person, rent and dinners paid at the new amounts and the census adding up.

Landed as `ledger.SCALE`, the scaled constants in `rent.lua`, `keeper_supply.lua`,
`meal.lua`, `player_meals.lua`, `trade_trips.lua`, `builder_market.lua` and `labour.lua`
(the porter's income), `builder_materials.sale_price`, the farmer's 64-emerald bundle,
`gossip.lua` scaling the trade window and the emerald's stack, and
`possessions.endow`'s one-time top-up. Run 37 (seed 2007, chunk 208,768, stopped on
day 5) showed a single loaf sold in conversation for 20 emeralds, a trade trip buying
one wool for 26 (in run 34 the same sale came to 0.42 of an emerald), both farmers
paying 64 rent, dinners at 64, and the census at 3328 emeralds every day.

### 12. Peddlers and the market

Peddler activity; `market.lua` stalls stocked from real surplus; browsers buy. The
cartographer's banners (wool and a stick) sell to villagers decorating for the market.

Landed as `market_stall.lua` (handed to `market.lua` by `init.lua` with the economy on),
the peddler in `labour.lua`, a value floor in `ledger.assess` (`least`), the banner and
peddle wants in `possessions.assess`, and the cartographer's recipes. Merged on tests and
an engine load check, without a probe run. Choices the design left open:

* A stall shows its seller's top two spare goods that it carries, by value. One with
  nothing spare shows the old fixed pair for its profession and sells nothing (12b:
  it now keeps no stall); a nitwit
  with nothing spare stays a browser, and one with spare goods, a peddler among them,
  now keeps a stall.
* Browsers buy by exchange.lua's rules, for the stall's goods alone: every 5 s the
  seller offers them to the adults within 6, each once a stall day. Other sellers do
  not browse.
* A peddler's deal is an item heard spare at one price and needed at 1.5 times that or
  more by another villager. Its lot is as many as both sides and its emeralds allow, up
  to 16, and its bid a third of the way from the asking price to the need's. Buying
  goes through its own trade trips and conversations: its ledger wants the lot, valued
  at the bid and no more. Holding the lot, or after a day, it sells at no less than the
  bid, through conversations, buyers' trips and its stall, for up to 4 days in all.
  It gathers nothing while peddling.
* A banner lasts 4 market days. A villager that kept a stall in the last 3 days and
  has none flying wants one, worth no more than its price. Only white banners, from 6
  white wool and a stick; the banner is not placed on the stall yet, only logged.
* The stall site search samples 144 spots instead of 48, and up to 3 nodes above and
  below the bell's floor instead of 1: in manual testing a village's sellers found no
  site at all. A search that finds none logs why its candidates were turned down.
* A villager with no bed (a village often has more villagers than free beds) found no
  work at all, since every activity's radius was from its bed. It now works from the
  nearest bell, or where it stands when it chooses its day.
* A porter's expected income was a flat two fees a day, so every unemployed villager
  portered, unhired, over any peddling deal (run 52). It is now one fee per hire per
  porter day it has had, from one in two. A seller the market skips (busy walking, or
  not eligible) is logged, and a stall's opening names its seller and goods.
* In a hilly village most villagers never came to the market: the bell was looked for
  within 48 across and 16 up or down of each bed, and a bell on a hill 18 above the
  beds was out of reach (run 52). It is now 64 and 32, and a villager that finds none
  logs it once a holiday. Villagers also walk at 1.8 m/s by default instead of 1.2
  (`living_villages_walk_velocity`), so a spread-out village's walks fit their stages.
* For testing by hand, `/living_villages_market` (`market_test.lua`) opens the market
  now as on a holiday, or starts a working day with labour chosen afresh.

### 12b. Market fixes

The Markets world (2026-11-10 and 11, game days 20 to 45, 12 to 16 adults) showed the
market and peddlers doing almost nothing:

* 37 seller set-ups failed with "no route to stall"; on day 44 all 12 within a second.
  A seller starts its stall walk while it still walks to the bell, and `gopath` refuses
  a request while a walk is in progress, which `start_market_walk` took as no route.
* 17 stalls opened and no villager bought at one. They showed wheat seeds, glass
  bottles, saplings, a stone shovel and iron armour: the seller's spare goods by value,
  which nobody needed.
* The keeper set off 15 times for cooked porkchop from the butcher's empty stash.
* No villager ever peddled. Deals were heard (wool at 14 needed at 28, porkchop at 10
  needed at 22), but the unemployed chose woodcutting every day, even with no grove.

The fixes:

* A seller that gopath cannot answer yet (still walking, or waiting out an earlier
  failed path, which VoxeLibre holds for 30 s) waits up to 45 s for its stall walk
  instead of giving the stall up (`market.lua`).
* A stall shows the spare goods its seller heard someone needs first, by the asking
  price, then the rest by value (`market_stall.lua`).
* A trip that finds a stash empty forgets the news of that spare and passes the seller
  over for a game day, not 600 s (`trade_trips.lua`).
* Gathering is reckoned at what it has yielded, as portering is at its hires: an
  activity's rate is scaled by what it gathered over the days it was chosen, counted
  from one day at the full rate (`labour.lua`, `_villages_gather_record`). A woodcutter
  was reckoned at ten logs a day, about 430 emeralds, against about 90 for the wool
  deal, while it felled four logs in eleven days.
* The stall walk goes to the seller's cell, not its feet: on a grass path (15/16 high)
  the feet are 0.55 below the cell and gopath rounded the goal into the path, "no safe
  standing space", for every seller of the Markets world's paved square.
* A refused walk waits out its retry only for the same goal (`navigation.lua`): the
  failed stall walks' retry also refused the bell walk 30 s later, and those villagers
  gave the bell up for the stage.
* A bell is looked for within 80 of the bed, not 64: the Markets world's eastern
  houses are 66 from its hilltop bell.
* A villager with nothing spare keeps no stall and browses. The fixed pair for its
  profession sold nothing and took a place on a square that held about 8 stalls.
* A seller at its own stall browses its neighbours' stalls: the cartographer, keeping
  a stall, never met the shepherd's wool it needed.

### 13. Prices that move

A base price comes from vanilla's tables and never moves (`ledger.lua`); a villager's
need moves its value from 0.5 to 3 times it. Needs nobody in the village can supply
(apples, berries, iron) sit at the full urgency and change nothing, and surplus nobody
wants (fish in the Markets world) never gets cheaper.

There is no village-wide price (Principle 3). Each villager keeps its own multiplier on
the base price (`prices.lua`, `_villages_prices`) and values an item at base price times
its multiplier times its urgency (`ledger.assess`'s `prices`):

* Once a game day, at the first conversation it finishes (`market_news.exchange`), its
  multipliers move with the news it has heard and its own needs and spare: times
  1.5 ^ imbalance, imbalance = (demand - supply) / (demand + supply + 4), the counts
  summed over the villagers it heard of and itself. A good nobody makes reaches 8 times
  its base in about five days; surplus nobody wants falls to an eighth.
* An item it heard nothing of drifts back toward the base (its multiplier to the 0.8).
* In every finished conversation the members' multipliers move a quarter of the way
  toward their geometric mean, so prices spread by gossip as news does and villagers
  that rarely talk can still disagree.
* Trades do not move them: a trade's price folds in both sides' urgency, and learning
  from it would turn a buyer's need into a lasting belief.

Everything that reads a value reads the new one: market news, trades, peddling deals,
labour incomes, stall goods, and the player's prices through `demand.lua`'s urgency.
The emerald amounts that do not move anchor the rest: the dinner (`ledger.DINNER`),
rent, a porter's fee and a new adult's emeralds, so prices move against each other and
an emerald keeps its worth. Each move is logged ("prices: villager ..., day ...") with
the furthest-moved multipliers, also shown in the inspector.

### 14. The mod's own trade window

Vanilla's trade tables, tiers and rare goods (enchanted books, diamond gear) are
dropped from player trade, to be brought back once the economy works. Talking to a
villager opens a window of its own:

* **It sells** its real spare goods, taken from its belongings, at its value.
* **It buys** what it needs, at what it would pay, up to the emeralds it holds. This is
  how the player takes part: a villager in need is a standing order.
* ~~**News**: a few needs it heard from others (market news), as a pointer to who wants
  what.~~ Dropped in ticket 16 at the user's request: it cluttered the window.

Reputation (`gossip.lua`) moves both sides' prices, as it does now. Selling a villager
something it needs is good gossip, more the more urgent the need. Below a threshold a
villager will not trade with the player at all.

Landed as `trade_window.lua`, installed after `gossip.lua` so it decides first on a
right-click. Choices:

* It sells at its value times 1.25 and buys at 0.9 of it, from the emeralds in its
  pouch; goods worth under an emerald come in lots that make one.
* Reputation moves both by a quarter of a percent a point, at most 25%. At -40 or
  below (two thefts seen) it will not trade. Every trade is "trading" gossip; filling a
  need at urgency 2 or more is "minor_positive" too.
* Every adult but the keeper and the Builder uses it, unemployed villagers and nitwits
  included, who had no trades before. `_trades` is left alone, since vanilla and
  `job_seek.lua` read it as the mark of a villager that keeps its job.
* Trades are logged ("trade window: <player> bought|sold ...").

### 15. Needs by purpose and conversions

The Markets world on day 56: not one villager's spare good matched another's need.
Apples were at 8 times their base for every villager, while four fishermen sat on raw
fish nobody wanted and the mason on birch logs the librarian, wanting oak, could not
use. Three causes: needs name one item where any of several would do; nobody turns one
good into the one that is needed; and nobody cooks fish.

**Needs by purpose.** Some needs are for an amount of something, and any item that gives
it counts:

| Category | Measured in | Members | Comes from |
|---|---|---|---|
| Food | food points | `food.POINTS` | hunger: a day's when starving, two days' when it holds over 5 dinners' emeralds (ticket 17) |
| Fuel | burn seconds | coal 80, charcoal 80, dried kelp block 200, any log 15, any planks 15, stick 5 | recipes that smelt (`fuel`), the butcher's kelp blocks (19g) |
| Logs | logs | any species | recipes, the Builder |
| Planks | planks | any species | recipes, the Builder |
| Wool | wool | any colour | the Builder's red beds (19i); the cartographer's banner takes white |

What a need is for decides its category: every coal need today is a smelting recipe's
fuel, so any fuel does. A recipe that uses coal itself (torches) asks for coal. Each item
keeps its own price (ticket 13): a category sets how much is needed, how urgent it is
and which items count. A buyer takes the member that gives the most of the need for its
price, so cheap fish feeds a village and apples stop being needed by everyone at once.
Needs and surplus are reckoned on the category, then put on the items: the members held
most of are the spare ones.

**Conversions at sale.** A few goods become another when a villager sells them to a
villager: instantly and for free, from the seller's spare source goods, in conversation
trades, at stalls and on trade trips. Used sparingly: each job has a short list, and
none is for food.

| Job | From | To | Ratio |
|---|---|---|---|
| Shepherd | wool (any colour) | string | 1 to 4 |
| Woodcutter (labour) | any log | planks | 1 to 4 |
| Mason | stone | carved stone brick | 1 to 1 |

Market news tells what a villager can supply after its conversions, so a fisherman in
need of string hears of the shepherd. This also starts the Builder's missing materials
(Open questions, 2026-11-09 directions).

**The butcher cooks fish.** Food is not converted: the butcher buys raw meat and fish and
cooks it in its smoker (`production.lua`, `recipes.lua`), using fuel, and sells it cooked.
Raw cod and salmon become its inputs and cooked cod and salmon its outputs. Pufferfish
and clownfish are not food and nobody buys them; the fisherman values them low.

**One cook for each food.** Only the butcher cooks meat and fish, and only the farmer
bakes bread. The keeper stops turning wheat into loaves and raw cod into cooked cod: it
fetches bread and potatoes from the farmers' chests, buys bread, cooked cod and cooked
beef as ledger inputs, and cooks only baked potatoes itself (`keeper_supply.lua`). A new
tavern's pantry starts with nine loaves in place of six loaves and nine wheat.

**Any species in recipes.** The categories decide what fills a need (ledger, news,
trades); production must take the same goods. A recipe written with oak logs or planks
takes any log or planks, the species held most first, and planks split from a log are of
its species (`production.lua`). Markets showed why: the cartographer bought 14 white wool
for banners, but the only woodcutter cut birch, and the stick recipe wanted oak.

**Wheat for the herd.** A farmer's crops stay in its pouch and work chest, which are not
goods it trades, so no villager could buy wheat and the leatherworker's herd never bred.
With the economy on, a farmer keeps up to 8 wheat over its keep in its belongings when it
deposits, for sale (`farmer.lua`).

**Bread for sale** (run of 2026-11-14). Buyers reached both farmers once trips fell back
to the seller's stash, and found nothing spare, while one farm chest held 27 loaves and
299 potatoes that only the keeper took. At its own chest a farmer now takes bread up to
16 and then potatoes up to 16 into its belongings, for sale, from what the chest holds
over 24 meals (the keeper's carry), so food reaches villagers who buy it themselves.

**The herd stays home.** A herd cow past 10 blocks from the leatherworker's jobsite walks
back; past 20, unseen, it is set down beside it. Only a herd down to fewer than two takes
on wild cows that come within 16, until it has two: a player can lead cows in to restart
one (`herd.lua`).

**Players.** No conversions in player trades. The categories still apply: a villager
that needs food buys any food the player brings, at its price for that item, and the
window shows such a need as a category ("food, 24 points") with the player's matching
items to sell.

### 16. The woodcutter

Only a villager with no job cut wood (`labour.lua`), so a village's wood fell as its job
blocks rose. The Markets world had one labourer among 16 adults, and the cartographer,
librarian, tool smith, Builder and the smiths' fuel all wait on logs. A woodcutter by
trade cuts wood whatever else the village does.

**The chopping block** (`chopping_block.lua`). An oak stump, tinted, that is no log: out
of the `tree` group, so it makes no planks, is never felled and is no wild tree, and an
axe does not strip it. A player crafts it from any log and a stone axe and places it
like any job block. Village generation puts one where the loom stood in some loomless
small houses (`loomless_house.lua`): half of them by default
(`living_villages_chopping_block_house_chance`), a quarter of all small houses.

**The role** (`woodcutter.lua`). VoxeLibre takes no new profession, so the woodcutter is a
role on the nitwit, which has no trades or workstation of its own, as the keeper is one
on the butcher. It claims the block through the node meta `villager`, which is all
vanilla's validate_jobsite checks, so vanilla keeps the jobsite and never hands a nitwit
another job. `_villages_woodcutter` marks it, recovered on activation for a nitwit whose
jobsite is a chopping block naming it. Without its block it is unemployed again and
looks for work. `job_blocks.lua` hands blocks out like any other: `village_staffing.lua`
when a village is placed, `job_seek.lua` to a villager out of work.

**The work** is `labour.lua`'s woodcutter activity every day, with no choice: its grove
is around the block (not its bed), up to GROVE_MAX_JOB (12) trees, felled and replanted,
logs past what it keeps burned to charcoal, logs sold as planks when a villager asks
(ticket 15). Through the work stage get_activity answers "chop" for it, so vanilla does
not call it back to the block between trees.

**A grove that grows.** A felled tree gave back one sapling, which was replanted, so a
grove never grew past its first tree; Markets' labourer felled four logs in eleven days.
Now a felled tree gives a second sapling while the grove is short of trees, as its leaves
would drop, and a grove short of trees with no sapling to plant takes one from under a
wild tree, once a day. This holds for labourers too.

Left for later: a woodcutter in a treeless biome waits for a player to bring saplings,
which it does not yet ask for; and the nitwit's skin, which it keeps.

### 17. The food loop

The Colony run (2026-11-13: two farmers, a fisherman, a butcher and a keeper) ran out of
food though food was made every day. Supply came to about a quarter of what villagers
ate. The causes:

* villagers ate whenever they fell to 8 points, at any hour, whatever they held;
* the fisherman's cod went to its barrel, which the keeper no longer fetched, and was
  lost past 16;
* the farmers gave bread away (household, bundles, handouts), so the keeper found its
  chests empty;
* trades settled at the midpoint of the two values, and a buyer's value carries its
  urgency and price beliefs. A hungry village valued a cooked salmon at four times what
  the butcher did, the butcher was paid half of that, and a keeper holding 144 emeralds
  bought nothing from a butcher who would have taken a third of the midpoint.

**One dinner a day** (`possessions.lua`). An adult at or below 8 points eats once a day,
at dinner: at the tavern when it can reach one and pay (`meal.lua` marks
`_villages_dined_day`), or else from its own prepared food at home (`food.is_prepared`:
not raw crops or apples), until above 8. Outside dinner, and raw food, only when
starving (0 points), and then only up to 4. Hunger falls 4 points a day, so one dinner
covers it.

**Skipped nights count** (`economy_clock.lua`). Hunger runs on the economic clock, game
seconds while a player is near. Skipping a night (players sleeping, or a test world's
`lv_keep`) moves the time of day but not game time, so a skipped night cost no hunger: about
2.3 points a calendar day instead of 4, and only every other dinner was eaten. Now each
stamp notes the calendar too, and a jump while the villager stays active adds what the
calendar ran past game time, up to a day. A village nobody is near still neither hungers
nor pays rent; production keeps only time in its work stage, so a skipped night is no
extra crafting.

**Starving hurts.** A starving adult walks at 0.7 times its speed and stops work at
12500 instead of 15500 (`common.lua`, `STARVING_WORK_END`).

**Buying food** (`ledger.lua`). A villager needs a food stock only when it holds more
than 5 dinners' emeralds (90): then two days' hunger (`STOCK_DAYS`). One starving needs
a day's. Others rely on the tavern; the broke on alms.

**Births** need both parents to own 8 food points or more (`possessions.can_parent`,
with `living_villages_births_need_food`), a sign the village eats well. A birth spends
neither the food nor the parents' hunger. The bed rule stays.

**Supply.** Cod goes to the fisherman's belongings (up to 16, and what its barrel still
holds comes back), to sell to the butcher. The farmer keeps 4 loaves for itself and
stocks its chest with the rest. The keeper carries a purse of 512, as much as it may
spend in one supply trip.

**Asks** (`asks.lua`). A seller posts one price per item, the same to every buyer: the
base price times its factor (1 at first). Each sale raises the factor by 5%; each game day
it held spare and sold none of it, the factor falls by 10%; it stays between 0.5 and 2. A
buyer that values the item at least at the ask pays the ask (less the standing discount,
`exchange.STANDING_SHIFT`), as many as it can afford. The ask is the price its market
news gives, and what trade trips and the stash pay. A peddler never asks under what it
paid for its lot.

Left for later: farm output, which the run showed to be short of a village's hunger even
with nothing given away.

### 18. Farm output

A survey of the ColonyFood world (2026-11-13) found two farmers sharing one field of 44
wet plots: 16 wheat, 20 carrots and 6 potatoes. It gave some 15 dinner-fit food points a
day against 88 eaten. Why:

* **Growth.** A crop grows one stage when VoxeLibre's growth timer (every 5.8 s, one
  chance in 35) picks it, and then with 3 in `floor(25 / (moisture × penalty)) + 1`.
  Wet all round with no crop of its kind beside it, that is certain: some 200 s a stage.
  Beside its own kind the penalty halves it: some 400 s, 2800 s for wheat's seven stages.
  A skipped night grows nothing. The farmer mostly waits on its field, so the stone
  hoe's speed bonus did nothing.
* **One field for two.** Each composter farms 8 around it, the cap of 40 plots counts
  every plot in range, and the two composters stood 6 apart: neither tilled more.
* **The crop mix.** A farmer sowed what it held most seed of. Carrots replant themselves
  generously, so they took almost half the field, though they are 1 point raw and no
  dinner. A potato harvest nets 1.5 potatoes, 6 points once baked; wheat 1.3 points as
  bread.

**Hoes multiply the harvest** (`wants.lua` tiers, `farm_field.harvest`). A hoe's rate is
now the yield of the crop's product, never its seeds: wood ×1.25 (30 uses), stone ×1.5
(64), iron ×2 (128), gold ×2.5 (16), diamond ×2.5 (512): about half VoxeLibre's
durability, gold yielding most for wearing out first. The best hoe held is taken up. The
ledger asks for a stone one, which the tool smith makes, and values every tier at its
worth (uses × a harvest's goods × the yield's gain), so a better hoe sells to a farmer.

**Tending** (`farmer.lua`). In the work stage, after every other job, the farmer tends
growing crops: each tend grows one a stage with 0.35 × the hoe's rate (by hand 0.35,
stone 0.53, iron 0.7, gold and diamond 0.875), a plot at most once in 120 s by any farmer.
Some 3.5 tends a plot a work day add to the 3 stages a plot grows by itself in a day 1.2 by
hand, 1.9 with a stone hoe, 2.5 with iron and 3.1 with gold or diamond: a tool is a bonus,
not a need. Like hunger it needs the village loaded.

**Starving still works** (`production.lua`). A starving villager crafted nothing, so a
village that ran out of food could not cook its way back: the ColonyFood world, starving
when this landed, made nothing in four days. It now crafts at a quarter of the rate (a
hungry one at half), on its shorter starving work day.

**Sowing for the village** (`farm_field.choose_seed`, `harvest_worth`). A harvest of each
crop is worth its net yield at the best price heard asked (market news `asking`) for the
crop or what it makes: bread a third a wheat, a baked potato a potato. A food need asks
for every food at its points. With nothing asked, base prices. The farmer sows the best,
still passing over a crop beside its own kind where another will do.

**A second farmer's land** (`farm_field.is_own`). Where claimed composters' fields
overlap, each counts and tills only the cells nearer its own composter, so a second
farmer tills outward and adds land. Harvesting, sowing and tending stay shared.

### 19. Money that circulates

The ColonyFood run of 2026-11-14 (days 117 to 166): hunger rose while the pantry was
never empty. Dinner costs 18 emeralds and 15 of 22 adults held under 20. The village's
money (about 4,000, flat) had gathered where nothing spends it:

| Flow | Emeralds |
|---|---|
| Dinners, through the keeper, into the farmers' chests | 5,438 |
| The farmers' rent into the Builder's bench | 2,561 |
| What the Builder took from its bench for cobble nobody sells | 1,177 |
| Donations to the cleric; alms out of its fund | 2,508; 1,775 |
| Every other sale between villagers | about 1,500 |

The farmers had nothing to buy: the hoe, cookie and book they wanted were not for sale,
and two of the ledger's preferences (cake, cookie) no village makes. The cleric kept half
of every gift. More than half the village sold nothing again and again: the smiths and
the armorer need iron, the tool smith had buyers for hoes but no cobble, nobody buys from
the fletcher, and the leatherworker's one buyer, the librarian, was broke.

The aim: every villager that holds money has something to spend it on, and every
profession something to sell from goods the village makes, with vanilla recipes and no
new professions. The alchemist, which would turn goods into iron, stays out of scope, and
so does cobble until the village has a quarry. Three parts, one PR each.

**19a. Comforts for savings** (`comforts.lua`). The ledger's fixed preferences go. A
villager has a slot for a comfort for every 4 dinners' emeralds (72) it holds over its
savings (8 dinners, as alms counts them), up to 6, and none below them. Each villager has
three tastes from the comforts, picked by its id; the slots go round them in turn. A
comfort held in its belongings fills a free slot and is used up some days later, so the
want comes back. The ledger wants one for each slot free or nearly done, worth at most
twice its base price.

| Comfort | Made by | Days |
|---|---|---|
| White banner | Cartographer | 6 |
| Bookshelf | Librarian | 8 |
| Apple | Forager | 2 |
| Poppy, dandelion | Foragers (19c) | 2 |
| White carpet | Shepherd (19c) | 4 |
| Item frame | Cartographer (19c) | 8 |

A villager that grows poorer keeps what it uses until it is used up, and wants no more.
The book stays a good that wears out for everyone (ticket 11e). Inspector line `Comforts`.

**The cleric's share** (`alms.lua`). The cleric keeps a tenth of each gift, not half, and
the rest goes to the alms fund. Alms top up anyone there with less than two dinners'
worth to two dinners (before, only one who could not pay one dinner).

**19b. Idle crafters labour** (`production.idle_today`, `labour.lua`). A crafter that can
make nothing when its work stage starts, for want of inputs or because it holds all of
its goods that will sell, does that day's labour as a nitwit does (forager, woodcutter,
porter, peddler; quarrier once there is a quarry), keeping its profession and jobsite.
It is asked each work day, not judged on what it made yesterday: away from its jobsite it
makes nothing, and would never come back. Its labour answers `putter` to vanilla, so it is
not called back to its jobsite. The smiths and the armorer, waiting on iron, earn their
dinners, and a trade short of goods gathers them.

**19c. New goods from existing professions**, each a vanilla recipe from village goods:

| Profession | Good | Recipe | Buyer |
|---|---|---|---|
| Fletcher | Fishing rod | 3 sticks, 2 string; its own sticks from logs | Fishermen: a rod wears out (`wants.lua`) |
| Cartographer | Item frame | 8 sticks, 1 leather | Comfort, for the richest (vanilla's 7 emeralds); leather's second buyer |
| Shepherd | Carpet | 2 wool make 3, at sale (a conversion that `takes` 2) | Comfort |
| Foragers | Poppy, dandelion | the bloom: the plant stays and blooms again 3 days later | Comfort |

A fishing rod makes a catch likelier, not quicker: one cast in four lands a fish by hand,
one and a half in four with a rod, which lasts 32 casts (half VoxeLibre's). A flower is
never dug, as before: the forager takes the bloom and leaves the plant, so the
"take only what comes back" rule holds.

Left out: the mason's flower pot (its bricks need clay, which no villager supplies) and
the librarian's glass bottle (its glass needs sand). Wants no village fills, such as the
cleric's rotten flesh, stay: a need is also how a player sells to a villager
(`trade_window.lua`), and Principle 1 makes the player the open edge.

**19d. Quarries players build** (`labour.lua`, `wants.lua`). An audit of every want on
2026-11-14 found cobble and stone behind most of the ones no villager can fill: the tool
smith's stone tools, the mason's stone and the Builder's cobble. A quarrier could mine
only a generator's cobble while it happened to be cobble, within 32 of its bed, standing
anywhere open beside it. Now:

- A generator's cell is cobble or stone with lava and water both beside or above it
  (VoxeLibre's Lava cooling: flowing lava cools to cobble where water touches it, water
  under lava turns to stone). Generators are found within 64 of its bed once a day, by
  looking around the lava there, and remembered (`_villages_quarries`). A remembered cell
  still counts while it holds air or a flowing liquid, between one block and the next.
- It stands on any cell a villager can stand on beside the cell, level, a step down or a
  step up: never in lava, water or fire, and nothing more. A player may build a safe
  quarry (a schematic with a safe spot, which the Builder could later build), but an
  unsafe one is worked too.
- It stays at the generator between blocks, and one quarrier works a cell at a time.
- Mining stone drops cobble, as in vanilla. The mason smelts cobble into stone (one
  fuel each), for its carved stone and to sell.
- At the generator it is held on its standing cell, as a fisherman is at the water. A
  mined cell is open, and often has a floor: at ColonyFood's first generator a quarrier
  stepped into it and burned when the lava flowed back.
- With a pick the lava flows back faster: REGEN_SECONDS (1, what a quarrier by hand
  measured at ColonyFood) over the pick's rate after a block, the cell turns to what the lava would cool
  it to, unless it refilled by then or someone stands in it. So a pick speeds both the
  mining and the generator; by hand the generator keeps its own pace, which is logged.
- A Builder builds a quarry (`schematics/quarry.mts`, from the user's first generator at
  ColonyFood: water, the cell and lava in a row, under glass, reached down a corridor that
  ends at the cell) when the village is short of cobble or stone and has no generator. It
  is never generated with a village. Its lava and water come in buckets, so a player
  supplies the lava bucket.
- A block takes 8 seconds by hand. A pickaxe divides that: wood by 2, stone by 3, and
  iron, gold and diamond by 4, past which a generator could not keep up. The tool smith
  also makes wooden picks and hoes from planks, so the first picks need no cobble. Picks
  are wanted by quarriers, idle crafters among them.

**19e. Every farm paid, and prices buyers can pay** (ColonyFood, 2026-11-14, days
202-205). Six villagers held 98% of some 3,400 emeralds. Two reasons stood out:

- The keeper always fetched from the nearest farm chest, so one farmer took every
  dinner's money (1169 emeralds, rising some 90 a day) while the other's chest held 345
  potatoes nobody fetched. The keeper now fetches from the chest with the most meals
  (a loaf or potato one, a carrot or beetroot a quarter), the nearest of equals
  (`keeper_supply.source`).
- Most villagers believed bread was worth eight times its price, the most a multiplier
  can be. Hungry villagers with an emerald each counted as demand, and a farm chest's
  food never counted as supply, so farmers asked some 250 a loaf and 55 a potato on trade
  trips, and buyers passed them over 243 times. Now a need counts only as far as its
  villager can pay at its own value (`prices.balance`): a need heard carries the needer's
  emeralds (`budget` in market news), and a villager's own needs are held to its own. A
  category's shortfall is priced at its cheapest member per unit. As the value includes
  the multiplier, a price that runs ahead of buyers' money cuts its own demand. A farmer
  also counts the food in its work chest over the keeper's 24 meals as supply
  (`farm_stock.food_for_sale`).

**19f. A stake for broke craftsmen, and asks that follow a glut** (ColonyFood,
2026-11-14). A tool smith with one emerald could not buy cobble and sticks for the stone
hoe a farmer wanted, and a butcher with one or two could not buy beef. Meanwhile the
leatherworker starved holding 26 raw beef, so no cooked beef reached the keeper, who
wanted it.

- The cleric's alms give a craftsman, one with a recipe at its tier (not the keeper or a
  Builder), a stake on top of two dinners: the price of four crafts of its cheapest
  recipe, fuel included, at base prices, at most three dinners (`alms.stake`; about 30 for
  most trades). Everyone's two dinners come first, the stakes after. With the fund short
  the cleric gives from its own emeralds over its savings: it held 610 it had no use for.
- A seller's ask fell only on a day it sold nothing. A leatherworker selling the butcher
  2 beef now and then kept asking near twice the base price. Now it falls on any day the
  seller sells less than a quarter of its spare (`asks.daily`).
- Price beliefs can fall to an eighth of base in a glut, and the beef beliefs had. An ask
  could not go below half, so buyers who believed the glut never met it. A seller that
  believes an item worth less than its base price now asks that much less (`asks.ask`). A
  belief over 1 leaves the ask to its sales, so demand is not counted twice.

**19g. News of inputs, and money that comes back** (ColonyFood, 2026-11-14, days
211-214, after 19e and 19f).

- The butcher needed 10 beef and valued it at 23, and the leatherworker would sell 29
  at 0.64, but the butcher had heard nothing of beef. Its top three needs, all that
  market news told, were vanilla trade wants nobody in the village makes (sweet berries,
  chicken, kelp blocks), so it never told of the beef it cooks. It laboured instead. A
  villager now also tells its top three needs among its recipes' inputs
  (`market_news.recipe_inputs`), as it already told its trade's outputs, and its fuel
  need whatever its rank, since every smelting recipe burns it (it came fourth of the
  butcher's seven inputs).
- The butcher's vanilla trade wants 10 dried kelp blocks, which nobody makes, while the
  unemployed held some 30 charcoal each at no value. Kelp blocks are now fuel (200 burn
  seconds), so the want is for 2000 seconds of any fuel: about 25 charcoal.
- A farmer hired a porter for one poppy and handed it its whole purse, 512. The porter
  left the 495 change in the farmer's stash, and nothing took emeralds out of a stash:
  they fell out of its budget, its donations and the village's money. A client now hands
  a porter the lot at its own value plus the fee (`trade_trips.purse_for`), one hire a
  day, and a villager takes the emeralds in its stash into its belongings whenever it
  stands within reach of it (`possessions.collect_stash_emeralds`).

**19h. Shepherds dye their wool** (ColonyFood, 2026-11-14). Three shepherds starved
holding grey wool nobody bought, valued at 2, while the cartographer wanted 14 white wool
(at 79) for the banners most villagers want. Grey and white wool share a base price, so
only demand told them apart.

- The shepherd has a recipe: grey wool and white dye make white wool. VoxeLibre dyes only
  white wool; Minecraft dyes any, as here. Unasked, it keeps one white in stock; heard of
  a buyer, it dyes on. Its wool still comes from its flock: a day with no dye never sends
  it to labour, and never holds its restock. Its recipe also makes it a craftsman for the
  alms' stake (19f), enough to buy dye.
- Its white dye comes from lily of the valley, priced as the other flowers (a twelfth of
  a vanilla emerald). Foragers pick the bloom as they pick poppies and dandelions, eight
  kept. Anyone selling a lily hands it over as white dye, one for one, VoxeLibre's recipe
  (`goods.conversions`, the first conversion that is not a job's).
- Bone meal is the other source, since no lily grew within 80 of ColonyFood. It crafts
  into white dye one for one too, and is priced as one. A farmer with a chest moves bone
  meal over its keep of 4 to its belongings, up to 8, as it does wheat, and anyone
  selling it hands it over as white dye. It composts on past its keep until it has
  those 8: it used to stop at 4, so it never had any to sell.
- Bones too: priced at the three bone meal a bone crafts into (a quarter of a vanilla
  emerald), so a forager picks up a skeleton's as it picks up rotten flesh. Anyone
  selling a bone hands over three bone meal or three white dye, whichever the buyer
  needs; the exchange already chooses among a good's conversions by the buyer's needs.
- Only grey for now, the colour that piled up. Silver wool's base price is 64, and as a
  recipe input it would put silver among the shepherd's top needs.

**19i. The Builder makes its red beds** (ColonyFood, 2026-11-14). The Builder wanted a
red bed (at 683) that nobody makes, so its house waited on a player. It now makes the
red beds it is short of, and any bed where any colour will do (a stock building), which
also puts its money into wood, wool and flowers.

- A bed is three wool of any colour, three planks and a red dye, a mod-side craft:
  VoxeLibre's beds take three wool of their own colour, or recolour a white bed with a
  dye. A player's order of another colour still wants that very bed.
- It wants the wool as any colour (`_villages_builder_wool`, a new `wool` category in
  goods.lua, one unit a wool, which is no job's target category), the planks with its
  other planks as logs (`_villages_builder_logs`), and the dye among its wants. Anyone
  selling a poppy or a red tulip hands it over as a red dye, one for one, VoxeLibre's
  recipe, so foragers' poppies have a buyer.
- It makes a bed from its pouch and its chests, a porter's delivery included, once it
  holds all three past what the building needs of wool and planks itself, so a bed never
  takes the building's own (`builder_market.lua`, logged `made N red bed(s)`).

### 20. The alchemist

The design is in [The alchemist](#the-alchemist). After 19 the village still had no
buyer for stone or wood beyond the Builder and the mason, and no source of iron, flint,
glass or gold. The alchemist was set out on 2026-11-09 as the future source of iron. On
2026-11-15 the user chose cost-based values, so the recipes keep their ratios and the
prices follow from them. Four parts, one PR each:

**20a. The stand and the role** (`alchemist.lua`, the stand's node and craft,
`job_blocks.lua`, `common.lua`). Register the stand and its recipe. Claim it as a role
over a cleric with `_villages_alchemist`, and give it a tinted robe and its own two
timetables. Take it out of hunger, meals, the tavern, the church, donations, alms,
comforts and wants. Village staffing leaves it out. Tests: the claim and its kind in
`job_blocks`, both timetables, food that never falls, no comfort slots, no donation and
no alms. A short headless check that a placed stand gets claimed and the alchemist
works at it through tavern time (`tools/lv_alchemist/run.sh`: it took the stand in 4 s,
kept it through tavern time and a reload, and lost the role when the stand was dug).

**20b. Cost-based prices** (`ledger.lua`, `goods.lua`). Add the base prices for the
alchemist's outputs, the `stone` category, and the cost floor for goods made from iron,
gold and flint. Drop the vanilla trade wants for iron, gold and flint that no recipe of
the profession uses. Tests: the prices in the tables above, and a check that every recipe
that takes iron, gold or flint gains at base prices.

**20c. Alchemy at the stand** (`recipes.lua`, `production.lua`, `goods.lua`,
`asks.lua`). Add the three recipes with their shares of the work day, the order and the
stops, and the input targets (logs while flint is short, stone always, values held at
base). Add the conversions with `reserve` and the ask floor at its reference value.
Tests: a day's output on each input, the stops at 12 glass and 32 flint, gold only past
108 nuggets and paid from the excess, and no input bought above base. A short run with a
quarrier and a smith, showing stone bought and iron sold.

Landed: the recipes carry `share`, `rank` and `upto` (`recipes.lua`); `production.cost`
turns a share into seconds from the villager's ordinary working day
(`common.work_day_ticks`). A recipe input's third field names a category, so a nugget
takes stone or cobble. `alchemist.targets` gives `possessions.assess` the stone and log
categories, caps each input's value at its base price (`worth`) and floors its goods'
value at theirs (`least`). Conversions count in whole batches (`goods.yield`,
`goods.sources_for`), so nine nuggets make exactly one ingot. Its stone need is the
category: one holding only cobble makes nuggets and no glass until stone comes. On the real engine
(`tools/lv_alchemist/run.sh`, 40 cobble given at the stand) it made a nugget every 30 s,
against the 29.2 s a share of the default day gives. The run with a quarrier and a smith
is left to a test world.

**20d. Trades with players** (`trade_window.lua`). Add the 1.5 and 0.5 margins,
conversions in the window, the buying rules with their stops, and goods bought kept as
they are. Tests: buying an ingot takes 9 nuggets and pays the pouch, gold is refused
under the reserve, and selling flint is refused at 32.

Landed: `trade_window.alchemy_rows` makes the alchemist's rows for its goods, at 1.5 and
0.5 of the base price (reputation moves both, as for anyone), and its other needs (stone,
logs) are rows as anyone's, at 0.9 of its value. A sell row made by conversion carries
the conversion; buying from it takes the alchemist's own first, then whole batches of
the source past any reserve, and logs `(from 9 mcl_core:iron_nugget)`. Its buy rows
offer for at most what the player carries, what it can pay for and, for flint and glass,
what fits under its keep (panes count as glass). A player can still buy ingots at 1.5 of
their base price and sell them to an urgent armorer at up to 0.9 of three times it: the
window's ordinary margins, bounded by the armorer's emeralds and need.

### 21. Price discovery

The design is in [Price discovery](#price-discovery). On 2026-11-15 the user asked for a
review of pricing as a whole. The alchemist in ColonyFood was stuck: broke, holding goods
that only penniless villagers wanted, while two farmers and the mason held most of the
money. The user wants prices that vary with supply and demand as far as possible, so a
situation like this finds its own equilibrium, and wants the player able to move that
equilibrium by trading. The user chose to let the dinner price float too. Five parts,
one PR each, each checked in ColonyFood before the next:

**21a. Money** (`ledger.lua`, `possessions.lua`, `comforts.lua`, `trade_window.lua`,
`farm_stock.lua`):
- Add `λ` and divide value by it. Comforts' WORTH cap becomes the reference price over `λ`.
- Add the window's Give field and its gossip.
- Stashes:
  - recognise trapped chests;
  - name the owner in the chest's infotext;
  - log each collection;
  - collect when the villager rises from bed.
- Add lv_keep's emerald-share line.

Tests: `λ` at 1, CUSHION and 3110 emeralds; a rich buyer paying over an ask a poor one
passes up; a gift's emeralds and gossip; a trapped-chest stash paying out.

Landed:
- `ledger.lambda` and `assess`'s `money` input. `possessions.money` gives it, less what
  is left of a porter's client purse, and nil for the keeper. The view also carries
  `lambda` and `real`.
- Barter (`exchange.lua`) compares `real` values. A buyer passes up an ask only when
  both its money value and its real value are under it.
- Vanilla's demand term (`demand.lua`) reads `real`, so vanilla trade prices are moved
  by want alone.
- A porter's purse is now the lot at no more than the heard price × 1.25, plus the fee.
  A rich client's value runs well past the price, and otherwise it would send all it has.
- Comforts' cap is WORTH × base price ÷ `λ`.
- The window's Give field (`trade_window.gift_amount`, `gift_gossip`).
- Stash changes:
  - trapped chests, open or shut, count as stashes;
  - the infotext reads "Stash of the farmer 84ebb7" and follows the owner's job;
  - each collection is logged;
  - getting up (`possessions.step` sees `_villages_sleeping` end), a villager collects
    from up to twice the stash radius of its bed.
- `tests/money.lua`.

Until 21c, the window still sells at the villager's value × 1.25. A rich villager's own
spare is worth more to it, so the window's prices for its goods rise with its money.

**21b. Reference prices** (`prices.lua` rewritten, `asks.lua`, `exchange.lua`,
`market_news.lua`, `alchemist.lua`):
- Move `_villages_prices` to `_villages_ref` in emeralds, converting old saves.
- Learn from trades, heard prices, missed buys and conversations.
- Put bids in `needs` news.
- Compute asks on reference prices, with the cash markdown and the new floor.
- Remove the alchemist's ask floor, `worth` caps and `least` floors.
- Add `tests/price_sim.lua` and lv_keep's per-item price lines.

Tests: each learning rule; the rails; old saves converted; the four simulation checks.

Landed:
- **Storage.** Reference prices stay factors in `_villages_prices`, under a category key
  for a category's members (see Reference prices), rather than emeralds in
  `_villages_ref`. This is the same thing, since the base price never moves, and old
  saves need only the fold into category keys.
- **Learning:**
  - `prices.learn` on every trade paid in emeralds: in `exchange.settle` for the buyer,
    in `asks.sold` for the seller, and on a trip's stash purchase.
  - `prices.missed` when `exchange.quote` turns down an ask.
  - `prices.hear`, `drift` and the missed asks, at the day's move.
- **Asks.** An ask is the reference price × its factor, no less than the seller's own
  value when its view is given. The factor is between 0.25 and 4. A sale pulls the factor
  back by LEARN_TRADE before the markup. A slow day lowers it ×0.81 instead of ×0.9 for a
  seller under CUSHION.
- **News.** A `needs` entry's price is capped at the needer's emeralds, and every entry
  carries `ref`.
- **The alchemist.** Its ask floor and its goods' `least` floors are gone. Its input
  `worth` caps stay until 21d: without an input valued by its output, a rich alchemist
  would bid up stone without limit.
- **`tests/price_sim.lua`.** Four checks, all passing:
  - A broke seller's glut of flint, against a fletcher with 30 emeralds, sold within days
    at a price between the two sides' values, below its base price of 64.
  - Three broke sellers of flint, feathers and string were each paid by a fletcher with
    3000 emeralds.
  - In 120 days of steady supply, flint settled at 20 emeralds and feathers at 2.3 from
    about day 60, every good made was sold, and nothing reached a rail.
  - The simulation surfaced COUNT_SPAN and the switch to learning from `ref`.
- **lv_keep** logs a `prices` line with each key's median factor among the adults and
  its range.

**21c. Players at the villagers' prices** (`trade_window.lua`):
- Rows at the villager's ask and bid.
- Remove the window's own margins and the alchemist's.
- A player trade settles through `asks.sold` and teaches its price.

Tests: a row at the ask; buying all of a good raises its next ask; a player's sale
lowers the buyer's reference price; no spread on any one villager's own goods.

**21d. Production by margin** (`production.lua`, `recipes.lua`, `ledger.lua`,
`possessions.lua`):
- Imputed values for inputs.
- Choose recipes by margin per second, and want only paying recipes' inputs.
- STORE_CAP; remove `upto`, ranks and COST_FLOOR as a price rule.

Tests: the alchemist switches to glass when panes bid high and flint doesn't sell; a
crafter with no paying recipe labours; an armorer's iron bid follows its armour price.

**21e. A dinner that floats** (`keeper_supply.lua`, `meal.lua`, `tavern.lua`,
`player_meals.lua`, `alms.lua`, `comforts.lua`, `rent.lua`):
- The keeper's food cost and dinner factor; the posted price and its news.
- Who dines by value.
- Amounts counted in dinners follow the reference price for a dinner.

Tests: a dinner price falls when broke guests are turned away from a full pantry and
rises when the pantry runs out; the keeper pays farmers its reference price; a villager
with dear dinners buys bread instead.

## Open questions

- Price discovery (ticket 21):
  - Whether rent, a new adult's emeralds, purses and a porter's fee should also follow
    the reference price for a dinner, once 21e shows how far it moves.
  - Whether the keeper should keep a margin over its food cost.
  - Whether glass should take cobble. Under 21d, the alchemist's bid for stone should
    draw the mason's stone instead.
  - Whether a villager should keep a reference price for goods it has never heard of,
    or seed them from the base price every time.
- Pacing: hunger rate, craft time, starting stock and rent all need probe runs on
  real villages before they are more than guesses.
- Whether the Builder becomes the next place money piles up, once the census has
  nothing left to build. If so, the Builder could spend its surplus on upkeep, or rent
  could fall with its savings.
- Iron: the alchemist (ticket 20) is its village supply, but nobody in the village buys
  iron goods. Until warriors exist (Warriors), the fletcher, the weapon smith and the
  armorer sell only to players, against Principle 6.
- The alchemist: whether the `stone` category should also take andesite, diorite,
  granite and cobbled deepslate; and whether to keep the cost floor once probe runs show
  what players will pay for iron gear at about twice vanilla's price.
- Once the basic money loops work: whether the keeper should keep a margin, and what it
  would spend it on.
- The Builder's other materials: a small house needs planks, logs, glass panes, carved
  stone brick and a bed besides cobble. The Builder buys logs for its planks, the mason
  carves stone brick and the Builder makes its red beds (19i). Glass and panes come
  from the alchemist (ticket 20), but only where a player has placed its stand.
- Money piling up at the tavern: in run 32 the pantry held 15 of the village's 41
  emeralds by day 6, since dinners bring in more than the keeper pays for food.
- After ticket 11h, prices relative to each other. A dinner first cost 64 while the
  loaf it is made of is worth about 11, which is why money piled up at the tavern; it
  now costs 18 (`ledger.DINNER`), a loaf's worth and a little for the cooking. Rent and
  starting money are still set against vanilla's prices.
- Emerald ore and emerald blocks still yield vanilla's 1 and 9 after ticket 11h, so
  mining becomes a small income next to trading. Whether ore drops should scale too.
- Whether a peddler walks to another village is the start of the next phase, and
  needs its own design (routes between villages, news carried across them).
- Whether stashes should be protected from players beyond the gossip cost, for
  servers that want it, is left to a later setting.
- Directions set on 2026-11-09, to be planned later:
  - **The Builder's missing materials** become trades of existing professions: a villager
    that sells wood also sells planks, taking the matching logs off its stock; the mason
    sells carved stone; and so on.
  - **Iron** comes from a future alchemist profession, which turns other raw materials
    into iron. Designed in ticket 20.
  - **Money piling up at the tavern** is answered with other expenses for the tavern.
- Player stalls on market days (set on 2026-11-11, to refine later): villagers browse a
  player's stall as any other and buy by the same rule. Whether the player claims a
  market stall site or places a stall block, and how a stall is priced, are open.
