# Mermaid Diagram Sync Report

Generated: 2026-06-17  
Repository: `cantrellr/kubeharbor`  
Reference pattern: `cantrellr/k8s-mystical-mesh-documents/diagrams`  
Source folder: `diagrams/mermaid-source`

## Source change set analyzed

The kubeharbor system design document Mermaid blocks were exported to source files and linked back from the Markdown document using the same folder contract as the reference documentation repository.

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

- Markdown includes a `Diagram export` line after each Mermaid block.
- Mermaid source files exist for each diagram in `diagrams/mermaid-source`.
- SVG and PNG assets are rendered from Mermaid CLI output, not placeholder exports.
- Diagram index metadata is maintained in Markdown and JSON form.
- The local sync workflow does not depend on GitHub Actions.

## Operational note

Keep Markdown, Mermaid source, SVG exports, PNG exports, and index metadata in the same commit. Otherwise the documentation asset chain will drift.
