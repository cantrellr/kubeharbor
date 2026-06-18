# kubeharbor documentation maintenance

This document defines how to maintain kubeharbor documentation without creating drift between Markdown, Mermaid source, rendered SVG/PNG files, and index metadata.

## Documentation ownership model

The repo has two documentation layers:

| Layer | Location | Owner action |
| --- | --- | --- |
| Operator docs | `README.md`, `docs/*.md` | Keep install, operations, image transfer, and hardening guidance current with script behavior. |
| Diagram assets | `diagrams/` | Keep Mermaid source, rendered exports, and index metadata synchronized. |

The system design document is both an operator document and a diagram consumer. Treat it as the primary architecture record.

## Source of truth

For diagrams, the source of truth is:

```text
diagrams/mermaid-source/*.mmd
```

The embedded Mermaid blocks in `docs/System-Design-Document.md` are synchronized from those `.mmd` files. The rendered export files are generated from those same `.mmd` files:

```text
diagrams/svg/*.svg
diagrams/png/*.png
```

The indexes are metadata outputs:

```text
diagrams/DIAGRAM-INDEX.md
diagrams/DIAGRAM-INDEX.json
```

## Local render workflow

GitHub Actions are not enabled for this repo. Render locally.

First-time setup on a workstation:

```bash
./diagrams/apply-diagram-updates.sh . --install-deps --install-browser-deps
```

Normal sync after editing diagrams or the system design document:

```bash
./diagrams/apply-diagram-updates.sh .
```

Render only, without the wrapper commit behavior:

```bash
./diagrams/render-mermaid-assets.sh --repo . --sync-index
```

## Do not use sudo for diagram rendering

Do **not** run the diagram renderer or wrapper with `sudo`.

Bad:

```bash
sudo ./diagrams/apply-diagram-updates.sh .
```

Good:

```bash
./diagrams/apply-diagram-updates.sh .
```

The renderer needs the normal user's Node.js/npm environment. Running with `sudo` can hide `node`, break `nvm`/`asdf` paths, and leave root-owned generated files in the repo. The `--install-browser-deps` option uses `sudo` internally only for `apt-get`.

## Required commit unit

When diagrams change, keep the complete asset chain in one commit:

- `docs/System-Design-Document.md`
- `diagrams/mermaid-source/*.mmd`
- `diagrams/svg/*.svg`
- `diagrams/png/*.png`
- `diagrams/DIAGRAM-INDEX.md`
- `diagrams/DIAGRAM-INDEX.json`
- `diagrams/DIAGRAM-SYNC-REPORT.md`

Splitting these files across commits creates drift. The next operator will not know which artifact is authoritative.

## Sync guardrails

`diagrams/sync-mermaid-markdown.py` is intentionally strict. It fails when:

- an indexed Markdown file is missing;
- an indexed Mermaid source file is missing;
- a diagram has zero or multiple matching export lines;
- a Mermaid block is not immediately followed by its matching export line;
- the document has fewer Mermaid blocks or export lines than the index expects.

This is by design. Failing fast is better than silently publishing a truncated or mismatched architecture document.

## Browser dependency remediation

On minimal Ubuntu/WSL hosts, Mermaid CLI can fail when Puppeteer's Chrome binary is missing shared libraries such as `libnspr4.so` or `libnss3.so`.

Fix from the repo root:

```bash
./diagrams/apply-diagram-updates.sh . --install-browser-deps
./diagrams/apply-diagram-updates.sh .
```

The package resolver handles Ubuntu 24.04/Noble `t64` package variants such as `libasound2t64`, `libgtk-3-0t64`, and `libcups2t64`.

## Documentation review checklist

Before merging or pushing documentation updates, validate:

```bash
grep -c '```mermaid' docs/System-Design-Document.md
grep -c 'Diagram export:' docs/System-Design-Document.md
python3 diagrams/sync-mermaid-markdown.py .
git status --short
```

Expected count for the current system design document:

```text
12 Mermaid blocks
12 Diagram export lines
```

If the counts do not match, stop and fix the document before rendering or committing.

## What not to do

- Do not hand-edit SVG or PNG exports.
- Do not commit `.diagram-tools/`.
- Do not commit `.diagram-sync-updated-files.txt`.
- Do not run the renderer as root unless you are deliberately repairing ownership and know the blast radius.
- Do not replace Mermaid diagrams with static images in the system design document. Keep both: live Mermaid for GitHub rendering and linked SVG/PNG exports for portability.
