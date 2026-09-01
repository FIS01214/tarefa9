#!/usr/bin/env bash

set -euo pipefail

shell_paths=(
  scripts/audit_repo_metadata.sh
  scripts/check_repo_about_metadata.sh
  scripts/check_docs.sh
  scripts/check_pr_merge_ready.sh
  scripts/check_pr_metadata_ready.sh
  scripts/ci-central-agent-verify.sh
  scripts/create_or_update_sync_pr.sh
  scripts/ensure_main_branch_ruleset.sh
  scripts/ensure_repo_labels.sh
  scripts/maintain_repo_milestones.sh
  scripts/apply-repo-profile.sh
)

for path in "${shell_paths[@]}"; do
  if [[ -f "${path}" ]]; then
    bash -n "${path}"
  fi
done

bash scripts/check_docs.sh
bash scripts/test_maintain_repo_milestones.sh

policy_command=""
if [[ -f .central-agent/repo-policy.yml ]]; then
  policy_command=$(/usr/bin/python3 - .central-agent/repo-policy.yml <<'PYCODE'
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

in_verification = False
with open(sys.argv[1], encoding="utf-8") as handle:
    for raw_line in handle:
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        if indent == 0:
            in_verification = stripped.split(":", 1)[0].strip() == "verification"
            continue
        if in_verification and stripped.startswith("command:"):
            print(parse_scalar(stripped.split(":", 1)[1]))
            break
PYCODE
)
fi

case "${policy_command}" in
  ""|"bash scripts/ci-central-agent-verify.sh"|"bash ./scripts/ci-central-agent-verify.sh"|"scripts/ci-central-agent-verify.sh"|"./scripts/ci-central-agent-verify.sh")
    ;;
  *)
    bash -c "${policy_command}"
    ;;
esac

git diff --check
