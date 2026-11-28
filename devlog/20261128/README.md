# November 28, 2026: Phase 9, wind, calendar, storms and rats

Not posted. A working record.

- The user chose **storms drawn on the map**, a **moderate wind**, seasons that change **wind, storms and prices**,
  and rats that **come aboard in port**.
- **Calendar:** a turn is a day, a month thirty days, and a voyage starts on 1 March, so 2,500 turns is about seven
  years. The HUD has a fourth line with the date and season (gold in autumn and winter), the wind, and any rats; it
  is left off while a card or sheet is drawn over the sea view.
- **Wind:** a direction and a force (calm, light, fresh, strong). Running before a strong wind is 130% of speed and
  beating into it 60%; a calm is 70% whatever the heading. The speed line shows the result whenever it differs from
  the sail set. The wind veers and backs, and its force rises and falls, more in autumn and winter.
- **Storms:** form 12 to 30 tiles from the ship (most often in autumn and winter, twice as often in a strong wind),
  last 60 to 150 turns, and drift downwind. In view they are drawn as dark cloud and rain, on the chart too. Sighting
  one stops sailing like sighting an island, and so does sailing into one. Each turn inside costs 2 to 6 hull (2 more
  in a strong wind, halved by a Pilot roll) and the wind drives the ship before it. Docked ships are safe. A course
  from Head for steers round storms in view, and straight through only if they close every way. Simulated: a ship
  sailing blind loses about 35 hull a voyage to storms.
- **Seasonal prices:** grain 110% in spring, 80% after the harvest and 125% in winter; wool cheap after the shearing;
  fish, timber and wool dearer in winter; spice up a little in autumn. Rations follow grain.
- **Rats:** a 25% chance that 2 to 6 come aboard each time you dock. Aboard they breed, eat a ration a turn for every
  twenty, and spoil flour, salt fish, rope, sailcloth and woolens ("Rats spoiled 3 cargo."). **Hunt rats** takes two
  turns, and each of the crew who makes a Track roll kills a few.
- Fishing and hunting rats moved into a new **Orders** item in the crew menu, so a full crew still fits in nine items.
  Orders shows at sea, or in port when there are rats.
- The weather has its own generator, saved with the voyage, so it never changes the rolls for fights, offers and
  markets. Save version 11 (86 bytes more). Older saves get the voyage's first weather, no storms and no rats.
- Checked in the browser pane: the HUD, a storm sighted, drawn and sailed into, the Orders menu, a rat hunt, the
  chart, and the whale encounter screen. 96 native tests.
- **HUD rework** (the user asked, as the top-left panel was crowded): two lines at the top (Food, Health, Hull;
  Money, Hold, Crew), a third only when something needs attention (Fed below 100, the dirtier hull side's cleanliness
  below 90%), and a strip along the bottom with the date and season, the wind, and rats aboard. The strip hides while a
  card covers the sea view.
