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
treats the player as it would a villager. Since ticket 21c it has no margins of its own:
it sells at its asks and buys at its value, as everyone does.

- **It sells** (first at 1.5 times its reference value, before 21c). The
  window lists what it holds spare and what its conversions can make: an iron ingot
  while it holds 9 nuggets, gold only past the reserve, a pane for each glass. Buying an
  ingot takes 9 nuggets from its pouch and puts the emeralds in it.
- **It buys** iron and gold, as nuggets or ingots, at any time; flint while it holds
  fewer than 32; and glass or panes while it holds 12 or fewer. It pays its value for one
  more (first half its reference value, before 21c), from the emeralds in its pouch. What it buys goes into
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
| The keeper's tab cap (ticket 27: a fraction, unscaled); a porter's fee | 1; 1 | 1; 64 |
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
  player better prices. Ticket 36 replaced it with a donation at the cleric only.
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
| `_villages_commission` | A commission under way (ticket 26b): the labour recipe, item, count, client, its chest, the price and the hire's day |
| `_villages_commissioned` | The good a client last commissioned and the day, so it orders no second while the first is out |

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
| 22 | Flows that answer prices: money that comes back (22a), the starving eat (22b), a tavern stocked to demand (22c) | 21 |
| 23 | Comforts the labourers make: labourers craft while they wait (23a), new comforts and flowers in pots (23b), slots that grow with wealth (23c), comforts at the bids heard and labourers that buy their inputs (23d) | 22 |
| 24 | Demand for the crafts with none: the cleric eats free, the alchemist hears all, leather clothes, bows and arrows and any carpet as comforts, the butcher's chickens | 23 |

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

