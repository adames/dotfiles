#!/usr/bin/env python3
"""
cheatsheet-gen — assemble ~/.config/workspace/cheatsheet.json from
@cs-annotated config files plus the layout shell.

Output schema (sigil's new wire shape):

    {
      "banner": [...],                  # from layout
      "views":  [Lens, ...],            # from layout (lens defs)
      "sections": {                     # built from @cs blocks
        "<id>": { title, rows, family, sub, idea, customLayout }
      }
    }

Source @cs syntax (in the file's native comment prefix — # for
toml/conf/zsh, -- for lua):

    # @cs section <title>
    # @cs id      <stable-slug>         (preferred; falls back to a slug
    #                                    derived from the title)
    # @cs family  <system|terminal|vim|nvim|git>
    # @cs sub     <subtitle>            (optional)
    # @cs idea    <one-line caption>    (optional)
    # @cs custom  keyboard              (optional: spatial keyboard widget)
    # @cs row     <chord> :: <description>
    # @cs row     <chord> :: <description>
    # ...
    # @cs end

Resilience model:
- Every per-section parse error is logged to stderr and the section is
  skipped. The rest of the cheatsheet still renders.
- Catastrophic failures (missing layout, unhandled exception) leave the
  existing cheatsheet.json untouched and exit with a warning.
- Lenses referencing missing section ids render with that column slot
  empty. The ws-cheatsheet renderer is permissive about absent ids.

Section content not referenced by any lens is still emitted into the
section pool — that way a future layout-only edit can surface it
without re-running the generator.

Optional fallback: --fallback <path-to-sigil-cheatsheet.json> reads
sigil's committed JSON and uses its section pool to fill any gap left
by the parsed sources (sections present in sigil but missing @cs
annotations upstream). Lets the user grow source coverage incrementally
without regressing the HUD.

Run manually:
    python3 lib/cheatsheet-gen.py \\
      --repo-root $HOME/dotfiles \\
      --layout    configs/workspace/cheatsheet-layout.json \\
      --fallback  $HOME/code/sigil/cheatsheet.json \\
      --out       configs/workspace/cheatsheet.json

macos/bootstrap.sh invokes the same command before install_file copies
the artifact onto disk.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


# Source files the parser walks, with their comment-prefix. Order
# matters: when two @cs blocks share an id, the first one wins. Add
# new sources here; the script silently skips paths that don't exist
# (with a stderr warning).
SOURCES: list[tuple[str, str]] = [
    ("configs/aerospace.toml",    "#"),
    ("configs/tmux.conf",         "#"),
    ("configs/zshrc",             "#"),
    ("configs/nvim-init.lua",     "--"),
    ("configs/nvim-keymaps.lua",  "--"),
    ("configs/ghostty-config",    "#"),
]


def warn(msg: str) -> None:
    """One-line warning to stderr. Format kept stable for test grep."""
    print(f"cheatsheet-gen: WARN: {msg}", file=sys.stderr)


def err(msg: str) -> None:
    """One-line error to stderr."""
    print(f"cheatsheet-gen: ERROR: {msg}", file=sys.stderr)


def slugify(title: str) -> str:
    """Best-effort id from a title. Lowercase ASCII alphanumerics,
    everything else collapses to single hyphens. Used only when an
    @cs block lacks an explicit `@cs id` directive."""
    s = re.sub(r"[^a-zA-Z0-9]+", "-", title.lower()).strip("-")
    return s or "untitled"


def parse_file(path: Path, comment_prefix: str) -> list[dict[str, Any]]:
    """Walk one source file, return a list of parsed @cs sections."""
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        warn(f"{path}: not found — skipping")
        return []
    except Exception as exc:
        warn(f"{path}: unreadable ({exc}) — skipping")
        return []

    # Match `<prefix> @cs <directive> <args>`.
    pattern = re.compile(
        rf"^\s*{re.escape(comment_prefix)}\s*@cs\s+(\S+)\s*(.*?)\s*$"
    )

    sections: list[dict[str, Any]] = []
    block: dict[str, Any] | None = None
    block_start_line = 0

    def flush(reason: str | None = None) -> None:
        nonlocal block
        if block is None:
            return
        if reason:
            warn(f"{path}:{block_start_line}: section "
                 f"'{block.get('title', '?')}' — {reason}")
        if "family" not in block:
            warn(f"{path}:{block_start_line}: section "
                 f"'{block.get('title', '?')}' missing @cs family — dropped")
            block = None
            return
        if not block.get("rows"):
            warn(f"{path}:{block_start_line}: section "
                 f"'{block.get('title', '?')}' has no rows — dropped")
            block = None
            return
        # Fill id from title if no explicit @cs id was provided.
        block.setdefault("id", slugify(block["title"]))
        sections.append(block)
        block = None

    for line_num, raw_line in enumerate(text.splitlines(), 1):
        m = pattern.match(raw_line)
        if not m:
            continue
        directive, arg = m.group(1), m.group(2).strip()

        if directive == "section":
            if block is not None:
                flush(reason="missing @cs end (auto-flushed at next section)")
            if not arg:
                warn(f"{path}:{line_num}: @cs section with empty title — skipped")
                continue
            block = {"title": arg, "rows": []}
            block_start_line = line_num
            continue

        if directive == "end":
            if block is None:
                warn(f"{path}:{line_num}: @cs end with no open section")
                continue
            flush()
            continue

        # All remaining directives require an open section.
        if block is None:
            warn(f"{path}:{line_num}: @cs {directive} outside section — dropped")
            continue

        if directive == "id":
            if not arg:
                warn(f"{path}:{line_num}: @cs id with empty value — ignored")
                continue
            block["id"] = arg
        elif directive == "family":
            if not arg:
                warn(f"{path}:{line_num}: @cs family with empty value — dropped")
                continue
            block["family"] = arg.lower()
        elif directive == "sub":
            block["sub"] = arg
        elif directive == "idea":
            block["idea"] = arg
        elif directive == "custom":
            if not arg:
                warn(f"{path}:{line_num}: @cs custom with empty value — dropped")
                continue
            block["customLayout"] = arg
        elif directive == "row":
            if "::" not in arg:
                warn(f"{path}:{line_num}: @cs row missing '::' separator — row dropped")
                continue
            chord, _, desc = arg.partition("::")
            block["rows"].append([chord.strip(), desc.strip()])
        else:
            warn(f"{path}:{line_num}: unknown directive @cs {directive}")

    if block is not None:
        flush(reason="missing @cs end (auto-flushed at EOF)")

    return sections


def load_json(path: Path, kind: str) -> dict[str, Any] | None:
    if not path.exists():
        err(f"{kind} file {path} not found")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        err(f"{kind} file {path} malformed: {exc}")
        return None


def section_to_pool_entry(s: dict[str, Any]) -> dict[str, Any]:
    """Drop the `id` field (it's the dict key); keep the renderer-facing
    keys. Preserves field order for readable JSON diffs."""
    out: dict[str, Any] = {
        "title": s["title"],
        "rows":  s["rows"],
        "family": s.get("family"),
    }
    for key in ("sub", "idea", "color", "customLayout"):
        if s.get(key) is not None:
            out[key] = s[key]
    return out


def build_document(
    parsed: list[dict[str, Any]],
    layout: dict[str, Any],
    fallback: dict[str, Any] | None,
) -> dict[str, Any]:
    """Assemble {banner, views, sections} from layout + parsed sections,
    with optional sigil-fallback for ids missing from upstream sources."""

    # Build the section pool with the "sigil-wins" merge policy:
    #
    # - Parsed @cs sources lay down their content first.
    # - sigil's fallback (committed cheatsheet.json) overwrites where
    #   ids overlap — sigil is the authoritative hand-maintained source
    #   of truth, @cs in source files is opportunistic fill-in for ids
    #   sigil doesn't already track.
    #
    # This prevents stale @cs annotations from regressing the HUD when
    # the user hand-edits cheatsheet.json directly. To make a parsed @cs
    # block authoritative for a given id, remove the matching entry
    # from sigil's cheatsheet.json sections.
    pool: dict[str, dict[str, Any]] = {}

    for s in parsed:
        pool[s["id"]] = section_to_pool_entry(s)

    fallback_sections = (fallback or {}).get("sections") or {}
    if not isinstance(fallback_sections, dict):
        warn("fallback `sections` is not an object — ignoring")
        fallback_sections = {}
    for sid, content in fallback_sections.items():
        if isinstance(content, dict):
            pool[sid] = dict(content)  # sigil wins for overlapping ids

    # Validate lens references — warn (don't crash) on missing ids.
    views = layout.get("views") or []
    referenced: set[str] = set()
    for v in views:
        vid = v.get("id", "?")
        for col in v.get("columns", []):
            for sid in col.get("sections", []):
                referenced.add(sid)
                if sid not in pool:
                    warn(f"lens '{vid}' references missing section id "
                         f"'{sid}' — column slot will render empty")

    # Surface orphan sections (parsed but not used by any lens).
    for sid in sorted(set(pool) - referenced):
        # Fallback-only ids are expected to be reachable via lenses too,
        # so the warning fires for both. Suppress noise when the section
        # came purely from fallback (it's just inherited content).
        from_parsed = any(s["id"] == sid for s in parsed)
        if from_parsed:
            warn(f"section '{sid}' parsed from sources but no lens "
                 f"references it — content sits in the pool unused")

    return {
        "banner":   layout.get("banner", []),
        "views":    views,
        "sections": pool,
    }


def atomic_write_json(out_path: Path, doc: dict[str, Any]) -> bool:
    """Write `doc` via tmp + os.replace. Validates parse-back before
    swapping in — guards against corruption mid-write."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_suffix(out_path.suffix + ".tmp")
    try:
        tmp_path.write_text(
            json.dumps(doc, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        # Parse-back sanity check.
        json.loads(tmp_path.read_text(encoding="utf-8"))
    except Exception as exc:
        err(f"failed to write {tmp_path}: {exc}")
        try: tmp_path.unlink()
        except FileNotFoundError: pass
        return False
    try:
        os.replace(tmp_path, out_path)
    except Exception as exc:
        err(f"failed to swap {tmp_path} → {out_path}: {exc}")
        return False
    return True


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--repo-root", type=Path, required=True,
                   help="dotfiles repo root (source paths are relative to it)")
    p.add_argument("--layout", type=Path, required=True,
                   help="layout JSON (banner + views)")
    p.add_argument("--fallback", type=Path, default=None,
                   help="sigil cheatsheet.json — provides section content "
                        "for ids missing from upstream @cs sources")
    p.add_argument("--out", type=Path, required=True,
                   help="destination cheatsheet.json (atomically replaced on success)")
    args = p.parse_args()

    layout = load_json(args.layout, "layout")
    if layout is None:
        err("no layout — leaving existing cheatsheet.json untouched")
        return 1

    fallback = None
    if args.fallback is not None:
        fallback = load_json(args.fallback, "fallback")
        if fallback is None:
            warn("fallback file unreadable — proceeding without it")

    parsed: list[dict[str, Any]] = []
    for rel, prefix in SOURCES:
        path = args.repo_root / rel
        try:
            parsed.extend(parse_file(path, prefix))
        except Exception as exc:
            warn(f"{path}: parse failed ({exc}) — skipping")

    try:
        doc = build_document(parsed, layout, fallback)
    except Exception as exc:
        err(f"build_document failed: {exc} — leaving cheatsheet.json untouched")
        return 1

    if not atomic_write_json(args.out, doc):
        return 1

    print(
        f"cheatsheet-gen: wrote {args.out} "
        f"({len(doc['views'])} views, {len(doc['sections'])} sections, "
        f"{len(parsed)} parsed from sources)",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
