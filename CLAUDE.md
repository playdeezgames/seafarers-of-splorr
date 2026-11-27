# CLAUDE.md

Seafarers of SPLORR!!: Odin compiled to `js_wasm32` with a 2D canvas shim. The design, the phase plan and the rules for
sessions live in the SPLORR!! vault at `/home/yermom/git/bok-of-splorr/splorr/Games/Seafarers of SPLORR!!.md`; read it
(and the vault's `Home.md` standing rules) before working here.

- `tools/test.sh` must pass before any commit. Rules go in `game/` (no browser code, testable natively); `src/web/` is
  the `#+build js` layer; `web/index.html` is the JS shim. Enum orders (`Action`, `Sound`) must match the page.
- Every loop in `game/` needs a bound. RNG is `game/rng.odin` only (splitmix64, `u64`).
- Changing the save layout means bumping `SAVE_VERSION` and adding a test.
- Never `git push` or ship (`shippit.sh --push`) without the user's word. "push" means git push; "ship" means itch.io.
