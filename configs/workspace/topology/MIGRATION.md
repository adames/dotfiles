# spaces.json v1 → v2 migration

## What changes

| Field | v1 | v2 |
|---|---|---|
| `version` | `1` | `2` |
| `spaces.<N>.icon` | raw glyph string (e.g. `""`) | _removed_ — superseded by `iconSpec` |
| `spaces.<N>.iconSpec` | _not present_ | typed object: `kind`, `codepoint` (ASCII-escaped `\uXXXX`), `fontFamily`, `fallbackSfSymbol`, `fallbackText`, `userOverridden` |
| `spaces.<N>.stableLogicalLabel` | _not present_ | persistent slot label; defaults to current `name`; preserved across renames |
| All `_doc_*` top-level keys | preserved | preserved |

The on-disk shape stays a JSON object keyed by the slot index (`"1".."N"`).
The existing `workspace` CLI's `_NORMALIZE` filter continues to keep the file
sorted numerically.

## Migration rules

For each slot:

1. If `iconSpec` already exists, leave it untouched.
2. Otherwise derive `iconSpec` from the legacy `.icon`:
   * Empty string → `{ kind: "none", fallbackSfSymbol, fallbackText }`.
   * Single scalar in a Private Use Area (U+E000..U+F8FF or U+F0000..U+FFFFD)
     → `{ kind: "nerdFont", codepoint: "\uXXXX", fontFamily: "JetBrainsMono Nerd Font", fallbackSfSymbol, fallbackText }`.
   * Anything else (e.g. emoji) → `{ kind: "text", fallbackText: <glyph> }`.
3. SF Symbol fallback comes from `SfSymbolFallbacks` keyed on the slot name
   (`stream → play.fill`, `hub → square.grid.2x2`, …); unknown names map to
   `circle.fill`.
4. Two-letter text fallback comes from the slot name's uppercase prefix.
5. `userOverridden` defaults to `false` so the auto-iconing pipeline can
   regenerate when the user renames a slot. Explicit `workspace icon ...`
   flips it to `true`.
6. `stableLogicalLabel` is set to the current `name`. This is the value the
   yabai `LABEL` will continue to use for slot identity.

## Rollout

1. **Inspect the diff first**:

   ```bash
   ws-topology migrate                  # writes nothing; prints v2 to stdout
   ws-topology migrate > /tmp/v2.json   # save for inspection
   diff <(jq -S . ~/.config/workspace/spaces.json) <(jq -S . /tmp/v2.json) | less
   ```

2. **Apply**:

   ```bash
   ws-topology migrate --apply
   ```

   Backs the original up to `~/.config/workspace/spaces.v1.json` before
   writing. `--apply` is a no-op if the file is already v2 with all required
   fields.

3. **Confirm cascade still works**:

   ```bash
   ~/.config/workspace/on-space-changed.sh
   cat ~/.cache/workspace/current.env   # MACOS_SPACE_ICON should be the literal glyph
   ```

4. **Rollback if needed**:

   ```bash
   ws-topology migrate --rollback       # restores from spaces.v1.json
   ```

## Coexistence with the bash `workspace` CLI

After migration:

* `workspace icon <slot> <glyph>` writes BOTH `.icon` (legacy field, preserved
  so v1 consumers in the cascade keep working during the migration window)
  AND `.iconSpec.codepoint` + `.iconSpec.userOverridden=true` (the v2
  authoritative shape).
* `workspace name <slot> <new>` only touches `.name`; the `iconSpec` is
  unchanged. If `userOverridden=true`, the icon survives the rename; if
  `userOverridden=false`, future auto-iconing can regenerate from the new
  name.
* `workspace migrate` is a thin wrapper that delegates to `ws-topology
  migrate`. It accepts the same flags (`--apply`, `--rollback`).

## Sanity check

```bash
ws-topology resolve-icon 1 --surface=font     # should print the Nerd Font glyph
ws-topology resolve-icon 1 --surface=native   # should print the SF Symbol name
ws-topology resolve-icon stream --surface=font  # by name, equivalent to slot 1
```

If the font-driven resolution returns the SF Symbol fallback or text instead
of the glyph, the Nerd Font family may be missing — check
`fc-list | grep -i 'nerd font'` or visit Font Book.
