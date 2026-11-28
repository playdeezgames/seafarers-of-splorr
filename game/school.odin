package game

// Training (the user's request, November 28, 2026; Claude's proposed design, which the user approved): some islands
// have a school or a master who teaches one or two skills, and every skill is taught somewhere. A lesson raises one
// skill of anyone aboard, captain included, by LESSON_GAIN points; it costs a fee that rises with the skill, and
// LESSON_TURNS turns in port. Schools are rolled from their own stream of the world seed, so they need no save space
// and older worlds keep everything else.

LESSON_GAIN :: 5
LESSON_TURNS :: 3
TRAIN_CAP :: 95 // lessons raise no skill past this
SCHOOLS_MIN :: 4
SCHOOLS_MAX :: 8

// Who teaches each skill; a school teaching two goes by its first.
SCHOOL_NAMES := [Skill]string {
	.Navigate = "a navigators' school",
	.Pilot    = "a pilots' guild",
	.Repair   = "a master shipwright",
	.Spot     = "a lookouts' tower",
	.Track    = "a hunters' lodge",
	.Bargain  = "a merchants' hall",
	.Gaming   = "a card sharp",
	.Melee    = "a fencing master",
}

// A third of the islands (four to eight) get a school; the eight skills are dealt out among them, so each is taught
// somewhere and a school teaches one or two.
generate_schools :: proc(g: ^Game) {
	g.schools = {}
	if g.n_islands == 0 {return}
	r := rng_make(g.seed ~ 0x5C_40_01_7E)
	n := min(clamp(g.n_islands / 3, SCHOOLS_MIN, SCHOOLS_MAX), g.n_islands)
	isles: [ISLAND_MAX]int
	for i in 0 ..< g.n_islands {isles[i] = i}
	for k in 0 ..< n { 	// a partial shuffle picks n islands
		j := k + rng_below(&r, g.n_islands - k)
		isles[k], isles[j] = isles[j], isles[k]
	}
	order: [len(Skill)]Skill
	for s, k in Skill {order[k] = s}
	for k := len(order) - 1; k > 0; k -= 1 {
		j := rng_below(&r, k + 1)
		order[k], order[j] = order[j], order[k]
	}
	for s, k in order {g.schools[isles[k % n]] += {s}}
}

// The fee for a lesson at a skill of v: 30 at 20%, 135 at 50%, 330 at 80%.
lesson_fee :: proc(v: int) -> int {return 10 + v * v / 20}

// Can crew member k take a lesson in skill s here now?
can_train :: proc(g: ^Game, k: int, s: Skill) -> bool {
	i := g.docked
	if i == NO_ISLAND || s not_in g.schools[i] || k < 0 || k >= g.n_crew {return false}
	v := g.crew[k].skills[s]
	return v < TRAIN_CAP && lesson_fee(v) <= g.money
}

// A lesson: pay, gain, then the turns pass in port. Returns the skill before and after (equal when refused).
train :: proc(g: ^Game, k: int, s: Skill) -> (before, after: int) {
	if !can_train(g, k, s) {return}
	before = g.crew[k].skills[s]
	g.money -= lesson_fee(before)
	after = min(before + LESSON_GAIN, TRAIN_CAP)
	g.crew[k].skills[s] = after
	note(g, .Trained, g.docked, int(g.crew[k].name_seed))
	for _ in 0 ..< LESSON_TURNS {
		if !tick(g, false) {break}
	}
	return
}

// "Melee" or "Melee and Spot": what the island's school teaches.
school_skills :: proc(g: ^Game, i: int, buf: []u8) -> string {
	n := 0
	for s in g.schools[i] {
		if n > 0 {n += copy(buf[n:], " and ")}
		n += copy(buf[n:], SKILL_NAMES[s])
	}
	return string(buf[:n])
}
