# Diagram Rendering Workflow

The kubeharbor system design document uses inline Mermaid diagrams for GitHub preview and checked-in SVG/PNG exports for direct download links.

GitHub Actions are **not required**. Render the exports locally from a normal clone of this repository.

## Source and output paths

| Path | Purpose |
| --- | --- |
| `diagrams/mermaid-source/*.mmd` | Source-of-truth Mermaid diagrams. |
| `diagrams/svg/*.svg` | Rendered SVG exports. |
| `diagrams/png/*.png` | Rendered PNG exports. |
| `docs/System-Design-Document.md` | Markdown document that links to the rendered exports. |
| `diagrams/DIAGRAM-INDEX.md` | Human-readable diagram index. |
| `diagrams/DIAGRAM-INDEX.json` | Machine-readable diagram index. |

## First-time setup and render

From the repository root:

```bash
./diagrams/render-mermaid-assets.sh --repo . --install-deps --sync-index
```

That command installs Mermaid CLI into `.diagram-tools/`, renders all `.mmd` files into SVG and PNG, and refreshes the diagram index/Markdown links.

## Render after Mermaid source changes

```bash
./diagrams/render-mermaid-assets.sh --repo . --sync-index
```

## Wrapper command

The wrapper does the same full sync and passes additional renderer options through:

```bash
./diagrams/apply-diagram-updates.sh . --install-deps
```

## Useful options

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

## Commit workflow

After rendering, review and commit the generated artifacts:

```bash
git status --short
git add diagrams/mermaid-source diagrams/svg diagrams/png diagrams/DIAGRAM-INDEX.md diagrams/DIAGRAM-INDEX.json diagrams/DIAGRAM-SYNC-REPORT.md docs/System-Design-Document.md
git commit -m "Render Mermaid diagram exports"
```
