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
./diagrams/apply-diagram-updates.sh . --install-deps --install-browser-deps
```

Use `--install-deps` the first time on a workstation that does not already have Mermaid CLI. It installs local tooling under `.diagram-tools/`, which is intentionally ignored by Git.

Use `--install-browser-deps` on minimal Ubuntu/WSL hosts that are missing Puppeteer/Chrome shared libraries.

After dependencies are installed, use:

```bash
./diagrams/apply-diagram-updates.sh .
```

Do **not** run the wrapper with `sudo`. The render operation should run as your normal user. Running the wrapper with `sudo` can hide user-scoped Node.js installs and can leave generated files owned by root.

## Browser shared-library dependencies

Mermaid CLI uses Puppeteer/Chrome to render SVG and PNG files. On minimal Ubuntu or WSL installs, Puppeteer may fail with a missing library error such as:

```text
error while loading shared libraries: libnspr4.so: cannot open shared object file
```

Install the browser dependencies through the repo script:

```bash
./diagrams/apply-diagram-updates.sh . --install-browser-deps
```

Then rerun the normal sync:

```bash
./diagrams/apply-diagram-updates.sh .
```

The browser dependency installer uses `sudo` only for `apt-get`. The renderer itself still runs as your normal user.

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

# Install Mermaid CLI and browser shared-library dependencies in one run.
./diagrams/apply-diagram-updates.sh . --install-deps --install-browser-deps
```

## Dependency model

The renderer looks for Mermaid CLI in this order:

1. `.diagram-tools/node_modules/.bin/mmdc`
2. `diagrams/node_modules/.bin/mmdc`
3. `mmdc` from `PATH`

Use `--install-deps` when Mermaid CLI is not already available.

The renderer also preflights the Puppeteer Chrome binary with `ldd` when a browser binary exists under the Puppeteer cache. If shared libraries are missing, the script fails before the render loop and tells the operator to rerun with `--install-browser-deps`.

## Strict sync guardrails

`sync-mermaid-markdown.py` fails fast when the Markdown and index do not agree. It does **not** silently accept a half-valid document. Current guardrails require:

- every indexed Markdown file must exist;
- every indexed Mermaid source file must exist;
- each indexed diagram must have exactly one matching `Diagram export` line;
- each `Diagram export` line must immediately follow its Mermaid code block;
- the system design document must have at least the expected number of Mermaid blocks and export lines.

For the current system design document, the expected counts are:

```text
12 Mermaid blocks
12 Diagram export lines
```

Quick validation:

```bash
grep -c '```mermaid' docs/System-Design-Document.md
grep -c 'Diagram export:' docs/System-Design-Document.md
python3 diagrams/sync-mermaid-markdown.py .
```

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
