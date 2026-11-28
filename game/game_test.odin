#+build !js
package game

import "core:math"
import "core:testing"

@(test)
rng_is_repeatable_and_seeded :: proc(t: ^testing.T) {
	a, b, c := rng_make(42), rng_make(42), rng_make(43)
	same, differ := true, false
	for _ in 0 ..< 16 {
		x, y, z := rng_next(&a), rng_next(&b), rng_next(&c)
		if x != y {same = false}
		if x != z {differ = true}
	}
	testing.expect(t, same)
	testing.expect(t, differ)
	// splitmix64's published first output for seed 0.
	zero := rng_make(0)
	testing.expect_value(t, rng_next(&zero), 0xE220A8397B1DCDAF)
}

@(test)
rng_below_stays_in_range :: proc(t: ^testing.T) {
	r := rng_make(7)
	for _ in 0 ..< 1000 {
		v := rng_below(&r, 13)
		testing.expect(t, v >= 0 && v < 13)
	}
	testing.expect_value(t, rng_below(&r, 0), 0)
}

@(test)
world_depends_only_on_seed :: proc(t: ^testing.T) {
	g, h, k := new(Game), new(Game), new(Game)
	defer {free(g); free(h); free(k)}
	title(g, 1)
	title(h, 1)
	title(k, 2)
	testing.expect(t, g.n_islands >= 20)
	testing.expect(t, g.land == h.land)
	testing.expect(t, g.land != k.land)
	for i in 0 ..< g.n_islands {testing.expect_value(t, island_name(g, i), island_name(h, i))}
}

@(test)
islands_keep_their_gap_and_shape :: proc(t: ^testing.T) {
	for seed in u64(1) ..= 20 {
		g := new(Game)
		defer free(g)
		title(g, seed)
		for i in 0 ..< g.n_islands {
			for j in i + 1 ..< g.n_islands {
				dx, dy := g.islands[i].x - g.islands[j].x, g.islands[i].y - g.islands[j].y
				testing.expect(t, dx * dx + dy * dy >= ISLAND_GAP * ISLAND_GAP)
			}
		}
		// Every land tile has a neighbour across and one up or down (the coastline tiles need it), and touches no
		// other island.
		for ty in 0 ..< WORLD_SIZE {
			for tx in 0 ..< WORLD_SIZE {
				i := land_at(g, tx, ty)
				if i == NO_ISLAND {continue}
				m := land_mask(g, tx, ty)
				testing.expect(t, m & 0b1010 != 0 && m & 0b0101 != 0)
				for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
					o := land_at(g, tx + d.x, ty + d.y)
					testing.expect(t, o == NO_ISLAND || o == i)
				}
			}
		}
	}
}

@(test)
island_names_follow_classic :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 3)
	for i in 0 ..< g.n_islands {
		name := island_name(g, i)
		testing.expect(t, len(name) >= 3 && len(name) <= 9)
		testing.expect(t, name[0] >= 'A' && name[0] <= 'Z')
		for j in 1 ..< len(name) {
			a, b := lower(name[j - 1]), name[j]
			testing.expect(t, is_vowel(a) != is_vowel(b)) // they alternate
			testing.expect(t, is_vowel(b) || b == 'h' || b == 'k' || b == 'l' || b == 'm' || b == 'p')
		}
		for j in 0 ..< i {testing.expect(t, island_name(g, j) != name)}
	}
}

lower :: proc(c: u8) -> u8 {return c >= 'A' && c <= 'Z' ? c + 32 : c}
is_vowel :: proc(c: u8) -> bool {return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u'}

@(test)
voyage_starts_docked_at_home :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 99)
	voyage(g)
	testing.expect_value(t, g.seed, 99)
	testing.expect_value(t, g.screen, Screen.Docked)
	testing.expect_value(t, g.docked, 0)
	testing.expect(t, g.islands[0].charted)
	testing.expect(t, !is_land(g, int(g.ship.x), int(g.ship.y)))
	testing.expect(t, island_distance(g, 0, g.ship.x, g.ship.y) <= DOCK_RANGE)
	do_cmd(g, .Undock, 0)
	testing.expect_value(t, g.screen, Screen.Sea)
	testing.expect_value(t, g.docked, NO_ISLAND)
}

@(test)
seed_picks_the_first_voyage :: proc(t: ^testing.T) {
	g, h := new(Game), new(Game)
	defer {free(g); free(h)}
	title(g, 99)
	title(h, 99)
	voyage(g)
	voyage(h)
	testing.expect(t, g.next_seed != 99)
	testing.expect_value(t, g.next_seed, h.next_seed)
}

@(test)
headings_wrap_and_name :: proc(t: ^testing.T) {
	testing.expect_value(t, wrap_heading(-45), 315)
	testing.expect_value(t, wrap_heading(360), 0)
	testing.expect_value(t, compass(0), "N")
	testing.expect_value(t, compass(90), "E")
	testing.expect_value(t, compass(315), "NW")
	testing.expect_value(t, compass(350), "N")
}

// A game on open water: no islands, the ship mid-map.
open_sea :: proc(g: ^Game) {
	title(g, 5)
	voyage(g)
	g.land = {}
	g.n_islands = 0
	g.docked = NO_ISLAND
	g.screen = .Sea
	g.ship = {x = 60.5, y = 60.5, heading = 0, speed = 100}
}

near :: proc(a, b: f32) -> bool {return abs(a - b) < 0.01} // fouling shaves a little off each turn

@(test)
helm_and_speed :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	do_cmd(g, .Set_Heading, 90)
	testing.expect_value(t, g.ship.heading, 90)
	do_cmd(g, .Open, int(Sub.Adjust))
	do_cmd(g, .Adjust, -10)
	do_cmd(g, .Adjust, -5)
	testing.expect_value(t, g.ship.heading, 75)
	testing.expect_value(t, g.sub, Sub.Adjust) // adjusting stays open for more
	do_cmd(g, .Set_Heading, 0)
	do_cmd(g, .Adjust, -1)
	testing.expect_value(t, g.ship.heading, 359)
	do_cmd(g, .Set_Speed, 50)
	testing.expect_value(t, g.ship.speed, 50)
	testing.expect_value(t, g.sub, Sub.None)
}

@(test)
sailing_moves_along_heading_at_speed :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	do_cmd(g, .Sail, 3) // north at full sail
	testing.expect(t, near(g.ship.x, 60.5) && near(g.ship.y, 57.5))
	testing.expect_value(t, g.turn, 3)
	do_cmd(g, .Set_Heading, 90)
	do_cmd(g, .Set_Speed, 50)
	do_cmd(g, .Sail, 4)
	testing.expect(t, near(g.ship.x, 62.5) && near(g.ship.y, 57.5))
	testing.expect_value(t, g.turn, 7)
	do_cmd(g, .Set_Speed, 0)
	do_cmd(g, .Sail, 5)
	testing.expect(t, near(g.ship.x, 62.5))
	testing.expect_value(t, g.turn, 12)
}

@(test)
sailing_stops_at_land_edge_and_sighting :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	// An island two tiles north, already charted.
	g.islands[0] = {x = 60, y = 57, charted = true}
	g.islands[0].name_len = 3
	copy(g.islands[0].name[:], "Kal")
	g.land[57 * WORLD_SIZE + 60] = 1
	g.land[57 * WORLD_SIZE + 61] = 1
	g.land[58 * WORLD_SIZE + 60] = 1
	g.land[58 * WORLD_SIZE + 61] = 1
	g.n_islands = 1
	do_cmd(g, .Sail, 10)
	testing.expect_value(t, g.turn, 1) // one step to 59.5, then land at 58
	testing.expect(t, near(g.ship.y, 59.5))

	g.ship = {x = 0.5, y = 0.5, heading = 0, speed = 100}
	do_cmd(g, .Sail, 5)
	testing.expect(t, near(g.ship.y, 0.5))

	// Uncharted, and in view after a few turns sailing towards it from the south.
	g.islands[0].charted = false
	g.ship = {x = 60.5, y = 72.5, heading = 0, speed = 100}
	do_cmd(g, .Sail, 25)
	testing.expect(t, g.islands[0].charted)
	testing.expect(t, island_distance(g, 0, g.ship.x, g.ship.y) <= VIEW_DISTANCE)
	testing.expect(t, island_distance(g, 0, g.ship.x, g.ship.y) > VIEW_DISTANCE - 1)
}

@(test)
head_for_points_at_the_island :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.islands[0] = {x = 70, y = 60, charted = true} // due east
	g.land[60 * WORLD_SIZE + 70] = 1
	g.n_islands = 1
	do_cmd(g, .Head_For, 0)
	testing.expect_value(t, g.ship.heading, 90)
	g.islands[0].charted = false
	g.ship.heading = 0
	do_cmd(g, .Head_For, 0) // uncharted islands cannot be targeted
	testing.expect_value(t, g.ship.heading, 0)
}

// Classic docked at the farthest island in range; dock at the nearest, and ask when there are several.
@(test)
dock_picks_nearest_or_asks :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.islands[0] = {x = 61, y = 60, charted = true} // land tile (61, 60): 1.0 away
	g.islands[1] = {x = 59, y = 61, charted = true} // land tile (59, 61): about 1.41 away
	g.land[60 * WORLD_SIZE + 61] = 1
	g.land[61 * WORLD_SIZE + 59] = 2
	g.n_islands = 2
	out: [4]int
	testing.expect_value(t, dockable(g, out[:]), 2)
	testing.expect_value(t, out[0], 0)
	testing.expect_value(t, out[1], 1)
	do_cmd(g, .Dock, NO_ISLAND)
	testing.expect_value(t, g.sub, Sub.Dock) // several: choose
	testing.expect_value(t, menu(g).n, 3)
	choose(g, 1)
	testing.expect_value(t, g.docked, 1)
	testing.expect_value(t, g.screen, Screen.Docked)

	do_cmd(g, .Undock, 0)
	g.land[61 * WORLD_SIZE + 59] = 0
	do_cmd(g, .Dock, NO_ISLAND) // one in range: straight in
	testing.expect_value(t, g.docked, 0)

	do_cmd(g, .Undock, 0)
	g.ship.x = 50.5
	do_cmd(g, .Dock, NO_ISLAND)
	testing.expect_value(t, g.docked, NO_ISLAND)
}

@(test)
menus_and_head_for_list :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 3)
	testing.expect_value(t, menu(g).n, 2) // no voyage yet: New voyage, Sound
	input(g, .Up)
	testing.expect_value(t, g.cursor, 1)
	click(g, PANEL_X + 5, MENU_Y) // first line
	testing.expect_value(t, g.screen, Screen.Start) // choose a captain first
	choose(g, 2) // Sailor
	testing.expect_value(t, g.screen, Screen.Docked)
	testing.expect_value(t, g.crew[0].profession, Profession.Sailor)
	testing.expect_value(t, g.n_crew, 1 + START_CREW)
	do_cmd(g, .Undock, 0)
	m := menu(g)
	testing.expect(t, m.n <= MENU_MAX)
	testing.expect_value(t, m.items[4].cmd, Cmd.Open) // Head for (the home port is charted)
	testing.expect_value(t, m.items[5].cmd, Cmd.Dock) // still alongside
	do_cmd(g, .Open, int(Sub.Head_For))
	m = menu(g)
	testing.expect(t, m.n >= 2)
	testing.expect_value(t, m.items[0].arg, 0) // the home port is nearest
	testing.expect_value(t, m.items[m.n - 1].cmd, Cmd.Back)
	input(g, .Back)
	testing.expect_value(t, g.sub, Sub.None)
	input(g, .Back)
	testing.expect_value(t, g.screen, Screen.Title)
	testing.expect_value(t, menu(g).items[0].cmd, Cmd.Continue)
	choose(g, 9) // out of range is refused
	testing.expect_value(t, g.screen, Screen.Title)
	choose(g, 0)
	testing.expect_value(t, g.screen, Screen.Sea) // continue where we left off
}

@(test)
every_menu_fits :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 11)
	voyage(g)
	do_cmd(g, .Undock, 0)
	for i in 0 ..< g.n_islands {g.islands[i].charted = true}
	// Alongside an island (dock in range) every sea menu still fits; add() asserts on overflow.
	for s in Sub {
		g.sub = s
		m := menu(g)
		testing.expect(t, m.n >= 1 && m.n <= MENU_MAX)
		for k in 0 ..< m.n {testing.expect(t, len(m.items[k].label) < MENU_TEXT)}
	}
	g.sub = .None
	testing.expect_value(t, menu(g).items[menu(g).n - 1].cmd, Cmd.To_Title)
	do_cmd(g, .Dock, NO_ISLAND)
	testing.expect_value(t, g.screen, Screen.Docked)
	do_cmd(g, .Open, int(Sub.Careen))
	testing.expect_value(t, menu(g).n, 3)
}

@(test)
log_keeps_the_newest_lines :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for i in 0 ..< LOG_LINES + 2 {logf(g, "line %d", i)}
	testing.expect_value(t, log_line(g, LOG_LINES - 1), "line 5")
	testing.expect_value(t, log_line(g, 0), "line 2")
	logf(g, "%s", "a very long line that will certainly not fit in the forty bytes")
	testing.expect_value(t, len(log_line(g, LOG_LINES - 1)), LOG_LEN)
}

