# November 27, 2026: Phase 0, the scaffold

Not posted. A working record.

- New repo `seafarers-of-splorr`: an Odin/wasm port of Seafarers of SPLORR!! Classic, with the 2021 C++ game's ideas
  folded in, built in ten phases (plan in the vault).
- Rules package `game/`: splitmix64 RNG on `u64` maths; a placeholder world of 100 by 100 tiles with up to 40 islands
  at least 8 tiles apart (Classic's gap); a ship with heading in degrees and speed in percent; title and sea menus; a
  four-line message log; a versioned 35-byte save with size, magic, version and range checks. 11 native tests.
- Web layer: a 400 by 240 canvas at whole-number zoom; the sea view (24 by 24 tiles) keeps the ship centred; the panel
  holds status, a numbered menu and the log. Keys, gamepad and taps. Autosave to localStorage after every action;
  `?seed=N` for QA leaves the save alone. Web Audio blips with M to mute.
- Font m6x11 (the user's pick). Tiles from Bountiful Bits; the ship is drawn so it can turn to any heading.

## Phase 1, the sea (same day)

- The world is 120 by 120 tiles with up to 40 islands at least 15 tiles apart. Each island is a union of 2 by 2
  blocks along a short random walk, so every land tile has a land neighbour across and one up or down; that keeps
  every tile inside the nine coastline pieces the Bountiful Bits `Natural` blob actually has (corners, shores,
  interior; the sheet's thin strips and knobs are not used). Interior tiles sometimes carry a tree.
- Names follow Classic: consonants h k l m p and the five vowels alternate, length 3 to 9 weighted towards 6, unique.
- Fog: islands with land within 9 tiles are charted; beyond that the sea is hazed and only charted islands show. A
  chart view shows the whole world at two pixels a tile.
- Helm: set heading (eight points), adjust (1, 5, 10 degrees either way), set speed (full, three quarters, half,
  quarter, all stop), sail 1 to 25 turns. Sailing stops at land, at the edge of the charts, or on sighting an island.
- Head for any charted island (nearest first, with rounded distance and bearing). The voyage starts docked at a home
  port; docking needs land within 1.5 tiles and picks the nearest island, asking when several are in range
  (Classic's fold docked at the farthest).
- Save version 2 (44 bytes: adds the docked island and the charted islands). A Phase 0 save is refused with a
  friendly line, since the world generator changed. 18 native tests.

## Phase 2, staying alive (same day)

- The user's answers: the score is **net worth only** (money now; cargo joins it with trade); a voyage lasts **2,500
  turns**; you start with **plenty of rations** (1,000) and cannot restock until trade arrives.
- Each turn one ration is eaten (Classic's rule): satiety rises by one to 100; with no rations it falls by one, and at
  zero health falls by one a turn. Full satiety mends health by one a turn. Health 0 ends the voyage: lost at sea.
- Hull fouling per side grows while under way, up to a quarter per side (both sides fouled halves the speed after 500
  turns); effective speed is speed times one less the fouling, as in Classic. Careen to port or starboard while docked
  (10 turns) to scrape that side clean.
- Reaching turn 2,500 retires you: the net worth is the score, and the best is kept in this browser. The ended
  voyage's save is cleared.
- A status bar over the sea shows food, satiety, health and both sides of the hull.
- Save version 3 (58 bytes) adds money, rations, satiety, health and fouling; Phase 1 saves load with the starting
  values.
- Every file URL now carries a build id (`?v=...`, stamped by `tools/build.sh`), so a new build is never mixed with a
  cached old `game.wasm` (the Pages CDN caches for ten minutes; this happened after the Phase 1 push).
- 24 native tests.

## Phase 3, trade (same day)

- Classic's market model: six commodities with base prices (grain 2, fish 3, timber 4, wool 5, ore 8, spice 20);
  every island keeps a supply and a demand for each, and a commodity's price there is base × demand ÷ supply.
- Twelve goods made of commodities, Claude's draft approved by the user: flour, salt fish, timber (2 tons), rope,
  sailcloth, woolens, nails, iron tools, rum, dyes, cutlasses, pepper. Each island trades 2 to 6 of them (chosen by
  each good's rarity) and sells at the summed commodity prices, buying back 10% lower.
- Trading moves the market one unit at a time (buying raises demand, selling raises supply), so bulk buying gets
  dearer; every market drifts back to its usual level a little each turn. The impact was cut to a fifth after the
  first try, when ten flour raised the price by half.
- A 50-ton hold, a 250 starting purse (the user's numbers), and rations in lots of ten at every market, priced off its
  grain and taking no hold space.
- Net worth (the retirement score) now counts cargo at its base value.
- About a third of island-pair routes for a traded good are profitable; the best margins run to 260 to 300%.
- Save version 4 (1,042 bytes: cargo and every island's current market). Version 2 and 3 saves load with the
  starting purse, an empty hold and markets at their usual levels. 32 native tests.

## Phase 4, islands, districts, deliveries (same day)

- Every island has docks and a market; from the seed, 70% have a delivery service, 60% a street vendor and 40% a dark
  alley (it opens in Phase 5). The docked menu lists the districts the island has.
- The user's answers: carry **up to three deliveries**; each has a **deadline of twice the distance** in turns (the
  C++ rule) and pays **half when late**; the street vendor sells **cheap rations**.
- The delivery service offers up to three jobs, fresh on each docking, as a letter in Classic's words ("Please
  promptly deliver this battered bundle to Imala the honest priest on Emopup."), with the sender, distance, pay and due
  turn. Pay is 10 plus one to three times the leagues. Accepting a job charts its destination; destinations show gold
  on the chart and starred in Head for. Deliveries pay on docking at the destination; abandoning one is free for now
  (reputation comes later).
- The street vendor sells lots of five rations at about 0.6 grain (the market's lot of ten costs two grain), ten lots
  a visit.
- Save version 5 (1,119 bytes: offers, deliveries carried, the vendor's stock, deliveries made). 41 native tests.

## The price book (the user's request, same day)

- "I should be able to compare last viewed prices for an island at which I docked. It should also show how old the
  price is." Every island's asking prices are recorded when you dock there and after every trade, with the turn.
- With a good open in a market, a table over the sea view lists every island you have docked at that trades it,
  dearest first: what it asked (Buy), what it would pay (Sell) and how many turns ago you saw it; the island you are
  at is in gold. At sea, Chart → Price book shows the same table and steps through the goods.
- Save version 6 (2,159 bytes: the book). Older saves start the book with the island you are docked at. 45 native
  tests.

## Phase 5, the dark alley; Head for paging (same day)

- Classic's in-between game with a 78-card tarot deck: trumps beat every suit card and rank by number, suit cards
  rank Ace to King with suits equal. Two cards up; a win (the third strictly between) pays even money.
- The user kept Classic's tie rule (a pair up, or a third card equal to either, loses) and asked that it be shown: the
  table spells out the rule and flags a pair before you bet.
- Classic's free fold made the alley a money farm (betting only wide spreads gains about 7.5% of the stake per hand
  dealt). The user chose an ante: dealing costs the island's minimum stake (5 to 25, from the seed), lost if you fold;
  bets are 1, 2, 5 or 10 times the minimum. Leaving the table mid-hand folds it, so no hand is ever saved.
- Sound pass: a riffle on the deal, a rising chord on a win, a drop on a loss, and a ship's bell when a sail finishes.
- **Head for paging** (the user's report: with more charted islands than the menu holds, the far ones could not be
  chosen): when they do not fit, seven a page, nearest first, with "More (page n of m)".
- 51 native tests. No save change (the hand is never saved; stakes come from the seed).

## Phase 6, crew and professions; the captain's log (same day)

- **Start choice:** New voyage now asks for a captain: a quick start (a profession chosen from the seed), Hunter,
  Sailor, Thief, Warrior, or Custom (spend 120 points, ten at a time, no skill past 90). Backing out keeps the voyage
  you had.
- **Eight percentile skills** (the user's pick, drawn from the C++ game's Basic Roleplaying list): Navigate (up to 20%
  faster), Pilot (slower fouling), Repair (careening in as few as 5 turns), Spot (see up to 3 leagues farther), Track
  (fishing at sea: five turns hove to), Bargain (up to 4% better prices), Gaming (a chance to swap a losing third card
  in the alley), Melee (fights, from Phase 8). The best skill aboard counts. Every effect starts above the base level,
  so a captain of base skills plays exactly as before.
- **Crew:** the captain and three to start, up to seven aboard. Everyone eats a ration a turn. In a famine the crew
  lose health with the captain and can die; the voyage ends only with the captain.
- **Wages and taverns:** a new tavern district (half the islands, rolled from its own stream so older worlds keep their
  districts) offers three sailors for hire. Wages mount per ten turns at sea and are paid on docking; whoever cannot be
  paid leaves, and a hungry crew may desert. Crew can be paid off in port.
- **The captain's log** (from the Features list): first landfalls, deliveries, hires, deaths and desertions, big alley
  wins and big sales, shown on the retirement screen and from Chart → Captain's log, fourteen to a page.
- To make room, Sound left the sea and docked menus (it stays on the title and the M key); Crew took its place.
- Save version 7 (2,826 bytes: crew, sailors for hire, wages owed, the log). Older saves get a captain of base skills
  and no crew, so they play on unchanged. 62 native tests.

## Piloting (the user's report, same day)

- "When I'm heading for an island for a delivery, other islands block me, which makes me have to move around them.
  This is less fun." Head for now sets a **course** (the user chose "pilot me there"): each turn under sail the ship
  finds a way over the sea tiles to the island, steers for the farthest point of that way it can see in a straight
  line, and stops alongside, with the sea menu back so Dock is one key away.
- On a course a new sighting is logged and sounded but no longer stops the ship (the user's choice). Setting the
  heading or the speed yourself drops the course; Head for at all stop sets full sail. The panel shows "For <island>".
- Save version 8 (one byte more: the course). Older saves load with none. 66 native tests.

## Fix: negative ages in the price book (the user's report, same day)

- The user saw some Seen ages in the market's price table go negative. A second voyage in one sitting built its world
  (recording the home port's prices and making its first delivery offers) before the turn count went back to 0, so
  those were stamped with the previous voyage's turn: the prices looked seen in the future and the first offers had
  deadlines far too long. Such a save would also have been refused on loading.
- The world now starts its clock at 0 before anything is stamped, and a save with a price seen "in the future" loads
  with it read as seen at the saved turn. 67 native tests.

## Phase 7, the shipyard (same day)

- The user chose **ship types and fittings**, approved Claude's draft list and prices, chose that **nothing damages
  the hull yet** (fights come in Phase 8, storms in Phase 9), and **passengers like deliveries**.
- **Ships:** the Sloop you start with (hold 50, hull 100, speed 100%, price 600), the Junk the C++ game had (60, 120,
  125%, 1,500) and a Brig (100, 200, 90%, 3,000). Your ship goes in part exchange at half its price, and your
  fittings move across.
- **Fittings:** extra hold (+25 tons, two at most, 400 each), copper sheathing (halves fouling, 600), passenger cabins
  (one passenger each, three at most, 300 each), stout timbers (+50 hull, 500). Repairs cost 2 a hull point.
- **Shipyards** on 40% of islands (their own stream, so older worlds keep their districts). The docked menu was full,
  so Careen moved into a new **Ship** menu, which also holds the shipyard where there is one.
- **Passengers** ask for passage at the delivery service when a cabin is free: a destination, a fare and a deadline
  (half fare when late), and they eat a ration a turn. Their islands show on the chart and in Head for like
  deliveries.
- The hull is drawn on the HUD; a ship that sinks ends the voyage (nothing sinks one yet).
- Save version 9 (59 bytes more). Older saves get a sloop with a sound hull. 73 native tests.

## Phase 8, things at sea and combat (same day)

- The user chose encounters **sprung while sailing**, about **one every fifty turns** under way; fights in **menu
  rounds** (the planning pass); a lost fight costs **hull, crew and cargo**; and merfolk who trade **pearls and coral**.
- A Spot roll sees an encounter coming, and then you may steer away or close. Each round your crew roll Melee (Track
  or Melee against a whale) and the foe strikes back: pirates and merfolk wound the crew, a monster or a whale hits the
  hull. Crew can be killed; the voyage ends if the ship sinks or the captain falls.
- **Pirates:** fight (loot), flee (a Pilot roll, easier in a faster ship; a failure gives them a free round), parley
  (a Bargain roll: they let you pass, or attack), or pay a tenth of your purse. If your crew fall below 60% of their
  health, they take half your money and half of every good.
- **Sea monster:** fight (salvage money) or flee. **Whale:** hunt it for whale oil, or let it go. **Merfolk:** trade
  (pearls and coral cheaply; they buy every land good aboard at 120%, or 130% after a good parley), parley, attack
  them, or sail on. A bad parley can insult them.
- Three **sea goods** (whale oil, pearls, coral) that no island trades but every island buys, under "Sea goods" in the
  market. The older save layout keeps the first twelve goods, so worlds and older saves are unchanged.
- Tuned by simulating 2,000 fights with a quick-start crew: pirates win about 81% of fights for you and rob you 18%,
  costing about 26 hull; a monster costs about 43 hull; whales and merfolk are rarely a danger.
- Save version 10 (an encounter in progress and the sea goods); Continue reopens an encounter. 85 native tests.
