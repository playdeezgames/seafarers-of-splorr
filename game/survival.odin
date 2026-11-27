package game

// Staying alive (Phase 2): rations, satiety and health, hull fouling, careening, and the end of the voyage.

TURN_LIMIT :: 2500 // the voyage ends in retirement when the turn count reaches this
START_RATIONS :: 1000
RATIONS_MAX :: 100_000
STAT_MAX :: 100 // satiety and health run 0 ..= 100
FOUL_PER_TURN :: 5 // fouling per side per turn under way, in ten-thousandths
FOUL_MAX :: 2500 // per side: both sides at the maximum halve the speed
CAREEN_TURNS :: 10

Side :: enum u8 {
	Port,
	Starboard,
}

Outcome :: enum u8 {
	None,
	Retired,
	Starved,
}

// The ship's speed after fouling, in percent of full sail.
effective_speed :: proc(g: ^Game) -> f32 {
	foul := f32(g.foul[.Port] + g.foul[.Starboard]) / 10000
	return f32(g.ship.speed) * (1 - foul)
}

// How clean one side of the hull is, 0 ..= 100 percent.
hull_clean :: proc(g: ^Game, s: Side) -> int {
	return 100 - g.foul[s] * 100 / FOUL_MAX
}

// One turn passes: everyone eats, the hull fouls if under way, and the voyage may end. Returns false when it ended.
tick :: proc(g: ^Game, under_way: bool) -> bool {
	if g.rations > 0 {
		g.rations -= 1
		g.satiety = min(g.satiety + 1, STAT_MAX)
	} else if g.satiety > 0 {
		g.satiety -= 1
	} else {
		g.health = max(g.health - 1, 0)
	}
	if g.satiety == STAT_MAX {g.health = min(g.health + 1, STAT_MAX)}
	if under_way {
		for s in Side {g.foul[s] = min(g.foul[s] + FOUL_PER_TURN, FOUL_MAX)}
	}
	g.turn += 1
	if g.rations == 0 && g.satiety == 0 && g.health > 0 && g.health % 20 == 0 {
		logf(g, "Starving! Health %d.", g.health)
	} else if g.rations == 0 && g.satiety == 50 {
		logf(g, "The rations are gone.")
	}
	if g.health == 0 {
		end_voyage(g, .Starved)
		return false
	}
	if g.turn >= TURN_LIMIT {
		end_voyage(g, .Retired)
		return false
	}
	return true
}

// Net worth: money now; cargo joins it with trade (Phase 3).
score :: proc(g: ^Game) -> int {
	return g.money
}

end_voyage :: proc(g: ^Game, o: Outcome) {
	g.outcome = o
	g.screen = .Over
	g.sub = .None
	g.cursor = 0
	g.has_voyage = false
	g.docked = NO_ISLAND
	g.want_save = true // the page clears the stored voyage
	g.new_best = false
	switch o {
	case .Retired:
		sound(g, .Retire)
		logf(g, "You retire from the sea.")
		if s := score(g); s > g.best || !g.has_best {
			g.best, g.has_best, g.new_best = s, true, true
			g.want_best = true
		}
	case .Starved:
		sound(g, .Lose)
		logf(g, "You starved at sea.")
	case .None:
	}
}

// Careening needs an island close by, as docking does.
can_careen :: proc(g: ^Game) -> bool {
	near: [1]int
	return dockable(g, near[:]) > 0
}

careen :: proc(g: ^Game, s: Side) {
	if !can_careen(g) {
		sound(g, .Deny)
		logf(g, "No beach to careen on.")
		return
	}
	for _ in 0 ..< CAREEN_TURNS {
		if !tick(g, false) {return}
	}
	g.foul[s] = 0
	logf(g, "%s side scraped clean.", s == .Port ? "Port" : "Starboard")
}