@(test)
save_round_trips :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 1234)
	voyage(g)
	do_cmd(g, .Undock, 0)
	do_cmd(g, .Set_Heading, 135)
	do_cmd(g, .Sail, 25)
	g.islands[3].charted = true
	buf: [SAVE_SIZE]u8
	save_encode(g, &buf)

	h := new(Game)
	defer free(h)
	title(h, 77)
	testing.expect_value(t, save_decode(h, buf[:]), Load_Error.None)
	testing.expect_value(t, h.seed, g.seed)
	testing.expect_value(t, h.rng.state, g.rng.state)
	testing.expect_value(t, h.turn, g.turn)
	testing.expect_value(t, h.ship, g.ship)
	testing.expect_value(t, h.docked, g.docked)
	testing.expect(t, h.land == g.land)
	for i in 0 ..< g.n_islands {testing.expect_value(t, h.islands[i].charted, g.islands[i].charted)}
	testing.expect_value(t, h.next_seed, 77) // the title's next voyage is untouched
	testing.expect(t, h.has_voyage)

	// Docked saves round-trip too.
	title(g, 1234)
	voyage(g)
	save_encode(g, &buf)
	testing.expect_value(t, save_decode(h, buf[:]), Load_Error.None)
	testing.expect_value(t, h.docked, 0)
	choose(h, 0)
	testing.expect_value(t, h.screen, Screen.Docked)
}

@(test)
save_rejects_bad_data :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 1)
	voyage(g)
	good: [SAVE_SIZE]u8
	save_encode(g, &good)

	h := new(Game)
	defer free(h)
	title(h, 2)
	testing.expect_value(t, save_decode(h, good[:10]), Load_Error.Size)
	testing.expect_value(t, save_decode(h, good[:3]), Load_Error.Size)
	v1: [35]u8 = {0 = 'S', 1 = 'O', 2 = 'S', 3 = 1} // a Phase 0 save
	testing.expect_value(t, save_decode(h, v1[:]), Load_Error.Version)
	bad := good
	bad[0] = 'X'
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Magic)
	bad = good
	bad[3] = 1 // Phase 0 saves describe another world
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Version)
	bad = good
	put_u16(bad[32:], 360)
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	bad[34] = 101
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	put_u32(bad[24:], transmute(u32)f32(WORLD_SIZE))
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	put_u32(bad[28:], 0x7FC00000) // NaN
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	put_u32(bad[20:], TURN_LIMIT)
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	bad[35] = u8(g.n_islands) // no such island
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	put_u64(bad[36:], 1 << uint(g.n_islands)) // charted bit past the last island
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	is := g.islands[0]
	put_u32(bad[24:], transmute(u32)(f32(is.x) + 0.5)) // on the home island's seed block
	put_u32(bad[28:], transmute(u32)(f32(is.y) + 0.5))
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	put_u32(bad[24:], transmute(u32)f32(1.5)) // docked, but far from the island
	put_u32(bad[28:], transmute(u32)f32(1.5))
	if !is_land(g, 1, 1) && math.abs(f32(is.x) - 1) > 3 {
		testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	}
	testing.expect_value(t, h.seed, 2) // untouched by every refusal
	testing.expect(t, !h.has_voyage)
}

@(test)
eating_and_starving :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	testing.expect_value(t, g.rations, START_RATIONS)
	do_cmd(g, .Sail, 10)
	testing.expect_value(t, g.rations, START_RATIONS - 10)
	testing.expect_value(t, g.satiety, STAT_MAX)
	g.rations = 0
	do_cmd(g, .Set_Speed, 0)
	do_cmd(g, .Sail, 25)
	testing.expect_value(t, g.satiety, STAT_MAX - 25)
	testing.expect_value(t, g.health, STAT_MAX)
	g.satiety = 1
	do_cmd(g, .Sail, 5) // one turn to empty, then four of hurting
	testing.expect_value(t, g.satiety, 0)
	testing.expect_value(t, g.health, STAT_MAX - 4)
	g.rations = 10
	g.satiety = STAT_MAX - 1
	do_cmd(g, .Sail, 3) // full on the first turn, so health returns on all three
	testing.expect_value(t, g.health, STAT_MAX - 1)
}

@(test)
starving_ends_the_voyage_as_a_loss :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.best, g.has_best = 500, true
	g.rations, g.satiety, g.health = 0, 0, 3
	do_cmd(g, .Set_Speed, 0)
	turn := g.turn
	do_cmd(g, .Sail, 25)
	testing.expect_value(t, g.turn, turn + 3) // stops on the turn it ends
	testing.expect_value(t, g.screen, Screen.Over)
	testing.expect_value(t, g.outcome, Outcome.Starved)
	testing.expect(t, !g.has_voyage)
	testing.expect(t, !g.new_best)
	testing.expect_value(t, g.best, 500)
	testing.expect_value(t, menu(g).items[0].cmd, Cmd.New_Voyage)
	choose(g, 0)
	testing.expect_value(t, g.screen, Screen.Start)
	choose(g, 0) // quick start
	testing.expect_value(t, g.screen, Screen.Docked) // a fresh voyage, fed and healthy
	testing.expect_value(t, g.health, STAT_MAX)
	testing.expect_value(t, g.best, 500)
}

@(test)
the_turn_limit_retires_with_a_score :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.money = 1234
	g.turn = TURN_LIMIT - 2
	do_cmd(g, .Set_Speed, 0)
	do_cmd(g, .Sail, 10)
	testing.expect_value(t, g.turn, TURN_LIMIT)
	testing.expect_value(t, g.outcome, Outcome.Retired)
	testing.expect_value(t, score(g), 1234)
	testing.expect(t, g.new_best && g.has_best && g.want_best)
	testing.expect_value(t, g.best, 1234)
	// A lower score later is not a new best; a zero first score is.
	h := new(Game)
	defer free(h)
	open_sea(h)
	h.best, h.has_best = 1234, true
	h.money = 10
	h.turn = TURN_LIMIT - 1
	do_cmd(h, .Sail, 1)
	testing.expect(t, !h.new_best)
	testing.expect_value(t, h.best, 1234)
	title(h, 9) // the best survives a return to the title
	testing.expect_value(t, h.best, 1234)
}

@(test)
fouling_slows_and_careening_cleans :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.ship.heading = 90
	g.rations = RATIONS_MAX
	for _ in 0 ..< 20 {do_cmd(g, .Sail, 25)} // 500 turns east, onto the world's edge at most
	testing.expect(t, g.foul[.Port] > 0)
	g.ship = {x = 60.5, y = 60.5, heading = 0, speed = 100}
	g.foul = {.Port = FOUL_MAX, .Starboard = FOUL_MAX}
	testing.expect(t, abs(effective_speed(g) - 50) < 0.01)
	testing.expect_value(t, hull_clean(g, .Port), 0)
	y0 := g.ship.y
	do_cmd(g, .Sail, 1)
	testing.expect(t, near(g.ship.y, y0 - 0.5))
	// Fouling does not grow at all stop.
	g.foul[.Port] = 100
	do_cmd(g, .Set_Speed, 0)
	do_cmd(g, .Sail, 5)
	testing.expect_value(t, g.foul[.Port], 100)

	// Careening needs land close by.
	turn := g.turn
	do_cmd(g, .Careen, int(Side.Port))
	testing.expect_value(t, g.turn, turn)
	testing.expect_value(t, g.foul[.Port], 100)
	g.islands[0] = {x = 61, y = 60, charted = true}
	g.land[60 * WORLD_SIZE + 61] = 1
	g.n_islands = 1
	testing.expect(t, can_careen(g))
	do_cmd(g, .Careen, int(Side.Port))
	testing.expect_value(t, g.turn, turn + CAREEN_TURNS)
	testing.expect_value(t, g.foul[.Port], 0)
	testing.expect_value(t, g.foul[.Starboard], FOUL_MAX)
}

@(test)
version_2_saves_load_with_starting_values :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 1234)
	voyage(g)
	buf: [SAVE_SIZE]u8
	save_encode(g, &buf)
	buf[3] = 2
	h := new(Game)
	defer free(h)
	title(h, 5)
	testing.expect_value(t, save_decode(h, buf[:SAVE_V2_SIZE]), Load_Error.None)
	testing.expect_value(t, h.rations, START_RATIONS)
	testing.expect_value(t, h.health, STAT_MAX)
	testing.expect_value(t, h.docked, 0)
	testing.expect_value(t, save_decode(h, buf[:]), Load_Error.Size) // version 2 at version 3's size
}

@(test)
survival_fields_round_trip_and_are_checked :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 77)
	voyage(g)
	g.money, g.rations, g.satiety, g.health = 321, 17, 40, 60
	g.foul = {.Port = 1200, .Starboard = 30}
	good: [SAVE_SIZE]u8
	save_encode(g, &good)
	h := new(Game)
	defer free(h)
	title(h, 5)
	testing.expect_value(t, save_decode(h, good[:]), Load_Error.None)
	testing.expect_value(t, h.money, 321)
	testing.expect_value(t, h.rations, 17)
	testing.expect_value(t, h.satiety, 40)
	testing.expect_value(t, h.health, 60)
	testing.expect_value(t, h.foul, g.foul)
	title(h, 5)
	bad := good
	bad[53] = 0 // dead
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	bad[52] = 101
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	put_u16(bad[54:], FOUL_MAX + 1)
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	put_u32(bad[48:], RATIONS_MAX + 1)
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	testing.expect(t, !h.has_voyage)
}

// Docked at the home port of a fresh voyage, with a known market: flour and timber traded, every commodity at 1.0.
trading_post :: proc(g: ^Game) {
	title(g, 21)
	voyage(g)
	g.trades[0] = {.Flour, .Timber, .Pepper}
	for c in Commodity {
		g.usual[0].supply[c], g.usual[0].demand[c] = 1000, 1000
	}
	g.markets[0] = g.usual[0]
	do_cmd(g, .Open, int(Sub.Market))
}

@(test)
goods_table_is_sane :: proc(t: ^testing.T) {
	testing.expect_value(t, base_value(.Flour), 6)
	testing.expect_value(t, base_value(.Rope), 9)
	testing.expect_value(t, base_value(.Pepper), 40)
	testing.expect_value(t, base_value(.Cutlasses), 28)
	for good in Good {
		testing.expect(t, GOODS[good].tons >= 1 && GOODS[good].tons <= 2)
		testing.expect(t, len(GOODS[good].name) > 0)
	}
}

@(test)
islands_trade_two_to_six_goods :: proc(t: ^testing.T) {
	for seed in u64(1) ..= 10 {
		g := new(Game)
		defer free(g)
		title(g, seed)
		for i in 0 ..< g.n_islands {
			n := card(g.trades[i])
			testing.expect(t, n >= GOODS_PER_ISLAND_MIN && n <= GOODS_PER_ISLAND_MAX)
			for c in Commodity {
				testing.expect(t, g.markets[i].supply[c] >= 600 && g.markets[i].supply[c] <= 1400)
			}
		}
		// The market menu (goods, rations, back) always fits.
		voyage(g)
		do_cmd(g, .Open, int(Sub.Market))
		testing.expect_value(t, menu(g).n, card(g.trades[0]) + 2)
	}
}

@(test)
prices_follow_supply_and_demand :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	trading_post(g)
	testing.expect_value(t, sell_price(g, 0, .Flour), 6) // at par: the base value
	testing.expect_value(t, buy_price(g, 0, .Flour), 5) // 10% below, rounded down
	testing.expect_value(t, ration_price(g, 0), 4)
	g.markets[0].demand[.Grain] = 2000
	testing.expect_value(t, sell_price(g, 0, .Flour), 12)
	g.markets[0].supply[.Grain] = 4000
	testing.expect_value(t, sell_price(g, 0, .Flour), 3)
}

// The user's report (November 28, 2026): buying 50 flour and selling it straight back made money. Across markets from
// glutted to starved, with the best bargainer aboard, a round trip in one port never gains.
@(test)
no_round_trip_profit :: proc(t: ^testing.T) {
	LEVELS :: [?]int{MARKET_MIN, 300, 600, 1000, 2000, 3500, MARKET_MAX}
	for sup in LEVELS {
		for dem in LEVELS {
			for good in Good.Flour ..= Good.Pepper {
				g := new(Game)
				defer free(g)
				trading_post(g)
				g.trades[0] += {good}
				g.crew[1] = {skills = BASE_SKILL, hp = STAT_MAX}
				g.n_crew = 2
				for sk in Skill {g.crew[1].skills[sk] = 100}
				for c in Commodity {g.markets[0].supply[c], g.markets[0].demand[c] = sup, dem}
				g.money = 1_000_000
				bought, _ := buy(g, good, 1000)
				sold, _ := sell(g, good, bought)
				testing.expect(t, bought > 0 && sold == bought)
				testing.expectf(t, g.money <= 1_000_000, "%v at supply %d demand %d: %d", good, sup, dem, g.money - 1_000_000)
			}
		}
	}
}

