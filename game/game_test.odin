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

near :: proc(a, b: f32) -> bool {return abs(a - b) < 0.001}

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
	for s in Sub {
		g.sub = s
		m := menu(g)
		testing.expect(t, m.n >= 1 && m.n <= MENU_MAX)
		for k in 0 ..< m.n {testing.expect(t, len(m.items[k].label) < MENU_TEXT)}
	}
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
	put_u32(bad[20:], TURN_MAX + 1)
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
