#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/provision_sync_token_secret.sh [--dry-run] [--repos-file PATH] [--secret-name NAME]

Provision the central-agent sync token into repositories listed in
config/central-agent-sync-consumers.txt.

Environment:
  GH_TOKEN                          GitHub token used by gh for API access
  CENTRAL_AGENT_SYNC_SECRET_VALUE   Secret value to store; defaults to GH_TOKEN

The script reads the secret value from stdin into `gh secret set`, so the token
does not appear in process arguments.
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_FILE="${ROOT_DIR}/config/central-agent-sync-consumers.txt"
SECRET_NAME="CENTRAL_AGENT_SYNC_TOKEN"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --repos-file)
      REPOS_FILE="$2"
      shift 2
      ;;
    --secret-name)
      SECRET_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "${REPOS_FILE}" ]]; then
  echo "repos file not found: ${REPOS_FILE}" >&2
  exit 1
fi

SECRET_VALUE="${CENTRAL_AGENT_SYNC_SECRET_VALUE:-${GH_TOKEN:-}}"
if [[ "${DRY_RUN}" != true && -z "${SECRET_VALUE}" ]]; then
  echo "CENTRAL_AGENT_SYNC_SECRET_VALUE or GH_TOKEN is required" >&2
  exit 1
fi

repos=()
while IFS= read -r repo; do
  repos+=("${repo}")
done < <(
  awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $3 == "source-only" { next }
    { print $1 }
  ' "${REPOS_FILE}" | sort -u
)

if [[ "${#repos[@]}" -eq 0 ]]; then
  echo "No sync workflow consumers found in ${REPOS_FILE}."
  exit 0
fi

for repo in "${repos[@]}"; do
  if [[ "${DRY_RUN}" == true ]]; then
    echo "Would set ${SECRET_NAME} in ${repo}"
    continue
  fi

  printf '%s' "${SECRET_VALUE}" | gh secret set "${SECRET_NAME}" --repo "${repo}"
done