// The user's request (November 28, 2026): the trade menu shows only buys you can afford and sales you have goods for.
@(test)
trade_menu_offers_only_what_you_can_do :: proc(t: ^testing.T) {
	labels :: proc(g: ^Game) -> (cmds: [8]Cmd, args: [8]int, n: int) {
		m := menu(g)
		for k in 0 ..< m.n {
			cmds[k], args[k] = m.items[k].cmd, m.items[k].arg
		}
		return cmds, args, m.n
	}
	g := new(Game)
	defer free(g)
	trading_post(g)
	do_cmd(g, .Pick_Good, int(Good.Flour))
	cmds, args, n := labels(g)
	testing.expect_value(t, n, 4) // Buy 1, Buy 10, Buy max, Back: nothing to sell
	testing.expect(t, cmds[0] == .Buy && args[0] == 1 && cmds[1] == .Buy && args[1] == 10 && cmds[2] == .Buy && args[2] == ALL)
	do_cmd(g, .Buy, 1)
	cmds, args, n = labels(g)
	testing.expect_value(t, n, 5) // the buys, Sell 1, Back
	testing.expect(t, cmds[3] == .Sell && args[3] == 1)
	g.money = your_cost(g, 0, .Flour) // one more and no more
	cmds, args, n = labels(g)
	testing.expect_value(t, n, 3) // Buy 1, Sell 1, Back
	testing.expect(t, cmds[0] == .Buy && args[0] == 1 && cmds[1] == .Sell && args[1] == 1)
	do_cmd(g, .Buy, 1)
	cmds, args, n = labels(g)
	testing.expect_value(t, n, 3) // Sell 1, Sell all, Back: no money left
	testing.expect(t, cmds[0] == .Sell && args[0] == 1 && cmds[1] == .Sell && args[1] == ALL)
	g.money = 0
	do_cmd(g, .Sell, 1)
	g.money = 0
	do_cmd(g, .Sell, 1)
	testing.expect_value(t, g.cargo[.Flour], 0)
	g.money = 0
	testing.expect(t, !can_trade(g))
	do_cmd(g, .Open, int(Sub.Market))
	do_cmd(g, .Pick_Good, int(Good.Flour))
	testing.expect_value(t, g.sub, Sub.Market) // nothing to buy or sell
	do_cmd(g, .Pick_Good, RATIONS)
	testing.expect_value(t, g.sub, Sub.Market)
}

@(test)
buying_and_selling :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	trading_post(g)
	testing.expect_value(t, g.money, START_MONEY)
	do_cmd(g, .Pick_Good, int(Good.Flour))
	testing.expect_value(t, g.sub, Sub.Trade)
	do_cmd(g, .Buy, 10)
	testing.expect_value(t, g.cargo[.Flour], 10)
	testing.expect(t, g.money < START_MONEY - 60) // the price rose as we bought
	testing.expect(t, g.markets[0].supply[.Grain] == 1000 - 10 * 3 * IMPACT)
	testing.expect_value(t, hold_used(g), 10)
	worth := score(g)
	testing.expect_value(t, worth, g.money + 60)
	money := g.money
	do_cmd(g, .Sell, ALL)
	testing.expect_value(t, g.cargo[.Flour], 0)
	testing.expect(t, g.money > money && g.money < START_MONEY) // the round trip loses the spread
	do_cmd(g, .Sell, 1) // nothing left
	testing.expect_value(t, g.cargo[.Flour], 0)
	// Goods the island does not trade cannot be picked.
	do_cmd(g, .Back, 0)
	testing.expect_value(t, g.sub, Sub.Market)
	do_cmd(g, .Pick_Good, int(Good.Rum))
	testing.expect_value(t, g.sub, Sub.Market)
	do_cmd(g, .Back, 0)
	testing.expect_value(t, g.sub, Sub.None)
}

@(test)
the_hold_and_the_purse_limit_buying :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	trading_post(g)
	g.money = 1_000_000
	do_cmd(g, .Pick_Good, int(Good.Timber))
	do_cmd(g, .Buy, ALL)
	testing.expect_value(t, g.cargo[.Timber], HOLD_TONS / 2) // two tons each
	testing.expect_value(t, hold_used(g), HOLD_TONS)
	do_cmd(g, .Back, 0)
	do_cmd(g, .Pick_Good, int(Good.Flour))
	do_cmd(g, .Buy, 1)
	testing.expect_value(t, g.cargo[.Flour], 0)

	h := new(Game)
	defer free(h)
	trading_post(h)
	h.money = 100
	do_cmd(h, .Pick_Good, int(Good.Pepper))
	do_cmd(h, .Buy, ALL)
	testing.expect_value(t, h.cargo[.Pepper], 2) // 40, then a little dearer, then out of money
	testing.expect(t, h.money < 40)
}

@(test)
rations_from_the_market :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	trading_post(g)
	do_cmd(g, .Pick_Good, RATIONS)
	do_cmd(g, .Buy, 10)
	testing.expect_value(t, g.rations, START_RATIONS + 100)
	testing.expect(t, g.money < START_MONEY - 39)
	testing.expect_value(t, hold_used(g), 0)
	do_cmd(g, .Sell, 1) // rations cannot be sold back
	testing.expect_value(t, g.rations, START_RATIONS + 100)
}

@(test)
markets_drift_back :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	trading_post(g)
	g.markets[0].demand[.Grain] = 3000
	g.markets[0].supply[.Ore] = 300
	for _ in 0 ..< 400 {drift_markets(g)}
	testing.expect_value(t, g.markets[0].demand[.Grain], 1000)
	testing.expect_value(t, g.markets[0].supply[.Ore], 1000)
	// Time passing at sea drifts them too.
	g.markets[0].demand[.Grain] = 2000
	do_cmd(g, .Back, 0)
	do_cmd(g, .Careen, int(Side.Port))
	testing.expect(t, g.markets[0].demand[.Grain] < 2000)
}

@(test)
trade_state_round_trips :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	trading_post(g)
	do_cmd(g, .Pick_Good, int(Good.Flour))
	do_cmd(g, .Buy, 7)
	good: [SAVE_SIZE]u8
	save_encode(g, &good)
	h := new(Game)
	defer free(h)
	title(h, 3)
	testing.expect_value(t, save_decode(h, good[:]), Load_Error.None)
	testing.expect_value(t, h.cargo, g.cargo)
	testing.expect_value(t, h.money, g.money)
	testing.expect_value(t, h.markets[0], g.markets[0])

	title(h, 3)
	bad := good
	put_u16(bad[58:], HOLD_TONS + 1) // more flour than the hold holds
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	put_u16(bad[82:], MARKET_MIN - 1)
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	put_u16(bad[SAVE_V4_SIZE - 2:], 1000) // a market for an island slot that does not exist
	if g.n_islands < ISLAND_MAX {testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)}
	testing.expect(t, !h.has_voyage)

	// A Phase 2 save (version 3) loads with the starting purse and an empty hold.
	v3 := good
	v3[3] = 3
	testing.expect_value(t, save_decode(h, v3[:SAVE_V3_SIZE]), Load_Error.None)
	testing.expect_value(t, h.money, START_MONEY)
	testing.expect_value(t, hold_used(h), 0)
}

// A fresh voyage whose home port has every district.
busy_port :: proc(g: ^Game) {
	title(g, 31)
	voyage(g)
	g.districts[0] = {.Delivery_Service, .Street_Vendor, .Dark_Alley}
	make_offers(g)
}

@(test)
districts_come_from_the_seed :: proc(t: ^testing.T) {
	g, h := new(Game), new(Game)
	defer {free(g); free(h)}
	title(g, 8)
	title(h, 8)
	testing.expect(t, g.districts == h.districts)
	with := 0
	for i in 0 ..< g.n_islands {if .Delivery_Service in g.districts[i] {with += 1}}
	testing.expect(t, with > 0 && with < g.n_islands)
}

@(test)
docked_menu_shows_the_districts :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	busy_port(g)
	m := menu(g)
	testing.expect_value(t, m.n, 8) // cast off, market, deliveries, vendor, alley, careen, sound, title
	testing.expect_value(t, m.items[2].arg, int(Sub.Deliveries))
	testing.expect_value(t, m.items[3].arg, int(Sub.Vendor))
	g.districts[0] = {}
	testing.expect_value(t, menu(g).n, 5)
}

@(test)
offers_and_accepting :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	busy_port(g)
	testing.expect_value(t, g.n_offers, OFFERS_MAX)
	for k in 0 ..< g.n_offers {
		o := g.offers[k]
		d := leagues_between(g, 0, o.to)
		testing.expect(t, o.from == 0 && o.to != 0)
		testing.expect(t, o.reward >= 10 + d && o.reward <= 10 + 3 * d)
		testing.expect_value(t, o.due, g.turn + DEADLINE_FACTOR * d)
	}
	g.islands[g.offers[0].to].charted = false
	to := g.offers[0].to
	do_cmd(g, .Open, int(Sub.Deliveries))
	do_cmd(g, .Pick_Offer, 0)
	testing.expect_value(t, g.sub, Sub.Offer)
	do_cmd(g, .Accept, 0)
	testing.expect_value(t, g.n_carried, 1)
	testing.expect_value(t, g.n_offers, OFFERS_MAX - 1)
	testing.expect(t, g.islands[to].charted) // accepting charts the destination
	testing.expect(t, is_destination(g, to))
	testing.expect_value(t, g.sub, Sub.Deliveries)
	// Three at most.
	do_cmd(g, .Pick_Offer, 0)
	do_cmd(g, .Accept, 0)
	do_cmd(g, .Pick_Offer, 0)
	do_cmd(g, .Accept, 0)
	testing.expect_value(t, g.n_carried, CARRY_MAX)
	make_offers(g)
	do_cmd(g, .Pick_Offer, 0)
	do_cmd(g, .Accept, 0)
	testing.expect_value(t, g.n_carried, CARRY_MAX)
	testing.expect_value(t, g.n_offers, OFFERS_MAX)
	// Abandoning one frees a slot.
	do_cmd(g, .Back, 0)
	do_cmd(g, .Open, int(Sub.Carried))
	do_cmd(g, .Pick_Carried, 1)
	do_cmd(g, .Abandon, 0)
	testing.expect_value(t, g.n_carried, CARRY_MAX - 1)
	testing.expect_value(t, g.sub, Sub.Carried)
}

@(test)
delivering_pays_on_docking_and_late_pays_half :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.islands[0] = {x = 61, y = 60, charted = true}
	g.land[60 * WORLD_SIZE + 61] = 1
	g.islands[1] = {x = 20, y = 20, charted = true}
	g.n_islands = 2
	g.carried[0] = {from = 1, to = 0, reward = 100, due = g.turn + 50}
	g.carried[1] = {from = 1, to = 0, reward = 60, due = g.turn - 1} // already late
	g.carried[2] = {from = 0, to = 1, reward = 80, due = g.turn + 50}
	g.n_carried = 3
	money := g.money
	do_cmd(g, .Dock, NO_ISLAND)
	testing.expect_value(t, g.docked, 0)
	testing.expect_value(t, g.money, money + 100 + 30)
	testing.expect_value(t, g.n_carried, 1)
	testing.expect_value(t, g.carried[0].to, 1)
	testing.expect_value(t, g.deliveries_made, 2)
}

@(test)
offers_stay_at_the_island :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	busy_port(g)
	do_cmd(g, .Undock, 0)
	testing.expect_value(t, g.n_offers, 0)
	g.districts[0] = {}
	do_cmd(g, .Dock, NO_ISLAND)
	testing.expect_value(t, g.n_offers, 0) // no delivery service, no offers
}

@(test)
the_street_vendor :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	busy_port(g)
	for c in Commodity {g.markets[0].supply[c], g.markets[0].demand[c] = 1000, 1000}
	testing.expect_value(t, vendor_price(g, 0), 1) // 0.6 grain: cheaper than the market's 4 for ten
	do_cmd(g, .Open, int(Sub.Vendor))
	rations := g.rations
	do_cmd(g, .Vendor_Buy, 5)
	testing.expect_value(t, g.rations, rations + 5 * VENDOR_LOT)
	testing.expect_value(t, g.vendor_stock, VENDOR_STOCK - 5)
	do_cmd(g, .Vendor_Buy, 100)
	testing.expect_value(t, g.vendor_stock, 0) // sold out
	testing.expect_value(t, g.rations, rations + VENDOR_STOCK * VENDOR_LOT)
	testing.expect_value(t, g.sub, Sub.None) // nothing left to buy: back to the port
	m := menu(g)
	for k in 0 ..< m.n {testing.expect(t, !(m.items[k].cmd == .Open && m.items[k].arg == int(Sub.Vendor)))}
	do_cmd(g, .Open, int(Sub.Vendor))
	testing.expect_value(t, g.sub, Sub.None)
	do_cmd(g, .Undock, 0)
	do_cmd(g, .Dock, NO_ISLAND)
	testing.expect_value(t, g.vendor_stock, VENDOR_STOCK) // restocked for the next visit
	g.money = 3 * vendor_price(g, 0) // three lots' worth: only the single lot shows
	do_cmd(g, .Open, int(Sub.Vendor))
	testing.expect_value(t, g.sub, Sub.Vendor)
	m = menu(g)
	testing.expect_value(t, m.n, 2) // buy one lot, Back
	testing.expect_value(t, m.items[0].arg, 1)
}

