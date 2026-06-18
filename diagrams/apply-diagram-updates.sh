#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${1:-}"
if [[ -z "${REPO_DIR}" || ! -d "${REPO_DIR}/.git" ]]; then
  echo "ERROR: Provide the path to a local clone of cantrellr/kubeharbor." >&2
  exit 1
fi

cd "${REPO_DIR}"
mkdir -p diagrams/mermaid-source diagrams/svg diagrams/png docs
python3 diagrams/sync-mermaid-markdown.py "${REPO_DIR}"
git status --short
