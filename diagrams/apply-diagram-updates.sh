#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./diagrams/apply-diagram-updates.sh /path/to/kubeharbor [render options]
#
# This applies the complete diagram sync unit, following the same operational
# model as cantrellr/k8s-mystical-mesh-documents/diagrams:
#   1. Mermaid source files under diagrams/mermaid-source
#   2. Regenerated SVG exports under diagrams/svg
#   3. Regenerated PNG exports under diagrams/png
#   4. Markdown files that embed/reference those diagrams
#   5. Diagram index node/edge metadata
#
# kubeharbor adds one important local-first control: it renders the SVG/PNG
# exports with Mermaid CLI because GitHub Actions are not enabled for this repo.
# Pass --install-deps to install Mermaid CLI locally under .diagram-tools/.

REPO_DIR="${1:-}"
if [[ -z "${REPO_DIR}" || ! -d "${REPO_DIR}/.git" ]]; then
  echo "ERROR: Provide the path to a local clone of cantrellr/kubeharbor." >&2
  echo "Example: ./diagrams/apply-diagram-updates.sh . --install-deps" >&2
  exit 1
fi
shift || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${REPO_DIR}" && pwd)"
cd "${REPO_DIR}"

mkdir -p diagrams/mermaid-source diagrams/svg diagrams/png docs

# Keep source-of-truth Mermaid files, rendered assets, Markdown, and indexes aligned.
"${SCRIPT_DIR}/render-mermaid-assets.sh" --repo "${REPO_DIR}" --sync-index "$@"

git status --short

# Stage the complete sync unit, including generated diagram assets and Markdown
# files touched by sync-mermaid-markdown.py.
git add \
  diagrams/mermaid-source/system-design-document-diagram-*.mmd \
  diagrams/svg/system-design-document-diagram-*.svg \
  diagrams/png/system-design-document-diagram-*.png \
  diagrams/DIAGRAM-INDEX.md \
  diagrams/DIAGRAM-INDEX.json \
  diagrams/DIAGRAM-SYNC-REPORT.md

if [[ -s .diagram-sync-updated-files.txt ]]; then
  while IFS= read -r file_path; do
    [[ -n "${file_path}" ]] && git add "${file_path}"
  done < .diagram-sync-updated-files.txt
fi
rm -f .diagram-sync-updated-files.txt

if git diff --cached --quiet; then
  echo "No changes staged. The repository is already synchronized."
else
  git commit -m "Synchronize Mermaid diagram documentation and exports"
fi