@(test)
every_docked_menu_fits :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	busy_port(g)
	for s in Sub {
		g.sub = s
		g.pick = 0
		m := menu(g)
		testing.expect(t, m.n >= 1 && m.n <= MENU_MAX)
		for k in 0 ..< m.n {testing.expect(t, len(m.items[k].label) < MENU_TEXT)}
	}
}

@(test)
delivery_text_reads_well :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	busy_port(g)
	buf: [200]u8
	text := delivery_text(g, g.offers[0], buf[:])
	testing.expect(t, len(text) > 40)
	testing.expect_value(t, text[:7], "Please ")
	testing.expect_value(t, text[len(text) - 1], '.')
}

@(test)
delivery_state_round_trips :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	busy_port(g)
	do_cmd(g, .Open, int(Sub.Deliveries))
	do_cmd(g, .Pick_Offer, 1)
	do_cmd(g, .Accept, 0)
	g.vendor_stock = 4
	g.deliveries_made = 7
	good: [SAVE_SIZE]u8
	save_encode(g, &good)
	h := new(Game)
	defer free(h)
	title(h, 3)
	testing.expect_value(t, save_decode(h, good[:]), Load_Error.None)
	testing.expect_value(t, h.n_offers, g.n_offers)
	testing.expect_value(t, h.n_carried, 1)
	testing.expect_value(t, h.carried[0], g.carried[0])
	testing.expect_value(t, h.offers[0], g.offers[0])
	testing.expect_value(t, h.vendor_stock, 4)
	testing.expect_value(t, h.deliveries_made, 7)

	title(h, 3)
	bad := good
	bad[SAVE_V4_SIZE + 37] = 4 // four carried
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	bad[SAVE_V4_SIZE + 37 + 2] = u8(g.n_islands) // carried to no island
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	bad[SAVE_V4_SIZE + 2 * 37] = VENDOR_STOCK + 1
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	testing.expect(t, !h.has_voyage)

	// A Phase 3 save loads with nothing carried.
	v4 := good
	v4[3] = 4
	testing.expect_value(t, save_decode(h, v4[:SAVE_V4_SIZE]), Load_Error.None)
	testing.expect_value(t, h.n_carried, 0)
	testing.expect_value(t, h.vendor_stock, VENDOR_STOCK)
}

@(test)
the_price_book_records_on_docking_and_trading :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	trading_post(g) // docked at the home port, which trades flour, timber and pepper at par
	record_prices(g)
	testing.expect_value(t, g.seen[0].turn, 0)
	testing.expect_value(t, g.seen[0].price[.Flour], 6)
	testing.expect_value(t, g.seen[0].price[.Rum], 0) // not traded there
	testing.expect_value(t, g.seen[1].turn, NEVER_SEEN)
	do_cmd(g, .Pick_Good, int(Good.Flour))
	do_cmd(g, .Buy, 50)
	testing.expect(t, g.seen[0].price[.Flour] > 6) // trading updates the record
	// Away from the island the record stays as it was, with its turn.
	g.turn = 40
	g.markets[0].demand[.Grain] = 3000
	testing.expect(t, g.seen[0].price[.Flour] < sell_price(g, 0, .Flour))
	testing.expect_value(t, g.seen[0].turn, 0)
	testing.expect_value(t, paid_for(10), 9)
}

@(test)
book_rows_sort_dearest_first :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 4)
	for i in 0 ..< 4 {
		g.trades[i] = {.Pepper}
		g.seen[i] = {turn = i}
	}
	g.seen[0].price[.Pepper] = 30
	g.seen[1].price[.Pepper] = 50
	g.seen[2].price[.Pepper] = 40
	g.seen[3].turn = NEVER_SEEN // never docked: not listed
	rows: [ISLAND_MAX]int
	n := book_rows(g, .Pepper, rows[:])
	testing.expect_value(t, n, 3)
	testing.expect_value(t, rows[0], 1)
	testing.expect_value(t, rows[1], 2)
	testing.expect_value(t, rows[2], 0)
	testing.expect_value(t, book_rows(g, .Flour, rows[:]), 0)
}

@(test)
the_price_book_from_the_chart :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 4)
	voyage(g)
	do_cmd(g, .Undock, 0)
	do_cmd(g, .Open, int(Sub.Chart))
	testing.expect_value(t, menu(g).items[0].arg, int(Sub.Book))
	do_cmd(g, .Open, int(Sub.Book))
	do_cmd(g, .Book_Step, -1)
	testing.expect_value(t, g.book_good, Good.Pepper) // wraps round
	do_cmd(g, .Book_Step, 1)
	testing.expect_value(t, g.book_good, Good.Flour)
	input(g, .Back)
	testing.expect_value(t, g.sub, Sub.Chart)
}

@(test)
the_price_book_round_trips :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	trading_post(g)
	record_prices(g)
	g.turn = 5
	good: [SAVE_SIZE]u8
	save_encode(g, &good)
	h := new(Game)
	defer free(h)
	title(h, 3)
	testing.expect_value(t, save_decode(h, good[:]), Load_Error.None)
	testing.expect_value(t, h.seen[0].turn, 0)
	for good in Good {
		if good in h.trades[0] && good in g.trades[0] {testing.expect_value(t, h.seen[0].price[good], g.seen[0].price[good])}
		if good not_in h.trades[0] {testing.expect_value(t, h.seen[0].price[good], 0)}
	}

	title(h, 3)
	bad := good
	put_u16(bad[SAVE_V5_SIZE:], 600) // seen after the saved turn (an older build's slip): read as seen now
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.None)
	testing.expect_value(t, h.seen[0].turn, 5)
	title(h, 3)
	bad = good
	put_u16(bad[SAVE_V5_SIZE + 2:], PRICE_MAX + 1)
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	testing.expect(t, !h.has_voyage)

	// A Phase 4 save starts the book with the docked island.
	v5 := good
	v5[3] = 5
	testing.expect_value(t, save_decode(h, v5[:SAVE_V5_SIZE]), Load_Error.None)
	testing.expect_value(t, h.seen[0].turn, 5)
	testing.expect_value(t, h.seen[1].turn, NEVER_SEEN)
}

@(test)
tarot_values_and_the_in_between_rule :: proc(t: ^testing.T) {
	testing.expect_value(t, card_value(0), 1) // Ace of Wands
	testing.expect_value(t, card_value(13), 14) // King of Wands
	testing.expect_value(t, card_value(14), 1) // Ace of Cups: suits are equal
	testing.expect_value(t, card_value(MINORS), 15) // The Fool beats every suit card
	testing.expect_value(t, card_value(DECK_SIZE - 1), 36) // The World
	two_of_wands, ten_of_cups, five_of_swords := 1, 14 + 9, 28 + 4
	testing.expect(t, in_between(two_of_wands, ten_of_cups, five_of_swords))
	testing.expect(t, in_between(ten_of_cups, two_of_wands, five_of_swords)) // either order
	testing.expect(t, !in_between(two_of_wands, ten_of_cups, 14 + 1)) // a tie with the two loses
	testing.expect(t, !in_between(two_of_wands, ten_of_cups, MINORS)) // a trump is above both
	testing.expect(t, is_pair(4, 14 + 4)) // fives of two suits
	testing.expect(t, !in_between(4, 14 + 4, 28 + 4))
	buf: [40]u8
	testing.expect_value(t, card_name(13 + 14 * 3, buf[:]), "King of Pentacles")
	testing.expect_value(t, card_name(MINORS + 13, buf[:]), "Death")
}

// Docked at a home port with a dark alley at stake 10.
alley :: proc(g: ^Game) {
	title(g, 41)
	voyage(g)
	g.districts[0] = {.Dark_Alley}
	g.stakes[0] = 10
	do_cmd(g, .Open, int(Sub.Alley))
}

@(test)
the_ante_and_a_bet :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	alley(g)
	testing.expect_value(t, menu(g).items[0].cmd, Cmd.Deal)
	do_cmd(g, .Deal, 0)
	testing.expect_value(t, g.money, START_MONEY - 10)
	testing.expect_value(t, g.hand_state, Hand_State.Dealt)
	testing.expect(t, g.hand[0] != g.hand[1] && g.hand[1] != g.hand[2] && g.hand[0] != g.hand[2])
	testing.expect_value(t, menu(g).n, len(BET_STEPS) + 1) // four bets and a fold
	// Rig the hand: a win, then a loss.
	g.hand = {1, 14 + 9, 28 + 4}
	do_cmd(g, .Bet, 5)
	testing.expect_value(t, g.hand_state, Hand_State.Shown)
	testing.expect(t, g.hand_won)
	testing.expect_value(t, g.money, START_MONEY - 10 + 50)
	do_cmd(g, .Deal, 0)
	g.hand = {1, 14 + 9, 14 + 1} // the third ties the two: Classic's rule, a loss
	money := g.money
	do_cmd(g, .Bet, 2)
	testing.expect(t, !g.hand_won)
	testing.expect_value(t, g.money, money - 20)
}

@(test)
folding_loses_only_the_ante :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	alley(g)
	do_cmd(g, .Deal, 0)
	do_cmd(g, .Fold, 0)
	testing.expect_value(t, g.hand_state, Hand_State.None)
	testing.expect_value(t, g.money, START_MONEY - 10)
	// Leaving the table mid-hand folds it too.
	do_cmd(g, .Deal, 0)
	input(g, .Back)
	testing.expect_value(t, g.sub, Sub.None)
	testing.expect_value(t, g.hand_state, Hand_State.None)
	testing.expect_value(t, g.money, START_MONEY - 20)
}

@(test)
the_alley_needs_money :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	alley(g)
	g.money = 9
	do_cmd(g, .Deal, 0)
	testing.expect_value(t, g.hand_state, Hand_State.None)
	testing.expect_value(t, g.money, 9)
	g.money = 30
	do_cmd(g, .Deal, 0) // 20 left: bets of 10 and 20 only
	testing.expect(t, !place_bet(g, 5))
	testing.expect(t, !place_bet(g, 0))
	testing.expect(t, place_bet(g, 2))
}

@(test)
stakes_come_from_the_seed :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 12)
	for i in 0 ..< g.n_islands {
		testing.expect(t, g.stakes[i] >= 5 && g.stakes[i] <= 25 && g.stakes[i] % 5 == 0)
	}
}

@(test)
head_for_pages_when_many_are_charted :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 13)
	voyage(g)
	do_cmd(g, .Undock, 0)
	for i in 0 ..< g.n_islands {g.islands[i].charted = true}
	n := g.n_islands
	pages := (n + HEAD_FOR_PAGE - 1) / HEAD_FOR_PAGE
	do_cmd(g, .Open, int(Sub.Head_For))
	seen: [ISLAND_MAX]bool
	for p in 0 ..< pages {
		m := menu(g)
		testing.expect(t, m.n <= MENU_MAX)
		testing.expect_value(t, m.items[m.n - 1].cmd, Cmd.Back)
		testing.expect_value(t, m.items[m.n - 2].cmd, Cmd.Next_Page)
		for k in 0 ..< m.n - 2 {
			testing.expect_value(t, m.items[k].cmd, Cmd.Head_For)
			testing.expect(t, !seen[m.items[k].arg])
			seen[m.items[k].arg] = true
		}
		choose(g, m.n - 2) // More
		testing.expect_value(t, g.sub, Sub.Head_For)
		_ = p
	}
	for i in 0 ..< n {testing.expect(t, seen[i])} // every island is reachable on some page
	testing.expect_value(t, menu(g).items[0].arg, charted_nearest(g)) // and it wraps to the first page
	// Choosing one far down the list sets a course for it.
	do_cmd(g, .Next_Page, 0)
	m := menu(g)
	target := m.items[0].arg
	choose(g, 0)
	testing.expect_value(t, g.course, target)
	testing.expect(t, abs(wrap_heading(g.ship.heading - bearing_to(g, target) + 180) - 180) < 90)
	// A few charted islands still fit without paging.
	for i in 3 ..< n {g.islands[i].charted = false}
	do_cmd(g, .Open, int(Sub.Head_For))
	testing.expect_value(t, menu(g).items[menu(g).n - 2].cmd, Cmd.Head_For)
}

charted_nearest :: proc(g: ^Game) -> int {
	out: [1]int
	charted_by_distance(g, out[:])
	return out[0]
}

// Starts a voyage the way Phases 1 to 5 did: a captain of base skills and no crew, so older tests keep their numbers.
voyage :: proc(g: ^Game) {
	do_cmd(g, .New_Voyage, 0)
	begin_voyage(g, .Custom, BASE_SKILL, false)
	g.weather_off = true // no wind, storms or rats unless a test turns them on (Phase 9)
}

// Phase 6: crew and professions.

// Docked at a home port with a tavern, a captain of base skills and three crew.
crewed :: proc(g: ^Game) {
	title(g, 61)
	do_cmd(g, .New_Voyage, 0)
	begin_voyage(g, .Custom, BASE_SKILL)
	g.districts[0] += {.Tavern}
	make_candidates(g)
}

