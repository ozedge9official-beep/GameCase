# Cheat compatibility

GameCase manages files and launch settings. Each game IPA contains its own
nxnative cheat VM; updating GameCase does not update that VM.

The format contract was checked against upstream
[`hle_cheats.c`](https://github.com/seedds/nxnative/blob/60284e7901cb4acd0e057d99fdf5560e0cd8e2fe/dm/host/hle_cheats.c)
(blob `41ddc08f31af639d7802143b99f24e72aa579cb5`; source-file identity, not a game IPA engine version). In particular, the current VM:

- Matches the first 16 hexadecimal digits of the main **NSO** Build ID against
  the `.txt` filename. Title ID, Mach-O UUID and iOS version are different values.
- Reads code words after a header, supports packed eight-digit hexadecimal
  words, and ignores prose-only sections. Code-like malformed lines are errors.
- Preserves case and internal whitespace in names, truncates at a UTF-8
  boundary to 127 bytes, and numbers duplicate headers including labels and
  masters. Later duplicates use `Name #2`, `Name #3`, etc. in `.enabled`.
- Reads `.enabled` keys exactly, with a fallback for repeated legacy raw names.
- Always runs `{master}` sections unless globally disabled. Without an explicit
  `DM_CHEATS` path, it can fall back to bundled cheats.
- Rejects writes to signed game-code pages on iOS. Data and heap cheats still
  require correct addresses, conditions and VM opcode support.

GameCase normalizes UTF-8 BOM / BOM-marked UTF-16, line endings, same-line
headers and packed words into UTF-8 text suitable for older parsers. It never
rewrites addresses, values or opcodes, renames a file to another Build ID, or
sets `DM_CHEATS_ANY_BUILD`. It shows malformed lines without deleting them.
Unknown opcodes are retained so the guest VM decides support.

An extracted Atmosphere folder can be selected. Under
`contents/<titleID>/cheats`, only files for this game's title are accepted.
Flat Build-ID-named files can also be selected. ZIP files need extracting
first. Imports manage `.txt` files; external `.enabled`, `.values`, and compiled
`.meta.tsv` selections are not imported or automatically enabled.

Different files with the same Build ID in a single batch are skipped rather
than arbitrarily choosing one. Replacing a file first copies its original text
and selections to `Documents/cheat-backups/<UUID>/`, then commits text and state
together. Unchanged entries retain selections; changed ordinary code requires selecting
the entry again. Master entries still follow the global switch. Unknown guest keys are retained. Backups are local files and
are not automatically pruned.

The global off switch creates a regular marker file and points `DM_CHEATS` at
a child path of that file. This prevents both ordinary and master entries
loading, including with older VMs that lack a master-switch API. Launch-time
env maintenance applies the setting; restarting the game is required.

Build IDs are read only from `dm/main.fixups.tsv` and `dm/pN/main.fixups.tsv` in
the installed game bundle. Missing metadata means **unknown**, not incompatible.
For multi-program IPAs, matching one known program does not establish which
program the player will launch. Log excerpts are explicitly previous-run
records with their modification date, not proof of current cheat effects.

`tests/run_cheat_regressions.py` compiles the production Foundation store with
Swift on macOS and exercises encoding, formatting, state round trips, duplicate
rules, replacement preservation and rollback, Build IDs and folder selection.
These checks do not measure a game-specific success rate. That requires an iOS
device, the player's game IPA and an observed in-game effect.
