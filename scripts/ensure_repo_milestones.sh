#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/ensure_repo_milestones.sh OWNER/REPO

Create or update milestones declared in .central-agent/repo-policy.yml.

For tests, set CENTRAL_AGENT_REPO_MILESTONES_PRINT_ONLY=true.
USAGE
}

if [[ ${1:-} == "--help" || $# -ne 1 ]]; then
  usage
  exit $([[ ${1:-} == "--help" ]] && echo 0 || echo 1)
fi

REPO=$1
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
POLICY_FILE=${CENTRAL_AGENT_REPO_POLICY_FILE:-"${ROOT_DIR}/.central-agent/repo-policy.yml"}

if [[ ! -f "${POLICY_FILE}" ]]; then
  echo "error: repo policy not found: ${POLICY_FILE}" >&2
  exit 1
fi

milestone_rows=$(/usr/bin/python3 - "${POLICY_FILE}" <<'PYCODE'
import sys

path = sys.argv[1]
stack = []
current = None
milestones = {}
order = []


def add_milestone(title, description="", due_on=""):
    if not title:
        return
    if title not in milestones:
        milestones[title] = {"title": title, "description": "", "due_on": ""}
        order.append(title)
    if description:
        milestones[title]["description"] = description
    if due_on:
        milestones[title]["due_on"] = due_on


with open(path, encoding="utf-8") as handle:
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
                    current[key.strip()] = raw_value.strip().strip('"')
                    if key.strip() == "title":
                        add_milestone(current["title"])
                continue
        if ":" not in text:
            continue
        key, raw_value = text.split(":", 1)
        key = key.strip()
        value = raw_value.strip().strip('"')
        if stack == ["milestones"] and key in ("default_title", "triage_title"):
            add_milestone(value)
        elif stack == ["milestones", "definitions"] and current is not None:
            current[key] = value
            if key == "title":
                add_milestone(value)
            elif current.get("title"):
                add_milestone(
                    current.get("title", ""),
                    current.get("description", ""),
                    current.get("due_on", ""),
                )

for title in order:
    milestone = milestones[title]
    print(f"{milestone['title']}\t{milestone['description']}\t{milestone['due_on']}")
PYCODE
)

if [[ -z "${milestone_rows}" ]]; then
  echo "No configured milestones."
  exit 0
fi

if [[ ${CENTRAL_AGENT_REPO_MILESTONES_PRINT_ONLY:-false} == "true" ]]; then
  printf '%s\n' "${milestone_rows}"
  exit 0
fi

owner=${REPO%%/*}
repo_name=${REPO##*/}
existing_json=$(gh api --paginate --slurp "repos/${owner}/${repo_name}/milestones?state=all&per_page=100")

while IFS=$'\t' read -r title description due_on; do
  [[ -n "${title}" ]] || continue
  number=$(
    EXISTING_JSON="${existing_json}" TITLE="${title}" /usr/bin/python3 - <<'PYCODE'
import json
import os

def flatten_pages(value):
    if isinstance(value, list):
        flattened = []
        for item in value:
            if isinstance(item, list):
                flattened.extend(item)
            else:
                flattened.append(item)
        return flattened
    return [value]


items = flatten_pages(json.loads(os.environ["EXISTING_JSON"]))
for item in items:
    if item.get("title") == os.environ["TITLE"]:
        print(item.get("number", ""))
        break
PYCODE
  )
  if [[ -n "${number}" ]]; then
    args=(api -X PATCH "repos/${owner}/${repo_name}/milestones/${number}" -f title="${title}")
    [[ -n "${description}" ]] && args+=(-f description="${description}")
    [[ -n "${due_on}" ]] && args+=(-f due_on="${due_on}")
    gh "${args[@]}" >/dev/null
    echo "Updated milestone: ${title}"
  else
    args=(api -X POST "repos/${owner}/${repo_name}/milestones" -f title="${title}")
    [[ -n "${description}" ]] && args+=(-f description="${description}")
    [[ -n "${due_on}" ]] && args+=(-f due_on="${due_on}")
    gh "${args[@]}" >/dev/null
    echo "Created milestone: ${title}"
  fi
done <<< "${milestone_rows}"