@(test)
choosing_a_captain :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 7)
	voyage(g)
	seed := g.seed
	do_cmd(g, .To_Title, 0)
	do_cmd(g, .New_Voyage, 0)
	testing.expect_value(t, g.screen, Screen.Start)
	testing.expect_value(t, menu(g).n, 7) // Quick start, four professions, Custom, Back
	input(g, .Back) // backing out keeps the voyage
	testing.expect_value(t, g.screen, Screen.Title)
	testing.expect(t, g.has_voyage)
	testing.expect_value(t, g.seed, seed)

	for p in Profession.Hunter ..= Profession.Warrior {
		title(g, 7)
		do_cmd(g, .New_Voyage, 0)
		do_cmd(g, .Begin, int(p))
		testing.expect_value(t, g.screen, Screen.Docked)
		testing.expect_value(t, g.crew[0].profession, p)
		testing.expect(t, g.crew[0].skills == profession_skills(p))
		testing.expect_value(t, g.crew[0].wage, 0)
		testing.expect_value(t, g.n_crew, 1 + START_CREW)
		total := 0
		for s in Skill {total += g.crew[0].skills[s] - BASE_SKILL[s]}
		testing.expect_value(t, total, SKILL_POINTS)
	}

	// A quick start is a profession chosen from the seed.
	h := new(Game)
	defer free(h)
	title(g, 9)
	title(h, 9)
	do_cmd(g, .New_Voyage, 0)
	do_cmd(h, .New_Voyage, 0)
	do_cmd(g, .Begin, QUICK)
	do_cmd(h, .Begin, QUICK)
	testing.expect(t, g.crew == h.crew)
	testing.expect(t, g.crew[0].profession != .Custom)
}

@(test)
a_custom_captain_spends_points :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 7)
	do_cmd(g, .New_Voyage, 0)
	do_cmd(g, .Open, int(Sub.Custom))
	testing.expect_value(t, menu(g).n, len(Skill) + 1)
	for _ in 0 ..< 20 {do_cmd(g, .Spend, int(Skill.Track))} // capped
	testing.expect_value(t, BASE_SKILL[.Track] + g.spent[.Track], SKILL_CAP)
	for _ in 0 ..< 20 {do_cmd(g, .Spend, int(Skill.Bargain))} // out of points
	testing.expect_value(t, points_left(g), 0)
	input(g, .Back) // back to the professions resets nothing until Custom is opened again
	do_cmd(g, .Open, int(Sub.Custom))
	testing.expect_value(t, points_left(g), SKILL_POINTS)
	do_cmd(g, .Spend, int(Skill.Gaming))
	do_cmd(g, .Begin, int(Profession.Custom))
	testing.expect_value(t, g.screen, Screen.Docked)
	testing.expect_value(t, g.crew[0].skills[.Gaming], BASE_SKILL[.Gaming] + SKILL_STEP)
	testing.expect_value(t, g.crew[0].skills[.Track], BASE_SKILL[.Track])
}

@(test)
names_are_stable_and_readable :: proc(t: ^testing.T) {
	buf, again: [NAME_LEN]u8
	r := rng_make(5)
	for _ in 0 ..< 200 {
		m := Member{name_seed = new_name_seed(&r)}
		name := member_name(m, buf[:])
		testing.expect(t, len(name) >= 3 && len(name) <= NAME_LEN)
		testing.expect(t, name[0] >= 'A' && name[0] <= 'Z')
		testing.expect_value(t, member_name(m, again[:]), name)
	}
}

@(test)
everyone_eats_and_crew_can_starve :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	crewed(g)
	do_cmd(g, .Undock, 0)
	do_cmd(g, .Set_Speed, 0)
	rations := g.rations
	do_cmd(g, .Sail, 1)
	testing.expect_value(t, g.rations, rations - g.n_crew)

	g.rations, g.satiety = 2, 1 // not enough to go round: nobody is fed
	do_cmd(g, .Sail, 1)
	testing.expect_value(t, g.rations, 0)
	testing.expect_value(t, g.satiety, 0)
	g.crew[1].hp = 2
	do_cmd(g, .Sail, 2)
	testing.expect_value(t, g.n_crew, START_CREW) // one died
	testing.expect_value(t, g.screen, Screen.Sea) // the captain lives on
	testing.expect_value(t, g.logbook[g.n_logbook - 1].kind, Log_Kind.Died)
}

@(test)
wages_are_paid_on_docking :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	crewed(g)
	w := wages(g)
	testing.expect(t, w > 0)
	do_cmd(g, .Undock, 0)
	do_cmd(g, .Set_Speed, 0)
	do_cmd(g, .Sail, 10)
	testing.expect_value(t, g.wage_turns, 10)
	money := g.money
	do_cmd(g, .Dock, 0)
	testing.expect_value(t, g.money, money - w)
	testing.expect_value(t, g.wage_turns, 0)
	testing.expect_value(t, g.n_crew, 1 + START_CREW)

	// Whoever cannot be paid leaves.
	do_cmd(g, .Undock, 0)
	do_cmd(g, .Sail, 10)
	g.money = g.crew[1].wage
	do_cmd(g, .Dock, 0)
	testing.expect_value(t, g.n_crew, 2)
	testing.expect_value(t, g.money, 0)
	testing.expect_value(t, g.logbook[g.n_logbook - 1].kind, Log_Kind.Deserted)
}

@(test)
hiring_and_dismissing :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	crewed(g)
	testing.expect_value(t, g.n_candidates, CANDIDATES_MAX)
	m := menu(g)
	found := false
	for k in 0 ..< m.n {if m.items[k].cmd == .Open && m.items[k].arg == int(Sub.Tavern) {found = true}}
	testing.expect(t, found)
	do_cmd(g, .Open, int(Sub.Tavern))
	testing.expect_value(t, menu(g).n, CANDIDATES_MAX + 1)
	c := g.candidates[0]
	do_cmd(g, .Pick_Candidate, 0)
	do_cmd(g, .Hire, 0)
	testing.expect_value(t, g.n_crew, 2 + START_CREW)
	testing.expect(t, g.crew[g.n_crew - 1] == c)
	testing.expect_value(t, g.n_candidates, CANDIDATES_MAX - 1)
	testing.expect_value(t, g.sub, Sub.Tavern)
	do_cmd(g, .Pick_Candidate, 0)
	do_cmd(g, .Hire, 0)
	do_cmd(g, .Pick_Candidate, 0)
	do_cmd(g, .Hire, 0)
	testing.expect_value(t, g.n_crew, CREW_MAX)
	make_candidates(g)
	testing.expect(t, !hire(g, 0)) // no room

	// The captain cannot be dismissed, nor anyone at sea.
	testing.expect(t, !dismiss(g, 0))
	do_cmd(g, .Open, int(Sub.Crew))
	testing.expect_value(t, menu(g).n, CREW_MAX + 1)
	do_cmd(g, .Pick_Member, 2)
	do_cmd(g, .Dismiss, 0)
	testing.expect_value(t, g.n_crew, CREW_MAX - 1)
	testing.expect_value(t, g.sub, Sub.Crew)
	do_cmd(g, .Back, 0)
	do_cmd(g, .Undock, 0)
	testing.expect_value(t, g.n_candidates, 0) // they stay at the tavern
	testing.expect(t, !dismiss(g, 1))
	do_cmd(g, .Open, int(Sub.Crew))
	testing.expect_value(t, menu(g).n, CREW_MAX + 1) // six aboard, Orders, Back
	do_cmd(g, .Pick_Member, 1)
	testing.expect_value(t, menu(g).n, 1) // just Back
}

@(test)
skills_change_the_ship :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 5)
	// Base skills change nothing.
	testing.expect_value(t, speed_factor(g), 1)
	testing.expect_value(t, foul_per_turn(g), FOUL_PER_TURN)
	testing.expect_value(t, view_distance(g), VIEW_DISTANCE)
	testing.expect_value(t, careen_turns(g), CAREEN_TURNS)
	testing.expect_value(t, bargain_percent(g), 0)
	testing.expect_value(t, gaming_chance(g), 0)
	// The best aboard counts.
	g.crew[1] = {skills = BASE_SKILL, hp = STAT_MAX}
	g.n_crew = 2
	for s in Skill {g.crew[1].skills[s] = 100}
	testing.expect(t, near(speed_factor(g), 1.2))
	testing.expect_value(t, foul_per_turn(g), 3)
	testing.expect_value(t, view_distance(g), VIEW_DISTANCE + 3)
	testing.expect_value(t, careen_turns(g), 5)
	testing.expect_value(t, bargain_percent(g), 4)
	testing.expect_value(t, gaming_chance(g), 30)
	// Bargaining never lets you buy and sell at a profit in one port.
	for i in 0 ..< g.n_islands {
		for good in Good {testing.expect(t, your_take(g, i, good) <= your_cost(g, i, good))}
	}
}

@(test)
fishing_feeds_the_crew :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.crew[0].skills[.Track] = 100
	g.rations = 0
	g.satiety = 50
	turn := g.turn
	do_cmd(g, .Open, int(Sub.Crew))
	do_cmd(g, .Open, int(Sub.Orders))
	do_cmd(g, .Fish, 0)
	testing.expect_value(t, g.turn, turn + FISH_TURNS)
	testing.expect(t, g.rations > 0) // every cast lands something
	testing.expect(t, near(g.ship.x, 60.5)) // hove to
}

@(test)
a_gamer_swaps_losing_cards :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	alley(g)
	g.crew[0].skills[.Gaming] = 100
	swaps := 0
	for _ in 0 ..< 400 {
		g.money = 1000
		do_cmd(g, .Deal, 0)
		pair := is_pair(g.hand[0], g.hand[1])
		do_cmd(g, .Bet, 1)
		if g.palmed {
			swaps += 1
			testing.expect(t, !pair)
		}
	}
	testing.expect(t, swaps > 20 && swaps < 200)
}

@(test)
the_captains_log :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	crewed(g)
	testing.expect_value(t, g.n_logbook, 1)
	testing.expect_value(t, g.logbook[0].kind, Log_Kind.Began)
	buf: [64]u8
	want: [64]u8
	testing.expect_value(t, logbook_text(g, g.logbook[0], buf[:]), bprint(want[:], "0: Sailed from ", island_name(g, 0), "."))
	other := 1
	x, y, ok := mooring(g, other)
	testing.expect(t, ok)
	do_cmd(g, .Undock, 0)
	g.ship.x, g.ship.y = x, y
	g.islands[other].charted = true
	do_cmd(g, .Dock, other)
	testing.expect_value(t, g.docked, other)
	testing.expect_value(t, g.logbook[g.n_logbook - 1].kind, Log_Kind.Landfall)
	n := g.n_logbook
	do_cmd(g, .Undock, 0)
	do_cmd(g, .Dock, other)
	testing.expect_value(t, g.n_logbook, n) // only the first time
	for k in 0 ..< 100 {
		g.turn = k
		note(g, .Sold, 0, k)
	}
	testing.expect_value(t, g.n_logbook, LOGBOOK_MAX)
	testing.expect_value(t, g.logbook[0].kind, Log_Kind.Began) // the first entry stays
	testing.expect_value(t, g.logbook[LOGBOOK_MAX - 1].value, 99)
	testing.expect_value(t, logbook_pages(g), 5)
	do_cmd(g, .Undock, 0)
	do_cmd(g, .Open, int(Sub.Chart))
	do_cmd(g, .Open, int(Sub.Logbook))
	testing.expect_value(t, menu(g).items[0].cmd, Cmd.Log_Page)
}

@(test)
crew_state_round_trips :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	crewed(g)
	g.crew[2].hp = 40
	g.wage_turns = 17
	g.turn = 20
	note(g, .Sold, 0, 777)
	note(g, .Died, NO_ISLAND, int(g.crew[3].name_seed))
	good: [SAVE_SIZE]u8
	save_encode(g, &good)
	h := new(Game)
	defer free(h)
	title(h, 3)
	testing.expect_value(t, save_decode(h, good[:]), Load_Error.None)
	testing.expect_value(t, h.n_crew, g.n_crew)
	testing.expect(t, h.crew == g.crew)
	testing.expect_value(t, h.n_candidates, g.n_candidates)
	testing.expect(t, h.candidates == g.candidates)
	testing.expect_value(t, h.wage_turns, 17)
	testing.expect_value(t, h.n_logbook, g.n_logbook)
	testing.expect(t, h.logbook == g.logbook)

	at := SAVE_V6_SIZE
	title(h, 3)
	bad := good
	bad[at] = 0 // no captain
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	bad[at + 1 + 5] = 101 // a skill past 100
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	bad[at + 1 + MEMBER_BYTES + 13] = 0 // a dead crew member aboard
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = good
	bad[at + 1 + CREW_MAX * MEMBER_BYTES + 1 + CANDIDATES_MAX * MEMBER_BYTES + 2 + 1 + 2] = 200 // a kind of entry that does not exist
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	testing.expect(t, !h.has_voyage)

	// A Phase 5 save gets a plain captain and no crew, so it plays on as before.
	v6 := good
	v6[3] = 6
	testing.expect_value(t, save_decode(h, v6[:SAVE_V6_SIZE]), Load_Error.None)
	v7 := good
	v7[3] = 7
	testing.expect_value(t, save_decode(h, v7[:SAVE_V7_SIZE]), Load_Error.None)
	testing.expect_value(t, h.course, NO_ISLAND)
	title(h, 3)
	v6[3] = 6
	testing.expect_value(t, h.n_crew, 1)
	testing.expect(t, h.crew[0].skills == BASE_SKILL)
	testing.expect_value(t, h.n_logbook, 0)
}

