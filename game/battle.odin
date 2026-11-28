package game

// Tactical battles (the user's request, November 28, 2026: keep the quick, strategic way, and add a way to fight it
// out in person, Final Fantasy style, with each crew member acting). "Take command" turns an encounter's round into a
// turn for each person aboard, captain first, then the foe's. Winning, losing and being robbed work as in a quick
// round. A battle is not saved: a voyage reloaded mid-battle is back at the encounter's orders, at the round's start.

Act :: enum u8 {
	Attack, // Melee (Track against a whale): 3 to 8, more with skill
	Aim, // an aimed shot, Spot less 15: 5 to 12, more with skill
	Defend, // half the wounds this person takes this round
	Patch, // Repair: mend 2 to 6 hull, more with skill (foes that strike the hull)
	All, // everyone left attacks: the rest of the round at once
}

AIM_PENALTY :: 15

Battle :: struct {
	on:     bool,
	actor:  int, // whose turn: a crew index
	guard:  [CREW_MAX]bool, // defending this round
	dealt:  int, // this round's damage to the foe, for the log
	mended: int, // this round's hull mended
}

can_command :: proc(g: ^Game) -> bool {
	f := g.foe
	if g.sub != .Encounter || f.state != .Close {return false}
	return f.kind == .Pirates || f.kind == .Monster || f.kind == .Whale || f.kind == .Merfolk
}

take_command :: proc(g: ^Game) {
	if !can_command(g) {return}
	if g.foe.kind == .Merfolk {g.foe.hostile = true}
	g.battle = {on = true}
	g.cursor = 0
}

// The skill this person attacks with, and its value.
attack_skill :: proc(g: ^Game, k: int) -> (s: Skill, v: int) {
	s = .Melee
	v = g.crew[k].skills[.Melee]
	if g.foe.kind == .Whale && g.crew[k].skills[.Track] > v {s, v = .Track, g.crew[k].skills[.Track]}
	return
}

patch_useful :: proc(g: ^Game) -> bool {return FOES[g.foe.kind].hull_hi > 0 && g.hull < hull_max(g)}

// One person's act. Returns true when the encounter is over (won, lost, or the voyage ended).
act :: proc(g: ^Game, a: Act) -> bool {
	b := &g.battle
	if !b.on || b.actor >= g.n_crew {return false}
	if a == .All {
		for b.actor < g.n_crew {
			if act(g, .Attack) {return true}
			if b.actor == 0 {return false} // the round ended: the foe has acted
		}
		return false
	}
	k := b.actor
	nb: [NAME_LEN]u8
	name := member_name(g.crew[k], nb[:])
	switch a {
	case .Attack, .Aim:
		_, v := attack_skill(g, k)
		if a == .Aim {v = max(g.crew[k].skills[.Spot] - AIM_PENALTY, 0)}
		if 1 + rng_below(&g.rng, 100) <= v {
			d := a == .Aim ? 5 + rng_below(&g.rng, 8) + v / 25 : 3 + rng_below(&g.rng, 6) + v / 25
			g.foe.hp = max(g.foe.hp - d, 0)
			b.dealt += d
			logf(g, "%s %s for %d.", name, a == .Aim ? "takes aim and hits" : "hits", d)
		} else {
			logf(g, "%s misses.", name)
		}
		if g.foe.hp == 0 {
			win_fight(g)
			return true
		}
	case .Defend:
		b.guard[k] = true
		logf(g, "%s stands guard.", name)
	case .Patch:
		v := g.crew[k].skills[.Repair]
		if 1 + rng_below(&g.rng, 100) <= v {
			m := min(2 + rng_below(&g.rng, 5) + v / 25, hull_max(g) - g.hull)
			g.hull += m
			b.mended += m
			logf(g, "%s patches the hull, +%d.", name, m)
		} else {
			logf(g, "%s can't stop the leak.", name)
		}
	case .All:
	}
	b.actor += 1
	if b.actor < g.n_crew {return false}
	// Everyone has acted: the foe's turn.
	hull, wounds := foe_attack(g)
	if g.screen == .Over {return true}
	logf(g, "Their turn: hull -%d, crew -%d.", hull, wounds)
	if g.foe.kind == .Pirates || g.foe.kind == .Merfolk {
		if fighting_strength(g) * 100 < g.foe.strength * BEATEN_PERCENT {
			beaten(g)
			return true
		}
	}
	g.battle = {on = true}
	return false
}

// A wound to crew member k, after any guard.
guarded :: proc(g: ^Game, k, w: int) -> int {
	if g.battle.on && k < CREW_MAX && g.battle.guard[k] {return (w + 1) / 2}
	return w
}
