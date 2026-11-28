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
	Sank, // the hull gave out (from Phase 8's fights and Phase 9's storms)
	Killed, // the captain fell in a fight
}

// The ship's speed after fouling, skill, the ship and the wind, in percent of full sail.
effective_speed :: proc(g: ^Game) -> f32 {
	foul := f32(g.foul[.Port] + g.foul[.Starboard]) / 10000
	return f32(g.ship.speed) * (1 - foul) * speed_factor(g) * ship_speed(g) * wind_factor(g)
}

// How clean one side of the hull is, 0 ..= 100 percent.
hull_clean :: proc(g: ^Game, s: Side) -> int {
	return 100 - g.foul[s] * 100 / FOUL_MAX
}

// One turn passes: everyone aboard eats a ration, the hull fouls if under way, wages mount, the weather turns (and a
// storm may batter the ship), and the voyage may end.
// Returns false when it ended.
tick :: proc(g: ^Game, under_way: bool) -> bool {
	eaters := max(g.n_crew, 1) + g.n_passengers
	if g.rations >= eaters {
		g.rations -= eaters
		g.satiety = min(g.satiety + 1, STAT_MAX)
	} else if g.rations > 0 || g.satiety > 0 {
		g.rations = 0 // not enough to go round
		g.satiety = max(g.satiety - 1, 0)
	} else {
		g.health = max(g.health - 1, 0)
		crew_starve(g)
	}
	if g.satiety == STAT_MAX {
		g.health = min(g.health + 1, STAT_MAX)
		crew_recover(g)
	}
	drift_markets(g)
	weather_turn(g)
	if under_way {
		for s in Side {g.foul[s] = min(g.foul[s] + foul_per_turn(g), FOUL_MAX)}
	}
	g.wage_turns = min(g.wage_turns + 1, TURN_LIMIT)
	g.turn += 1
	if in_storm(g) {
		n := storm_hit(g)
		if g.screen == .Over {return false}
		sound(g, .Storm)
		logf(g, "Storm! Hull -%d.", n)
	}
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

// Net worth: money plus the cargo at its base value (the user's choice of score, November 27, 2026).
score :: proc(g: ^Game) -> int {
	return g.money + cargo_value(g)
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
	g.log_page = logbook_pages(g) - 1 // the newest page first: how the voyage ended
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
	case .Sank:
		sound(g, .Lose)
		logf(g, "Your ship went down.")
	case .Killed:
		sound(g, .Lose)
		logf(g, "You fell in the fight.")
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
	for _ in 0 ..< careen_turns(g) {
		if !tick(g, false) {return}
	}
	g.foul[s] = 0
	logf(g, "%s side scraped clean.", s == .Port ? "Port" : "Starboard")
}