// Piloting: Head for steers round land and stops alongside.

// An open sea with a wall of land between the ship and island 1, the destination.
walled :: proc(g: ^Game) {
	open_sea(g)
	g.islands[0] = {x = 60, y = 50, charted = true} // the wall: x 50 ..< 70 at y 50, 51
	for x in 50 ..< 70 {
		g.land[50 * WORLD_SIZE + x] = 1
		g.land[51 * WORLD_SIZE + x] = 1
	}
	g.islands[1] = {x = 60, y = 30, charted = true}
	for y in 30 ..< 32 {for x in 60 ..< 62 {g.land[y * WORLD_SIZE + x] = 2}}
	g.n_islands = 2
}

@(test)
head_for_pilots_round_land :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	walled(g)
	do_cmd(g, .Open, int(Sub.Head_For))
	do_cmd(g, .Head_For, 1)
	testing.expect_value(t, g.course, 1)
	for _ in 0 ..< 20 {
		if g.course == NO_ISLAND {break}
		do_cmd(g, .Sail, 25)
		testing.expect(t, !is_land(g, int(g.ship.x), int(g.ship.y)))
	}
	testing.expect_value(t, g.course, NO_ISLAND)
	testing.expect(t, arrived_at(g, 1))
	testing.expect(t, g.turn < 120) // round the end of the wall, not stuck against it
	do_cmd(g, .Dock, 1)
	testing.expect_value(t, g.docked, 1)
}

arrived_at :: proc(g: ^Game, i: int) -> bool {
	near: [ISLAND_MAX]int
	n := dockable(g, near[:])
	for j in 0 ..< n {if near[j] == i {return true}}
	return false
}

@(test)
a_course_keeps_going_past_sightings_and_drops_on_the_helm :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	walled(g)
	g.islands[2] = {x = 75, y = 45} // uncharted, sighted on the way
	g.land[45 * WORLD_SIZE + 75] = 3
	g.n_islands = 3
	do_cmd(g, .Head_For, 1)
	do_cmd(g, .Sail, 25)
	testing.expect(t, g.islands[2].charted)
	testing.expect(t, g.course == 1 || arrived_at(g, 1)) // the sighting did not stop it
	testing.expect(t, g.turn > 5)

	do_cmd(g, .Head_For, 1)
	if g.course == 1 {
		do_cmd(g, .Adjust, 5)
		testing.expect_value(t, g.course, NO_ISLAND)
	}
	do_cmd(g, .Set_Speed, 0)
	do_cmd(g, .Head_For, 1)
	if g.course == 1 {testing.expect_value(t, g.ship.speed, 100)} // a course needs way on
}

@(test)
no_way_means_no_course :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	walled(g)
	// Close the ship in a ring of land.
	for y in 57 ..< 64 {for x in 57 ..< 64 {
		if x == 57 || x == 63 || y == 57 || y == 63 {g.land[y * WORLD_SIZE + x] = 1}
	}}
	do_cmd(g, .Head_For, 1)
	testing.expect_value(t, g.course, NO_ISLAND)
}

@(test)
the_course_round_trips :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 5)
	voyage(g)
	do_cmd(g, .Undock, 0)
	other := 1
	g.islands[other].charted = true
	do_cmd(g, .Head_For, other)
	testing.expect_value(t, g.course, other)
	buf: [SAVE_SIZE]u8
	save_encode(g, &buf)
	h := new(Game)
	defer free(h)
	title(h, 3)
	testing.expect_value(t, save_decode(h, buf[:]), Load_Error.None)
	testing.expect_value(t, h.course, other)
	buf[SAVE_V7_SIZE] = u8(h.n_islands)
	title(h, 3)
	testing.expect_value(t, save_decode(h, buf[:]), Load_Error.Range)
}

// A second voyage in one sitting starts its clock at 0 before anything is stamped with it (the user saw negative ages
// in the price book, November 27, 2026).
@(test)
a_second_voyage_starts_at_turn_zero :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 5)
	voyage(g)
	g.turn = 300
	do_cmd(g, .To_Title, 0)
	do_cmd(g, .New_Voyage, 0)
	do_cmd(g, .Begin, QUICK)
	testing.expect_value(t, g.turn, 0)
	testing.expect_value(t, g.seen[0].turn, 0)
	for k in 0 ..< g.n_offers {
		testing.expect_value(t, g.offers[k].due, DEADLINE_FACTOR * leagues_between(g, 0, g.offers[k].to))
	}
	buf: [SAVE_SIZE]u8
	save_encode(g, &buf)
	h := new(Game)
	defer free(h)
	title(h, 3)
	testing.expect_value(t, save_decode(h, buf[:]), Load_Error.None)
}

// Phase 7: the shipyard.

// Docked at a home port with a shipyard and a delivery service, money to spend.
shipyard :: proc(g: ^Game) {
	title(g, 71)
	voyage(g)
	g.districts[0] = {.Shipyard, .Delivery_Service}
	g.money = 10_000
}

@(test)
the_ship_menu_and_the_shipyard :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	shipyard(g)
	m := menu(g)
	found := -1
	for k in 0 ..< m.n {if m.items[k].cmd == .Open && m.items[k].arg == int(Sub.Ship) {found = k}}
	testing.expect(t, found >= 0)
	choose(g, found)
	m = menu(g)
	testing.expect_value(t, m.items[0].cmd, Cmd.Careen)
	testing.expect_value(t, m.n, 5) // two careens, Ships, Fittings, Back (no repair: the hull is sound)
	g.districts[0] = {}
	testing.expect_value(t, menu(g).n, 3) // careening only, without a shipyard
}

@(test)
buying_a_ship_and_fittings :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	shipyard(g)
	testing.expect_value(t, g.ship_type, Ship_Type.Sloop)
	testing.expect_value(t, hold_tons(g), 50)
	testing.expect_value(t, g.hull, 100)
	do_cmd(g, .Open, int(Sub.Ship))
	do_cmd(g, .Open, int(Sub.Fittings))
	do_cmd(g, .Fit, int(Fitting.Extra_Hold))
	do_cmd(g, .Fit, int(Fitting.Extra_Hold))
	do_cmd(g, .Fit, int(Fitting.Extra_Hold)) // at most two
	testing.expect_value(t, g.fitted[.Extra_Hold], 2)
	testing.expect_value(t, hold_tons(g), 100)
	testing.expect_value(t, g.money, 10_000 - 800)
	do_cmd(g, .Fit, int(Fitting.Timbers))
	testing.expect_value(t, g.hull, 150)
	do_cmd(g, .Fit, int(Fitting.Copper))
	testing.expect_value(t, foul_per_turn(g), (FOUL_PER_TURN + 1) / 2)

	// A new ship: part exchange at half price, fittings carried across, a sound hull.
	do_cmd(g, .Back, 0)
	do_cmd(g, .Open, int(Sub.Ships))
	money := g.money
	do_cmd(g, .Buy_Ship, int(Ship_Type.Brig))
	testing.expect_value(t, g.ship_type, Ship_Type.Brig)
	testing.expect_value(t, g.money, money - (3000 - 300))
	testing.expect_value(t, hold_tons(g), 150)
	testing.expect_value(t, g.hull, 250)
	testing.expect(t, near(ship_speed(g), 0.9))
	testing.expect_value(t, g.logbook[g.n_logbook - 1].kind, Log_Kind.New_Ship)

	// Not into a ship too small for the cargo.
	g.cargo[.Flour] = 120
	testing.expect_value(t, buy_ship(g, .Sloop), Refusal.Hold)
	g.cargo[.Flour] = 0
	g.money = 0
	testing.expect_value(t, buy_ship(g, .Junk), Refusal.None) // the brig is taken for 1500: an even swap
	testing.expect_value(t, buy_ship(g, .Brig), Refusal.Money) // and back costs 2250
}

@(test)
repairs_and_sinking :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	shipyard(g)
	damage_hull(g, 30)
	testing.expect_value(t, g.hull, 70)
	testing.expect_value(t, repair_cost(g), 60)
	do_cmd(g, .Open, int(Sub.Ship))
	testing.expect_value(t, menu(g).items[2].cmd, Cmd.Repair)
	g.money = 21 // mends what it can pay for
	do_cmd(g, .Repair, 0)
	testing.expect_value(t, g.hull, 80)
	testing.expect_value(t, g.money, 1)
	g.money = 1000
	do_cmd(g, .Repair, 0)
	testing.expect_value(t, g.hull, 100)
	g.districts[0] = {}
	damage_hull(g, 10)
	testing.expect_value(t, repair(g), 0) // only at a shipyard
	damage_hull(g, 1000)
	testing.expect_value(t, g.screen, Screen.Over)
	testing.expect_value(t, g.outcome, Outcome.Sank)
}

@(test)
passengers_like_deliveries :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	shipyard(g)
	make_fare_offers(g)
	testing.expect_value(t, g.n_fare_offers, 0) // no cabins, no passengers
	do_cmd(g, .Open, int(Sub.Ship))
	do_cmd(g, .Open, int(Sub.Fittings))
	do_cmd(g, .Fit, int(Fitting.Cabin))
	testing.expect_value(t, g.n_fare_offers, 1) // one free cabin
	do_cmd(g, .Fit, int(Fitting.Cabin))
	testing.expect_value(t, g.n_fare_offers, FARE_OFFERS_MAX)
	do_cmd(g, .Back, 0)
	do_cmd(g, .Back, 0)
	do_cmd(g, .Open, int(Sub.Deliveries))
	m := menu(g)
	testing.expect(t, m.n <= MENU_MAX)
	testing.expect_value(t, m.items[g.n_offers].cmd, Cmd.Pick_Fare)
	p := g.fare_offers[0]
	do_cmd(g, .Pick_Fare, 0)
	do_cmd(g, .Take_Fare, 0)
	testing.expect_value(t, g.n_passengers, 1)
	testing.expect(t, is_destination(g, p.to))
	testing.expect(t, g.islands[p.to].charted)

	// They eat.
	do_cmd(g, .Undock, 0)
	testing.expect_value(t, g.n_fare_offers, 0)
	do_cmd(g, .Set_Speed, 0)
	rations := g.rations
	do_cmd(g, .Sail, 1)
	testing.expect_value(t, g.rations, rations - 2)

	// They pay on arrival: full fare by the due turn, half after.
	g.passengers[0].due = g.turn - 1
	x, y, ok := mooring(g, p.to)
	testing.expect(t, ok)
	g.ship.x, g.ship.y = x, y
	money := g.money
	do_cmd(g, .Dock, p.to)
	testing.expect_value(t, g.docked, p.to)
	testing.expect_value(t, g.n_passengers, 0)
	testing.expect_value(t, g.money, money + p.fare / 2)
	testing.expect_value(t, g.logbook[g.n_logbook - 1].kind, Log_Kind.Passage)
}

@(test)
every_ship_menu_fits :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	shipyard(g)
	g.fitted = {.Extra_Hold = 2, .Copper = 1, .Cabin = 3, .Timbers = 1}
	g.ship_type = .Brig
	g.hull = 1
	make_fare_offers(g)
	g.passengers[0] = {name_seed = 77, from = 0, to = 1, fare = 9999, due = 5}
	g.n_passengers = 1
	for s in Sub {
		g.sub = s
		g.pick = 0
		m := menu(g)
		testing.expect(t, m.n >= 1 && m.n <= MENU_MAX)
		for k in 0 ..< m.n {testing.expect(t, len(m.items[k].label) < MENU_TEXT)}
	}
}

@(test)
ship_state_round_trips :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	shipyard(g)
	g.ship_type = .Junk
	g.fitted = #partial [Fitting]int{.Extra_Hold = 1, .Cabin = 2}
	g.hull = 77
	make_fare_offers(g)
	g.passengers[0] = {name_seed = 77, from = 0, to = 1, fare = 50, due = 30}
	g.n_passengers = 1
	g.cargo[.Flour] = 80 // more than a sloop holds: fine on a junk with an extra hold
	buf: [SAVE_SIZE]u8
	save_encode(g, &buf)
	h := new(Game)
	defer free(h)
	title(h, 3)
	testing.expect_value(t, save_decode(h, buf[:]), Load_Error.None)
	testing.expect_value(t, h.ship_type, Ship_Type.Junk)
	testing.expect(t, h.fitted == g.fitted)
	testing.expect_value(t, h.hull, 77)
	testing.expect_value(t, h.n_fare_offers, g.n_fare_offers)
	testing.expect(t, h.fare_offers == g.fare_offers)
	testing.expect_value(t, h.n_passengers, 1)
	testing.expect(t, h.passengers[0] == g.passengers[0])

	at := SAVE_V8_SIZE
	bad := buf
	bad[at] = 9 // no such ship
	title(h, 3)
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = buf
	bad[at + 1] = 3 // three extra holds
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = buf
	put_u16(bad[at + 1 + len(Fitting):], 500) // past the hull's most
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = buf
	bad[at + 1 + int(Fitting.Cabin)] = 0 // a passenger with no cabin
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	testing.expect(t, !h.has_voyage)

	// A version 8 save gets a sloop with a sound hull.
	g.cargo[.Flour] = 0
	save_encode(g, &buf)
	v8 := buf
	v8[3] = 8
	testing.expect_value(t, save_decode(h, v8[:SAVE_V8_SIZE]), Load_Error.None)
	testing.expect_value(t, h.ship_type, Ship_Type.Sloop)
	testing.expect_value(t, h.hull, SHIPS[.Sloop].hull)
	testing.expect_value(t, h.n_passengers, 0)
}

