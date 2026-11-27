package game

import "core:math"

// Save format, little-endian, fixed size. Bump SAVE_VERSION whenever the layout or the world generator changes (the
// world is rebuilt from the seed, so a new generator makes an old save describe a different sea). An older version is
// refused with Load_Error.Version and the page says so.
//
// Version 2 (Phase 1):
//  0  "SOS"  magic
//  3  u8     version
//  4  u64    world seed
// 12  u64    rng state
// 20  u32    turn
// 24  f32    ship x (tiles)
// 28  f32    ship y (tiles)
// 32  u16    heading (degrees)
// 34  u8     speed (percent)
// 35  u8     docked island, 255 at sea
// 36  u64    charted islands, bit i for island i
SAVE_VERSION :: 2
SAVE_SIZE :: 44
NOT_DOCKED :: 255

Load_Error :: enum u8 {
	None,
	Size,
	Magic,
	Version,
	Range,
}

#assert(ISLAND_MAX <= 64)

save_encode :: proc(g: ^Game, buf: ^[SAVE_SIZE]u8) {
	buf[0], buf[1], buf[2], buf[3] = 'S', 'O', 'S', SAVE_VERSION
	put_u64(buf[4:], g.seed)
	put_u64(buf[12:], g.rng.state)
	put_u32(buf[20:], u32(g.turn))
	put_u32(buf[24:], transmute(u32)g.ship.x)
	put_u32(buf[28:], transmute(u32)g.ship.y)
	put_u16(buf[32:], u16(g.ship.heading))
	buf[34] = u8(g.ship.speed)
	buf[35] = g.docked == NO_ISLAND ? NOT_DOCKED : u8(g.docked)
	charted: u64
	for i in 0 ..< g.n_islands {
		if g.islands[i].charted {charted |= 1 << uint(i)}
	}
	put_u64(buf[36:], charted)
}

// Restores a voyage into g (on the title screen, ready to continue). On any error g is left as it was.
save_decode :: proc(g: ^Game, data: []u8) -> Load_Error {
	if len(data) < 4 {return .Size}
	if data[0] != 'S' || data[1] != 'O' || data[2] != 'S' {return .Magic}
	if data[3] != SAVE_VERSION {return .Version} // before the size: older versions have other sizes
	if len(data) != SAVE_SIZE {return .Size}
	turn := get_u32(data[20:])
	x := transmute(f32)get_u32(data[24:])
	y := transmute(f32)get_u32(data[28:])
	heading := int(get_u16(data[32:]))
	speed := int(data[34])
	if turn > TURN_MAX {return .Range}
	if !in_world(x) || !in_world(y) {return .Range}
	if heading >= 360 || speed > 100 {return .Range}

	// The rest needs the world, so build it aside and only copy it over when everything checks out.
	t := new(Game)
	defer free(t)
	start_world(t, get_u64(data[4:]))
	docked := int(data[35])
	charted := get_u64(data[36:])
	if docked != NOT_DOCKED && docked >= t.n_islands {return .Range}
	if t.n_islands < 64 && charted >> uint(t.n_islands) != 0 {return .Range}
	if is_land(t, int(x), int(y)) {return .Range}
	t.ship = {x = x, y = y, heading = heading, speed = speed}
	t.docked = docked == NOT_DOCKED ? NO_ISLAND : docked
	if t.docked != NO_ISLAND && island_distance(t, t.docked, x, y) > DOCK_RANGE {return .Range}
	for i in 0 ..< t.n_islands {t.islands[i].charted = charted & (1 << uint(i)) != 0}

	t.rng.state = get_u64(data[12:])
	t.turn = int(turn)
	t.next_seed = g.next_seed
	t.muted = g.muted
	t.log, t.log_len = g.log, g.log_len
	t.has_voyage = true
	t.screen = .Title
	g^ = t^
	return .None
}

in_world :: proc(v: f32) -> bool {
	return !math.is_nan(v) && !math.is_inf(v) && v >= 0 && v < WORLD_SIZE
}

put_u16 :: proc(b: []u8, v: u16) {
	b[0], b[1] = u8(v), u8(v >> 8)
}
put_u32 :: proc(b: []u8, v: u32) {
	for i in 0 ..< 4 {b[i] = u8(v >> (8 * uint(i)))}
}
put_u64 :: proc(b: []u8, v: u64) {
	for i in 0 ..< 8 {b[i] = u8(v >> (8 * uint(i)))}
}
get_u16 :: proc(b: []u8) -> u16 {
	return u16(b[0]) | u16(b[1]) << 8
}
get_u32 :: proc(b: []u8) -> (v: u32) {
	for i in 0 ..< 4 {v |= u32(b[i]) << (8 * uint(i))}
	return
}
get_u64 :: proc(b: []u8) -> (v: u64) {
	for i in 0 ..< 8 {v |= u64(b[i]) << (8 * uint(i))}
	return
}
