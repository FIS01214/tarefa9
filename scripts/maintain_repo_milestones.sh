#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/maintain_repo_milestones.sh OWNER/REPO --close-complete

Close open milestones only when they have no open issues and no open pull
requests assigned to them.

For tests, set CENTRAL_AGENT_MILESTONE_MAINTENANCE_JSON.
USAGE
}

if [[ ${1:-} == "--help" || $# -ne 2 || ${2:-} != "--close-complete" ]]; then
  usage
  exit $([[ ${1:-} == "--help" ]] && echo 0 || echo 1)
fi

REPO=$1
owner=${REPO%%/*}
repo_name=${REPO##*/}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
POLICY_FILE=${CENTRAL_AGENT_REPO_POLICY_FILE:-"${ROOT_DIR}/.central-agent/repo-policy.yml"}

if [[ -n "${CENTRAL_AGENT_MILESTONE_MAINTENANCE_JSON:-}" ]]; then
  maintenance_json=${CENTRAL_AGENT_MILESTONE_MAINTENANCE_JSON}
else
  maintenance_json=$(gh api graphql \
    -f owner="${owner}" \
    -f repo="${repo_name}" \
    -f query='
      query($owner: String!, $repo: String!) {
        repository(owner: $owner, name: $repo) {
          milestones(first: 100, states: OPEN) {
            nodes {
              number
              title
              issues(first: 1, states: OPEN) { totalCount }
              pullRequests(first: 1, states: OPEN) { totalCount }
            }
          }
        }
      }
    ')
fi

mapfile -t complete_rows < <(MILESTONE_JSON="${maintenance_json}" POLICY_FILE="${POLICY_FILE}" /usr/bin/python3 - <<'PYCODE'
import json
import os


def configured_delivery_milestones(path):
    protected = set()
    definitions = set()
    stack = []
    current = None
    try:
        handle = open(path, encoding="utf-8")
    except OSError:
        return set()
    with handle:
        for raw_line in handle:
            if not raw_line.strip() or raw_line.lstrip().startswith("#"):
                continue
            indent = len(raw_line) - len(raw_line.lstrip(" "))
            text = raw_line.strip()
            if not text.startswith("- ") and text.endswith(":"):
                key = text[:-1]
                if indent == 0:
                    stack = [key]
                elif indent == 2:
                    stack = stack[:1] + [key]
                elif indent == 4:
                    stack = stack[:2] + [key]
                current = None
                continue
            if text.startswith("- "):
                value = text[2:].strip()
                if stack == ["milestones", "definitions"]:
                    current = {}
                    if ":" in value:
                        key, raw_value = value.split(":", 1)
                        key = key.strip()
                        value = raw_value.strip().strip('"')
                        current[key] = value
                        if key == "title" and value:
                            definitions.add(value)
                    continue
            if ":" not in text:
                continue
            key, raw_value = text.split(":", 1)
            key = key.strip()
            value = raw_value.strip().strip('"')
            if stack == ["milestones"] and key in ("default_title", "triage_title") and value:
                protected.add(value)
            elif stack == ["milestones", "definitions"] and current is not None:
                current[key] = value
                if key == "title" and value:
                    definitions.add(value)
    return definitions - protected


root = json.loads(os.environ["MILESTONE_JSON"])
milestones = root.get("data", {}).get("repository", {}).get("milestones", {}).get("nodes", [])
if not milestones and "milestones" in root:
    milestones = root["milestones"]
closable_titles = configured_delivery_milestones(os.environ["POLICY_FILE"])
for milestone in milestones:
    title = milestone.get("title") or ""
    if title not in closable_titles:
        continue
    open_issues = (milestone.get("issues") or {}).get("totalCount", 0)
    open_prs = (milestone.get("pullRequests") or {}).get("totalCount", 0)
    if open_issues == 0 and open_prs == 0:
        print(f"{milestone.get('number')}\t{title}")
PYCODE
)

if [[ ${#complete_rows[@]} -eq 0 ]]; then
  echo "No completed open milestones to close."
  exit 0
fi

for row in "${complete_rows[@]}"; do
  number=${row%%$'\t'*}
  title=${row#*$'\t'}
  if [[ -z "${CENTRAL_AGENT_MILESTONE_MAINTENANCE_JSON:-}" ]]; then
    gh api -X PATCH "repos/${owner}/${repo_name}/milestones/${number}" -f state=closed >/dev/null
  fi
  echo "Closed completed milestone: ${title}"
done