// Phase 8: things at sea and combat.

// At sea with a crew of the given skill, an encounter of kind already close.
met :: proc(g: ^Game, kind: Foe_Kind, skill: int) {
	open_sea(g)
	for k in 1 ..< 4 {
		g.crew[k] = {name_seed = u32(k * 7 + 1), skills = BASE_SKILL, hp = STAT_MAX}
	}
	g.n_crew = 4
	for k in 0 ..< 4 {
		for s in Skill {g.crew[k].skills[s] = skill}
	}
	begin_encounter(g, kind)
	g.foe.state = .Close
}

@(test)
encounters_spring_while_sailing :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.ship.heading = 90
	sprung := false
	for _ in 0 ..< 200 {
		g.ship = {x = 60.5, y = 60.5, heading = 90, speed = 100}
		turn := g.turn
		do_cmd(g, .Sail, 25)
		if g.sub == .Encounter {
			sprung = true
			testing.expect(t, g.turn - turn <= 25)
			testing.expect(t, g.foe.kind != .None)
			testing.expect(t, g.foe.hp == g.foe.hp_max)
			break
		}
		g.rations = 1000
	}
	testing.expect(t, sprung)
	testing.expect(t, !maybe_encounter(g)) // one at a time
	input(g, .Back) // can't be backed out of
	testing.expect_value(t, g.sub, Sub.Encounter)
	m := menu(g)
	testing.expect(t, m.n >= 2 && m.n <= MENU_MAX)
}

@(test)
seen_coming_you_can_steer_away :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met(g, .Monster, 25)
	g.foe.state = .Distant
	testing.expect_value(t, menu(g).items[0].cmd, Cmd.Flee)
	do_cmd(g, .Flee, 0)
	testing.expect_value(t, g.foe.kind, Foe_Kind.None)
	testing.expect_value(t, g.sub, Sub.None)
	testing.expect_value(t, g.hull, hull_max(g))
}

@(test)
beating_pirates_pays :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met(g, .Pirates, 100)
	money := g.money
	for _ in 0 ..< 50 {
		if g.foe.kind == .None {break}
		do_cmd(g, .Fight, 0)
	}
	testing.expect_value(t, g.foe.kind, Foe_Kind.None)
	testing.expect(t, g.money > money)
	testing.expect_value(t, g.logbook[g.n_logbook - 1].kind, Log_Kind.Victory)
}

@(test)
beaten_by_pirates_you_are_robbed :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met(g, .Pirates, 0) // a crew that cannot land a blow
	g.money = 400
	g.cargo[.Flour] = 10
	for _ in 0 ..< 200 {
		if g.foe.kind == .None || g.screen == .Over {break}
		do_cmd(g, .Fight, 0)
	}
	if g.screen != .Over {
		testing.expect_value(t, g.foe.kind, Foe_Kind.None)
		testing.expect_value(t, g.money, 200)
		testing.expect_value(t, g.cargo[.Flour], 5)
		testing.expect_value(t, g.logbook[g.n_logbook - 1].kind, Log_Kind.Robbed)
	}
}

@(test)
pirates_take_a_bribe_or_a_parley :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met(g, .Pirates, 25)
	g.money = 500
	do_cmd(g, .Bribe, 0)
	testing.expect_value(t, g.money, 450)
	testing.expect_value(t, g.foe.kind, Foe_Kind.None)
	met(g, .Pirates, 100) // a silver tongue always talks its way past
	do_cmd(g, .Parley, 0)
	testing.expect_value(t, g.foe.kind, Foe_Kind.None)
}

@(test)
a_monster_strikes_the_hull :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met(g, .Monster, 0)
	for _ in 0 ..< 500 {
		if g.screen == .Over {break}
		do_cmd(g, .Fight, 0)
	}
	testing.expect_value(t, g.screen, Screen.Over)
	testing.expect_value(t, g.outcome, Outcome.Sank)
}

@(test)
the_captain_can_fall :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met(g, .Pirates, 0)
	g.n_crew = 1 // alone: every wound is the captain's
	g.foe.strength = 0 // never counted as beaten
	for _ in 0 ..< 500 {
		if g.screen == .Over {break}
		do_cmd(g, .Fight, 0)
	}
	testing.expect_value(t, g.outcome, Outcome.Killed)
}

@(test)
hunting_a_whale :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met(g, .Whale, 100)
	for _ in 0 ..< 50 {
		if g.foe.kind == .None {break}
		do_cmd(g, .Fight, 0)
	}
	testing.expect(t, g.cargo[.Whale_Oil] >= 4)
	testing.expect(t, hold_used(g) <= hold_tons(g))
	// A full hold takes none.
	met(g, .Whale, 100)
	g.cargo[.Flour] = hold_tons(g)
	oil := g.cargo[.Whale_Oil]
	for _ in 0 ..< 50 {
		if g.foe.kind == .None {break}
		do_cmd(g, .Fight, 0)
	}
	testing.expect_value(t, g.cargo[.Whale_Oil], oil)
	// Or let it go.
	met(g, .Whale, 0)
	do_cmd(g, .Sail_On, 0)
	testing.expect_value(t, g.foe.kind, Foe_Kind.None)
}

@(test)
trading_with_merfolk :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met(g, .Merfolk, 100)
	g.money = 1000
	g.cargo[.Rope] = 10
	do_cmd(g, .Parley, 0) // Bargain 100: they warm to you
	testing.expect(t, g.foe.friendly)
	do_cmd(g, .Mer_Trade, 1)
	testing.expect_value(t, g.foe.state, Foe_State.Trading)
	do_cmd(g, .Mer_Buy, int(Good.Pearls))
	testing.expect_value(t, g.cargo[.Pearls], 1)
	testing.expect_value(t, g.money, 1000 - base_value(.Pearls) / 2)
	money := g.money
	do_cmd(g, .Mer_Sell, 0)
	testing.expect_value(t, g.cargo[.Rope], 0)
	testing.expect_value(t, g.cargo[.Pearls], 1) // they don't buy back their own
	testing.expect_value(t, g.money, money + 10 * (base_value(.Rope) * 130 / 100))
	do_cmd(g, .Mer_Trade, 0)
	do_cmd(g, .Sail_On, 0)
	testing.expect_value(t, g.foe.kind, Foe_Kind.None)
}

@(test)
sea_goods_sell_in_any_port :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 5)
	voyage(g)
	testing.expect(t, .Pearls not_in g.trades[0])
	g.cargo[.Pearls] = 3
	g.cargo[.Coral] = 1
	do_cmd(g, .Open, int(Sub.Market))
	m := menu(g)
	found := false
	for k in 0 ..< m.n {if m.items[k].cmd == .Open && m.items[k].arg == int(Sub.Sea_Goods) {found = true}}
	testing.expect(t, found)
	testing.expect(t, m.n <= MENU_MAX)
	do_cmd(g, .Open, int(Sub.Sea_Goods))
	do_cmd(g, .Pick_Good, int(Good.Pearls))
	testing.expect_value(t, g.sub, Sub.Trade)
	do_cmd(g, .Buy, 1) // they can't be bought here
	testing.expect_value(t, g.cargo[.Pearls], 3)
	money := g.money
	do_cmd(g, .Sell, ALL)
	testing.expect_value(t, g.cargo[.Pearls], 0)
	testing.expect(t, g.money > money)
	testing.expect_value(t, g.sub, Sub.Sea_Goods) // sold out: back to the list
	testing.expect_value(t, menu(g).n, 2) // coral, Back
	do_cmd(g, .Pick_Good, int(Good.Coral))
	do_cmd(g, .Sell, 1)
	testing.expect_value(t, g.sub, Sub.Market) // none left at all: back to the market
	for k in 0 ..< menu(g).n {testing.expect(t, menu(g).items[k].arg != int(Sub.Sea_Goods) || menu(g).items[k].cmd != .Open)}
	do_cmd(g, .Open, int(Sub.Sea_Goods)) // an empty list is never shown
	testing.expect_value(t, g.sub, Sub.Market)
	// No world changes: islands never trade sea goods.
	for i in 0 ..< g.n_islands {
		for good in Good.Whale_Oil ..= Good.Coral {testing.expect(t, good not_in g.trades[i])}
	}
}

@(test)
every_encounter_menu_fits :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for kind in Foe_Kind.Pirates ..= Foe_Kind.Merfolk {
		for state in Foe_State {
			for flags in 0 ..< 8 {
				met(g, kind, 50)
				g.cargo[.Rope] = 3
				g.foe.state = state
				g.foe.parleyed, g.foe.friendly, g.foe.hostile = flags & 1 != 0, flags & 2 != 0, flags & 4 != 0
				m := menu(g)
				testing.expect(t, m.n >= 2 && m.n <= MENU_MAX)
				for k in 0 ..< m.n {testing.expect(t, len(m.items[k].label) < MENU_TEXT)}
			}
		}
	}
}

@(test)
encounter_state_round_trips :: proc(t: ^testing.T) {
	testing.expect_value(t, SAVE_V6_SIZE, 2159) // the older layout keeps the twelve land goods
	g := new(Game)
	defer free(g)
	title(g, 5)
	voyage(g)
	do_cmd(g, .Undock, 0)
	begin_encounter(g, .Merfolk)
	g.foe.state = .Close
	g.foe.hp = 7
	g.foe.parleyed, g.foe.friendly = true, true
	g.cargo[.Whale_Oil], g.cargo[.Coral] = 4, 2
	g.cargo[.Pepper] = 3
	buf: [SAVE_SIZE]u8
	save_encode(g, &buf)
	h := new(Game)
	defer free(h)
	title(h, 3)
	testing.expect_value(t, save_decode(h, buf[:]), Load_Error.None)
	testing.expect(t, h.foe == g.foe)
	testing.expect(t, h.cargo == g.cargo)
	do_cmd(h, .Continue, 0)
	testing.expect_value(t, h.sub, Sub.Encounter) // it waits for you

	bad := buf
	bad[SAVE_V9_SIZE + 2] = 0 // a foe with no health
	title(h, 3)
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = buf
	bad[SAVE_V9_SIZE] = 9 // no such foe
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)

	// A version 9 save has met nothing and carries no sea goods.
	v9 := buf
	v9[3] = 9
	testing.expect_value(t, save_decode(h, v9[:SAVE_V9_SIZE]), Load_Error.None)
	testing.expect_value(t, h.foe.kind, Foe_Kind.None)
	testing.expect_value(t, h.cargo[.Whale_Oil], 0)
	testing.expect_value(t, h.cargo[.Pepper], 3)
}

// Phase 9: wind, calendar, storms and rats.

@(test)
the_calendar :: proc(t: ^testing.T) {
	testing.expect_value(t, MONTH_NAMES[month(0)], "Mar")
	testing.expect_value(t, day_of_month(0), 1)
	testing.expect_value(t, year(0), 1)
	testing.expect_value(t, season(0), Season.Spring)
	testing.expect_value(t, season(90), Season.Summer)
	testing.expect_value(t, MONTH_NAMES[month(90)], "Jun")
	testing.expect_value(t, season(180), Season.Autumn)
	testing.expect_value(t, MONTH_NAMES[month(300)], "Jan")
	testing.expect_value(t, year(300), 2)
	testing.expect_value(t, season(300), Season.Winter)
	testing.expect_value(t, day_of_month(329), 30)
	testing.expect_value(t, season(TURN_LIMIT - 1), season((TURN_LIMIT - 1) % 360)) // a year is 360 turns
}

@(test)
the_wind_speeds_and_slows :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	testing.expect_value(t, wind_factor(g), 1) // tests sail without weather
	g.weather_off = false
	g.wind_dir, g.wind_force = 270, .Strong // from the west
	g.ship.heading = 90
	testing.expect(t, near(wind_factor(g), 1.30)) // running before it
	g.ship.heading = 270
	testing.expect(t, near(wind_factor(g), 0.60)) // into it
	g.ship.heading = 0
	testing.expect(t, near(wind_factor(g), 0.95)) // across it
	g.wind_force = .Calm
	testing.expect(t, near(wind_factor(g), 0.70))
	for f in Wind_Force {
		g.wind_force = f
		for h in 0 ..< 360 {
			g.ship.heading = h
			w := wind_factor(g)
			testing.expect(t, w >= 0.6 - 0.001 && w <= 1.3 + 0.001)
		}
	}
	// It moves the ship.
	g.wind_force = .Strong
	g.ship = {x = 60.5, y = 60.5, heading = 90, speed = 100}
	do_cmd(g, .Sail, 1)
	testing.expect(t, abs(g.ship.x - 61.8) < 0.01)
}

