#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/ensure_repo_labels.sh OWNER/REPO

Create or update labels declared in .central-agent/repo-policy.yml.
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

label_rows=$(/usr/bin/python3 - "${POLICY_FILE}" <<'PYCODE'
import sys

labels = {}
label_order = []
current = None
stack = []
in_definitions = False
DEFAULT_LABELS = {
    "type:feature": ("a2eeef", "Feature work or new behavior"),
    "type:bug": ("d73a4a", "Bug fix or regression repair"),
    "type:docs": ("0075ca", "Documentation-only or documentation-heavy work"),
    "area:governance": ("5319e7", "Agent, issue, PR, review, or repository governance"),
    "area:workflow": ("1d76db", "Local automation, validation, or workflow behavior"),
    "priority:high": ("b60205", "High-priority work"),
}


def clean(value):
    return value.strip().strip('"')


def add_label(name, color="", description=""):
    if not name:
        return
    if not color and name in DEFAULT_LABELS:
        color = DEFAULT_LABELS[name][0]
    if not description and name in DEFAULT_LABELS:
        description = DEFAULT_LABELS[name][1]
    if name not in labels:
        labels[name] = {
            "name": name,
            "color": color or "ededed",
            "description": description or "Managed by central-agent policy",
        }
        label_order.append(name)
        return
    if color:
        labels[name]["color"] = color
    if description:
        labels[name]["description"] = description


with open(sys.argv[1], "r", encoding="utf-8") as handle:
    for raw_line in handle:
        line = raw_line.rstrip("\n")
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))

        if not stripped.startswith("- ") and stripped.endswith(":"):
            key = stripped[:-1]
            if indent == 0:
                stack = [key]
            elif indent == 2:
                stack = stack[:1] + [key]
            elif indent == 4:
                stack = stack[:2] + [key]
            if stack == ["labels", "definitions"]:
                in_definitions = True
            else:
                in_definitions = False
                current = None
            continue

        if stripped.startswith("- "):
            value = clean(stripped[2:])
            if stack in (
                ["labels", "apply_when_present"],
                ["labels", "required_for_issues"],
                ["labels", "required_for_pull_requests"],
            ):
                add_label(value)
            elif stack == ["labels", "definitions"]:
                current = {}
                if value.startswith("name:"):
                    current["name"] = clean(value.split(":", 1)[1])
                    add_label(current["name"])
                in_definitions = True
            continue

        if indent == 2 and stripped == "definitions:":
            in_definitions = True
            continue
        if in_definitions and indent <= 2 and not stripped.startswith("- "):
            in_definitions = False
        if not in_definitions:
            continue
        if indent == 4 and stripped.startswith("- name:"):
            current = {"name": clean(stripped.split(":", 1)[1]), "color": "", "description": ""}
            add_label(current["name"])
        elif current is not None and indent == 6 and ":" in stripped:
            key, value = stripped.split(":", 1)
            current[key.strip()] = clean(value)
            if current.get("name"):
                add_label(
                    current["name"],
                    current.get("color", ""),
                    current.get("description", ""),
                )

for name in label_order:
    label = labels[name]
    print(f"{label['name']}\t{label.get('color', '')}\t{label.get('description', '')}")
PYCODE
)

if [[ ${CENTRAL_AGENT_REPO_LABELS_PRINT_ONLY:-false} == "true" ]]; then
  printf '%s\n' "${label_rows}"
  exit 0
fi

while IFS=$'\t' read -r name color description; do
  [[ -n "${name}" ]] || continue
  if gh label list --repo "${REPO}" --limit 200 --json name --jq '.[].name' | grep -Fxq "${name}"; then
    gh label edit "${name}" --repo "${REPO}" --color "${color}" --description "${description}"
    echo "Updated label: ${name}"
  else
    gh label create "${name}" --repo "${REPO}" --color "${color}" --description "${description}"
    echo "Created label: ${name}"
  fi
done <<< "${label_rows}"
