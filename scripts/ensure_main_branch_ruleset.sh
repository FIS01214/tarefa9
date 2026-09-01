#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/ensure_main_branch_ruleset.sh OWNER/REPO [STATUS_CHECK]

Create or update the repository ruleset expected by central-agent-managed repos.
The ruleset targets main and requires:
- pull requests before merging, with zero required approvals
- all review threads resolved
- the configured required status check to pass when policy defines one
- signed commits
- linear history
- no branch deletions
- no non-fast-forward updates

Requires a GitHub token with Administration write permission for the repository.
USAGE
}

if [[ ${1:-} == "--help" || $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit $([[ ${1:-} == "--help" ]] && echo 0 || echo 1)
fi

REPO=$1
STATUS_CHECK_UNSET="__central_agent_status_check_unset__"
STATUS_CHECK=${2-${STATUS_CHECK_UNSET}}
STRICT_STATUS_CHECKS=true
RULESET_NAME="Main branch protection"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
POLICY_FILE=${CENTRAL_AGENT_REPO_POLICY_FILE:-"${ROOT_DIR}/.central-agent/repo-policy.yml"}

if [[ -f "${POLICY_FILE}" ]]; then
  STRICT_STATUS_CHECKS=$(/usr/bin/python3 - "${POLICY_FILE}" <<'PYCODE'
import sys


def parse_key(line):
    key, separator, _value = line.partition(":")
    if not separator:
        return ""
    return key.strip()


in_branch_ruleset = False
strict = "true"
with open(sys.argv[1], encoding="utf-8") as handle:
    for raw_line in handle:
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        if indent == 0:
            in_branch_ruleset = parse_key(stripped) == "branch_ruleset"
            continue
        if in_branch_ruleset and stripped.startswith("require_strict_status_checks:"):
            value = stripped.split(":", 1)[1].split("#", 1)[0].strip().strip('"').strip("'").lower()
            strict = "false" if value in {"false", "no", "0"} else "true"
            break
print(strict)
PYCODE
  )
fi

if [[ "${STATUS_CHECK}" == "${STATUS_CHECK_UNSET}" && -f "${POLICY_FILE}" ]]; then
  STATUS_CHECK=$(/usr/bin/python3 - "${POLICY_FILE}" <<'PYCODE'
import sys

def parse_scalar(value):
    value = value.strip()
    if not value:
        return ""
    if value[0] in ("'", '"'):
        quote = value[0]
        escaped = False
        result = []
        for char in value[1:]:
            if quote == '"' and escaped:
                result.append(char)
                escaped = False
                continue
            if quote == '"' and char == "\\":
                escaped = True
                continue
            if char == quote:
                return "".join(result)
            result.append(char)
        return "".join(result)

    result = []
    for index, char in enumerate(value):
        if char == "#" and (index == 0 or value[index - 1].isspace()):
            break
        result.append(char)
    return "".join(result).strip()

def parse_key(line):
    key, separator, _value = line.partition(":")
    if not separator:
        return ""
    return key.strip()

in_branch_ruleset = False
found = False
with open(sys.argv[1], encoding="utf-8") as handle:
    for raw_line in handle:
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        if indent == 0:
            in_branch_ruleset = parse_key(stripped) == "branch_ruleset"
            continue
        if in_branch_ruleset and stripped.startswith("required_status_check:"):
            print(parse_scalar(stripped.split(":", 1)[1]))
            found = True
            break
if not found:
    print("__central_agent_status_check_unset__")
PYCODE
)
fi
if [[ "${STATUS_CHECK}" == "${STATUS_CHECK_UNSET}" ]]; then
  STATUS_CHECK=validate
fi

payload_file=$(mktemp)
trap 'rm -f "${payload_file}"' EXIT

python3 - "${payload_file}" "${RULESET_NAME}" "${STATUS_CHECK}" "${STRICT_STATUS_CHECKS}" <<'PYCODE'
import json
import sys

payload_path, ruleset_name, status_check, strict_status_checks = sys.argv[1:5]
strict_required_status_checks = strict_status_checks.lower() != "false"
payload = {
    "name": ruleset_name,
    "target": "branch",
    "enforcement": "active",
    "bypass_actors": [],
    "conditions": {
        "ref_name": {
            "include": ["refs/heads/main"],
            "exclude": [],
        }
    },
    "rules": [
        {"type": "deletion"},
        {"type": "non_fast_forward"},
        {"type": "required_linear_history"},
        {"type": "required_signatures"},
        {
            "type": "pull_request",
            "parameters": {
                "allowed_merge_methods": ["squash", "rebase"],
                "dismiss_stale_reviews_on_push": False,
                "require_code_owner_review": False,
                "require_last_push_approval": False,
                "required_approving_review_count": 0,
                "required_review_thread_resolution": True,
                "required_reviewers": [],
            },
        },
    ],
}
if status_check:
    payload["rules"].append({
        "type": "required_status_checks",
        "parameters": {
            "strict_required_status_checks_policy": strict_required_status_checks,
            "do_not_enforce_on_create": False,
            "required_status_checks": [{"context": status_check}],
        },
    })
with open(payload_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PYCODE

ruleset_id=$(gh api "repos/${REPO}/rulesets?includes_parents=false" --jq '
  (.[] | select(.name == "Main branch protection" and .target == "branch") | .id),
  (.[] | select(.name == "Validation" and .target == "branch") | .id)
' | head -n 1)

if [[ -n "${ruleset_id}" ]]; then
  gh api --method PUT "repos/${REPO}/rulesets/${ruleset_id}" --input "${payload_file}" >/dev/null
  echo "Updated ${RULESET_NAME} ruleset ${ruleset_id} for ${REPO}."
else
  created_id=$(gh api --method POST "repos/${REPO}/rulesets" --input "${payload_file}" --jq .id)
  echo "Created ${RULESET_NAME} ruleset ${created_id} for ${REPO}."
fi

gh api "repos/${REPO}/rules/branches/main" --jq '
  .[] | select(.ruleset_source == "'"${REPO}"'") | {type, parameters, ruleset_id, ruleset_source}
'
