# Mermaid Diagram Sync Report

Generated: 2026-06-18  
Repository: `cantrellr/kubeharbor`  
Reference pattern: `cantrellr/k8s-mystical-mesh-documents/diagrams`  
Source folder: `diagrams/mermaid-source`

## Source change set analyzed

The kubeharbor system design document Mermaid blocks are exported to source files and linked back from the Markdown document using the same folder contract as the reference documentation repository.

The current design document is expected to contain:

```text
12 Mermaid blocks
12 Diagram export lines
12 Mermaid source files
12 SVG exports
12 PNG exports
```

## Folder contract

| Folder or file | Purpose |
| --- | --- |
| `diagrams/mermaid-source/` | Source-of-truth Mermaid `.mmd` files. |
| `diagrams/svg/` | Rendered SVG exports for Markdown download links. |
| `diagrams/png/` | Rendered PNG exports for Markdown download links. |
| `diagrams/DIAGRAM-INDEX.md` | Human-readable diagram inventory. |
| `diagrams/DIAGRAM-INDEX.json` | Machine-readable diagram inventory and node/edge metadata. |
| `diagrams/apply-diagram-updates.sh` | Full sync wrapper patterned after the reference repo. |
| `diagrams/sync-mermaid-markdown.py` | Markdown and index synchronization utility patterned after the reference repo. |
| `diagrams/render-mermaid-assets.sh` | kubeharbor-specific local Mermaid CLI renderer because GitHub Actions are not enabled. |

## Export correction

The first generated SVG and PNG files were placeholder/card-style assets and did not reflect Mermaid's rendered layout engine. That was the defect. The corrected process renders each `.mmd` source through Mermaid CLI (`mmdc`) so the checked-in SVG and PNG files match the Mermaid diagrams shown in Markdown.

## Sync hardening correction

The sync process is now strict about Markdown/export bindings. The script fails fast when:

- an indexed Markdown file is missing;
- an indexed Mermaid source file is missing;
- an indexed diagram has zero or multiple matching `Diagram export` lines;
- a Mermaid block is not immediately followed by its matching export line;
- the Markdown file has fewer Mermaid blocks or export lines than the diagram index expects.

This prevents truncated or partially rewritten documentation from being treated as valid.

## Generated assets

| Diagram | Mermaid source | SVG | PNG |
| ---: | --- | --- | --- |
| 01 | `diagrams/mermaid-source/system-design-document-diagram-01.mmd` | `diagrams/svg/system-design-document-diagram-01.svg` | `diagrams/png/system-design-document-diagram-01.png` |
| 02 | `diagrams/mermaid-source/system-design-document-diagram-02.mmd` | `diagrams/svg/system-design-document-diagram-02.svg` | `diagrams/png/system-design-document-diagram-02.png` |
| 03 | `diagrams/mermaid-source/system-design-document-diagram-03.mmd` | `diagrams/svg/system-design-document-diagram-03.svg` | `diagrams/png/system-design-document-diagram-03.png` |
| 04 | `diagrams/mermaid-source/system-design-document-diagram-04.mmd` | `diagrams/svg/system-design-document-diagram-04.svg` | `diagrams/png/system-design-document-diagram-04.png` |
| 05 | `diagrams/mermaid-source/system-design-document-diagram-05.mmd` | `diagrams/svg/system-design-document-diagram-05.svg` | `diagrams/png/system-design-document-diagram-05.png` |
| 06 | `diagrams/mermaid-source/system-design-document-diagram-06.mmd` | `diagrams/svg/system-design-document-diagram-06.svg` | `diagrams/png/system-design-document-diagram-06.png` |
| 07 | `diagrams/mermaid-source/system-design-document-diagram-07.mmd` | `diagrams/svg/system-design-document-diagram-07.svg` | `diagrams/png/system-design-document-diagram-07.png` |
| 08 | `diagrams/mermaid-source/system-design-document-diagram-08.mmd` | `diagrams/svg/system-design-document-diagram-08.svg` | `diagrams/png/system-design-document-diagram-08.png` |
| 09 | `diagrams/mermaid-source/system-design-document-diagram-09.mmd` | `diagrams/svg/system-design-document-diagram-09.svg` | `diagrams/png/system-design-document-diagram-09.png` |
| 10 | `diagrams/mermaid-source/system-design-document-diagram-10.mmd` | `diagrams/svg/system-design-document-diagram-10.svg` | `diagrams/png/system-design-document-diagram-10.png` |
| 11 | `diagrams/mermaid-source/system-design-document-diagram-11.mmd` | `diagrams/svg/system-design-document-diagram-11.svg` | `diagrams/png/system-design-document-diagram-11.png` |
| 12 | `diagrams/mermaid-source/system-design-document-diagram-12.mmd` | `diagrams/svg/system-design-document-diagram-12.svg` | `diagrams/png/system-design-document-diagram-12.png` |

## Validation

Run this from the repo root:

```bash
grep -c '```mermaid' docs/System-Design-Document.md
grep -c 'Diagram export:' docs/System-Design-Document.md
python3 diagrams/sync-mermaid-markdown.py .
./diagrams/apply-diagram-updates.sh .
```

Expected result: 12 Mermaid blocks, 12 export lines, no sync errors, and no unexpected unstaged drift after the wrapper completes.

## Operational note

Keep Markdown, Mermaid source, SVG exports, PNG exports, and index metadata in the same commit. Otherwise the documentation asset chain will drift.
