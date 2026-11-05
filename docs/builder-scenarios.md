# Builder scenarios

Manual in-game checks for `builder.lua`, for what the stubbed tests and the headless probe can't prove: the
status window in a real client, buying from it, how a site and its Builder look, and villagers using what
it builds. Use a world on VoxeLibre with this mod. The Lookup Tool (`doc_identifier`, with the `server` or
`debug` privilege) shows a villager's `Builder` line: its state, building and site. `debug.txt` has a
`[living_villages]` line when a villager takes a bench, chooses a building and a site, and finishes.

A Builder works only from 7000 to 15500, and only with a player within 48 nodes. Stay close by. To go
faster, use `/time 7:00` and lower `living_villages_builder_block_seconds`.

To skip gathering, stand near a Builder waiting for materials and run `/giveme build_project_materials`. You
get what it is missing, less what you already hold, to put in a chest near its bench. If the nearest Builders
aren't waiting, it warns you and gives nothing. It needs the `give` privilege, like any `/giveme`.

## The house

Find a new village with `/living_villages_goto new`.

- It has one Builder's house: a bench, one bed, and a double chest that opens as one, with 54 slots.
- The bench is tinted, unlike a crafting table, and right-clicking it opens nothing.
- The house's villager wears a mason's outfit, and the Lookup Tool shows it holds the bench.

## An older village

Craft a bench and place it in a village generated before this mod, or with Builders off.

- A villager with no job walks to it and takes it, unless a free composter comes first.
- It builds with the generator's usual mix, as the village left no record.
- Break the bench. The Builder goes back to being unemployed, and what it carried drops.

## The window

Right-click the Builder in each state.

- `requires_materials`: a table of item, needed, in chests, carried and missing. Missing is red.
- Everything fits at the window's size, including the longest item names. A long list scrolls, and its Buy
  buttons still work once scrolled.
- Refresh shows a change in the chest. Closing it and opening it again does too.
- Off work, the window says so.
- Nitwits, other masons and children still open what they did before.

## Buying

With the Builder short of something on sale (a lamp's sea lantern, a farm's water, a belltower's bell):

- The row shows its price per item and an emerald under `Price each`, and the button says `Buy 1`. Hovering
  over it says what one costs.
- With too few emeralds the window says so, and nothing is taken.
- With enough, one is taken per item's price, the item appears in the chest by the bench, and the row
  updates. Once none is missing the Buy button goes.
- With the chests full it arrives in your inventory, or at your feet if that is full too.
- Walk more than 10 nodes away and press Buy: the window says you are too far.
- Things it does not need, and items never on sale, have no button. Buying doesn't change `Gossip`.

## No site

Keep it from finding one, by building all around the village or with a very low
`living_villages_builder_site_gap`.

- The window names the building and says what it needs: size, height and how near.
- It stays on that building. Clear a spot big enough, and within a minute it chooses it.

## Earthwork

Make a site with a small bump and a small dip, in a village with no flat ground left near it.

- While it waits for materials, the bump and the dip stay as they are.
- Once the chest is stocked, it breaks the bump and fills the dip first, at its one-a-second pace, and neither
  costs nor yields anything. No dirt drops.
- A site that needs 13 of either isn't chosen. Nor is one where the bump is stone, or next to water.

## Building

Stock the chest.

- It walks to the chest, takes what it needs, walks to the site, and places from outside the footprint, never
  shutting itself in.
- It places solid blocks from the bottom up, then torches, doors and crops. Water and lava go in last and
  stay inside the walls.
- Stand in a cell it wants. It works round you and comes back to it.
- Above 5 blocks over the floor it works from scaffolding (a church's upper walls and roof, a lighthouse). It
  puts up a column one cell out from the walls, climbs it a block at a time and stands level with the layer
  it lays, turning to each block. When the work moves along it comes down, taking the column with it, and
  puts up another further round. The window says "Working from the scaffolding". No scaffolding is on the
  bill and none is left when it finishes, nor dropped.
- At 15500 it stops, and goes on the next day. Up a column, it climbs down first and takes the column away.

## Things going wrong

- Take materials from the chest mid-build. It goes back to `requires_materials`, and the table shows the rest.
- Break a block it placed. It puts it back, using more materials.
- Put a stone in a cell it has yet to build. It stops at `blocked` and the window gives the position. Remove
  the stone and it carries on.
- Kill it mid-build. Its pouch drops. Put that back in the chest, and whoever takes the bench next carries on.
- Kill it up a column. The column stays until whoever takes the bench next walks over and takes it down,
  before anything else, without dropping any scaffolding.
- Put a block over a column it is climbing. It stops under it, comes down and tries a column elsewhere.
- Before it has placed anything, wall off the site. It gives up on that site, untouched, and finds another,
  and `debug.txt` says so. It can choose that site again after 30 minutes.
- Once it has begun, wall off the site or the chest. The window says it can't get there, and it keeps the site.

## What it built

- The copy looks like the building it is modelled on, with its rotation and the village's surface.
- Doors open, and the bed works. A villager without a bed takes it, and a new villager can be born there
  (`births.lua`).
- Chests are empty and open, and a double chest is a double chest.
- Profession blocks are left out. Put a stonecutter or a lectern where one belongs, and an unemployed villager
  takes it. The church has no pulpit until you place one.
- Its next building keeps the village's mix: `village_census.lua` counts what it built.

## The bench's menu

Right-click a bench. What the tests cannot show is how the window looks in a real client.

1. **Layout:** the three tabs, the table's columns lining up with its header row, nothing overlapping the panel on the right, and a long schematic name or problem text staying inside its area.
2. **Default tab:** one row per stock building, with shares, no weights and `>` on the next. **Build from these** is replaced by a green line while the tab is in use.
3. **Schemedit tab:** export something with a Schematic Creator, press **Refresh** and it is listed. Select it: size, blocks and most-used materials show.
4. **A schematic it cannot use:** one holding a portal node is marked `x` in red, and says which node.
5. **Weights:** set one and press **Set**, or Enter in the field. The window stays open, the shares change and `<world>/schems/builder_projects.json` has it. Try `lots`: it says what a weight is and changes nothing.
6. **Project folder tab:** opening it creates `<world>/builder_schems`.
7. **Build from these:** with a project waiting for materials, it drops that project and picks from the new source. With one being built, that one is finished first.
8. **Pictures:** put `cottage.png` next to `cottage.mts`, press **Refresh** and select it. The picture appears in the side panel in place of the materials, in its own shape, with nothing overlapping. Replace the file and press **Refresh**: the new one shows. A text file renamed `cottage.png` leaves the materials showing.
9. **Permissions:** without `server` the weight is a label. On a bench protected against you, tabs still work, but there is no button.
