#!/usr/bin/env python3
"""
Synchronize Markdown Mermaid blocks and diagram indexes with Mermaid source files.

This mirrors the diagram-management pattern used by
cantrellr/k8s-mystical-mesh-documents/diagrams while keeping kubeharbor's
local render workflow intact.

Source of truth:
  diagrams/mermaid-source/*.mmd

Generated/managed metadata:
  diagrams/DIAGRAM-INDEX.json
  diagrams/DIAGRAM-INDEX.md
  .diagram-sync-updated-files.txt

The script updates Markdown files that contain Mermaid code blocks followed by a
matching "Diagram export" line, then refreshes diagram index node/edge counts.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Iterable

EXCLUDED_DIRS = {
    ".git",
    ".github",
    ".diagram-tools",
    "node_modules",
    ".venv",
    "venv",
    "dist",
    "build",
}


def iter_markdown_files(repo_dir: Path) -> Iterable[Path]:
    for path in repo_dir.rglob("*.md"):
        relative_parts = path.relative_to(repo_dir).parts
        if any(part in EXCLUDED_DIRS for part in relative_parts):
            continue
        yield path


def load_index_entries(repo_dir: Path) -> list[dict]:
    index_json = repo_dir / "diagrams" / "DIAGRAM-INDEX.json"
    if not index_json.exists():
        raise FileNotFoundError(f"Missing diagram index: {index_json}")
    return json.loads(index_json.read_text(encoding="utf-8"))


def read_mmd(repo_dir: Path, base_name: str) -> str:
    source = repo_dir / "diagrams" / "mermaid-source" / f"{base_name}.mmd"
    if not source.exists():
        raise FileNotFoundError(f"Missing Mermaid source: {source}")
    return source.read_text(encoding="utf-8").strip()


def sync_markdown_mermaid_blocks(repo_dir: Path, entries: list[dict]) -> list[str]:
    changed_files: list[str] = []

    for md_path in iter_markdown_files(repo_dir):
        original = md_path.read_text(encoding="utf-8")
        updated = original

        for entry in entries:
            base_name = entry["base_name"]
            source_body = read_mmd(repo_dir, base_name)

            # Match a Mermaid block immediately associated with the matching
            # export line. The export line is the binding contract that tells
            # us which diagram number the preceding code block represents.
            pattern = re.compile(
                r"```mermaid\n(?P<body>.*?)\n```\s*\n> Diagram export: "
                r"\[SVG\]\((?P<svg>[^)]*" + re.escape(base_name) + r"\.svg)\) "
                r"\| \[PNG\]\((?P<png>[^)]*" + re.escape(base_name) + r"\.png)\)",
                flags=re.DOTALL,
            )

            def repl(match: re.Match[str]) -> str:
                return (
                    "```mermaid\n"
                    + source_body
                    + "\n```\n\n"
                    + f"> Diagram export: [SVG]({match.group('svg')}) | [PNG]({match.group('png')})"
                )

            updated = pattern.sub(repl, updated)

        if updated != original:
            md_path.write_text(updated, encoding="utf-8")
            changed_files.append(str(md_path.relative_to(repo_dir)))

    return changed_files


def count_nodes_edges(mmd_text: str) -> tuple[int, int]:
    node_ids: set[str] = set()
    edge_count = 0

    for raw_line in mmd_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("%%") or line.startswith("flowchart") or line.startswith("style"):
            continue
        # Node declaration variants used in this repository:
        #   NodeID["Label"]
        #   NodeID{"Decision"}
        node_match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[|\{)", line)
        if node_match:
            node_ids.add(node_match.group(1))
        # Mermaid edge variants used in this repository.
        if re.search(r"(-->|<-.+?->|-.+?->|==>|---)", line):
            edge_count += 1

    return len(node_ids), edge_count


def refresh_diagram_indexes(repo_dir: Path, entries: list[dict]) -> list[str]:
    changed_files: list[str] = []
    index_json = repo_dir / "diagrams" / "DIAGRAM-INDEX.json"
    index_md = repo_dir / "diagrams" / "DIAGRAM-INDEX.md"

    original_json = index_json.read_text(encoding="utf-8")

    for entry in entries:
        source_path = repo_dir / entry["mermaid_source"]
        if source_path.exists():
            nodes, edges = count_nodes_edges(source_path.read_text(encoding="utf-8"))
            entry["nodes"] = nodes
            entry["edges"] = edges

    updated_json = json.dumps(entries, indent=2) + "\n"
    if updated_json != original_json:
        index_json.write_text(updated_json, encoding="utf-8")
        changed_files.append(str(index_json.relative_to(repo_dir)))

    original_md = index_md.read_text(encoding="utf-8") if index_md.exists() else ""
    lines = [
        "# Diagram Export Index",
        "",
        "The diagrams below were exported from Mermaid code blocks in the kubeharbor system design document.",
        "",
        "| Source file | Diagram | Mermaid source | SVG | PNG | Nodes | Edges |",
        "| --- | ---: | --- | --- | --- | ---: | ---: |",
    ]
    for entry in entries:
        base = entry["base_name"]
        # DIAGRAM-INDEX.md lives in diagrams/, so links are relative to that folder.
        lines.append(
            f"| `{entry['source_file']}` | {entry['diagram_number']} | "
            f"[`{base}.mmd`](mermaid-source/{base}.mmd) | "
            f"[SVG](svg/{base}.svg) | [PNG](png/{base}.png) | "
            f"{entry['nodes']} | {entry['edges']} |"
        )
    updated_md = "\n".join(lines) + "\n"
    if updated_md != original_md:
        index_md.write_text(updated_md, encoding="utf-8")
        changed_files.append(str(index_md.relative_to(repo_dir)))

    return changed_files


def main() -> int:
    repo_dir = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    if not (repo_dir / ".git").exists():
        print(f"ERROR: {repo_dir} does not look like a Git repository.", file=sys.stderr)
        return 2

    entries = load_index_entries(repo_dir)
    changed: list[str] = []
    changed.extend(sync_markdown_mermaid_blocks(repo_dir, entries))
    changed.extend(refresh_diagram_indexes(repo_dir, entries))

    # Preserve order while removing duplicates.
    unique_changed = list(dict.fromkeys(changed))
    marker = repo_dir / ".diagram-sync-updated-files.txt"
    marker.write_text("\n".join(unique_changed) + ("\n" if unique_changed else ""), encoding="utf-8")

    if unique_changed:
        print("Updated Markdown/index files:")
        for path in unique_changed:
            print(f"  - {path}")
    else:
        print("No Markdown/index files required changes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
