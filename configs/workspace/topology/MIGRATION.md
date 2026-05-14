# spaces.json v1 → v2 migration (historical / import-only)

**This document is historical.** The system has been v2-only since well
before the keybinding/mode redesign in 2026-05; fresh installs ship
v2 directly. The migrator is kept around solely as importer
infrastructure for the rare case where someone pastes a legacy v1
`spaces.json` (or a `spaces.default.json` from an old commit) on top
of their config — running `ws-topology migrate --apply` rewrites it
in place. Cascade readers do NOT fall back to legacy `.icon`, so
always `--apply` before reloading.

## What changed

| Field | v1 | v2 |
|---|---|---|
| `version` | `1` | `2` |
| `spaces.<N>.icon` | raw glyph string (e.g. `""`) | _removed_ — superseded by `iconSpec` |
| `spaces.<N>.iconSpec` | _not present_ | typed object: `kind`, `codepoint` (ASCII-escaped `\uXXXX`), `fontFamily`, `fallbackSfSymbol`, `fallbackText`, `userOverridden`, optional `symbolName` |
| `spaces.<N>.stableLogicalLabel` | _not present_ | persistent slot label; defaults to current `name`; preserved across renames |
| All `_doc_*` top-level keys | preserved | preserved |

The on-disk shape is still a JSON object keyed by the slot index
(`"1".."N"`). The `workspace` CLI's `WS_NORMALIZE_JQ` filter keeps it sorted
numerically AND actively strips any legacy `.icon` field that sneaks in.

## Migration rules (still applied on `ws-topology migrate`)

For each slot:

1. If `iconSpec` already exists, leave it untouched.
2. Otherwise derive `iconSpec` from the legacy `.icon`:
   * Empty string → `{ kind: "none", fallbackSfSymbol, fallbackText }`.
   * Single scalar in a Private Use Area (U+E000..U+F8FF or U+F0000..U+FFFFD)
     → `{ kind: "nerdFont", codepoint: "\uXXXX", fontFamily: "JetBrainsMono Nerd Font", fallbackSfSymbol, fallbackText }`.
   * Anything else (e.g. emoji) → `{ kind: "text", fallbackText: <glyph> }`.
3. SF Symbol fallback comes from the table in `SfSymbolFallbacks.swift`
   keyed on the slot name. Unknown names map to `circle.fill`.
4. Two-letter text fallback comes from the slot name's uppercase prefix.
5. `userOverridden` defaults to `false`.
6. `stableLogicalLabel` is set to the current `name`.

## Importing a legacy v1 config

```bash
# Dry-run — print the proposed v2 shape without writing
ws-topology migrate

# Apply in place
ws-topology migrate --apply
```

The cascade readers (`on-space-changed.sh`, `paint-all.sh`) read
`iconSpec.codepoint` exclusively — they no longer fall back to the
legacy `.icon` field. So a v1 import without `--apply` would leave
the bar rendering empty icons; always migrate before reloading.

## Coexistence with the `workspace` CLI

* `workspace icon <slot> <glyph-or-SF-name>` writes `iconSpec.codepoint` +
  flips `userOverridden=true`. Accepts SF Symbol names (looked up in
  `~/.config/workspace/lib/sf-to-nerd.json`) or literal Nerd Font glyphs.
  Does NOT write the legacy `.icon` field.
* `workspace name <slot> <new>` only touches `.name`. The `iconSpec`
  stays put. If `userOverridden=true`, the icon survives the rename.
* `workspace migrate` thin-wraps `ws-topology migrate`. Accepts `--apply`.

## Sanity check after import

```bash
ws-topology resolve-icon 1 --surface=font     # should print the Nerd Font glyph
ws-topology resolve-icon 1 --surface=native   # should print the SF Symbol name
ws-topology resolve-icon stream --surface=font  # by name, equivalent to slot 1
```

If the font-driven resolution returns the SF Symbol fallback or text
instead of the glyph, the Nerd Font family may be missing — check
`fc-list | grep -i 'nerd font'` or visit Font Book.
