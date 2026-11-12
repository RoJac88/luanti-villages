-- Cases tests/stock_buildings.lua knows fail, as patterns over its case names.
-- Each says why; a fix removes its rule.
return {
	{
		match = "^tavern r%d+.- jobsite barrel_closed %(10,2,7%)",
		reason = "The barrel, a fisherman's jobsite, is in the kitchen behind the counter: a fence "
			.. "(1.5 nodes high) closes off x 9-10 and villagers cannot jump it. A villager that "
			.. "claimed it could never get there.",
	},
	{
		match = "^tavern r%d+.- leave from %(9,2,[3-7]%)",
		reason = "The same kitchen, as the room a barrel's approach cells are in.",
	},
	{
		match = "^tavern r%d+.- leave from %(10,2,[4-6]%)",
		reason = "The same kitchen.",
	},
	{
		match = "^village_woodcutter_shed r%d+.- chopping block %(1,1,5%)",
		reason = "The shed's chopping block is set into the floor (schematic (1,0,5)), so no cell beside it "
			.. "is at its level and a villager out of work cannot walk to it to claim it. Generation "
			.. "staffs it directly. Stood on the floor, at (1,1,5), every route passes.",
	},
}
