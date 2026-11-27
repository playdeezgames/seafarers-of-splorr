# Seafarers of SPLORR!!

A sailing and trading game in the browser: steer by heading and speed across a tile-drawn sea, chart islands, trade,
make deliveries, gamble in the dark alley, and retire at the end of your years with a score. An Odin/wasm port of
Seafarers of SPLORR!! "Classic" (F#, 2020) with the ideas of the unfinished 2021 C++ game folded in.

**Status:** Phases 0 to 8 built (scaffold, the sea, staying alive, trade, deliveries, the dark alley, crew, the
shipyard, things at sea) of a thirteen-phase plan (0 to 12). The plan and every design decision live in the SPLORR!! vault
(`splorr/Games/Seafarers of SPLORR!!.md`).

## Build and run

Needs Odin (`odin` on the PATH) and Python 3 for the local server.

```bash
tools/test.sh      # native tests of the rules, then a wasm type check of the web layer
tools/serve.sh     # build and serve on http://localhost:8000 (PORT=... to change)
tools/pages.sh     # size build into docs/ for GitHub Pages (does not commit or push)
./shippit.sh       # itch.io zip; pushes only with --push
```

`?seed=N` builds a repeatable world for QA and neither loads nor overwrites the stored voyage.

## Layout

- `game/`: the rules, no browser code (`game.odin`, `rng.odin` splitmix64, `save.odin` versioned save format,
  `game_test.odin`).
- `src/web/main.odin`: the `#+build js` layer: frame loop, input exports, drawing calls.
- `web/index.html`: the canvas shim (tiles, bitmap text, the ship, Web Audio, localStorage), footer links and the
  LootLocker feedback kit (`web/lootlocker.js`, hidden until the game has LootLocker keys).
- `assets/`: tiles, font, cover and screenshots.

## Credits

- Tiles: **Bountiful Bits** by VEXED, https://v3x3d.itch.io/bountiful-bits (CC0; see `assets/tiles/LICENSE-RECORD.txt`).
- Font: **m6x11** by Daniel Linssen (managore), https://managore.itch.io/m6x11 (free to use with attribution).
- Made in Odin by an AI agent (Claude Code) at the author's direction.
