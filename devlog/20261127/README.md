# November 27, 2026: Phase 0, the scaffold

Not posted. A working record.

- New repo `seafarers-of-splorr`: an Odin/wasm port of Seafarers of SPLORR!! Classic, with the 2021 C++ game's ideas
  folded in, built in ten phases (plan in the vault).
- Rules package `game/`: splitmix64 RNG on `u64` maths; a placeholder world of 100 by 100 tiles with up to 40 islands
  at least 8 tiles apart (Classic's gap); a ship with heading in degrees and speed in percent; title and sea menus; a
  four-line message log; a versioned 35-byte save with size, magic, version and range checks. 11 native tests.
- Web layer: a 400 by 240 canvas at whole-number zoom; the sea view (24 by 24 tiles) keeps the ship centred; the panel
  holds status, a numbered menu and the log. Keys, gamepad and taps. Autosave to localStorage after every action;
  `?seed=N` for QA leaves the save alone. Web Audio blips with M to mute.
- Font m6x11 (the user's pick). Tiles from Bountiful Bits; the ship is drawn so it can turn to any heading.
