#!/usr/bin/env bash
set -euo pipefail

# Apply the full local diagram sync workflow for kubeharbor.
#
# This wrapper renders Mermaid source diagrams into SVG/PNG exports and then
# refreshes Markdown/index metadata. It does not require GitHub Actions.
#
# Usage:
#   ./diagrams/apply-diagram-updates.sh /path/to/kubeharbor
#   ./diagrams/apply-diagram-updates.sh /path/to/kubeharbor --install-deps
#
# Extra arguments are passed to render-mermaid-assets.sh.

REPO_DIR="${1:-}"
if [[ -z "${REPO_DIR}" ]]; then
  echo "ERROR: Provide the path to a local clone of cantrellr/kubeharbor." >&2
  echo "Example: ./diagrams/apply-diagram-updates.sh . --install-deps" >&2
  exit 1
fi
shift || true

REPO_DIR="$(cd "${REPO_DIR}" && pwd)"
if [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "ERROR: Repo path does not look like a Git clone: ${REPO_DIR}" >&2
  exit 1
fi

cd "${REPO_DIR}"
mkdir -p diagrams/mermaid-source diagrams/svg diagrams/png docs

./diagrams/render-mermaid-assets.sh --repo "${REPO_DIR}" --sync-index "$@"

git status --short

cat <<'EOF'

Diagram sync complete.

Commit the updated diagram artifacts when the output looks correct:
  git add diagrams/mermaid-source diagrams/svg diagrams/png diagrams/DIAGRAM-INDEX.md diagrams/DIAGRAM-INDEX.json diagrams/DIAGRAM-SYNC-REPORT.md docs/System-Design-Document.md
  git commit -m "Render Mermaid diagram exports"
EOF
