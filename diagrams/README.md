# Diagram Rendering Workflow

The kubeharbor diagram folder follows the same documentation asset pattern used by `cantrellr/k8s-mystical-mesh-documents/diagrams`:

- Mermaid source files live in `diagrams/mermaid-source/`.
- Rendered SVG exports live in `diagrams/svg/`.
- Rendered PNG exports live in `diagrams/png/`.
- `DIAGRAM-INDEX.md` provides a human-readable diagram inventory.
- `DIAGRAM-INDEX.json` provides machine-readable diagram metadata.
- `DIAGRAM-SYNC-REPORT.md` documents the export and sync contract.
- `apply-diagram-updates.sh` applies the complete diagram sync unit.
- `sync-mermaid-markdown.py` keeps Markdown Mermaid blocks and index metadata aligned with the `.mmd` files.

The only intentional kubeharbor difference is that SVG/PNG exports are rendered locally with Mermaid CLI because GitHub Actions are not enabled.

## Source and output paths

| Path | Purpose |
| --- | --- |
| `diagrams/mermaid-source/*.mmd` | Source-of-truth Mermaid diagrams. |
| `diagrams/svg/*.svg` | Rendered SVG exports. |
| `diagrams/png/*.png` | Rendered PNG exports. |
| `docs/System-Design-Document.md` | Markdown document that embeds Mermaid blocks and links to rendered exports. |
| `diagrams/DIAGRAM-INDEX.md` | Human-readable diagram index. |
| `diagrams/DIAGRAM-INDEX.json` | Machine-readable diagram index. |

## Recommended full sync

From the repository root, run the wrapper. This mirrors the reference repo's workflow and commits the complete sync unit when changes are staged.

```bash
./diagrams/apply-diagram-updates.sh . --install-deps
```

Use `--install-deps` the first time on a workstation that does not already have Mermaid CLI. It installs local tooling under `.diagram-tools/`, which is intentionally ignored by Git.

After dependencies are installed, use:

```bash
./diagrams/apply-diagram-updates.sh .
```

## Render only

Use the lower-level renderer when you want to generate SVG/PNG files without automatically staging and committing the full sync unit.

```bash
./diagrams/render-mermaid-assets.sh --repo . --sync-index
```

## Useful render options

```bash
# Clean previous exports first.
./diagrams/render-mermaid-assets.sh --repo . --clean --sync-index

# Render with a different Mermaid theme.
./diagrams/render-mermaid-assets.sh --repo . --theme dark --background transparent --sync-index

# Render larger PNG files.
./diagrams/render-mermaid-assets.sh --repo . --scale 3 --sync-index
```

## Dependency model

The renderer looks for Mermaid CLI in this order:

1. `.diagram-tools/node_modules/.bin/mmdc`
2. `diagrams/node_modules/.bin/mmdc`
3. `mmdc` from `PATH`

Use `--install-deps` when Mermaid CLI is not already available.

## Operator contract

Keep these files in the same commit whenever diagrams change:

- `diagrams/mermaid-source/*.mmd`
- `diagrams/svg/*.svg`
- `diagrams/png/*.png`
- `diagrams/DIAGRAM-INDEX.md`
- `diagrams/DIAGRAM-INDEX.json`
- `diagrams/DIAGRAM-SYNC-REPORT.md`
- Any Markdown files updated by `sync-mermaid-markdown.py`, especially `docs/System-Design-Document.md`

Splitting the Mermaid source, rendered exports, and Markdown links across separate commits creates diagram drift. Do not do that.
