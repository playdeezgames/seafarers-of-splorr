package game

// Careening beaches (the user's rule, November 28, 2026): not every island has a beach fit to careen on, and the
// seasons change it, so each island's beach is rated for each season. A fair beach takes half again as long and a poor
// one twice as long, and both leave some growth on the hull; with none, the ship cannot be careened there. Beaches
// come from their own stream of the world seed, so they need no save space.

Beach :: enum u8 {
	None,
	Poor,
	Fair,
	Good,
}

BEACH_NAMES := [Beach]string {
	.None = "none",
	.Poor = "poor",
	.Fair = "fair",
	.Good = "good",
}

BEACH_TURNS := [Beach]int{.None = 0, .Poor = 200, .Fair = 150, .Good = 100} // percent of the careening time
BEACH_LEFT := [Beach]int{.None = 0, .Poor = 25, .Fair = 10, .Good = 0} // percent of FOUL_MAX left on the side

// Each island's beach: 15% have none to speak of, 30% poor, 35% fair, 20% good; then each season may be a step worse
// (a quarter of the time, half again in winter's surf) or a step better (a sixth of the time, not in winter).
generate_beaches :: proc(g: ^Game) {
	r := rng_make(g.seed ~ 0xBE_AC_4E_5D)
	for i in 0 ..< ISLAND_MAX {g.beaches[i] = {}}
	for i in 0 ..< g.n_islands {
		roll := rng_below(&r, 100)
		base := roll < 15 ? 0 : roll < 45 ? 1 : roll < 80 ? 2 : 3
		for s in Season {
			shift := rng_below(&r, 100)
			b := base
			worse := s == .Winter ? 40 : 25
			if shift < worse {
				b -= 1
			} else if s != .Winter && shift >= 100 - 16 {
				b += 1
			}
			g.beaches[i][s] = Beach(clamp(b, 0, int(max(Beach))))
		}
	}
}

// Said on docking: the beach this season.
log_beach :: proc(g: ^Game) {
	b := beach_here(g)
	if b == .None {
		logf(g, "No careening beach in %s.", SEASON_NAMES[season(g.turn)])
	} else {
		logf(g, "A %s beach for careening.", BEACH_NAMES[b])
	}
}

// The beach at the docked island this season (None at sea).
beach_here :: proc(g: ^Game) -> Beach {
	if g.docked == NO_ISLAND {return .None}
	return g.beaches[g.docked][season(g.turn)]
}
