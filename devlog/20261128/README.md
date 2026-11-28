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
- **Fixed a money glitch** (the user's report: buy 50 flour, sell it straight back, come out ahead). Buying raised the
  island's demand while selling raised its supply; demand multiplies the price and supply divides it, so where demand
  was low a round trip paid. Now buying draws down the supply, and a sale is priced with its unit already added back,
  so selling retraces the prices paid, less the 10% spread (bargaining tops out at 4%). A new test tries every good
  across markets from glutted to starved with the best bargainer aboard; the old code failed it.
- **Street vendor** (the user's request, like the sea goods): it shows only purchases you can make (money, stock and
  ration room), drops off the port menu when there is nothing you can buy, and sends you back to the port after the
  last lot you can buy.
- **Market trade menu** (the user's request): buys show only when you can afford them and have room (Buy 10 only for
  ten, Buy max only for more than one, prices rising as you buy), sales only when you have the goods (Sell 10 only
  with ten aboard), the same for rations. Picking a good with nothing to buy or sell says so and stays in the market;
  doing the last thing you can with a good goes back to the market.
- **Captain's log opens on its newest page** (the user's report: two crew died and the log did not show it). The
  deaths were written; the log opened on page one, the oldest fourteen entries, so on a long voyage they were pages
  away. It now opens on the latest page, from the chart and on the voyage's end screen; Page still cycles.
- **A full log keeps the crew's fates.** The log holds 64 entries; once full, each new one pushed out the oldest after
  "Sailed from", so on a long voyage early deaths could vanish under landfalls and sales. Now the oldest routine entry
  (landfall, delivery, alley win, sale, fares) goes first, and deaths, desertions, hirings, pay-offs, fights and ships
  stay. Every way a crew member leaves the ship (killed in a fight, starved, unpaid, hungry, paid off) writes an entry.
- **Seeing the cargo** (the user's request; they chose all three): a **Cargo** panel, from the chart at sea and the
  ship menu in port (both top menus are full at nine), lists each good aboard with its count, tons and worth at base
  price, sea goods in gold, then rations and the total. The market draws the same list over the sea, and its list
  shows how many you carry beside each good's prices ("Salt fish 10/9 (10)") when the label fits, and rations held.
- **Careening in a submenu** (the user's request): the ship menu's two careen lines were too long to fit; now one
  "Careen, 87% clean" item (the dirtier side) opens Port side / Starboard, and careening or Back returns to the ship
  menu.
- **Training** (the user's request; they approved Claude's design): a third of the islands (four to eight) have a
  school or master (a navigators' school, a pilots' guild, a master shipwright, a lookouts' tower, a hunters' lodge, a
  merchants' hall, a card sharp, a fencing master), and the eight skills are dealt out among them, so each is taught
  somewhere and a school teaches one or two. Docking (and the home port) says "Taught here: Track." Pick anyone aboard,
  captain included, from Crew: their menu offers "Train Track 10%, 15" for each skill taught there that you can pay
  for. A lesson adds 5 points (to at most 95), costs 10 + skill²/20 (15 at 10%, 135 at 50%, 330 at 80%), and takes
  three turns in port. Logged as "trained at". Schools come from the world seed, so saves are unchanged. Checked in
  the browser: Doni's Track 10% to 15%.
