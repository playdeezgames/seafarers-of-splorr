package game

// splitmix64 on u64 maths: the same sequence natively and in js_wasm32. A zero state still moves on (it adds the
// constant first), so an uninitialised generator cannot stall a loop.
Rng :: struct {
	state: u64,
}

rng_make :: proc(seed: u64) -> Rng {
	return {state = seed}
}

rng_next :: proc(r: ^Rng) -> u64 {
	r.state += 0x9E3779B97F4A7C15
	z := r.state
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

// 0 ..< n. The modulo bias is negligible for the small n a game uses.
rng_below :: proc(r: ^Rng, n: int) -> int {
	if n <= 1 {return 0}
	return int(rng_next(r) % u64(n))
}