**Fix (2026-11-15): a product at its sources' price.** A conversion sells the product
for what its sources are worth: an ingot for nine nuggets. This ticket priced a converted
sale at the seller's value of the source over the ratio. Ticket 17 put asks first in
`exchange.quote`, and for a converted sale it asked the product's own price, so the
source path ran only for items with no base price. Seed prices hid it (an ingot's seed is
nine nuggets'). Once 21b let prices learn, an alchemist that held nuggets unsold marked
their ask down daily, while its ingot ask, for a good it never held or sold, stayed at
the 115 seed; an armorer with 46 emeralds could buy none, and the alchemist went broke on
19 nuggets. Now:
- `asks.converted(seller, conversion, view)` is the product's ask capped at the source's
  ask over the ratio (nine nuggets' ask for an ingot, a quarter of the wool's for string,
  a glass's for a pane); the product's own ask stands only when lower.
- `exchange.quote` asks it for every converted sale; `market_news` tells a converted `has`
  at it; the alchemist's trade-window rows made by conversion are priced by it.
- A converted sale is also recorded as a sale of the sources it used (`asks.sold`, in
  `exchange.settle` and the window), so their ask, which now prices the product, rises on
  the sale and stops falling.
- Tests: `tests/alchemist_trade.lua` (nuggets marked down to MIN, the ingot ask at its
  seed: an armorer with 46 emeralds buys at nine nuggets' ask, and the nuggets count as
  sold), `tests/market_news.lua` (string told at a quarter of the wool's ask) and
  `tests/trade_window.lua` (an ingot row at nine nuggets' price). The old test set both
  factors to 0.5 together, so it never saw them apart.

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

Until 21c, the window still sold at the villager's value × 1.25, so its prices for a rich
villager's goods rose with that villager's money. Since 21c it sells at the villager's
ask, which a rich seller's own value floors.

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
  `worth` caps stayed until 21d, which values an input by its output instead: without
  that, a rich alchemist would bid up stone without limit.
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

Landed:
- **Rows.** `trade_window.rows` takes the villager's asks (`ask(item)`, `asks.ask` with
  its view) and sells at them, or at its value for an item with no base price. It buys
  at its value. Reputation still moves both by up to REP_MAX.
- **The alchemist.** It sells its goods and what its conversions make at its asks, and
  buys iron, gold, flint and glass at its value for one more, within the same stops.
- **Margins removed:** MARKUP, BID_SHARE, ALCHEMY_MARKUP and ALCHEMY_BID.
- **Player trades teach.**
  - A player's purchase goes through `asks.sold` with the price paid: the villager's
    reference price learns it, its ask rises, and the sale counts against the slow-day
    markdown.
  - A player's sale goes through `prices.learn` on the villager's side.
- **Tests:** `tests/trade_window.lua` checks rows at the ask and at the value, and the
  learning after each kind of trade.

**21d. Production by margin** (`production.lua`, `recipes.lua`, `ledger.lua`,
`possessions.lua`):
- Imputed values for inputs.
- Choose recipes by margin per second, and want only paying recipes' inputs.
- STORE_CAP; remove `upto`, ranks and COST_FLOOR as a price rule.

Tests: the alchemist switches to glass when panes bid high and flint doesn't sell; a
crafter with no paying recipe labours; an armorer's iron bid follows its armour price.

Landed:
- **Margin.** `ledger.margin(recipe, price_of)` is the output's price × its count, less
  its inputs and fuel, at `price_of`: the villager's reference price × its ask factor
  (`possessions.prices_of`). A category input is priced at its cheapest member. An input
  nothing prices (gravel, sand) is gathered, not bought, and counts as 0.
- **Choosing.** `production.choose` makes the recipe with the best margin per second
  (`production.gain` / `production.cost`), the output priced at no less than a heard
  ask. A margin of 0 still counts as paying, so a craft at its inputs' cost goes on; one
  that loses is never made, and a crafter with nothing that pays labours
  (`idle_today`).
- **Imputed values.** `ledger.imputed` caps what each input is worth to a crafter at what
  its best recipe returns per unit of it. `possessions.assess` applies the caps, and
  drops the needs that only losing recipes would use (`ledger.unpaid`). An armorer whose
  armour stops selling bids less for iron, and none once no armour pays.
- **Seed prices.** Every recipe output starts priced at no less than its inputs and fuel
  (two passes, so chains settle), and one made from iron, gold or flint at COST_FLOOR
  times that, as before. Without this vanilla's prices put bricks under their clay and
  white wool under grey wool and dye, and those crafts would never be made, so their
  prices could never learn. COST_FLOOR stays as a seed, not a rule: after the seed, an
  output's price moves like any other.
- **The alchemist.** Its stops (`upto`) and ranks stay, and now act only among recipes
  that pay; ranks break ties. At the seed prices glass and flint pay 0 and nuggets pay,
  so it makes nuggets until their price falls, then glass and flint. It wants stone only
  while glass or nuggets pay, and logs only while flint does (`alchemist.targets`). Its
  `worth` caps on stone and logs are replaced by the imputed values.
- **Not done:** STORE_CAP. The stock caps (STOCK, UNASKED_STOCK and `upto`) still bound
  what a crafter holds.
- **Tests:** `tests/production.lua` (a crafter whose tools fetch a 32nd labours; an
  armorer's iron bid follows its armour; white wool is dyed while it pays),
  `tests/alchemist_trade.lua` (nuggets first, glass then flint when nuggets glut, flint
  first when it sells dear; stone and cobble bids at their imputed caps) and
  `tests/ledger.lua`.
- **Thin crafts.** A fishing rod pays 0.3 over its string at the seed prices, so the
  fletcher stops wanting string for rods as soon as string's price rises a little.
  `tests/price_sim.lua`'s rich fletcher is now tier 2, so its string goes into bows.

**21e. A dinner that floats** (`keeper_supply.lua`, `meal.lua`, `tavern.lua`,
`player_meals.lua`, `alms.lua`, `comforts.lua`, `rent.lua`):
- The keeper's food cost and dinner factor; the posted price and its news.
- Who dines by value.
- Amounts counted in dinners follow the reference price for a dinner.

Tests: a dinner price falls when broke guests are turned away from a full pantry and
rises when the pantry runs out; the keeper pays farmers its reference price; a villager
with dear dinners buys bread instead.

Landed (`dinner.lua`, read by `meal.lua`, `keeper_supply.lua`, `player_meals.lua`,
`possessions.lua`, `alms.lua`, `rent.lua` and `trade_window.lua`):
- **Food cost.** A meal's food at the keeper's reference price for a loaf
  (`dinner.food_cost`), since a guest values a meal as a loaf. The keeper pays a farm
  chest that per meal the food makes (a potato is one, a carrot a quarter). Not each
  food's own price: at vanilla's a potato is about a quarter of a loaf, and pricing a
  dinner by the cheapest food would have cut it from 18 to 2 overnight and the farmers'
  pay with it. The keeper's food price learns as anyone's does (21b); no separate
  learning from its own payments, which would only teach it its own price.
- **The price.** Food cost × the dinner factor, in whole emeralds, at least 1. MARKUP is
  1.1 and MARKDOWN 0.9; the rails are the asks' 0.25 and 4. The factor moves once a day
  for the evening before: up if a guest who would have paid found no dish, else down if a
  hungry guest would not pay while dishes were left. A guest counts once a day. The
  keeper settles and posts the price each tick, in the jukebox meta
  (`villages_dinner_price`), and reckons a dinner worth its own price.
- **Who dines.** A hungry guest dines when the price is no more than a loaf's value in its
  view. Short of the price in emeralds it gets the raw plate at BROKE_PRICE as before;
  with the emeralds but not the will, it is not served and eats at home or buys food.
  Its choice is kept per day and price.
- **Not in the news.** The price is not a `has` entry: those drive porter trips, peddling
  and supply counts, and a dinner can be bought only at the tavern. A villager learns it
  on reaching the tavern (LEARN_NEWS) and on paying it (LEARN_TRADE), under the
  pseudo-item `living_villages:dinner`, base price `ledger.DINNER`.
- **Players** pay the posted price unless `living_villages_player_meal_price` is set.
- **Amounts in dinners** follow `dinner.scale`, the villager's reference price for a
  dinner over 18: the cushion and STOCK_MONEY (`ledger.assess`'s `dinner` input), the
  asks' cushion and the comfort slots (`possessions.in_dinners`), alms' savings, gifts,
  top-up and stake cap, the trade window's gift gossip, and rent's keep-back.
  `wants.DAILY_WORK` stays fixed.
- **Tests:** `tests/dinner.lua`, and `tests/meal.lua` and `tests/keeper_supply.lua` at
  the posted price and the food cost.
- **lv_keep** logs a `dinner` line per keeper: the posted price, the factor, and the
  evening's turned-away count and whether it ran out.

### 22. Flows that answer prices

On 2026-11-15, with 21a–21e merged, the user asked how the price changes had done and
what still held the economy back. Two runs from the same snapshot (ColonyFood at day 302,
main 5f2c997) answered it: ColonyFood as it was, and ColonyRich, a local copy where every
villager was given 2,000 emeralds once. By day 315:

| | ColonyFood | ColonyRich (+2,000 each) |
|---|---|---|
| Money in the village | 4,961 → 3,286 | 48,697 → 44,196 |
| Dinner posted | 1 (factor 0.28, falling) | 1 → 13 (factor 1.42, rising) |
| Food, median reference | ×0.12 → ×0.09 | ×0.20 → ×0.53 |
| Wheat; beef | ×0.16; ×0.18 | ×0.29; ×0.27 |
| Stone, planks, books, banners | flat | flat |
| Hungry / starving | 7 / 4 | 4 / 1 |

Prices did their part. Food fell under a glut (about 370 potatoes in the farm chest) and
rose where the new money chased it; goods nobody wanted more of stayed put; crafters made
what paid and laboured otherwise. What failed was the flows prices are meant to steer:

- **Money that stops.** Over the 13 days in ColonyFood, villagers gave the cleric 1,337
  emeralds and it gave 18 back (its fund reached about 1,036). The farmers paid 786 in
  rent into the Builder's bench and the Builder took 153 out. Those two hoards are the
  1,675 the village lost: its deflation is money leaving, not goods arriving. Rent is
  still 64 every 2 days, fixed since 11h, now about 60 dinners at the posted price, and the farmers paid it
  from savings (the richest went from 2,525 to 1,293) while the tavern paid them about 20
  a day.
- **Supply that ignores price.** The keeper fetches only while the pantry holds under
  TARGET_MEALS (12), CARRY (24) at a time. In ColonyRich it fetched 7 times in 13 days and
  ran out most evenings; dinner climbed to 13 and one load of 24 potatoes paid the farmers
  295, while 352 more sat in their chest. A higher price brought more money for the same
  meals, never more meals.
- **Starving in a glut.** λ is up to 8 for one with nothing and urgency at most 3. With
  food at ×0.09 a loaf is worth about 0.8 emerald to a starving villager holding 2, so it
  turns down a dinner at 1; it can pay, so it gets no raw plate either. The keeper reads
  its refusal as a price too high and marks down a factor already pinned at the 1-emerald
  floor: 0.28 now, about 13 days of MARKUP from 1 when demand returns.
- **No income.** Porters and nitwits wait for hire nobody offers; the fisherman's raw fish
  are worth 0 to anyone (only the butcher cooks fish, and the keeper does not buy it), so
  it holds 0 emeralds and 190 in rent arrears; the alchemist made about 2 ingots' worth of
  nuggets while the armorer wants 31. Trade between villagers came to 58 sales and 650
  emeralds, less than the rent.

Three parts, one PR each, the first two smallest and most urgent:

**22a. Money that comes back** (`alms.lua`, `rent.lua`, `builder_market.lua`):
- **The alms fund spends down.** A donation is taken only while the fund is under
  FUND_TARGET: four holidays of alms for the congregation it sees (ALMS_TO, at each poor
  villager's own dinner scale, plus the stakes). Above it donors keep their money, which
  their own spending puts back in circulation. Over FUND_TARGET the cleric tops the poor
  past ALMS_TO, up to SAVINGS, until the fund is back at it, so a hoard already gathered
  goes out over a few holidays.
- **Rent in dinners.** RENT becomes RENT_DINNERS (64 / 18, the 11h rent at the old dinner)
  at the tenant's `dinner.scale`, like every other amount counted in dinners since 21e.
  At a dinner of 1 to 2 emeralds that is 4 to 7 every 2 days, not 64.
- **Rent the landlord uses.** No rent is billed while the bench's chests hold more than
  the Builder's PURSE: a Builder with nothing to buy does not draw its tenants' money into
  a chest. Billing resumes when the Builder has taken it down.
- Tests: the fund stops taking at FUND_TARGET and pays out over it; rent at a cheap
  dinner; no rent billed over a full chest, billed again once taken.

Landed (`alms.lua`, `rent.lua`):
- **The fund.** `alms.level` is a villager's ALMS_TO plus its stake at its dinner scale;
  `alms.fund_target` is FUND_HOLIDAYS (4) times the congregation's levels, the cleric's
  own aside. A donation is capped at what the fund lacks of the target, and a donor at the
  target is marked as having given that holiday. After the alms and stakes, the fund over
  the target goes out from the fund only, poorest first, each topped up toward its
  SAVINGS. The cleric's own emeralds are not spent down.
- **Rent.** `rent.rent` and `rent.cap` are RENT and RENT_CAP at the tenant's dinner
  scale, at least 1. A due period is not billed while `rent.in_chests` (the bench's
  chests, never a food chest) holds more than PURSE (512, builder_market.lua's); the
  periods skipped are not billed later. `builder_market.lua` is unchanged: what stops the
  hoard is no billing, not more buying.
- **Tests:** `tests/alms.lua` (the level and target; a donation capped at what the fund
  lacks; none at the target; the excess to the poorest down to the target) and
  `tests/rent.lua` (rent and its cap at a dinner of 9; no billing over 512 waiting, and
  none later; billed again once it is taken).
- **Fix, 2026-11-15 (day 327 census in ColonyFood).** The fund over its target gave 15 of
  1,702: it topped villagers up toward SAVINGS at their own dinner scale, 8 emeralds at a
  dinner of 1. Now it tops up toward SAVINGS at the old dinner, 144. And seven adults on
  the west side, the starving fletcher among them, never went to church at all: they
  looked for one within 48 of their bed and the village's one church stood 55-61 away.
  `church.lua` now looks within 48, then within 128 (rent's VILLAGE_RADIUS), and with
  none in the village waits 60 s before looking again. Tests: `tests/alms.lua` (a
  villager at a dinner of 1 topped up to 144) and `tests/church.lua` (a bed 88 from the
  pulpit goes to it).

**22b. The starving eat** (`ledger.lua`, `meal.lua`, `dinner.lua`):
- **Food first.** For a villager at or under possessions' starving point, the money
  factor on food is at most 1: it values a meal as a villager of average means would, so
  its last emeralds go on food before anything else. Other goods keep their λ.
- **The raw plate for the starving.** A starving guest who will not pay the dinner price
  still gets the raw plate at BROKE_PRICE, as one who cannot pay does.
- **A factor that holds at the floor.** The keeper does not mark down when the price is
  already 1 and the markdown would leave it at 1; guests turned away then say nothing
  about the price.
- Tests: a starving villager with 2 emeralds dines at 1 at food ×0.09 and one fed does
  not; a starving refuser gets the raw plate; the factor stays when the price is 1.

Landed (`ledger.lua`, `meal.lua`, `dinner.lua`):
- **Food first.** In `ledger.assess`, with `food_points` at or under 0, a food-category
  item's value is divided by min(λ, 1) instead of λ. Other goods keep λ, so a starving
  villager still passes up a book. `real`, the value with no money in it for barter,
  multiplies back by the same divisor. With 2 emeralds and food at ×0.09 a loaf is worth about
  2.9 to it, not 0.5.
- **The raw plate.** In `meal.lua`'s order, a starving villager guest that will not pay
  falls through to the broke branch: the raw plate (four carrots or beetroot) at
  BROKE_PRICE when the pantry holds one. It still counts as turned away.
- **The floor.** `dinner.settle` marks down only while the keeper's price is over 1.
- **Tests:** `tests/dinner.lua` (a starving villager dines at 1 and a fed one does not;
  a book keeps its λ; the factor held at the floor and marked down above it) and
  `tests/meal.lua` (a starving unwilling guest gets the raw plate for one emerald; a
  hungry one is refused).
  `tests/money.lua`'s rich-and-poor check moved from bread for the starving to coal for
  two armorers, since a starving villager no longer shows λ on food.

**22c. A tavern stocked to demand** (`keeper_supply.lua`, `dinner.lua`):
- **The target from last night.** TARGET_MEALS becomes the meals the keeper served the
  evening before plus the guests it ran out on (a count kept in `_villages_dinner`), at
  least 12, and CARRY rises with it, up to CARRY_MAX.
- **A second trip.** A keeper that ran out goes again the next free hours, not only when
  the pantry next drops under the target.
- **Paying for more.** It pays the farm chest per meal at the food cost as now; its tab
  and TAB_CAP scale with the target, so a busier tavern does not just forgive more.
- With supply following demand, a rising dinner price draws more food out of the farm
  chest and more money to the farmers, and falls back once the pantry stops running out.
- Tests: the target follows a night of 20 diners and 5 turned away by an empty pantry; a
  keeper that ran out fetches the next day; its tab at the larger target.

Landed (`dinner.lua`, `meal.lua`, `keeper_supply.lua`):
- **Demand.** `dinner.served` counts each meal served at the keeper's tavern (`meal.lua`'s
  serve, players and the household too), and `dinner.ran_out` now takes the guest's id,
  kept once a day in `short`. At the day's turn `settle` stores served plus short as
  `demand` in the new record (`dinner.demand`); a day without either leaves 0.
- **Target and carry.** `keeper_supply.target` is the demand, at least TARGET_MEALS (12);
  `carry` is the target, at least CARRY (24) and at most CARRY_MAX (64). The keeper
  fetches while the pantry holds less than the target, checking every CHECK_SECONDS of its
  free hours as before, so a short pantry brings a second trip without a separate rule.
- **Tab.** `keeper_supply.tab_cap` is TAB_CAP × target / TARGET_MEALS.
- **lv_keep**'s dinner line adds `served=`, `short=` and `demand=`.
- **Tests:** `tests/dinner.lua` (20 served and 5 short, one twice, make a demand of 25 the
  next day, then 0), `tests/keeper_supply.lua` (a demand of 30 sends the keeper out with
  14 meals in the pantry and it carries 30; CARRY_MAX; the tab's cap) and
  `tests/meal.lua` (a served meal is counted).

**Not in this ticket** (open, for after 22): income for those with none — hiring porters
and nitwits, a buyer for raw fish (the keeper or the butcher), and iron enough for the
armorer and smiths. Two bugs seen in the same runs: villager 840a99 in ColonyFood never
reaches the tavern (17 failed walks, last dined 77 days earlier, no market news); and on
days 307, 309 and 310 the whole ColonyRich village slept through the tavern (possibly
the local Luanti 5.17; not seen in ColonyFood).

### 23. Comforts the labourers make

ColonyFood at day 334 (main c247d45, 2026-11-15) holds 4,711 emeralds, with dinner posted
at 1. Money is not short, and neither is demand. The goods are:

- **Bids nobody fills.** Villagers bid 2,000 to 9,000 emeralds for a banner, a
  bookshelf or an item frame: their money factor is low, so the comforts of 19a are worth
  a great deal to them. Banners stand at ×4 and books at ×5.7, but every comfort above a
  flower comes from a chain with a bottleneck: frames need leather, a bookshelf 3 books,
  a banner 6 wool.
- **Raw goods nobody buys.** Nitwits, the unemployed and crafters labouring (19b) hold 50
  to 130 cobble and 60 logs each at about 1 emerald (stone ×0.13, logs ×0.23). A
  woodcutter labouring holds 33 charcoal at 3. Foragers hold 8 to 10 lilies of the valley,
  which are no comfort.
- **Labour that waits.** Several labourers stand at "woodcutter, grove of 0", or beside a
  generator between blocks.

So comforts made from stone and wood, by the labourers who hold it, join the two: the
richest pay the poorest for their work, and the cobble, logs and charcoal get a use.

**Crafted, not converted.** A conversion (ticket 15) sells its product at no more than
its sources' ask (`asks.converted`, #103), so a flower pot converted from 3 cobble would
sell for 3 cobble while its buyer bid hundreds: the comfort would be bought for almost
nothing and little money would move. A conversion also takes one input, and a torch or
a lantern needs two. A crafted good takes work time, and production by margin (21d)
prices it from what buyers want and makes more of what pays.

Three parts, one PR each.

**23a. Labourers craft while they wait** (`production.lua`, `labour.lua`, `recipes.lua`).
- **Who.** Every labourer (`_villages_labour`: nitwits, the unemployed, crafters
  labouring under 19b), whatever its activity, from one list, `recipes.labour`. Which it
  makes is production by margin, as at a jobsite: the inputs it holds or can buy steer
  it, so a woodcutter makes torches and a quarrier flower pots without a rule saying so.
- **When.** Work-stage time its activity has no job for (a woodcutter with no tree ready,
  a quarrier waiting on its generator, a forager with nothing in bloom, a porter waiting
  for hire) is banked in `_villages_craft` as a crafter's time at its jobsite is, at the
  same hunger rates. It crafts at home, at no block. Time spent working its activity
  banks nothing, so crafting never takes a labourer from its labour.
- **Buying inputs.** What it lacks for the recipe that would pay best is a need, posted
  in market news and bought like a crafter's inputs; nuggets from an alchemist, wool from
  a shepherd.
- **The list.** Vanilla recipes, except the flower pot, which in vanilla takes 3 bricks
  from clay no village can get:

| Makes | From | Note |
|---|---|---|
| 4 sticks | 2 planks | as the tool smith's |
| 4 torches | 1 stick, 1 coal or charcoal | an input of the lantern; the Builder's houses take torches too |
| 1 flower pot | 3 stone or cobble, or 3 planks | the mod's own recipe; players still need bricks |
| 1 painting | 8 sticks, 1 wool | |
| 1 barrel | 7 planks | 6 planks and 2 wood slabs (3 planks make 6 slabs) |
| 1 armor stand | 6 sticks, 1 stone or cobble | a stone slab (3 stone make 6), rounded up |
| 1 lantern | 8 iron nuggets, 1 torch | only where an alchemist makes nuggets |

- **Prices.** The lantern (librarian, 1 emerald) and the painting (shepherd, 2 for 3) have
  vanilla trades; the flower pot, barrel, armor stand and torch take their base price
  from their inputs and work, as the alchemist's goods do (20b).
- **Tests:** a labourer whose activity has no job banks time and makes the recipe that
  pays best; one working its activity banks none; a flower pot from cobble, from stone and
  from planks; a lantern from bought nuggets.

Landed (`recipes.lua`, `production.lua`, `labour.lua`, `possessions.lua`, `ledger.lua`,
`market_news.lua`):
- **`recipes.labour`**, the table above, with planks from logs first (a woodcutter holds
  logs, and logs to planks is otherwise only a conversion at sale) and torches from coal as
  well as charcoal.
- **Waiting.** `labour.waiting` is set at each labour tick: true with no activity, a
  porter not on a trip, no target, or at a generator between blocks; false while walking
  or working. `do_custom` calls `production.labour_step`, which banks clock time only
  while waiting, in `_villages_labour_craft`, and makes by margin from `recipes.labour`.
  A labour craft counts toward no tier.
- **The plan.** Every PLAN_SECONDS (60) while waiting, `production.labour_plan` picks the
  labour recipe that pays best, of the goods someone has asked for or it wants itself,
  and keeps its index in `_villages_labour_plan` for the day. `possessions.assess` wants
  one craft of its inputs (stone, wool and planks as their categories) and caps their worth
  by that recipe alone (`ledger.imputed`); `market_news.recipe_inputs` tells them.
- **Prices.** The torch, flower pot, barrel and armor stand join `COST_PRICED`: a torch
  about 1.7 emeralds, a pot 12, a barrel 28, an armor stand 15. The lantern, now made from
  nuggets, is cost-floored at about 130.
- **Tests:** `tests/production.lua` (a pot made only while waiting, from cobble, stone or
  birch planks; torches then a lantern; the lantern plan wants 8 nuggets and a torch and
  tells them; a pot plan wants stone; no plan with nothing asked, nor from yesterday) and
  `tests/labour.lua` (waiting at a generator between blocks, not while setting off).

**23b. New comforts, and flowers in pots** (`comforts.lua`).
- **Comforts.** `COMFORTS` gains the flower pot, painting, barrel, armor stand and lantern.
  Each villager's tastes rise from 3 to 4 (TASTES), as the list nearly doubles.
- **Flowers.** Poppy and dandelion become one comfort, *a flower*: any of the village's
  flowers (`mcl_flowers:*` in `ledger.lua`), the lily of the valley too, so the foragers'
  lilies get a buyer.
- **Flowers in pots.** A flower pot in use holds a flower. While one is in use, its owner
  wants a flower for it every FLOWER_DAYS (2), worth what a flower comfort is to it, and
  a flower it holds goes in the pot. A pot keeps its slot with or without one; the flower
  is its upkeep, so a pot keeps buying flowers for as long as it lasts.
- **Everything perishes.** Every comfort has its days, and one used up is gone: it never
  goes back to belongings or the stash, and nothing is left of it. A flower in a pot
  wilts after FLOWER_DAYS and goes too. A test checks that every entry in `COMFORTS` has
  days, at most MAX_DAYS (12), so no comfort is added that lasts forever.

| Comfort | Made by | Days |
|---|---|---|
| A flower (any) | Foragers | 2 |
| Apple | Foragers | 2 |
| White carpet | Shepherd | 4 |
| Flower pot (wants a flower every 2 days) | Labourers | 8 |
| Painting | Labourers | 6 |
| Barrel | Labourers | 6 |
| White banner | Cartographer | 6 |
| Armor stand | Labourers | 8 |
| Bookshelf | Librarian | 8 |
| Item frame | Cartographer | 8 |
| Lantern | Labourers | 10 |

- **Tests:** a pot in use wants a flower every 2 days and takes one it holds; a pot with
  no flower keeps its slot; a used-up comfort and a wilted flower are gone from the
  villager; every comfort has days, none over MAX_DAYS; a lily of the valley fills a
  flower slot.

Landed (`comforts.lua`, `goods.lua`, `possessions.lua`):
- **`goods.CATEGORIES.flower`**: the twelve flowers the ledger prices, after stone in
  ORDER. Like wool and stone it is no job's target category; its members share one
  reference price (`group:flower`), and an old save's per-flower beliefs fold into it.
- **`COMFORTS`** as in the table, the flower an entry with `category = "flower"`; `by_item`
  maps every flower to it, so an old save's poppy or dandelion in use keeps its days.
  TASTES is 4; FLOWER_DAYS 2; MAX_DAYS 12.
- **`targets`** returns a third value, `{category = count}`: a flower slot, and each pot in
  use with no flower or one nearly wilted. `possessions.assess` adds it to the ledger's
  `extra_categories`, so a need for a flower is told once, under the cheapest flower, and
  any flower fills it. Worth is set for every flower.
- **`update`** drops what is used up, then wilts each pot's flower past `flower_until`
  and puts in one it holds, then fills free slots; logs `puts a … in its …` and `… wilted`.
- **Tests:** `tests/comforts.lua` (every comfort within MAX_DAYS; a lily fills a flower
  slot and wilts away; a pot without a flower wants one and keeps its slot, takes one,
  wants the next when nearly wilted, and is gone with its flower after 8 days) and
  `tests/possessions.lua` (a pot's want is a need for any flower, grouped as `flower`).
- **Fix after landing** (ColonyFood, 2026-11-15): slots were matched to tastes by their
  place in the list in use, so an armorer holding lilies filled all nine of its slots with
  them, a lily a minute. Each taste now fills and wants only its own slots (`per_taste`),
  and a comfort in use counts against its taste's.

**23c. Slots that grow with wealth** (`comforts.lua`). Farmer 84ebb7 holds 1,163
emeralds and fills the same 6 slots as a villager with 576: past that its money buys
nothing more. The first BASE_SLOTS (6) still come one for every STEP (4 dinners) over
SAVINGS; each slot past them needs twice the span of the one before (2, 4, 8 … STEPs), up
to MAX_SLOTS (12). At today's dinner of 18 that is a 7th slot at 720 emeralds, an 8th at
1,008, a 9th at 1,584 and the 12th at 9,648 (in dinners, at the villager's own dinner
scale, as now). The richest spend more, by less for each slot, so a hoard is drawn down
without one villager buying up every comfort. The slots still go round its tastes, so a
villager with 4 tastes and 9 slots wants some comforts twice.
- **Tests:** slots at SAVINGS, at 6 STEPs over it, and at each doubling, never over
  MAX_SLOTS; a villager with 9 slots and 4 tastes wants the first taste three times.

Landed (`comforts.lua`): `BASE_SLOTS` (6) and `MAX_SLOTS` (12); `slots` counts STEPs over
SAVINGS one a slot up to BASE_SLOTS, then a span of 2, 4, 8 … STEPs a slot. Tests
(`tests/comforts.lua`): 719 and 720 emeralds give 6 and 7 slots, 1,008 gives 8, farmer
84ebb7's 1,163 gives 8, then 9 to 12 at 1,584, 2,736, 5,040 and 9,648, never more; 9 slots
want the first taste once each round of its tastes.

**23d. Comforts sold at what buyers bid, and labourers that buy their inputs**
(ColonyFood, days 340–346, after 23a–c landed). Money moved, but little of it: 9 comfort
sales in six days, labour-made ones at their cost (a barrel for 28 to a leatherworker
that valued it at 374, armor stands for 31 against bids near 200), and no lantern or
painting made, though seven labourers planned paintings and three lanterns.
- **Asks** (`asks.lua`): a comfort (not a flower, told as its category) is asked at no
  less than BID_SHARE (½) of the best bid for it the seller heard in the last BID_DAYS
  (2) game days, a bid capped at its bidder's emeralds. The reference price found it one
  5% markup a sale, and comforts sell a few a day. The bid ages out with its news, so the
  ask falls back once the bidder has its comfort. A converted comfort (carpets from wool)
  stays capped by its source's ask (#103), and an apple, a food, is left out.
- **Fix after landing** (ColonyFood, 2026-11-15): a buyer tells only its top three needs,
  so a weapon smith that never heard the leatherworker's barrel bid sold it one for 18 in
  their conversation. A bid made to the seller's face, in a conversation or on a trade
  trip, now counts too (`asks.with_bid`): half of it, never over it, so the sale goes ahead.
- **Plan inputs** (`production.labour_caps`, `possessions.assess`): the plan's caps
  price its output at the best bid heard, as its gain does, and come with the plan; an
  input it is short of for one craft is worth at least PLAN_SHARE (½) of its cap, its
  money factor left out, since it buys to sell on. A labourer with 134 emeralds valued
  wool at 8 for a painting bid at 500, while shepherds asked 90.
- **Nuggets** were not short by price: the only seller, the alchemist-cleric, was stuck
  at its bed exit, talked once in 70 minutes, sold all 63 of its nuggets to the armorer
  as ingots at its stall, and died on fire. Lanterns wait on an alchemist that talks.
- **Tests:** `tests/asks.lua` (the floor at half the best affordable bid, none for beef
  or flowers, none once the bid is stale); `tests/production.lua` (the plan's caps price
  nuggets at the lantern bid, its nugget value at least half the cap and urgent; wool for
  a painting bid at 500 worth over 90, in any colour, until it holds one).

**Not in this ticket:** placing comforts in the villager's house (out of scope: a
comfort is held, used up and gone), and the Builder buying torches from labourers for
its houses.

### 24. Demand for the crafts with none

ColonyFood at day 416 (main b8d3957, 2026-11-16): 7 of 23 adults hold under 25
emeralds, among them the leatherworker (0, holding 76 beef), the three shepherds (14, 9
and 104), the fletcher (0, starving, wanting 23 flint) and the cleric (15). The alchemist
has heard nothing (`heard=0`) and holds 1,161 emeralds it cannot spend well. Comfort
prices sit at ×4.

**The cleric eats free** (`meal.lua`). It lives on alms and sells nothing a village wants,
so a dinner at 1 emerald was one it could not always pay. At the tavern it pays nothing,
as the keeper's household does. Not the alchemist, a cleric underneath, which never eats.

**The alchemist hears everything** (`market_news.lua`, `market.lua`, `trade_trips.lua`).
It goes to neither the tavern nor the church, and talked once in 70 minutes, so it never
learnt who had stone and logs to spare or who wanted its nuggets.
- **Overhearing** (`market_news.overhear`, installed by `market_news.install`): every
  OVERHEAR_SECONDS (60) it takes in the own news (`market_news.own`) of every loaded adult
  villager, a hop away, and keeps up to OVERHEAR_ENTRIES (96) rather than 24. It makes its
  prices' daily move there first, which a villager otherwise makes in its first
  conversation, so its reference prices for stone and logs follow what the village needs
  and has, and with them whether glass, flint or nuggets pay (ticket 21d).
- **No stall.** On a holiday it goes to the bell and browses the stalls, buying there as
  any browser does (`market_stall.serve`), and opens none of its own (`market.eligible`:
  `alchemist`). It tells its news in the conversations there.
- **Straight to a seller.** It plans trade trips in its work stage too, as the Builder
  does, since its timetable has almost no putter time: it walks to whoever it heard has
  the stone or logs its plan wants, at the seller's home, its stall or its stash.

**New comforts** (`comforts.lua`, `goods.lua`, `recipes.lua`). The leatherworker and the
fletcher had goods nobody wanted for themselves, and the shepherds' wool went only into
banners, paintings and white carpet.

| Comfort | Made by | Days |
|---|---|---|
| A carpet (any colour) | Shepherd, two wool for three at sale | 4 |
| Arrow | Fletcher, 4 from a flint, a stick and a feather | 2 |
| Leather cap (`helmet_leather`) | Leatherworker, 5 leather | 10 |
| Leather boots | Leatherworker, 4 leather | 10 |
| Leather tunic (`chestplate_leather`) | Leatherworker, 8 leather | 12 |
| Leather pants (`leggings_leather`) | Leatherworker, 7 leather | 12 |
| Bow | Fletcher, 3 sticks and 3 string | 12 |

- **A carpet** is a category, as a flower is (`goods.CATEGORIES.carpet`, the 16 colours,
  after `flower` in ORDER): any colour fills the slot, so the shepherds' grey, black and
  brown wool sells as carpet too. An old save's white carpet in use keeps its days, and a
  per-item white carpet price folds into `group:carpet` (`prices.migrate`).
- **The leatherworker crafts** at its cauldron, from vanilla's armour recipes (its trade
  table sells all four). Its leather still goes to the librarian and the cartographer when
  that pays better: production by margin decides. An input a profession makes itself
  (`ledger.lua`'s MAKES) is now wanted for one craft, not a batch (`ledger.inputs`), so the
  leatherworker holds 8 leather, not 32, before it sells; the shepherd likewise holds one
  grey wool for its white, and sells the rest, as carpet or wool.
- **The fletcher** already made bows and arrows; now they sell, and pay for the flint its
  arrows need.
- VoxeLibre 0.92 has no bundle and no harness, so neither is a comfort.
- With 17 comforts and 4 tastes each villager's tastes change (they are rolled by `_id`
  over the list); a comfort in use from a taste it no longer has is used up as before.

**The butcher's chickens** (`coop.lua`). Nobody made feathers, an input of every arrow. A
butcher with a jobsite (not the keeper) keeps a flock as the leatherworker keeps its herd
(11e): chickens marked `_villages_coop`, bound to the jobsite by `herd.keep_near` (back
past 10, set down beside it past 20 with no player near).
- **Never given any.** No chickens are spawned for it. While its flock, chicks included,
  is under MIN_FLOCK (2), the next unmarked chicken or chick within ADOPT_RADIUS (10) of
  the jobsite joins it: the player lures some there, or hands the butcher eggs.
- **Eggs.** In its work stage it picks up the eggs its hens lay within 16 of the jobsite
  (up to 16 held; eggs have no price, so it keeps them). With a flock under MIN_FLOCK it
  throws one every THROW_SECONDS (20) near the jobsite through `mcl_throwing`, as a player
  would: a chick one time in eight, which then joins the flock.
- **Tending**, every TEND_SECONDS (300) of work: a feather from each adult (up to 64
  held), then with more than COOP_SIZE (4) adults it slaughters one for a raw chicken and
  0 to 2 feathers (vanilla's drops), or else, with two adults, room for a chick and 2
  wheat seeds, it breeds them. It wants 4 wheat seeds held (`possessions.assess`), bought
  from the farmers.
- Feathers and raw chicken are its own make (`ledger.lua`'s MAKES): it sells feathers, and
  cooks its chicken at the smoker.

**Why comfort prices are stuck at ×4.** Not a fault in the arithmetic. COUNT_SPAN (4) is
as far as the daily balance of needs and offers can take a price from its base (21b); a
trade or a heard price can take it further. Painting (×3.99), banner (×3.99), bookshelf
(×3.97) and white carpet (×3.91) had demand told every day and no offer at all, so every
villager's price climbed to the ceiling and stayed, with nothing to bring it down. They
had no offer because their inputs never came: labourers planned a painting about 1,000
times in the run and made one (no wool), the librarian made 4 bookshelves and sold none
(books need leather), one banner sold and 4 carpets. Comforts that do sell, barrels (42)
and armor stands (25), are not at the ceiling. The fix is supply, which this ticket's
leather, wool and feathers go toward.

One side effect of 23d's floor is worth watching: a comfort is asked at no less than half
the best bid heard, and the best bid is the richest bidder's. The cartographer asked
3,296 for an item frame, a bid from the villager with 4,054 emeralds, while 12 frames sat
unsold and the other bidders held a few hundred. The ask came down as that bid aged (453
by day 416). If it recurs, ask the bid that would clear the seller's spare (the n-th best
for n held) instead of the best.

- **Tests:** `tests/meal.lua` (the cleric eats free with no emerald); `tests/market_news.lua`
  (the alchemist overhears every loaded adult's news, a hop away, past NEWS_ENTRIES, never
  a child's or its own, and makes its prices' day move); `tests/market.lua` (the alchemist
  opens no stall); `tests/trade_trips.lua` (the alchemist plans a trip for cobble in its
  work stage); `tests/comforts.lua` (a grey carpet fills a carpet slot; leather clothes,
  bows and arrows are wanted); `tests/coop.lua` (no chickens of its own; eggs thrown only under MIN_FLOCK, one a
  THROW_SECONDS; a hatched chick and a lured hen join, a third does not; eggs picked up; a
  stray set back; a feather a hen, a chick bred on 2 seeds, a slaughter past 4 adults;
  wheat seeds wanted, not by the keeper).

### 25. Dinner that catches up

**What happened.** In ColonyFood (days 424-429, main 33cec90), dinner cost 1 emerald,
the farm chests held about 480 potatoes, and still 6 to 12 adults woke hungry each day.
Each morning the adults stood in two groups 4 points apart, about 5.5 and about 1.5. A
dish is 4 points and an adult loses 4 a day, so one dinner a day only held a guest where
it was, and one that missed a dinner stayed 4 points down for good. Between dinners a
starving villager ate only up to 4, out of starving and no further. On day 428 the keeper
could not reach either farm chest, the pantry was empty, 16 adults went without, and 5
woke starving. Villagers holding bread and hundreds of emeralds stayed hungry, because
they had already dined that day.

- **Seconds** (`meal.lua`). Once a villager guest has been served a dish, it is served
  more, one dish after another, while it is still at or below EAT_AT (8), up to
  MAX_DISHES (3) in all. That is enough to take it from 0 to 12. Each dish is paid at the
  price of the first and counted toward the evening's demand (`dinner.served`). Only dishes
  count: a raw plate is a last resort and is never a second. If the pantry has no dish
  left, it counts as running out (`dinner.ran_out`), as it does for a guest who found none.
  Each payment is logged as "for another dish", and the seconds as "had N more dish(es)".
- **Eat to full when starving** (`possessions.lua`). A villager still eats between dinners
  only when starving, but it then eats everything it has, raw food too, best first, until
  full (12) or until it has nothing left.
- **Stock margin** (`keeper_supply.lua`). The keeper stocks the pantry to the last
  evening's demand plus a quarter (STOCK_MARGIN 1.25, rounded up), at least TARGET_MEALS.
  It had been stocking exactly 21 for 21 diners, which left 5 dishes after dinner and
  nothing to cover a day it could not fetch.
- **Tests:** `tests/meal.lua` (three loaves from 0, two from 4, the pantry running out on
  seconds, carrots never a second); `tests/possessions.lua` (starving, it eats all it has
  up to 12 and no further, its raw catch too); `tests/keeper_supply.lua` (30 wanted, 38
  stocked).

### 26. Making what nobody sells

ColonyFood at day 693 (5ebbfc7, 2026-11-19): money is stable at 14.2k but sits with
whoever wants only what nobody offers. The fletcher's 7.2k went to the leatherworker for
three leather caps, and on to the cartographer for item frames; the cartographer now holds
6.6k and wants a bookshelf, a white banner and glass panes, none of them offered. Trade fell
from 67 deals in ten days to 14-37. Four unemployed villagers and the mason hold 2-19
emeralds and starve on and off; they portered on 565 days and were hired 19 times, always
for bread, fish or wheat that the client could have fetched itself. Three things kept the
poorest from making what the rich want:

- **The alchemist is never heard.** It opens no stall and goes nowhere news is told, and
  ticket 24's overhearing ran one way. It held 63 nuggets at 0.29 while labourers planned a
  lantern 880 times and two villagers bid 2,081 for one: no villager heard of a nugget for
  sale, and none was ever traded. With no sales it had no emeralds, so it bought no stone or
  logs, and glass, flint and iron stopped.
- **The poorest cannot pay for inputs.** A painting's wool costs about 120, a lantern's
  nuggets about 100 at their reference price; they hold under 20, and the money factor
  lowers their bids further.
- **A crafter values a good it makes for itself at its market price.** The cartographer
  makes banners and wants three at 3,072 each, but valued white wool at 60 (a banner's
  reference price over six wool) while the shepherds asked 120.

Labourers making banners and bookshelves (raised in review) waits for these to land.

#### 26a. The alchemist is overheard

`market_news.overhear` also hands the alchemist's own news (`market_news.own`) to every
loaded adult villager it overheard, a hop away, as if told face to face, each trimmed to
NEWS_ENTRIES. A buyer then plans a trip to it as to any seller (`trade_trips.plan`): to its
bed, then after it where it stands. Its asks start at its own low value and rise with each
sale (`asks.lua`), so its emeralds come back and it buys stone and logs again. The log line
says how many entries it took in and how many the others kept of its news.

- **Tests:** `tests/market_news.lua` (four villagers hear of its nuggets at first hand, a
  child hears nothing, the same news again is nothing new).

#### 26b. Commissions

A porter is paid to walk, and walking is cheap, so nobody hires one. What a rich villager
cannot get is a good nobody has. A commission is portering with a craft in the middle: the
client pays a labourer up front to make the good and bring it. The porter hire stays as the
case with no craft. Saved state keeps its names (the activity is still `porter`).

- **Hire** (`trade_trips.hire`, end of a conversation, the same once-a-day client rules). A
  client with no porter trip to plan (`trade_trips.plan` finds no seller) commissions instead
  when one of its urgent needs (urgency at least URGENT) is the output of a labour recipe
  (`recipes.labour`). The price is the recipe's inputs at the client's prices
  (`possessions.prices_of`, a category at its cheapest member) times PRICE_SLACK, plus
  PORTER_FEE, at most PURSE. The client pays it only when it values the output at least that
  much and holds it. It is handed over in full, as a porter's purse is: that money is what
  lets one with 3 emeralds buy wool at 120.
- **The commission** (`_villages_commission` on the worker, saved: recipe index, item,
  count, client id, delivery chest, price, day). While it lasts:
  - the worker's labour plan is the commissioned recipe (`possessions.labour_plan`), its
    input caps reckoned with the output at the client's value, so the inputs are needs with
    23d's floors and are told as news;
  - the output is a target worth the client's value to it, so it never sells it;
  - it plans trade trips for the inputs in its work stage too, as the alchemist does, with
    its own emeralds (the price included);
  - it crafts at home as any labourer does (`production.labour_work`).
- **Delivery.** Holding the count, it walks to the client's delivery chest (its stash, or a
  Builder's bench chest) on the porter's delivery leg and leaves the goods. What it did not
  spend of the price is its pay.
- **Expiry.** A commission not delivered once the worker has had WORK_DAYS (2) work stages
  since the hire, or within MAX_DAYS (6) days, is dropped: the worker leaves the price, or
  what it still holds of it, in the client's chest, and keeps any inputs it bought. At first
  it lasted to the end of the day after the hire; hires fall at the evening tavern, so that
  left one work stage, none when the day was a holiday (every fourth), and all four of
  ColonyFood's first commissions ran out (2026-11-19): two porters never worked, one bought
  the nuggets in its last minutes, one found the alchemist's stash empty.
- **Choosing the work** (`labour.lua`). A commission counts as a porter hire in the porter's
  record, so villagers who are commissioned choose portering again.
- **As built** (`commission.lua`). Only the labour goods no labour recipe takes in are
  commissioned (`commission.goods`: not planks, sticks or torches), and a heard need for one
  opens portering (`labour.craft_waiting`). A client orders no second commission for a good
  while one is out (`_villages_commissioned`). The undelivered price counts neither in the
  worker's money factor nor toward its comforts (`commission.reserve`). The commissioned
  craft is made at the price (`production.choose` asks no less for its output).
- **The client's goods** (`possessions.owed`, `possessions.take_own`). What a worker
  carries for another, a commission's output and a porter's purchase on the way to its
  client, is never taken up as its own comfort, nor put in its stash. In ColonyFood
  (2026-11-20, day 776) a porter that wanted a barrel itself enjoyed the one it had just
  made for its client, a second later, and delivered nothing.
- **Tests:** `tests/trade_trips.lua` (a client with no seller for a lantern commissions a
  porter at the price; the plan, the inputs as needs, the output held back, the reserve; no
  second for the same good; made and delivered with the price kept; run out, the price
  returned and the inputs kept; none over what the client holds); `tests/labour.lua` (a
  heard need for a lantern opens portering, one for sticks does not; a commission keeps it
  portering); `tests/possessions.lua` (`take_own` leaves a porter's and a commission's
  goods).

#### 26d. Making for itself

A crafter that needs one of its own outputs reckons that output at no less than its own
value for it, not only its market price: in its inputs' caps (`possessions.assess`'s
`ledger.imputed`, recomputed with the lifted price when an output is among its needs) and in
what a craft gains (`production.choose`, `production.labour_plan`). The cartographer then
values six wool for a 3,072 banner near 500 each, buys at the shepherds' 120 and makes its
own banners. The lift covers only the outputs it needs, and only up to its need, so what it
makes to sell is priced as before.

- **Tests:** `tests/possessions.lua` (wool caps for a cartographer needing banners, and not
  for one that does not); `tests/production.lua` (it makes a banner for itself where the
  market price would not pay).

#### 26e. Goods left in the stash

- **Problem.** A buyer that finds the seller away and out of reach buys from its stash,
  but a stash only held what was put in it: emeralds and food, never goods. The
  alchemist carried 228 spare nuggets, its value for them down to 8, while three of seven
  trips for them found it out and its stash empty, among them a commission's porter
  (ColonyFood, days 700-735). Its rate of making them was never the limit.
- **Rule** (`possessions.stash_spare`). Within STASH_REACH of its stash, and near its bed
  as it gets up, a villager puts its spare goods in the stash, keeping half of each
  surplus, at most CARRY (8), on itself for sales in person (exchange.lua sells from
  belongings). Food stays with it (it eats from its belongings first), and emeralds, and
  a peddler's stock, its trade being to carry it. What the chest has no room for stays
  carried. What it holds (belongings and stash) is unchanged, so its asks and news are.
- **Room left.** It leaves STASH_FREE_SLOTS (3) slots free, topping up stacks it already
  has there, so what a porter, a commission or a purchase brings still fits. A porter
  that finds the delivery chest full anyway hands what does not fit, goods and change, to
  the client in person if it is within TRIP_RADIUS of the chest; otherwise it keeps them
  and logs it. In ColonyFood (2026-11-19, day 763) a leatherworker's stash held 576 logs
  and charcoal in all 27 slots, and the armorer kept the armor stand it was paid 65 to
  make, and the price.
- **Tests:** `tests/possessions.lua` (only within reach; keeps 8 of 40 nuggets; a single
  spare lantern stays carried; food and emeralds stay; nothing more once only the keep is
  carried; a full chest; a peddler keeps its stock; 3 slots left free);
  `tests/trade_trips.lua` (a full delivery chest: handed over in person, the change too,
  kept with the client away).

### 27. The tavern pays its way

- **Problem.** The keeper's tab was meant for fractions: what a purse cannot pay in whole
  emeralds. It took the food whatever it could pay, and owed the rest up to a cap that
  grew with the tavern (22c). By ColonyFood day 809 (2026-11-20) it owed the two farm
  chests 987 and 959, about 1,950 of the village's 8,200, and the debt rose about 15 a
  day. It fetched about 28 meals a day at a food cost of about 1.2 each and took in 17 to
  20 from dinners: dinner posted 1 (1.2 × factor 0.97, rounded), a third of the food fed
  diners who pay nothing (the keeper's household, two clerics, seconds), and one of
  those clerics held 2,700 emeralds. Meanwhile bread traded at 8.5 and potatoes at 1.7 in
  the street, and the farm chests held 483 potatoes: food was plentiful, money short,
  and the tab hid the gap from the price.
- **Rule: only what it pays for** (`keeper_supply.fetch`). It takes, item by item, only
  as much food as its purse pays for at the food cost; the fraction left it owes, up to
  TAB_CAP (1). A tab over that, from before, is written off when it next fetches there
  (`write_off`, logged): money the farms never held.
- **Its float as working capital** (`take_purse`). Short in the pantry, its purse tops up
  from its own emeralds (the float, refilled from the pantry on shift), so a pantry that
  has run out of money still buys the food the next dinners pay for.
- **The price follows the food** (`dinner.dear`). When dinner money did not pay for the
  food (it went without some the pantry lacked, or paid from its float) the dinner factor
  goes up MARKUP the next day, as when it runs out, and the log says so ("food dearer than
  dinners pay"). At about 1.2 a meal the price should move between 1 and 2.
- **A rich cleric pays** (`meal.lua`). The cleric eats free only with no more than 8
  dinners' savings at its own price for one (alms.lua's SAVINGS); over that it pays and
  always dines, never weighing the price, since a cleric that weighed it starved (ticket
  24). The keeper's household still eats free.
- **Tests:** `tests/keeper_supply.lua` (a fraction owed and paid first; a purse of 40
  takes the 20 potatoes it pays for and raises the next day's dinner; with no dinner money
  its float pays, and that raises it too; an old tab of 987.39 written off and nothing
  taken from the purse for it; the cap stays 1); `tests/meal.lua` (a cleric with 3,000
  pays into the pantry).

### 28. The alchemist spends on stone and wood

- **Problem.** The alchemist was the village's money sink. In ColonyFood (2026-11-20, days
  772-816) it held 2,745 of the village's 8,200 emeralds, earned 540 from trades and spent
  37. Its goods were priced at their inputs' cost and its bids at what its goods returned
  (ledger.imputed, 21d), so a glut of stone and logs drove both down together: it believed
  stone worth 0.05, a log 0.25 and charcoal 0.07, and bid 0.01 for cobble, while flint
  sold at 8.5 and 2,500 logs, 1,100 cobble and 890 charcoal lay unsold. A glut of nuggets
  (217) made nuggets lose, so it wanted no stone either. Alms were not to be the only way
  out: the money should go to those who quarry and cut wood.
- **28a. A daily budget** (`alchemist.floors`). Each day it means to spend what it holds over
  RESERVE_DINNERS (8) dinners, at its own price for one, over SPEND_DAYS (30), on the day's
  wants: 72 stone or cobble, 8 lumps' worth of fuel, and logs for the flint it is short
  of. The budget is shared by base price, so the day's wants at those prices cost the
  budget, and each is a least value (`least`, after the money factor) on its members. At
  2,745 emeralds that is about 91 a day: 0.37 a stone or cobble, 1.9 a log and 0.55 a lump
  of charcoal. Recomputed each day from what it holds, it spends its savings and its
  takings down together, and stops at its reserve.
- **28b. A share of its takings.** What it last sold each good for is kept
  (`_villages_sold_at`, in asks.sold, any sale of an alchemist's); an input's least value is
  also SALE_SHARE (0.5) of that over the input count: flint at 8.5 makes a log worth 1.06.
  The greater of 28a and 28b stands, so a good that sells dear lifts its input at once.
- **28c. Fuel.** Each of its crafts burns half a lump (`fuel = 4` smelts, recipes.lua): a
  buyer for charcoal and, after charcoal and coal, logs (production.lua burns them for an
  alchemist, though its flint takes them, since its ledger counts logs as fuel). The fuel
  is in its goods' cost (ledger.lua's COST_PRICED), so an ingot is still nine nuggets: a
  nugget's base price is 15.1 (12.8 before), an ingot's 136, an iron helmet's 856 (724).
- **It works its stand.** It wants stone, fuel and logs whether its goods pay or not
  (`targets(held)`, no `unpaid`), and makes them at a loss too, by rank after any that
  pays (production.choose), so its budget turns into work and nuggets, not idle stone.
- **Its bids move prices.** A buyer pays the seller's ask, so a higher bid alone would
  only buy more at the glut's price. Stone, logs, planks and fuel are now asked at no
  less than asks.BID_SHARE (0.5) of the best bid heard in the news (`bid_priced`), a
  category's bid counted per unit, as comforts have been since 23d. Not at a bid made to
  the seller's face (`with_bid` stays comforts only): there an urgent buyer, a porter
  carrying a smith's purse, would hand over most of its value for coal.
- **Not done.** Placing Builder orders (public works) was ruled out: no villager places
  Builder orders.
- **Tests:** `tests/alchemist_trade.lua` (18 nuggets burn 9 lumps; no fuel, no craft; flint
  burns charcoal, then logs; nuggets at a loss at 32 flint; fuel wanted; the input cap less
  the fuel; the budget's floors cost the budget, follow its dinner scale and stop at its
  reserve; half of flint's 8.5 over four logs; the greater stands; a nugget glut no longer
  zeroes its cobble bid; sales kept, an alchemist's only; a quarrier asks half the
  alchemist's per-unit stone bid for cobble; bread is not bid-priced); `tests/ledger.lua`
  (fuel in the alchemist's goods, an ingot still nine nuggets, iron goods' new floors).

### 29. A use for iron

- **Problem.** The alchemist makes nuggets without end (28), but iron barely sold. In
  ColonyFood (days 772-816) about 68 nuggets changed hands for 73 emeralds, 20 of them
  the alchemist's; it held 217, asked about 0.2 each. Two reasons:
  - **Ingot trips failed.** 20 trips set off for the alchemist's ingots (mostly the
    armorer's, for 31-32), and all 20 failed. The news told an ingot at nine nuggets' ask
    (16.37), but to its face trade_trips priced the ingot without the conversion, at an
    ingot's own price ("asks 149.42 each, over our 138.79"), and its stash, holding only
    nuggets, had "0" ingots.
  - **Nobody needs iron goods.** No villager wants iron armour or tools; the lanterns
    (8 nuggets) were the only outlet. The armorer had nothing to sell and 12 emeralds.
- **29a. Ingots by conversion on trips.** A product told from a conversion carries its
  sources (`from`, `ratio`, `takes`, `reserve`) in the news entry and the trip. To its
  face the seller asks the lowest of its own stock's ask and each conversion's it has
  the sources for (trade_trips' `in_person_ask`), as exchange.offer sells. A stash
  holding none of the product sells whole batches of its sources, at the told price.
- **29b. Iron tools.** Every tool (wants.lua) comes in stone, iron, gold and diamond tiers,
  the hoe and pick wood too (the tool smith's first ones). Each better tier works faster
  (a hoe yields more); gold works as well as diamond but wears out fastest of all:

  | Tool | Wood | Stone | Iron | Gold | Diamond |
  |---|---|---|---|---|---|
  | Hoe (yield) | 30 × 1.25 | 64 × 1.5 | 128 × 2 | 16 × 2.5 | 512 × 2.5 |
  | Axe (felling) | | 32 × 1.5 | 64 × 2 | 8 × 2.5 | 256 × 2.5 |
  | Pick (mining) | 30 × 2 | 64 × 3 | 128 × 4 | 16 × 5 | 512 × 5 |

  (uses × rate). Each asks for the iron tier and, while it has none in use at all, the
  stone one too (`starter`), so it never waits by hand for iron. It takes up the best it
  holds, so with a stone one in use the iron one is asked for again only when it is
  nearly worn. At base prices each iron tool pays: a hoe 819 against 347, an axe 5,120
  against 518, a pick 983 against 518. The tool smith makes the pick (3 ingots, 2 sticks,
  3 smelts) and the hoe (2 ingots, 2 sticks, 2 smelts); the weapon smith's iron axe,
  which no villager bought, is the woodcutter's.
- **The pick hastens the generator too.** labour.lua refills a mined cell REGEN_SECONDS
  over the pick's rate (19d), so with the cap of 4 lifted, gold and diamond picks both
  mine (1.6 s a block) and refill (0.2 s) faster.
- **29c. A cauldron comfort.** The armorer makes a cauldron from 7 ingots (7 smelts), a
  comfort lasting 12 days. Adding a comfort reshuffles every villager's tastes (they are
  picked from the list by `_id`), as ticket 24 did.
- **29d. A clock comfort, for gold.** No recipe took gold, so the alchemist's gold (an
  ingot from 162 nuggets past its 108 reserve) had no buyer, and a gold tool, at three
  gold ingots (about 9,200), could never pay over its 16 uses. The cleric makes a clock
  from one gold ingot and one iron ingot, a comfort lasting 12 days: cheaper than a
  player's craft (four gold and a redstone), which is unchanged. A cleric's vanilla
  trades still restock with nothing to make a clock from, as a shepherd's do
  (production.restock_held). A player's held clock turns into one of VoxeLibre's 64
  frames (`mcl_clock:clock_N`), which is no comfort; villagers' and chests' stay
  `mcl_clock:clock`.
- **Pricing.** Neither the iron pick, the iron hoe, the cauldron nor the clock has a trade
  table price, so the cost floor now prices a recipe output from iron, gold or flint that
  nothing else prices: the pick at 518 (1.25 × 3 ingots, 2 sticks and fuel), the hoe at
  347, the cauldron at 1,198 and the clock at 3,238. Its real price follows the
  alchemist's: at a nugget ask of 0.2 a gold ingot is 32.
- **Tests:** `tests/trade_trips.lua` (three ingots from 30 nuggets in a stash, 3 left; none
  without the sources told; a plan carries them; an alchemist holding only nuggets sells
  ingots to its face at nine nuggets' ask); `tests/alchemist_trade.lua` (a told ingot
  carries its sources); `tests/wants.lua` (a quarrier asks for both picks, none with a fresh
  stone one, only the iron one when nearly worn, takes up the iron one first; every tool
  has the four tiers, faster by tier, gold as fast as diamond and wearing out first, the
  iron one asked for and paying at base prices; an iron axe fells at 2, a gold pick mines
  at 5); `tests/labour.lua` (a stone, iron and gold pick refill the generator in 1/3, 1/4
  and 1/5 of REGEN_SECONDS); `tests/production.lua` (a cleric restocks with nothing to make
  a clock from, and makes one from a gold and an iron ingot); `tests/ledger.lua` (the floor
  prices of the pick, cauldron and clock; the cleric wants gold;
  the tool smith wants ingots); `tests/need_bubble.lua`, `tests/production.lua`.

### 30. The alchemist breaks even

- **Problem.** On ticket 28 (ColonyFood, days 820-826) the alchemist paid 0.18 for cobble,
  1.0 for charcoal and up to 1.75 for logs, so a nugget cost it 1.22 and it sold one for
  1.0; flint, about 6.5's worth, sold for 2.25. It asked 0.95 for a nugget while it
  believed one worth 0.24: a seller never asked under its own value, and the money factor
  of its 2,600 emeralds raised that fourfold; its bids for inputs were raised alike (stone
  at 1.33). Its takings floor (28b) never acted: its only sale was at its stash, and a
  stash sale reached neither its ask nor its record. It made 9 nuggets and 13 flint in 7
  days, short of fuel, buying sticks at 4.4 a lump's worth.
- **Its book.** It keeps the average it paid for a unit of stone, log and fuel (a burn
  second) over what it holds (`_villages_input_cost`, `alchemist.bought`, from
  exchange.settle, a stash purchase and the trade window); a recipe's cost is its inputs
  and fuel at those (`alchemist.cost`), and its stock of each good is at the average cost
  it was made at (`_villages_made_cost`, `alchemist.made`, from production.make). Stock
  from before the book is entered at its reference price once, then kept: a seed that
  followed the reference would rise with every sale at the margin.
- **30a. Asks at cost.** An alchemist asks for its goods no less than their stock cost
  times MARGIN (1.05), an ingot nine nuggets', and no longer its own value (asks.ask), so
  its wealth is in none of its prices.
- **30b. Bids at what its goods pay.** For each recipe it would still make (under its
  `upto`), its good's sale price (`_villages_sold_at`, else its reference price) over its
  cost at the book scales the book's unit costs; the best recipe's is each category's
  cap (`alchemist.caps`), applied after the money factor and `least` (ledger.assess's new
  `ceiling`). At its caps a craft costs what its good sells for. A stick is capped at a
  lump's burn second (5 of 80), so a dear stick is passed over. At its stops every cap
  is 0. 28b's half-share floor is gone: the cap is the whole share.
- **Its budget (28a) buys stock ahead.** The budget's floors stand above the caps (the
  ceiling is the greater): it turns its savings into a day's stock of inputs, which its
  targets bound, and what it pays goes into its book, so its asks cover it. Its hoard
  drains into stock that sells at cost, never into losses.
- **30c. Stops and output.** Nuggets stop at NUGGET_KEEP (192), and the gold reserve falls
  from 108 to 24, so a gold ingot's 162 still fits under the stop. A day makes twice what
  it did: 72 glass, 12 flint or 36 nuggets (`share` halved); a day's wants double to 144
  stone, 16 lumps' worth of fuel and up to 48 logs.
- **Stash sales count.** A purchase from a stash whose owner is loaded is counted as its
  sale (asks.sold, for the product and its sources): its ask and reference learn it, and
  an alchemist keeps the price.
- **Tests:** `tests/alchemist_trade.lua` (pace and a day's wants at twice; nugget stop and
  room for gold; asks at cost and margin, entered once, not raised by a dearer reference
  or its wealth; the budget's floors; the book's averages, a nugget's cost and stock
  cost, an ingot at nine, none for a plain villager, a settled trade booked; caps break
  even, logs only as fuel at flint's stop, sticks at a lump's burn second, 0 at its stops
  so a rich one bids only its budget floor and a broke one nothing; the bid between its
  floor and caps); `tests/trade_trips.lua` (a stash sale reaches its loaded owner's asks
  and record, per ingot and per nugget); `tests/trade_window.lua` (an ingot at its cost and
  margin; gold past 24).

### 33. The tavern keeper's window

Every villager but the keeper traded through the mod's window (ticket 14); the keeper still
opened vanilla's, with keeper.lua's fixed menu (3 bread for 1 emerald) and tiers, outside the
economy. Now it opens the mod's window like everyone else (`trade_window.lua`):

- **It sells its pantry's dishes.** Each `keeper.MENU` dish in the pantry is a row, one
  dinner at its posted dinner price (`dinner.posted`), reputation's share off as anyone's.
  The player pays into the pantry, the tavern's till, as for a meal at a table
  (`player_meals.lua`), so the money reaches the farms as dinner money does.
- **It keeps dinner.** It sells only the meals past the last evening's demand
  (`dinner.demand`, cookable potatoes counted as `keeper_supply.meals` counts them), so a
  player cannot empty the pantry before the village eats.
- **It buys as anyone.** Its needs are its role's inputs (bread, potatoes, cooked fish and
  beef, `ledger.lua`), bought at its value from its float; keeper_supply.lua carries them to
  the pantry on its shift. With no pantry it sells what it holds, as anyone.
- With the economy off it keeps vanilla's window and menu, as everyone does.
- **Tests:** `tests/trade_window.lua` (rows from the pantry past the reserve, not its
  surplus; the friend's share; the window named for the keeper; a purchase takes the
  dishes and pays the pantry, not its purse).

### 34. Variety in meals

Food was valued by its points alone, so nothing told a villager what it had eaten before:
villages settled on one dish (bread, the baked potato), and the tavern served what it had.
Now a villager tires of a food it ate a lot of lately (`variety.lua`). It is worth less to it,
though it feeds as much, so it buys, eats and dines on others first, and the tavern follows.

- **The record.** Every adult meal goes through `food.receive`, which notes it in
  `_villages_meals`, `{[day] = {[item] = count}}` over the last 7 days. That covers tavern
  dishes, seconds, raw plates and food eaten at home. A child's feeds are not noted.
- **The factor.** A meal weighs (7 - age) / 7. An item's share is its weight over all the
  weight plus PRIOR (3) meals, so one meal is not a whole diet, and its factor is
  1 - DEPTH (0.5) × share. Bread every day for a week gives about 0.71, two dishes in turn
  about 0.85 each, and a whole diet of one food no less than 0.5. No food becomes worthless.
- **Values.** `ledger.assess` multiplies a food's value by its factor (`input.variety`,
  before `worth`, `least` and `ceiling`). Needs, targets and points don't change, so a
  villager wants as much food as before, but exchange.lua's trades, chosen by buyer value
  over the ask, buy the food it is tired of last. A starving villager tires of nothing (food
  first, ticket 22b), and nor does the alchemist, which doesn't eat.
- **Eating at home.** `possessions.eat` takes the food with the most points × factor, from
  its belongings and then its stash. A pie still beats a fresh loaf.
- **The tavern.** A villager guest is served the dish it is least tired of, at random among
  equals; a player is served any. `dinner.wants` values a dinner at a loaf's worth without
  bread's own factor, times the best factor among the dishes on offer. A tavern serving one
  dish to tired guests is turned down more, and `dinner.turned` marks its price down.
- **The keeper.** Each dish served, seconds too, is noted on the keeper
  (`_villages_served_dishes`). Its buying (`possessions.variety_of`) follows that record, so it
  bids less for the inputs of the dish it served most (a potato counts as the baked potato it
  makes) and buys the others first. Its farm fetches don't change.
- **Tests:** `tests/variety.lua` (weights, PRIOR, the floor, trimming past the week, one dish
  against two in turn, `best`); `tests/ledger.lua` (food values only, needs unchanged);
  `tests/possessions.lua` (eating the less eaten food, a pie over a loaf, values, starving,
  the keeper's record); `tests/dinner.lua` (tired of the only dish against a new one, starving
  tires of nothing); `tests/meal.lua` (served the less eaten dish, noted on guest and keeper).

### 35. A little of every dish

Since ticket 34 a guest is served the dish it is least tired of, but the tavern could hold only
dishes it is tired of. The keeper bought from a fixed list (bread, potatoes, cooked fish, cooked
beef) whatever the pantry held, and only `keeper.MENU` dishes were ever shelved or served, so a
cooked chicken it bought never reached a plate. Now it keeps a few of every dish it has heard of:

- **Dishes it knows.** A keeper notes each prepared food it hears offered ("has" news,
  `market_news.lua`'s `receive`) in `_villages_known_dishes` (item to day). It hears every
  diner's news at the tavern. One not heard of in `KNOWN_DAYS` (7) is forgotten, so it doesn't
  chase a seller that is gone (`keeper.known_dishes`).
- **A minimum stock.** On its shift `keeper_supply.dish_wants` sets `_villages_dish_wants`:
  `MIN_DISHES` (3) less what the pantry holds of each known dish, 0 when it has enough. Its
  fixed inputs (wanted already) and the baked potato it bakes are left out.
  `possessions.assess` adds each to `extra`, no fewer than it holds, so a dish it carries to the
  pantry is never spare. A shortfall is a need like any, in its news, trades and porter hires.
- **Never at a loss.** Its value for such a dish is capped at its dinner price (`worth`): a dish
  served earns one dinner. While dinner is cheap, a dear dish isn't bought. The fixed inputs
  keep their values as they were.
- **Every dish reaches a plate.** The menu is `keeper.dishes()`: MENU's, then every other
  prepared food. The meal, the pantry's meal count, the keeper's own meals, shelving and the
  trade window all use it. Shelving takes from its stash too, where a porter leaves what it
  bought.
- **Guards.** At most 3 of each dish, at no more than a dinner, so the float isn't drained and a
  hungry villager who values food more outbids it. It forgets a dish after a week, and porter
  hires stay one a day. A pantry holding the new dishes counts them as meals, so the keeper
  fetches a little less from the farms.
- **Tests:** `tests/keeper.lua` (dishes' order, known dishes forgotten after a week);
  `tests/keeper_supply.lua` (wants to 3, 0 when stocked, none for fixed inputs, the baked potato
  or a forgotten dish; a new dish counts as a meal and is shelved); `tests/possessions.lua` (a
  need, capped at the dinner, a carried dish not spare); `tests/market_news.lua` (a keeper notes
  an offered dish, not a need, not a raw food, no one else); `tests/meal.lua` (a cooked chicken
  served).

### 36. Donations at the cleric only

Every villager's window had a "Give emeralds" field (ticket 21a). A gift of 8 dinners was
`major_positive` (100 reputation, which never fades) on top of `minor_positive` (25), so a
player could buy the best prices with money alone. Now only donations to the cleric count,
and they count for little. A player should earn a good name by trading, selling to urgent
needs and errands.

- **The window.** Only the cleric's window (`trade_window.takes_donations`: a cleric, not
  the keeper or the alchemist) has a field, "Donate to the alms fund". A donation goes to
  the fund as a villager's does (`alms.receive`): the cleric keeps a tenth, and the rest
  goes to the poor at the next holiday, with anything over the fund's target paid out
  toward `SAVINGS`. Money a player gives still reaches the village.
- **Reputation.** A donation of a dinner or more (`DONATION_MIN`, at the cleric's scale) is
  `donation` gossip (gossip.lua: gain 5, cap 10, decays 1 a game day, shared less 3). It
  counts once a day per player (`_villages_donors` on the cleric, holding only today).
  Donations alone get a player 10 at the cleric, a 2.5% discount (the discount maxes at
  100), and 7 or less at the villagers who hear of it. Trading caps at 25 and good deeds at
  25 plus 100.
- **Other ways to give.** Emeralds left in a villager's stash are still collected. Emeralds
  thrown to a villager are now picked up (`possessions.pick_up`, through vanilla's item
  pickup, which waits until no player is within 2 nodes). An adult takes them into its
  belongings; a child leaves them. Neither way makes gossip. Before this, villagers picked
  up only food.
- **Kept.** `major_positive` and `minor_positive` gossip already earned by gifts stays until
  it fades (`major_positive` never fades). Villagers' own donations at the holiday service
  are unchanged.
- **Tests:** `tests/trade_window.lua` (no field at a farmer and nothing taken; the cleric's
  donation goes to the fund, gossips once a day, not below a dinner, not past what the player
  holds); `tests/money.lua` (`donation_counts`, `takes_donations`); `tests/gossip.lua`
  (capped at 10, shared as 7); `tests/possessions.lua` (an adult picks up emeralds, a child
  doesn't, the block and food are left alone).

### 37. Premium trades

The mod took vanilla's tiers and random rare goods out of player trade (ticket 14). Now the
top-tier goods come back, changed to fit the economy. Each is made at the sale from a base
good the profession keeps: the one exception, with the alchemist's, to "player trades convert
nothing". They are bought by players with a good name, and they are how a player's hoard of
emeralds returns to the village's money supply. The cleric's rotten flesh (37b) is the way out
again.

- **Unlocking.** A premium good has a level from 3 to 5. The villager's tier
  (`_max_trade_tier`, which rises on supply days) and the player's reputation with that
  villager (gossip.lua, decentralised) each set a level, and the lower one counts:
  Known (15) level 3, Friend (30) level 4, Honoured (50) level 5. Fifty can be earned without
  curing anyone: trading caps at 25, a sale to an urgent need at 25, and donation gossip
  passes on 7. It fades by about 4 a game day, so it is kept by trading. A Hero (100) unlocks
  nothing more, but the reputation share the window already applies (up to a quarter off at
  100, an eighth at 50) takes more off premium prices too. Every good at or below the level is
  offered, not a random pick, so one master librarian sells every top book.
- **The base good.** From journeyman up a profession keeps its base good: a target the ledger
  never sells below, which its trips restock, and which its own crafts leave alone. Each sale
  takes the base; with none the good is out of stock.
- **Prices.** P dinners at the seller's own reference price for a dinner (so premium prices
  follow the village's food), plus the base's reference value, less the reputation share.
  P comes from one table of enchantments: a headline enchantment's top level is 32 dinners and
  each level below costs half; utility ones top out at 24 to 28; treasure ones exist only at
  their one level. Enchanted gear costs the sum of its enchantments, so it is never cheaper
  than the books. `premium.SCALE` tunes them all.

  | Enchantment | Dinners by level |
  |---|---|
  | Mending | 40 |
  | Silk Touch, Infinity | 24 |
  | Efficiency, Sharpness, Power | III 8, IV 16, V 32 |
  | Fortune | I 8, II 16, III 32 |
  | Unbreaking | I 6, II 12, III 24 |
  | Protection | II 7, III 14, IV 28 |
  | Feather Falling | II 4, III 8, IV 16 |
  | Lure, Luck of the Sea | I 3/4, II 6/8, III 12/16 |

  An enchantment line sells its maximum level at premium level 5, one below at 4, two below at
  3, where that level exists.
- **Not traded among villagers.** Premium goods never enter asks, reference prices, market
  news or villager trade. They exist only once a player buys one.
- **The window.** A villager with premium goods has a Special tab: every good of its
  profession with its price, and how many its base allows, "out of stock", or why it is
  locked ("needs a master", "needs a friend (30)").

The lines, by sub-ticket (one PR each, against `main`):

- **37a. Framework and the librarian (done).** `premium.lua`, the Special tab, the base kept
  and left out of crafts, the base used in the tally. The librarian keeps 4 books and sells
  Mending (40), Efficiency V (32), Fortune III (32), Protection IV (28), Silk Touch (24),
  Unbreaking III (24) at level 5; Efficiency IV, Fortune II, Protection III, Unbreaking II at 4;
  Efficiency III, Fortune I, Protection II, Unbreaking I at 3. At a dinner of 18 a Mending book
  is 736 emeralds; the master set is about 180 dinners.
- **37b. The cleric (done).** It keeps 9 glass bottles from journeyman up, which it makes
  from glass (a new recipe: 3 glass, 3 bottles). It sells ender pearls (4 dinners) from level
  4, 2 a day per player there and 8 at level 5, and bottles o' enchanting (2 dinners) at level
  5, 16 a day. Each takes a bottle. The window offers "All" for these: as many as its
  bottles, the day's cap and the player's emeralds allow.
  - **Rotten flesh.** It buys rotten flesh from anyone it will trade with, while it holds
    fewer than 96: at a third of its reference price for leather, falling to half that as its
    stock fills (at base prices about 1.8, so whole emeralds pay 1). No villager sells it flesh:
    flesh and bottles are no longer cleric inputs (`ledger.lua`'s `NOT_BOUGHT`). It sells
    leather made 3 flesh to 1 (`goods.lua`'s cleric conversion), to players in its window and
    to villagers in the market, as the alchemist sells ingots, never dearer than its flesh.
    Nor ever at a loss or break even: it keeps its average cost per flesh
    (`_villages_flesh_cost`, `asks.note_cost` at each purchase), and a leather made from it
    sells for at least a quarter over three flesh's cost and at least an emerald over it
    (`asks.cost_floor`, through the conversion's `cost` field). The floor holds in its window
    past the reputation share, in the market past a buyer's standing (`exchange.asking`), and
    in the news it tells. A buyer who will not pay that gets no leather.
  - **Paying for it.** Donations are progressive: a tenth of savings from 8 to 24 dinners, a
    fifth from 24 to 64, three tenths past 64, in place of a tenth of all past 8. The fund's
    target (`alms.target`) adds a flesh reserve of 12 dinners to its 4 holidays of alms, and
    each service notes the alms part (`_villages_alms_need`). Flesh is paid from the fund past
    that part, then the cleric's own emeralds past its savings (`flesh_budget`, `pay_flesh`).
    Until its first service it pays from its own only. Leather it sells pays its own
    emeralds, which alms draw on past its savings too, so they go back round.
  - **Money flows.** The tally keeps `premium_in` (what players paid for premium goods) and
    `flesh_out` (what the cleric paid for flesh) for today and yesterday
    (`economy_tally.money`). The bench's Economy tab shows both and the village's net under
    Today and Yesterday.
  - **Tests:** `tests/premium.lua` (the cleric's offers, caps by level, sales noted a day,
    rows); `tests/trade_window.lua` (flesh paid from the budget up to its keep, its price
    falling, leather from flesh, pearls capped then fresh the next day, out of stock, a friend's
    smaller cap and no bottles o' enchanting); `tests/alms.lua` (progressive bands at the
    donor's scale, the flesh reserve in the target, the budget fund first and never the alms
    part); `tests/ledger.lua` (no flesh or bottles bought, glass for its bottles);
    `tests/goods.lua` (three flesh to a leather, not the alchemist's); `tests/asks.lua` and
    `tests/exchange.lua` (the cost floor: averaged, an emerald over at the least, past a fallen
    flesh ask and a friend's standing, no sale to a buyer below it); `tests/economy_report.lua`
    and `tests/builder_bench_menu.lua` (the money flows).
- **37c. The farmer (done).** Golden carrots, 3 dinners each plus the base: two offers, one
  from 6 wheat and one from 8 potatoes (about two loaves' worth of food either way), sharing
  one cap a day per player, 4 at level 4 and 16 at level 5 (`bases` and `cap` in
  `premium.lua`). At a dinner of 18 one is about 73 emeralds, about seven loaves: vanilla's
  ratio is six. From journeyman up it keeps 24 wheat and 24 potatoes (`keeps`) in its
  belongings, where premium sales take them from: at its chest wheat goes there past its
  8 for sale and potatoes past their 16 (`farmer.lua`'s `kept`), the keeper's reserve of
  meals still left in the chest. A kept good is a target, so it is never spare, and below it
  the farmer will buy some, as the librarian buys books.
  - **Tests:** `tests/premium.lua` (two offers, the shared cap, prices from each base, the
    keeps); `tests/trade_window.lua` (carrots from wheat, then potatoes up to the shared cap);
    `tests/farmer.lua` (24 wheat and 24 potatoes more in its belongings at journeyman).
- **37d. Smiths and the armorer (done).** Enchanted gear (`goods` with their own `enchants`
  and `inputs` in `premium.lua`), each priced as the sum of its enchantments plus its inputs'
  reference values. Iron gear takes a piece it made and holds (out of stock without one);
  diamond gear takes the real recipe's diamonds and sticks. From journeyman up each keeps
  8 diamonds (the smiths 4 sticks too), a target, so its window buys diamonds from players
  at its value, and its crafts leave them alone.

  | | Level 3 | Level 4 | Level 5 |
  |---|---|---|---|
  | Tool smith | iron pick, Efficiency III, Unbreaking I (14) | diamond axe or shovel, Efficiency IV, Unbreaking II (28) | diamond pick, Efficiency V, Unbreaking III (56) |
  | Weapon smith | iron sword, Sharpness III (8) | diamond axe, Sharpness IV, Unbreaking II (28) | diamond sword, Sharpness V, Unbreaking III (56) |
  | Armorer | each iron piece, Protection II (7) | diamond leggings or boots, Protection III (14) | diamond helmet or chestplate, Protection IV, Unbreaking III (52) |

  A villager that buys diamonds from a player receives two for each one sold (the trade
  window's `DIAMOND_BONUS`), so a smith's gear can sell at a profit and still leave the
  player better off. Its reference price learns the price paid per diamond sold, so the
  bonus doesn't lower what it pays next time.
  The weapon smith makes iron swords from journeyman up (2 iron and a stick), priced at its
  iron like its axe. At a dinner of 18 a diamond pick is 1,204 emeralds: 1,008 for its
  enchantments, 196 for three diamonds and two sticks.
  - **Tests:** `tests/premium.lua` (the three lines, labels, levels, prices with every input,
    stock by the scarcest input, keeps); `tests/trade_window.lua` (a diamond pick refused with
    one stick and nothing taken, then made from three diamonds and two sticks, tallied; a
    diamond sold, two received, the price learnt per diamond sold).
    Checked on the real engine: all fifteen come out enchanted as registered items.
- **37e. Fletcher, fisherman, leatherworker (done).**

  | | Level 3 | Level 4 | Level 5 |
  |---|---|---|---|
  | Fletcher | bow, Power III (8) | bow, Power IV, Unbreaking II (28) | bow, Power V, Infinity (56) |
  | Fisherman | rod, Lure I, Luck of the Sea I (7) | rod, Lure II, Luck of the Sea II (14) | rod, Lure III, Luck of the Sea III (28) |
  | Leatherworker | leather boots, Feather Falling II (4) | saddle from 4 leather (8) | leather boots, Feather Falling IV (16) |

  The fletcher's bows come from bows it made, and it keeps none (out of stock without one).
  The fisherman keeps one rod past the one it fishes with (wants.lua's), and never sells
  that one (an input's `leave`), so it buys a spare from the fletcher. The leatherworker keeps
  4 leather for saddles (VoxeLibre has no saddle recipe), and both pairs of boots are ones it made. The
  saddle has no enchantments and its own price (`dinners`).
  - **Tests:** `tests/premium.lua` (the three lines, the rod it fishes with left, the saddle's
    own price, keeps); `tests/trade_window.lua` (a rod refused while it holds only its own,
    then sold from a second). Checked on the real engine: all nine come out as registered
    items, enchanted as listed.
- **None.** The shepherd, mason, butcher and keeper have no rare goods in vanilla; the
  Builder, alchemist and nitwit keep their own roles.
- **The cartographer: ticket 38.** Its explorer maps need land found and generated first, so
  they are a ticket of their own.
- **Tests (37a):** `tests/premium.lua` (bands and levels, enchantment levels, the librarian's 14
  books, prices, the base kept, rows); `tests/trade_window.lua` (the Special tab, a locked book
  not sold, a book taken and the enchanted one made, paid and tallied, out of stock, a farmer
  with no tab); `tests/possessions.lua` (books a need and not spare); `tests/production.lua` (no
  bookshelf from the kept books).

### 38. Explorer maps

The cartographer's premium goods, as vanilla's: an ocean explorer map and a woodland
explorer map. VoxeLibre has neither (its `villager.lua` leaves both trades as `FIXME`, and
`mcl_maps` has a `TODO` for them), so this ticket draws them. VoxeLibre's stand-ins for the
structures are `ocean_temple` (prismarine, guardians, an elder guardian) for the ocean
monument and `woodland_cabin` (a cabin or an outpost in RoofedForest, vindicators and evokers)
for the woodland mansion, which it lacks.

**Why a search.** Minecraft lays structures on a grid fixed by the seed, so it lists
candidates without generating anything. VoxeLibre registers each structure as an engine
decoration with an empty schematic: the engine picks spots while generating, keeps those
whose real terrain passes (an ocean temple wants sand or gravel with 4 water around it, at
sea level -4 or deeper), and Lua then rolls a chance seeded by the spot (a cabin's 1 in 800).
The engine's choice depends on the real ground and isn't exposed to Lua, so a structure is
known only once its land is generated. The cartographer finds them by generating likely land,
slowly, in the background, before any player asks. It never places a structure itself: every
map leads to one the world made.

**Measured (2026-11-21).** A probe generated 500 likely-ocean and every likely-RoofedForest
chunk within 5,000 nodes of the origin, on the ColonyFood seed and seed 2001:

| | ColonyFood | Seed 2001 |
|---|---|---|
| Ocean temples in 500 likely-ocean chunks | 14 | 8 |
| Woodland cabins in likely-RoofedForest chunks | 11 of 188 | 5 of 88 |
| Chunks generated, seconds | 688, 190 | 588, 167 |

- About 1 ocean chunk in 45 holds a temple, and about a fifth of chunks are ocean: the
  nearest is typically some 700 nodes away, about 45 chunks to generate.
- About 1 RoofedForest chunk in 17 holds a cabin, but the biome is only 0.6 to 1.2% of
  chunks: the nearest is 1,500 to 3,500 nodes away, about 17 chunks to generate. Cabins
  cluster in one forest.
- A Lua copy of the v7 terrain-height formula (`MapgenV7::baseTerrainLevelAtPoint`, through
  `core.get_perlin` with the world's `mgv7_np_*` noise) matches the generated ground to about
  a node. Chunks it calls deep ocean were deep ocean 84% of the time; RoofedForest guesses
  (`core.get_biome_data` at that height) 92%. `core.get_spawn_level` is no help: it is nil on
  high land as well as at sea.
- The probe mod and its logs are kept outside the repository; its method is 38a's.

**Minecraft against this mod.**

| | Minecraft | Here |
|---|---|---|
| Finding | seed grid, a search when the offer is made | a background search when the cartographer reaches the level |
| Map | 1:2, blank until explored, land and water outlined | 1:2 (zoom 1), drawn whole at once, as VoxeLibre's maps are |
| Marker | the structure's icon, players, frames | a structure icon painted into the image; the player's arrow as VoxeLibre draws it |
| Price | 13 or 14 emeralds and a compass | dinners plus 8 paper, as the other premium goods |
| Second map | usually the same structure | the nearest site that player hasn't bought |

The sub-tickets (one PR each, against `main`):

- **38a. Charting.** `charting.lua`, pure where it can be, finds sites and keeps them.
  - **Seen sites.** It wraps `mcl_structures.place_structure` (looked up on the table at each
    call, as `village_index.lua` wraps `settlements.place_schematics`) and logs every
    `ocean_temple` and `woodland_cabin` placed: name and position, in mod storage. Exploring
    players chart for free.
  - **Charts by village.** A village is its bell (`_villages_bell`). Once a cartographer with
    that bell reaches tier 3 a chart for ocean temples starts there, and at tier 4 one for
    woodland cabins. A chart keeps up to 3 sites nearest the bell, each with its map (38b).
    Logged sites within its radius count first.
  - **The search.** Chunks (80 nodes, from -32) within the radius, nearest first: 3,000
    nodes for temples, 6,000 for cabins. Each is classified by noise alone, 16 samples: deep
    ocean if 12 lie below sea level -6, forest if 8 are RoofedForest on land. Only those are
    generated (`core.emerge_area`, y -32 to 47), one at a time, with a pause between
    (a setting, 2 s by default), and the hook catches what is placed. Classifying is cheap
    (15,000 chunks in under 3 s) but runs in slices so a step never stalls. A chart walks on
    until it has 3 sites or reaches its radius, and keeps its place across restarts.
  - **Old land.** A chunk generated before the mod was installed comes back from disk
    (the emerge callback's action is not `EMERGE_GENERATED`) and never fires the hook. Those
    are scanned with `core.find_nodes_in_area` for nodes only the structure has, chosen from
    its schematics (`tools/extract_schematics`), and the cluster's centre is the site.
  - **When it can't.** No chart if the structure is disabled (`mcl_structures.is_disabled`)
    or the mapgen is singlenode or flat. The classifier needs v7, VoxeLibre's default: other
    mapgens chart only from seen sites. A chart that reaches its radius with no site says so,
    and doesn't search again.
  - `/living_villages_charts` lists a village's charts, their sites and how far each search
    has got.
  - **Tests:** `tests/charting.lua` (chunk maths, nearest-first order, the classifier on stub
    noise, logged sites counted first, a chart stopping at 3 sites and at its radius, resumed
    from storage, no chart for a disabled structure or another mapgen, the scan's cluster
    centre). On the real engine: a chart from the ColonyFood bell finds a temple and a cabin.
- **38b. The map.** `explorer_map.lua` draws a site's map once, when it is charted.
  - **Drawing.** Its own copy of `mcl_maps`' renderer (local there): VoxeLibre's
    `colors.json`, heights shaded, y -32 to 63, 128 pixels over 256 nodes (zoom 1), centred
    on the site's map cell as `mcl_maps` centres any map. It generates the chunks it needs
    (4 or 5 a side, two high: 32 to 50, some 10 to 15 s), so the land is drawn whole, as VoxeLibre draws any
    new map.
  - **The marker.** An icon painted into the pixels at the site: a teal temple for the ocean,
    a dark green cabin for the woodland, each 9 by 9, our own drawing (defined in the Lua as a
    grid, since nothing reads a PNG back). Being in the image, it shows in the hand, the
    offhand and an item frame.
  - **An ordinary map.** The PNG goes where `mcl_maps` keeps its own,
    `<world>/mcl_maps/mcl_maps_map_<id>.png`, with an id of ours
    (`<cx>_overworld_<cz>_1_lv_<kind><n>`), and the item is a `mcl_maps:filled_map` with that
    id, its centre, zoom 1, dimension, corners and a description ("Ocean Explorer Map").
    `mcl_maps` then loads it, draws the player's arrow and the off-map dots, copies it at the
    crafting grid (meta and all) and shows it in frames, untouched.
  - **Locked.** `mcl_maps:locked` is set, so the cartography table won't zoom it: zooming
    calls `mcl_maps.regenerate_map`, which would redraw it without its marker.
  - **Tests:** `tests/explorer_map.lua` (on a stub world: the marker's pixels at the centre,
    the id, the meta, locked, the area generated before drawing). On the real engine: a map
    from 38a's chart in the hand, copied, in a frame, refused by the table.
- **38c. The cartographer's premium line.**

  | | Level 3 | Level 4 |
  |---|---|---|
  | Cartographer | ocean explorer map (6) | woodland explorer map (10) |

  - Each takes 8 paper (the empty map's recipe; the cartographer stands in for the compass
    no village can make). From journeyman up it keeps 16 paper (`keeps`), so it buys paper
    from players and makes its own from cane, as now.
  - **Stock.** A map row's stock is the lower of its paper and the chart's sites that player
    hasn't bought from this village. A sale hands over that site's map, drawn already, so
    buying stays at once. The window says why one is missing: "still charting the sea", or
    "knows of no woodland cabin within 6,000 blocks".
  - **One map a site a player.** A village remembers which sites each player bought. Another
    player gets the nearest; the same player the next. A chart refills to 3 behind sales.
  - The offer has a `chart` field (`ocean_temple`, `woodland_cabin`); `premium.rows` takes
    the sites as it takes held goods, and `make` builds the map from the site.
  - **Tests:** `tests/premium.lua` (the two rows, levels, prices, stock by paper and by sites);
    `tests/trade_window.lua` (a map sold with its site's meta and paper taken; the same
    player's second map is the next site; another player's first is the nearest; out of stock
    while charting, with the reason).
- **Open.** Whether a woodland map at 1,500 to 3,500 nodes is too far for the game's pace,
  and whether the prices sit right beside the saddle (8) and pearls (4).

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
- Iron: the alchemist (ticket 20) is its village supply. Since ticket 29 quarriers buy iron
  picks and hoes from the tool smith, woodcutters the weapon smith's axes and villagers
  the armorer's cauldrons and the cleric's clocks (gold), but iron armour still sells only to players until warriors
  exist (Warriors), against Principle 6.
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
