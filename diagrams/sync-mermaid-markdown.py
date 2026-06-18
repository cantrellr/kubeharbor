#!/usr/bin/env python3
"""
Synchronize Markdown Mermaid blocks and diagram indexes with Mermaid source files.

This follows the diagram-management pattern used by
cantrellr/k8s-mystical-mesh-documents/diagrams while keeping kubeharbor's
local render workflow intact.

Source of truth:
  diagrams/mermaid-source/*.mmd

Managed outputs:
  Markdown files listed in diagrams/DIAGRAM-INDEX.json
  diagrams/DIAGRAM-INDEX.json
  diagrams/DIAGRAM-INDEX.md
  .diagram-sync-updated-files.txt

The sync contract is intentionally strict. Each indexed diagram must have one
and only one matching "Diagram export" line in its source Markdown file. This
prevents the tool from silently accepting truncated documentation or mismatched
Mermaid/export bindings.
"""
from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Iterable


EXPORT_LINE_TEMPLATE = (
    "> Diagram export: [SVG](../diagrams/svg/{base}.svg) | "
    "[PNG](../diagrams/png/{base}.png)"
)


def load_index_entries(repo_dir: Path) -> list[dict]:
    index_json = repo_dir / "diagrams" / "DIAGRAM-INDEX.json"
    if not index_json.exists():
        raise FileNotFoundError(f"Missing diagram index: {index_json}")

    entries = json.loads(index_json.read_text(encoding="utf-8"))
    if not isinstance(entries, list) or not entries:
        raise ValueError(f"Diagram index is empty or invalid: {index_json}")

    required = {"source_file", "diagram_number", "base_name", "mermaid_source", "svg", "png"}
    for idx, entry in enumerate(entries, start=1):
        missing = sorted(required - set(entry))
        if missing:
            raise ValueError(f"Diagram index entry {idx} is missing required keys: {', '.join(missing)}")
    return entries


def group_entries_by_source(entries: Iterable[dict]) -> dict[str, list[dict]]:
    grouped: dict[str, list[dict]] = defaultdict(list)
    for entry in entries:
        grouped[entry["source_file"]].append(entry)
    for source_file, source_entries in grouped.items():
        source_entries.sort(key=lambda item: int(item["diagram_number"]))
    return dict(grouped)


def read_mmd(repo_dir: Path, base_name: str) -> str:
    source = repo_dir / "diagrams" / "mermaid-source" / f"{base_name}.mmd"
    if not source.exists():
        raise FileNotFoundError(f"Missing Mermaid source: {source}")
    body = source.read_text(encoding="utf-8").strip()
    if not body.startswith(("flowchart", "graph", "sequenceDiagram", "classDiagram", "stateDiagram")):
        raise ValueError(f"Mermaid source does not look like a Mermaid diagram: {source}")
    return body


def export_line_regex(base_name: str) -> re.Pattern[str]:
    return re.compile(
        r"> Diagram export: \[SVG\]\((?P<svg>[^)]*" + re.escape(base_name) + r"\.svg)\) "
        r"\| \[PNG\]\((?P<png>[^)]*" + re.escape(base_name) + r"\.png)\)"
    )


def mermaid_block_with_export_regex(base_name: str) -> re.Pattern[str]:
    return re.compile(
        r"```mermaid\n(?P<body>.*?)\n```\s*\n"
        r"> Diagram export: \[SVG\]\((?P<svg>[^)]*" + re.escape(base_name) + r"\.svg)\) "
        r"\| \[PNG\]\((?P<png>[^)]*" + re.escape(base_name) + r"\.png)\)",
        flags=re.DOTALL,
    )


def validate_markdown_bindings(repo_dir: Path, source_file: str, entries: list[dict], text: str) -> None:
    mermaid_blocks = len(re.findall(r"```mermaid\n", text))
    export_lines = len(re.findall(r"> Diagram export: \[SVG\]\(", text))
    expected = len(entries)

    if mermaid_blocks < expected:
        raise ValueError(
            f"{source_file} contains {mermaid_blocks} Mermaid block(s), but {expected} diagram(s) are indexed. "
            "The document may be truncated or missing diagram blocks."
        )
    if export_lines < expected:
        raise ValueError(
            f"{source_file} contains {export_lines} Diagram export line(s), but {expected} diagram(s) are indexed. "
            "Each indexed diagram must have one export line."
        )

    for entry in entries:
        base_name = entry["base_name"]
        matches = export_line_regex(base_name).findall(text)
        if len(matches) != 1:
            raise ValueError(
                f"{source_file} must contain exactly one Diagram export line for {base_name}; found {len(matches)}."
            )

        block_matches = mermaid_block_with_export_regex(base_name).findall(text)
        if len(block_matches) != 1:
            raise ValueError(
                f"{source_file} must contain exactly one Mermaid block immediately followed by the export line "
                f"for {base_name}; found {len(block_matches)}."
            )


def sync_markdown_mermaid_blocks(repo_dir: Path, entries: list[dict]) -> list[str]:
    changed_files: list[str] = []
    grouped = group_entries_by_source(entries)

    for source_file, source_entries in grouped.items():
        md_path = repo_dir / source_file
        if not md_path.exists():
            raise FileNotFoundError(f"Indexed Markdown source file does not exist: {md_path}")

        original = md_path.read_text(encoding="utf-8")
        validate_markdown_bindings(repo_dir, source_file, source_entries, original)
        updated = original

        for entry in source_entries:
            base_name = entry["base_name"]
            source_body = read_mmd(repo_dir, base_name)
            pattern = mermaid_block_with_export_regex(base_name)

            def repl(match: re.Match[str]) -> str:
                return (
                    "```mermaid\n"
                    + source_body
                    + "\n```\n\n"
                    + f"> Diagram export: [SVG]({match.group('svg')}) | [PNG]({match.group('png')})"
                )

            updated, replacements = pattern.subn(repl, updated)
            if replacements != 1:
                raise RuntimeError(f"Expected one replacement for {base_name} in {source_file}; got {replacements}.")

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
        node_match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[|\{)", line)
        if node_match:
            node_ids.add(node_match.group(1))
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
        if not source_path.exists():
            raise FileNotFoundError(f"Indexed Mermaid source does not exist: {source_path}")
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
        "The diagrams below are exported from Mermaid code blocks in the kubeharbor system design document.",
        "",
        "| Source file | Diagram | Mermaid source | SVG | PNG | Nodes | Edges |",
        "| --- | ---: | --- | --- | --- | ---: | ---: |",
    ]
    for entry in entries:
        base = entry["base_name"]
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

    try:
        entries = load_index_entries(repo_dir)
        changed: list[str] = []
        changed.extend(sync_markdown_mermaid_blocks(repo_dir, entries))
        changed.extend(refresh_diagram_indexes(repo_dir, entries))
    except Exception as exc:  # noqa: BLE001 - CLI script should print clean operator errors.
        print(f"ERROR: diagram sync failed: {exc}", file=sys.stderr)
        return 1

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
