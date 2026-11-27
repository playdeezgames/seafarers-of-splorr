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
	do_cmd(g, .New_Voyage, 0)
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
	do_cmd(g, .New_Voyage, 0)
	do_cmd(h, .New_Voyage, 0)
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
	do_cmd(g, .New_Voyage, 0)
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
	testing.expect_value(t, g.screen, Screen.Docked)
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
	do_cmd(g, .New_Voyage, 0)
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
	do_cmd(g, .New_Voyage, 0)
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
	do_cmd(g, .New_Voyage, 0)
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
	do_cmd(g, .New_Voyage, 0)
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
	do_cmd(g, .New_Voyage, 0)
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
	do_cmd(g, .New_Voyage, 0)
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
	do_cmd(g, .New_Voyage, 0)
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
		do_cmd(g, .New_Voyage, 0)
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
	testing.expect(t, g.markets[0].demand[.Grain] == 1000 + 10 * 3 * IMPACT)
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
	put_u16(bad[SAVE_SIZE - 2:], 1000) // a market for an island slot that does not exist
	if g.n_islands < ISLAND_MAX {testing.expect_value(t, save_decode(h, bad[:]), Load_Error.Range)}
	testing.expect(t, !h.has_voyage)

	// A Phase 2 save (version 3) loads with the starting purse and an empty hold.
	v3 := good
	v3[3] = 3
	testing.expect_value(t, save_decode(h, v3[:SAVE_V3_SIZE]), Load_Error.None)
	testing.expect_value(t, h.money, START_MONEY)
	testing.expect_value(t, hold_used(h), 0)
}