@(test)
the_wind_shifts_with_the_seasons :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.weather_off = false
	changes, strong := 0, 0
	dir := g.wind_dir
	for turn in 0 ..< 2000 {
		g.turn = turn
		weather_turn(g)
		g.n_storms = 0
		testing.expect(t, g.wind_dir >= 0 && g.wind_dir < 360)
		if g.wind_dir != dir {changes += 1}
		dir = g.wind_dir
		if g.wind_force == .Strong {strong += 1}
	}
	testing.expect(t, changes > 50 && changes < 400)
	testing.expect(t, strong > 0 && strong < 2000)
}

@(test)
storms_drift_downwind_and_blow_out :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.weather_off = false
	g.wind_dir, g.wind_force = 0, .Fresh // from the north: storms drift south
	g.storms[0] = {x = 30, y = 30, radius = 2, turns = 2}
	g.n_storms = 1
	g.weather = rng_make(1)
	weather_turn(g)
	testing.expect(t, g.n_storms >= 1)
	testing.expect(t, near(g.storms[0].x, 30))
	testing.expect(t, abs(g.storms[0].y - 30.35) < 0.01)
	weather_turn(g)
	for k in 0 ..< g.n_storms {testing.expect(t, g.storms[k].turns > 1)} // the old one blew out
	// Storms form often enough to matter in the stormy months and keep their distance when they do.
	formed := 0
	g.n_storms = 0
	for turn in 0 ..< 2500 {
		g.turn = turn
		before := g.n_storms
		weather_turn(g)
		if g.n_storms > before {
			formed += 1
			st := g.storms[g.n_storms - 1]
			dx, dy := st.x - g.ship.x, st.y - g.ship.y
			testing.expect(t, dx * dx + dy * dy >= (STORM_NEAR - 0.5) * (STORM_NEAR - 0.5))
			testing.expect(t, st.radius >= 1.5 && st.radius <= 4)
		}
	}
	testing.expect(t, formed > 5 && formed < 60)
}

@(test)
a_storm_batters_the_hull :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.storms[0] = {x = 60.5, y = 60.5, radius = 3, turns = 100, seen = true}
	g.n_storms = 1
	do_cmd(g, .Set_Speed, 0)
	do_cmd(g, .Sail, 1)
	testing.expect(t, g.hull < hull_max(g))
	testing.expect(t, g.hull >= hull_max(g) - STORM_DAMAGE_HI - 2)
	testing.expect(t, in_storm(g) || g.ship.y != 60.5) // driven before the wind
	// Docked ships are safe.
	h := new(Game)
	defer free(h)
	title(h, 5)
	voyage(h)
	h.storms[0] = {x = h.ship.x, y = h.ship.y, radius = 3, turns = 100}
	h.n_storms = 1
	tick(h, false)
	testing.expect_value(t, h.hull, hull_max(h))
	// A long storm sinks a ship.
	g.hull = 3
	g.storms[0] = {x = g.ship.x, y = g.ship.y, radius = 4, turns = 100, seen = true}
	do_cmd(g, .Sail, 10)
	testing.expect_value(t, g.outcome, Outcome.Sank)
}

@(test)
sailing_stops_for_storms :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.ship.heading = 90
	g.storms[0] = {x = 80.5, y = 60.5, radius = 2, turns = 150}
	g.n_storms = 1
	do_cmd(g, .Sail, 25)
	testing.expect(t, g.storms[0].seen)
	testing.expect(t, g.turn < 25)
	testing.expect(t, !in_storm(g))
	for _ in 0 ..< 5 {
		if g.sub == .Encounter {end_encounter(g)} // anything met on the way
		do_cmd(g, .Sail, 25)
		if in_storm(g) {break}
	}
	testing.expect(t, in_storm(g))
	if g.sub == .Encounter {end_encounter(g)}
	turn := g.turn
	do_cmd(g, .Sail, 3) // once inside, it sails on through
	testing.expect_value(t, g.turn, turn + 3)
}

@(test)
a_course_keeps_clear_of_storms :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	g.islands[0] = {x = 60, y = 30, charted = true}
	for y in 30 ..< 32 {for x in 60 ..< 62 {g.land[y * WORLD_SIZE + x] = 1}}
	g.n_islands = 1
	g.ship = {x = 60.5, y = 52.5, heading = 0, speed = 100}
	g.storms[0] = {x = 60.5, y = 45, radius = 3, turns = 150, seen = true}
	g.n_storms = 1
	do_cmd(g, .Head_For, 0)
	testing.expect_value(t, g.course, 0)
	testing.expect(t, g.ship.heading != 0) // round it, not straight through
	for _ in 0 ..< 60 {
		if g.course == NO_ISLAND {break}
		do_cmd(g, .Sail, 1)
		testing.expect(t, !in_storm(g))
	}
	testing.expect(t, arrived(g) || g.course == NO_ISLAND)
	near_isles: [ISLAND_MAX]int
	testing.expect(t, dockable(g, near_isles[:]) == 1)
	// Boxed in, it goes through.
	g.storms[0] = {x = 60.5, y = 40, radius = 4, turns = 150, seen = true}
	g.ship = {x = 60.5, y = 40, heading = 0, speed = 100}
	_, _, ok := steer(g, 0)
	testing.expect(t, ok)
}

@(test)
seasons_move_prices :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	trading_post(g) // flour at par asks 6
	g.weather_off = false
	testing.expect_value(t, sell_price(g, 0, .Flour), 7) // spring: grain 110%
	g.turn = 200 // September
	testing.expect_value(t, sell_price(g, 0, .Flour), 5) // after the harvest
	g.turn = 300 // January
	testing.expect_value(t, sell_price(g, 0, .Flour), 8)
	testing.expect_value(t, sell_price(g, 0, .Pepper), 40) // spice keeps its price in winter
	g.weather_off = true
	testing.expect_value(t, sell_price(g, 0, .Flour), 6)
}

@(test)
rats_come_aboard_breed_and_feed :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 5)
	voyage(g)
	g.weather_off = false
	boarded := false
	for _ in 0 ..< 40 {
		do_cmd(g, .Undock, 0)
		do_cmd(g, .Dock, NO_ISLAND)
		if g.rats > 0 {
			boarded = true
			break
		}
	}
	testing.expect(t, boarded)
	testing.expect(t, g.rats >= 2 && g.rats <= 6)

	h := new(Game)
	defer free(h)
	open_sea(h)
	h.weather_off = false
	h.rats = 200
	h.rations = 1000
	h.cargo[.Flour] = 40
	h.cargo[.Pepper] = 5
	do_cmd(h, .Set_Speed, 0)
	h.n_storms = 0
	do_cmd(h, .Sail, 25)
	testing.expect(t, h.rations < 1000 - 25 - 10 * 20) // 200 rats eat ten a turn
	testing.expect(t, h.cargo[.Flour] < 40)
	testing.expect_value(t, h.cargo[.Pepper], 5) // they don't eat pepper
	testing.expect_value(t, h.spoiled, 0) // reported
	testing.expect(t, h.rats <= RATS_MAX)
}

@(test)
hunting_rats :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	do_cmd(g, .Open, int(Sub.Crew))
	do_cmd(g, .Open, int(Sub.Orders))
	m := menu(g)
	testing.expect_value(t, m.n, 2) // Fish, Back: no rats
	g.rats = 10
	g.crew[0].skills[.Track] = 100
	turn := g.turn
	testing.expect_value(t, menu(g).items[1].cmd, Cmd.Hunt_Rats)
	do_cmd(g, .Hunt_Rats, 0)
	testing.expect_value(t, g.turn, turn + HUNT_TURNS)
	testing.expect_value(t, g.rats, 0)
	testing.expect_value(t, g.sub, Sub.Crew)
	// Docked, Orders shows only with rats aboard.
	h := new(Game)
	defer free(h)
	title(h, 5)
	voyage(h)
	do_cmd(h, .Open, int(Sub.Crew))
	for k in 0 ..< menu(h).n {testing.expect(t, menu(h).items[k].arg != int(Sub.Orders) || menu(h).items[k].cmd != .Open)}
	h.rats = 5
	found := false
	for k in 0 ..< menu(h).n {if menu(h).items[k].cmd == .Open && menu(h).items[k].arg == int(Sub.Orders) {found = true}}
	testing.expect(t, found)
}

@(test)
weather_state_round_trips :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	title(g, 5)
	voyage(g)
	do_cmd(g, .Undock, 0)
	g.weather_off = false
	for _ in 0 ..< 40 {weather_turn(g)}
	g.wind_dir, g.wind_force = 135, .Strong
	g.storms[0] = {x = 33.25, y = 70.5, radius = 2.7, turns = 88, seen = true}
	g.storms[1] = {x = 10, y = 11, radius = 4, turns = 150}
	g.n_storms = 2
	g.rats = 17
	buf: [SAVE_SIZE]u8
	save_encode(g, &buf)
	h := new(Game)
	defer free(h)
	title(h, 3)
	testing.expect_value(t, save_decode(h, buf[:]), Load_Error.None)
	testing.expect_value(t, h.weather.state, g.weather.state)
	testing.expect_value(t, h.wind_dir, 135)
	testing.expect_value(t, h.wind_force, Wind_Force.Strong)
	testing.expect_value(t, h.n_storms, 2)
	testing.expect(t, h.storms[0] == g.storms[0])
	testing.expect(t, h.storms[1] == g.storms[1])
	testing.expect_value(t, h.rats, 17)

	bad := buf
	bad[SAVE_V10_SIZE + 10] = 4 // no such force
	title(h, 3)
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = buf
	bad[SAVE_V10_SIZE + 11] = STORMS_MAX + 1
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)
	bad = buf
	bad[SAVE_V10_SIZE + 12 + 8] = 90 // a storm too big
	testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)

	// A version 10 save gets fair weather, no storms and no rats.
	v10 := buf
	v10[3] = 10
	testing.expect_value(t, save_decode(h, v10[:SAVE_V10_SIZE]), Load_Error.None)
	testing.expect_value(t, h.n_storms, 0)
	testing.expect_value(t, h.rats, 0)
	testing.expect_value(t, h.wind_force, Wind_Force.Fresh)
}

// The user's report (November 28, 2026): two crew died and the captain's log did not seem to show it. The deaths were
// written, but the log opened on its first page, the oldest entries. Now it opens on the newest.
@(test)
crew_deaths_show_in_the_log :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	for _ in 0 ..< 20 {note(g, .Landfall, NO_ISLAND, 0)} // a long voyage's worth: two pages
	for k in 1 ..< 4 {
		g.crew[k] = hireling(&g.rng)
		g.crew[k].hp = 3
		g.n_crew += 1
	}
	begin_encounter(g, .Merfolk)
	g.foe.state = .Close
	g.foe.hp, g.foe.hp_max = 10_000, 10_000
	for _ in 0 ..< 50 {
		if g.foe.kind == .None || g.screen == .Over {break}
		do_cmd(g, .Fight, 0)
	}
	testing.expect(t, g.n_crew < 4)
	died := 0
	for k in 0 ..< g.n_logbook {if g.logbook[k].kind == .Died {died += 1}}
	testing.expect_value(t, died, 4 - g.n_crew)
	g.sub = .Chart
	do_cmd(g, .Open, int(Sub.Logbook))
	testing.expect_value(t, g.log_page, logbook_pages(g) - 1)
	last := g.log_page * LOGBOOK_PAGE
	testing.expect_value(t, g.logbook[g.n_logbook - 1].kind == .Died || g.logbook[g.n_logbook - 1].kind == .Robbed, true)
	testing.expect(t, g.n_logbook - 1 >= last) // the newest entry is on the page shown
}

// A full log drops routine entries first: a death early in a long voyage stays.
@(test)
a_full_log_keeps_the_crews_fates :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	open_sea(g)
	note(g, .Died, NO_ISLAND, 7)
	note(g, .Deserted, 0, 8)
	for k in 0 ..< 200 {note(g, k % 2 == 0 ? .Landfall : .Sold, 0, k)}
	testing.expect_value(t, g.n_logbook, LOGBOOK_MAX)
	testing.expect_value(t, g.logbook[0].kind, Log_Kind.Began)
	testing.expect_value(t, g.logbook[1].kind, Log_Kind.Died)
	testing.expect_value(t, g.logbook[2].kind, Log_Kind.Deserted)
	testing.expect_value(t, g.logbook[LOGBOOK_MAX - 1].value, 199) // the newest still goes in
	// With nothing routine left, the oldest after the first goes.
	for k in 0 ..< LOGBOOK_MAX {note(g, .Hired, 0, k)}
	testing.expect_value(t, g.logbook[0].kind, Log_Kind.Began)
	testing.expect_value(t, g.logbook[LOGBOOK_MAX - 1].value, LOGBOOK_MAX - 1)
}
