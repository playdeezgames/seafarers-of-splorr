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
