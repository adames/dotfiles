#!/usr/bin/env python3
"""
cheatsheet-gen — assemble configs/workspace/cheatsheet.json from
@cs-annotated config files.

Each source config (skhdrc, tmux.conf, nvim-init.lua, …) carries
cheatsheet content in its own comment syntax via `@cs` directive
blocks. A small layout file (configs/workspace/cheatsheet-layout.json)
declares the banner strip + the column → family mapping. This script
parses all of it and writes a single JSON document that the
ws-cheatsheet binary renders.

Annotation format (in the file's native comment syntax — `# ` for
bash/skhd/tmux/zsh, `-- ` for lua):

    # @cs section <title>
    # @cs family <system|terminal|vim|nvim|git>
    # @cs sub <subtitle>          (optional)
    # @cs idea <one-line caption> (optional)
    # @cs row <chord> :: <description>
    # @cs row <chord> :: <description>
    # ...
    # @cs custom keyboard         (optional: opt into spatial keyboard widget)
    # @cs end

Resilience: every step is independently fault-isolated. The script
NEVER blocks deploy. On any per-section error it warns to stderr and
skips that section; the rest of the cheatsheet still renders. On a
catastrophic failure (layout file missing, unhandled exception) it
either falls back to a single-column synthesized layout or leaves the
existing cheatsheet.json untouched. Exit code is 0 as long as a JSON
was successfully written.

Run manually:
    python3 lib/cheatsheet-gen.py \\
      --layout configs/workspace/cheatsheet-layout.json \\
      --out    configs/workspace/cheatsheet.json

macos/bootstrap.sh invokes the same command before install_file copies
the artifact onto disk.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import traceback
from pathlib import Path
from typing import Any


# Source files the parser walks, with their comment-prefix. Order
# matters: when two sections share a family, the first source wins on
# placement order within the column. Add new sources here; the script
# will silently skip any path that doesn't exist (with a stderr warning).
SOURCES: list[tuple[str, str]] = [
    ("configs/skhdrc",            "#"),
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


def parse_file(path: Path, comment_prefix: str) -> list[dict[str, Any]]:
    """
    Walk one source file and return its valid @cs sections.

    Resilience strategy: per-section errors are warnings, not exceptions.
    A malformed section either gets dropped (if it can't be rescued) or
    flushed in best-effort form (if the recoverable fields are present).
    """
    if not path.exists():
        warn(f"{path}: not found — skipping")
        return []

    try:
        text = path.read_text(encoding="utf-8")
    except Exception as exc:
        warn(f"{path}: unreadable ({exc}) — skipping")
        return []

    # Match `<prefix> @cs <directive> <args>` with arbitrary whitespace
    # between tokens. The `re.escape` lets us pass `#` or `--` verbatim.
    pattern = re.compile(
        rf"^\s*{re.escape(comment_prefix)}\s*@cs\s+(\S+)\s*(.*?)\s*$"
    )

    sections: list[dict[str, Any]] = []
    block: dict[str, Any] | None = None
    block_start_line = 0

    def flush(reason: str | None = None) -> None:
        """Close the current block — append if minimally valid, else drop."""
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
        sections.append(block)
        block = None

    for line_num, raw_line in enumerate(text.splitlines(), 1):
        m = pattern.match(raw_line)
        if not m:
            continue
        directive, arg = m.group(1), m.group(2).strip()

        if directive == "section":
            # New section — flush any previous one that lacked its @cs end.
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

        if directive == "family":
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
                warn(f"{path}:{line_num}: @cs row missing '::' separator "
                     f"— row dropped")
                continue
            chord, _, desc = arg.partition("::")
            block["rows"].append([chord.strip(), desc.strip()])
        else:
            warn(f"{path}:{line_num}: unknown directive @cs {directive}")

    # End-of-file: flush any unclosed block.
    if block is not None:
        flush(reason="missing @cs end (auto-flushed at EOF)")

    return sections


def load_layout(path: Path) -> dict[str, Any] | None:
    """Read the layout file. Return None on any failure — caller falls back."""
    if not path.exists():
        err(f"layout file {path} not found")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        err(f"layout file {path} malformed: {exc}")
        return None


def build_document(
    sections: list[dict[str, Any]],
    layout: dict[str, Any] | None,
) -> dict[str, Any]:
    """
    Assemble the final {banner, columns} document. If `layout` is None,
    synthesize a single-column fallback so the HUD still has something
    sane to render.
    """
    by_family: dict[str, list[dict[str, Any]]] = {}
    for s in sections:
        by_family.setdefault(s["family"], []).append(s)

    if layout is None:
        # Catastrophic fallback — one column with everything we parsed.
        warn("no layout — emitting single-column fallback")
        return {
            "banner": [],
            "columns": [{"sections": sections}],
        }

    banner = layout.get("banner", [])
    column_specs = layout.get("columns", [])
    if not column_specs:
        warn("layout has no columns — emitting single-column fallback")
        return {"banner": banner, "columns": [{"sections": sections}]}

    columns: list[dict[str, Any]] = []
    placed_families: set[str] = set()
    for col_spec in column_specs:
        families = col_spec.get("families", [])
        col_sections: list[dict[str, Any]] = []
        for fam in families:
            fam_norm = str(fam).lower()
            placed_families.add(fam_norm)
            col_sections.extend(by_family.get(fam_norm, []))
        columns.append({"sections": col_sections})

    # Any parsed family not claimed by the layout is dropped — warn so
    # the user notices unmapped content rather than wondering where it went.
    for fam in by_family:
        if fam not in placed_families:
            count = len(by_family[fam])
            warn(f"family '{fam}' has {count} section(s) but isn't placed "
                 f"in the layout — sections dropped")

    return {"banner": banner, "columns": columns}


def atomic_write_json(out_path: Path, doc: dict[str, Any]) -> bool:
    """
    Write `doc` to `out_path` via tmp + os.replace. Validates the tmp
    parses back as JSON before swapping in (guards against corruption
    from a crashed write). Returns True on success, False otherwise —
    on failure, the existing file at out_path is untouched.
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_suffix(out_path.suffix + ".tmp")
    try:
        # `ensure_ascii=False` keeps Unicode glyphs (·, ↵, ⇧, …) as
        # themselves rather than escape sequences — easier to diff and
        # the cheatsheet renderer expects them as-is.
        payload = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
        tmp_path.write_text(payload, encoding="utf-8")
        # Read-back validation: if json.loads fails here something is
        # very wrong with the encoding round-trip.
        json.loads(tmp_path.read_text(encoding="utf-8"))
        os.replace(tmp_path, out_path)
        return True
    except Exception as exc:
        err(f"atomic write to {out_path} failed: {exc}")
        try:
            tmp_path.unlink(missing_ok=True)
        except Exception:
            pass
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--layout",
        required=True,
        help="path to the layout file (banner + column → family map)",
    )
    parser.add_argument(
        "--out",
        required=True,
        help="destination cheatsheet.json path (atomically replaced on success)",
    )
    parser.add_argument(
        "--repo-root",
        default=".",
        help="repo root for resolving relative source paths (default: cwd)",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()

    # Walk every source file. Each call is independently fault-isolated:
    # a missing file produces a warning, never an exception.
    all_sections: list[dict[str, Any]] = []
    for rel_path, prefix in SOURCES:
        sections = parse_file(repo_root / rel_path, prefix)
        all_sections.extend(sections)

    layout = load_layout(Path(args.layout))
    doc = build_document(all_sections, layout)

    if not atomic_write_json(Path(args.out), doc):
        # Last-resort: existing cheatsheet.json (if any) is intact;
        # this run produced nothing. Exit non-zero so bootstrap warns.
        return 2

    n_sections = sum(len(col["sections"]) for col in doc["columns"])
    print(
        f"cheatsheet-gen: wrote {args.out} "
        f"({len(doc['columns'])} columns, {n_sections} sections)",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Catastrophic fallback: log + exit non-zero so bootstrap notices,
        # but DO NOT touch the existing cheatsheet.json. The HUD keeps
        # rendering whatever was previously installed.
        err("unhandled exception (existing cheatsheet.json untouched):")
        traceback.print_exc()
        sys.exit(2)
