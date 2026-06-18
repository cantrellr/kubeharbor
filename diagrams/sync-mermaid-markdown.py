#!/usr/bin/env python3
"""Refresh diagram indexes for kubeharbor Mermaid documentation exports."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
SOURCE = REPO / "diagrams" / "mermaid-source"
INDEX_JSON = REPO / "diagrams" / "DIAGRAM-INDEX.json"
INDEX_MD = REPO / "diagrams" / "DIAGRAM-INDEX.md"


def count_nodes_edges(text: str) -> tuple[int, int]:
    nodes: set[str] = set()
    edges = 0
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("flowchart") or line.startswith("%%") or line.startswith("style"):
            continue
        node_match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[|\{)", line)
        if node_match:
            nodes.add(node_match.group(1))
        if re.search(r"(-->|-.+?->|==>|---|<-.+?->)", line):
            edges += 1
    return len(nodes), edges


def main() -> int:
    if not SOURCE.exists() or not INDEX_JSON.exists():
        print("No diagram source/index found.")
        return 0
    entries = json.loads(INDEX_JSON.read_text(encoding="utf-8"))
    for entry in entries:
        path = REPO / entry["mermaid_source"]
        if path.exists():
            entry["nodes"], entry["edges"] = count_nodes_edges(path.read_text(encoding="utf-8"))
    INDEX_JSON.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")
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
        lines.append(
            f"| `{entry['source_file']}` | {entry['diagram_number']} | "
            f"[`{base}.mmd`](mermaid-source/{base}.mmd) | "
            f"[SVG](svg/{base}.svg) | [PNG](png/{base}.png) | "
            f"{entry['nodes']} | {entry['edges']} |"
        )
    INDEX_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("Diagram index refreshed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
