#+build !js
package game

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
islands_keep_their_gap_and_depend_on_seed :: proc(t: ^testing.T) {
	g, h, k: Game
	title(&g, 1)
	title(&h, 1)
	title(&k, 2)
	testing.expect(t, g.n_islands > 10)
	testing.expect_value(t, g.n_islands, h.n_islands)
	testing.expect(t, g.islands == h.islands)
	testing.expect(t, g.islands != k.islands)
	for i in 0 ..< g.n_islands {
		for j in i + 1 ..< g.n_islands {
			dx, dy := g.islands[i].x - g.islands[j].x, g.islands[i].y - g.islands[j].y
			testing.expect(t, dx * dx + dy * dy >= ISLAND_GAP * ISLAND_GAP)
		}
	}
	testing.expect(t, !is_land(&g, int(g.ship.x), int(g.ship.y)))
}

@(test)
seed_picks_the_first_voyage :: proc(t: ^testing.T) {
	g, h: Game
	title(&g, 99)
	title(&h, 99)
	do_cmd(&g, .New_Voyage)
	do_cmd(&h, .New_Voyage)
	testing.expect_value(t, g.seed, 99)
	testing.expect_value(t, g.screen, Screen.Sea)
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

@(test)
sailing_moves_along_heading :: proc(t: ^testing.T) {
	g: Game
	title(&g, 5)
	g.n_islands = 0 // open water
	do_cmd(&g, .New_Voyage)
	g.n_islands = 0
	x0, y0 := g.ship.x, g.ship.y
	do_cmd(&g, .Sail) // north
	testing.expect(t, abs(g.ship.x - x0) < 0.001)
	testing.expect(t, abs(g.ship.y - (y0 - 1)) < 0.001)
	testing.expect_value(t, g.turn, 1)
	do_cmd(&g, .Starboard)
	do_cmd(&g, .Starboard) // east
	do_cmd(&g, .Sail)
	testing.expect(t, abs(g.ship.x - (x0 + 1)) < 0.001)
	testing.expect_value(t, g.turn, 2)
}

@(test)
sailing_stops_at_land_and_edge :: proc(t: ^testing.T) {
	g: Game
	title(&g, 5)
	do_cmd(&g, .New_Voyage)
	g.ship = {x = 10.5, y = 10.5, heading = 0, speed = 100}
	g.islands[0] = {10, 9}
	g.n_islands = 1
	do_cmd(&g, .Sail)
	testing.expect_value(t, g.ship.y, 10.5)
	testing.expect_value(t, g.turn, 0)
	g.ship = {x = 0.5, y = 0.5, heading = 0, speed = 100}
	do_cmd(&g, .Sail)
	testing.expect_value(t, g.ship.y, 0.5)
	testing.expect_value(t, g.turn, 0)
}

@(test)
menu_wraps_and_clicks :: proc(t: ^testing.T) {
	g: Game
	title(&g, 3)
	m := menu(&g)
	testing.expect_value(t, m.n, 2) // no voyage yet: New voyage, Sound
	input(&g, .Up)
	testing.expect_value(t, g.cursor, 1)
	click(&g, PANEL_X + 5, MENU_Y) // first line
	testing.expect_value(t, g.screen, Screen.Sea)
	testing.expect_value(t, menu(&g).n, 5)
	input(&g, .Back)
	testing.expect_value(t, g.screen, Screen.Title)
	testing.expect_value(t, menu(&g).items[0].cmd, Cmd.Continue)
	choose(&g, 9) // out of range is refused
	testing.expect_value(t, g.screen, Screen.Title)
}

@(test)
log_keeps_the_newest_lines :: proc(t: ^testing.T) {
	g: Game
	for i in 0 ..< LOG_LINES + 2 {logf(&g, "line %d", i)}
	testing.expect_value(t, log_line(&g, LOG_LINES - 1), "line 5")
	testing.expect_value(t, log_line(&g, 0), "line 2")
	logf(&g, "%s", "a very long line that will certainly not fit in the forty bytes")
	testing.expect_value(t, len(log_line(&g, LOG_LINES - 1)), LOG_LEN)
}

@(test)
save_round_trips :: proc(t: ^testing.T) {
	g: Game
	title(&g, 1234)
	do_cmd(&g, .New_Voyage)
	g.n_islands = 0
	do_cmd(&g, .Starboard)
	do_cmd(&g, .Sail)
	buf: [SAVE_SIZE]u8
	save_encode(&g, &buf)

	h: Game
	title(&h, 77)
	testing.expect_value(t, save_decode(&h, buf[:]), Load_Error.None)
	testing.expect_value(t, h.seed, g.seed)
	testing.expect_value(t, h.rng.state, g.rng.state)
	testing.expect_value(t, h.turn, g.turn)
	testing.expect_value(t, h.ship, g.ship)
	testing.expect_value(t, h.next_seed, 77) // the title's next voyage is untouched
	testing.expect(t, h.has_voyage)
	fresh: Game
	title(&fresh, g.seed)
	testing.expect(t, h.islands == fresh.islands) // the world is rebuilt from the seed
}

@(test)
save_rejects_bad_data :: proc(t: ^testing.T) {
	g: Game
	title(&g, 1)
	do_cmd(&g, .New_Voyage)
	good: [SAVE_SIZE]u8
	save_encode(&g, &good)

	h: Game
	title(&h, 2)
	testing.expect_value(t, save_decode(&h, good[:10]), Load_Error.Size)
	bad := good
	bad[0] = 'X'
	testing.expect_value(t, save_decode(&h, bad[:]), Load_Error.Magic)
	bad = good
	bad[3] = SAVE_VERSION + 1
	testing.expect_value(t, save_decode(&h, bad[:]), Load_Error.Version)
	bad = good
	put_u16(bad[32:], 360)
	testing.expect_value(t, save_decode(&h, bad[:]), Load_Error.Range)
	bad = good
	bad[34] = 101
	testing.expect_value(t, save_decode(&h, bad[:]), Load_Error.Range)
	bad = good
	put_u32(bad[24:], transmute(u32)f32(WORLD_SIZE))
	testing.expect_value(t, save_decode(&h, bad[:]), Load_Error.Range)
	bad = good
	put_u32(bad[28:], 0x7FC00000) // NaN
	testing.expect_value(t, save_decode(&h, bad[:]), Load_Error.Range)
	bad = good
	put_u32(bad[20:], TURN_MAX + 1)
	testing.expect_value(t, save_decode(&h, bad[:]), Load_Error.Range)
	testing.expect_value(t, h.seed, 2) // untouched by every refusal
	testing.expect(t, !h.has_voyage)
}
