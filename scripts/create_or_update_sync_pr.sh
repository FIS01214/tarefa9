#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/create_or_update_sync_pr.sh

Create or update the managed central-agent sync pull request for the current
repository checkout, applying the PR governance metadata expected by the
central-agent baseline.

Environment overrides:
  CENTRAL_AGENT_SYNC_PR_BRANCH
  CENTRAL_AGENT_SYNC_PR_BASE
  CENTRAL_AGENT_SYNC_PR_TITLE
  CENTRAL_AGENT_SYNC_PR_COMMIT_MESSAGE
  CENTRAL_AGENT_SYNC_PR_LABELS
  CENTRAL_AGENT_SYNC_PR_ASSIGNEES
  CENTRAL_AGENT_SYNC_PR_MILESTONE
  CENTRAL_AGENT_SYNC_PR_PROJECTS
  CENTRAL_AGENT_SYNC_ISSUE_TITLE
  CENTRAL_AGENT_SYNC_PR_CENTRAL_REPO
  CENTRAL_AGENT_SYNC_PR_CENTRAL_REF
  CENTRAL_AGENT_SYNC_PR_CENTRAL_SHA
USAGE
}

if [[ ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
POLICY_FILE=${CENTRAL_AGENT_REPO_POLICY_FILE:-"${ROOT_DIR}/.central-agent/repo-policy.yml"}

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  GITHUB_REPOSITORY=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi

REPO=${GITHUB_REPOSITORY}
REPO_OWNER=${REPO%%/*}
BRANCH=${CENTRAL_AGENT_SYNC_PR_BRANCH:-chore/sync-central-agent}
BASE=${CENTRAL_AGENT_SYNC_PR_BASE:-${GITHUB_REF_NAME:-main}}
TITLE=${CENTRAL_AGENT_SYNC_PR_TITLE:-chore: sync central-agent baseline}
COMMIT_MESSAGE=${CENTRAL_AGENT_SYNC_PR_COMMIT_MESSAGE:-chore: sync central-agent baseline}
CENTRAL_REPO=${CENTRAL_AGENT_SYNC_PR_CENTRAL_REPO:-diemort/central-agent}
CENTRAL_REF=${CENTRAL_AGENT_SYNC_PR_CENTRAL_REF:-main}
CENTRAL_SHA=${CENTRAL_AGENT_SYNC_PR_CENTRAL_SHA:-local-working-tree}
ISSUE_TITLE=${CENTRAL_AGENT_SYNC_ISSUE_TITLE:-Track central-agent baseline sync}

if [[ ! -f "${POLICY_FILE}" ]]; then
  echo "error: repo policy not found: ${POLICY_FILE}" >&2
  exit 1
fi

mapfile -t policy_rows < <(/usr/bin/python3 - "${POLICY_FILE}" "${REPO_OWNER}" <<'PYCODE'
import sys

path = sys.argv[1]
repo_owner = sys.argv[2]
data = {
    "pr_labels": [],
    "issue_labels": [],
    "assignees": [],
    "milestone": "",
    "projects": [],
    "issue_types_enabled": "false",
    "issue_type_default": "",
    "issue_type_label_map": {},
}
stack = []
current_project = None
with open(path, "r", encoding="utf-8") as handle:
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
            current_project = None
            continue
        if text.startswith("- "):
            value = text[2:].strip().strip('"')
            if stack == ["labels", "required_for_pull_requests"]:
                data["pr_labels"].append(value)
            elif stack == ["labels", "required_for_issues"]:
                data["issue_labels"].append(value)
            elif stack == ["assignees", "required"]:
                data["assignees"].append(value)
            elif stack == ["projects", "required"]:
                current_project = {}
                data["projects"].append(current_project)
                if ":" in value:
                    key, raw_value = value.split(":", 1)
                    current_project[key.strip()] = raw_value.strip().strip('"')
            continue
        if ":" not in text:
            continue
        if stack == ["issue_types", "label_map"] and text.startswith('"') and '":' in text:
            parsed_key, raw_value = text[1:].split('":', 1)
            data["issue_type_label_map"][parsed_key] = raw_value.strip().strip('"')
            continue
        key, raw_value = text.split(":", 1)
        parsed_key = key.strip().strip('"')
        value = raw_value.strip().strip('"')
        if stack == ["milestones"] and key.strip() == "default_title":
            data["milestone"] = value
        elif stack == ["issue_types"]:
            if key.strip() == "enabled":
                data["issue_types_enabled"] = value
            elif key.strip() == "default":
                data["issue_type_default"] = value
        elif stack == ["issue_types", "label_map"]:
            data["issue_type_label_map"][parsed_key] = value
        elif stack == ["projects", "required"] and current_project is not None:
            current_project[key.strip()] = value

if not data["pr_labels"]:
    data["pr_labels"] = ["area:governance", "area:workflow", "type:docs"]
if not data["issue_labels"]:
    data["issue_labels"] = list(data["pr_labels"])
if not data["assignees"]:
    data["assignees"] = [repo_owner]

for key in ("pr_labels", "issue_labels", "assignees"):
    print(f"{key}\t{','.join(data[key])}")
print(f"milestone\t{data['milestone']}")
print(f"issue_type_enabled\t{data['issue_types_enabled']}")
print(f"issue_type_default\t{data['issue_type_default']}")
for label, issue_type in data["issue_type_label_map"].items():
    print(f"issue_type_map\t{label}={issue_type}")
for project in data["projects"]:
    owner = project.get("owner", "")
    number = project.get("number", "")
    title = project.get("title", "")
    if owner and number:
        print(f"project\t{owner}#{number}")
    elif title:
        print(f"project\t{title}")
PYCODE
)

policy_value() {
  local key=$1
  printf '%s\n' "${policy_rows[@]}" | awk -F '\t' -v key="${key}" '$1 == key { print $2; exit }'
}

mapfile -t policy_projects < <(printf '%s\n' "${policy_rows[@]}" | awk -F '\t' '$1 == "project" { print $2 }')

split_csv() {
  local raw=$1
  /usr/bin/python3 - "${raw}" <<'PYCODE'
import sys
for item in sys.argv[1].split(","):
    item = item.strip()
    if item:
        print(item)
PYCODE
}

mapfile -t pr_labels < <(split_csv "${CENTRAL_AGENT_SYNC_PR_LABELS:-$(policy_value pr_labels)}")
mapfile -t issue_labels < <(split_csv "${CENTRAL_AGENT_SYNC_ISSUE_LABELS:-$(policy_value issue_labels)}")
mapfile -t assignees < <(split_csv "${CENTRAL_AGENT_SYNC_PR_ASSIGNEES:-$(policy_value assignees)}")
milestone=${CENTRAL_AGENT_SYNC_PR_MILESTONE:-$(policy_value milestone)}
if [[ -n "${CENTRAL_AGENT_SYNC_PR_PROJECTS:-}" ]]; then
  mapfile -t policy_projects < <(split_csv "${CENTRAL_AGENT_SYNC_PR_PROJECTS}")
fi
issue_type_enabled=$(policy_value issue_type_enabled)
issue_type_default=$(policy_value issue_type_default)
mapfile -t policy_issue_type_maps < <(printf '%s\n' "${policy_rows[@]}" | awk -F '\t' '$1 == "issue_type_map" { print $2 }')

derive_issue_type() {
  local labels_csv=$1
  /usr/bin/python3 - "${labels_csv}" "${issue_type_default}" "${policy_issue_type_maps[@]}" <<'PYCODE'
import sys

labels = [label.strip() for label in sys.argv[1].split(",") if label.strip()]
default = sys.argv[2]
mapping = {}
for entry in sys.argv[3:]:
    if "=" in entry:
        label, issue_type = entry.split("=", 1)
        mapping[label] = issue_type
for label in labels:
    if label in mapping:
        print(mapping[label])
        sys.exit(0)
print(default)
PYCODE
}

join_by_comma() {
  local IFS=,
  echo "$*"
}

sync_issue_type=${CENTRAL_AGENT_SYNC_ISSUE_TYPE:-}
if [[ -z "${sync_issue_type}" && "${issue_type_enabled}" == "true" ]]; then
  sync_issue_type=$(derive_issue_type "$(join_by_comma "${issue_labels[@]}")")
fi

write_output() {
  local key=$1
  local value=$2
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "${key}" "${value}" >> "${GITHUB_OUTPUT}"
  fi
}

ensure_label() {
  local label=$1
  local color=5319e7
  local description="Managed central-agent governance metadata"
  case "${label}" in
    type:feature) color=a2eeef; description="Feature work or new behavior" ;;
    type:bug) color=d73a4a; description="Bug fix or regression repair" ;;
    type:docs) color=0075ca; description="Documentation-only or documentation-heavy work" ;;
    area:governance) color=5319e7; description="Agent, issue, PR, review, or repository governance" ;;
    area:workflow) color=1d76db; description="Local automation, validation, or workflow behavior" ;;
    priority:high) color=b60205; description="High-priority work" ;;
  esac

  if gh label list --repo "${REPO}" --limit 200 --json name --jq '.[].name' | grep -Fxq "${label}"; then
    return
  fi
  gh label create "${label}" --repo "${REPO}" --color "${color}" --description "${description}"
}

add_projects() {
  local item_url=$1
  local target_name=$2
  local project
  for project in "${policy_projects[@]}"; do
    [[ -n "${project}" ]] || continue
    if [[ "${project}" != *"#"* ]]; then
      echo "error: project '${project}' for ${target_name} must be configured as owner#number" >&2
      return 1
    fi
    local owner=${project%%#*}
    local number=${project##*#}
    local output
    if output=$(gh project item-add "${number}" --owner "${owner}" --url "${item_url}" 2>&1); then
      echo "Ensured project ${owner}#${number} for ${target_name}"
    elif grep -qi "already" <<< "${output}"; then
      echo "Project ${owner}#${number} already contains ${target_name}"
    else
      echo "${output}" >&2
      return 1
    fi
  done
}

set_issue_type() {
  local issue_number=$1
  local expected_type=$2
  if [[ -z "${expected_type}" ]]; then
    return 0
  fi

  local repo_name=${REPO##*/}
  local query_result
  if ! query_result=$(gh api graphql \
    -f owner="${REPO_OWNER}" \
    -f repo="${repo_name}" \
    -F number="${issue_number}" \
    -f query='
      query($owner: String!, $repo: String!, $number: Int!) {
        repository(owner: $owner, name: $repo) {
          issue(number: $number) { id issueType { name } }
          owner {
            __typename
            ... on Organization {
              issueTypes(first: 20) { nodes { id name isEnabled } }
            }
          }
        }
      }
    ' 2>/dev/null); then
    echo "Warning: unable to query Issue Type support for issue #${issue_number}; continuing with other metadata." >&2
    return
  fi

  local type_rows
  type_rows=$(ISSUE_TYPE_JSON="${query_result}" EXPECTED_ISSUE_TYPE="${expected_type}" /usr/bin/python3 - <<'PYCODE'
import json
import os
import sys

root = json.loads(os.environ["ISSUE_TYPE_JSON"])
repo = root.get("data", {}).get("repository") or {}
issue = repo.get("issue") or {}
owner = repo.get("owner") or {}
if owner.get("__typename") != "Organization":
    sys.exit(0)
expected = os.environ["EXPECTED_ISSUE_TYPE"]
current = (issue.get("issueType") or {}).get("name") or ""
if current == expected:
    sys.exit(0)
for node in (owner.get("issueTypes") or {}).get("nodes", []):
    if node.get("name") == expected and node.get("isEnabled", True):
        print(issue.get("id", ""))
        print(node.get("id", ""))
        sys.exit(0)
sys.exit(0)
PYCODE
)
  if [[ -z "${type_rows}" ]]; then
    return 0
  fi

  local issue_id issue_type_id
  issue_id=$(printf '%s\n' "${type_rows}" | sed -n '1p')
  issue_type_id=$(printf '%s\n' "${type_rows}" | sed -n '2p')
  if [[ -z "${issue_id}" || -z "${issue_type_id}" ]]; then
    return
  fi

  gh api graphql \
    -F issueId="${issue_id}" \
    -F issueTypeId="${issue_type_id}" \
    -f query='
      mutation($issueId: ID!, $issueTypeId: ID!) {
        updateIssueIssueType(input: {issueId: $issueId, issueTypeId: $issueTypeId}) {
          issue { number issueType { name } }
        }
      }
    ' >/dev/null
  echo "Ensured issue #${issue_number} Issue Type: ${expected_type}"
}

ensure_linked_branch() {
  local issue_number=$1
  if [[ "${CENTRAL_AGENT_SYNC_LINKED_BRANCH:-true}" != "true" ]]; then
    return
  fi

  local linked_branches
  local linked_branch_name=${BRANCH}
  if linked_branches=$(gh issue develop --list "${issue_number}" --repo "${REPO}" 2>/dev/null); then
    if printf '%s\n' "${linked_branches}" | awk '{ print $1 }' | grep -Fxq "${BRANCH}"; then
      return
    fi
  fi

  local output
  if output=$(gh issue develop "${issue_number}" --repo "${REPO}" --base "${BASE}" --name "${linked_branch_name}" 2>&1); then
    echo "Ensured linked development branch for issue #${issue_number}: ${output}"
  else
    echo "Warning: unable to create linked development branch for issue #${issue_number}: ${output}" >&2
  fi
}

edit_issue_metadata() {
  local issue_number=$1
  if [[ -n "${milestone}" ]]; then
    bash "${SCRIPT_DIR}/ensure_repo_milestones.sh" "${REPO}"
  fi
  local label
  for label in "${issue_labels[@]}"; do
    ensure_label "${label}"
    gh issue edit "${issue_number}" --repo "${REPO}" --add-label "${label}"
  done
  local assignee
  for assignee in "${assignees[@]}"; do
    gh issue edit "${issue_number}" --repo "${REPO}" --add-assignee "${assignee}"
  done
  if [[ -n "${milestone}" ]]; then
    gh issue edit "${issue_number}" --repo "${REPO}" --milestone "${milestone}"
  fi
  set_issue_type "${issue_number}" "${sync_issue_type}"
}

edit_pr_metadata() {
  local pr_number=$1
  if [[ -n "${milestone}" ]]; then
    bash "${SCRIPT_DIR}/ensure_repo_milestones.sh" "${REPO}"
  fi
  local label
  for label in "${pr_labels[@]}"; do
    ensure_label "${label}"
    gh pr edit "${pr_number}" --repo "${REPO}" --add-label "${label}"
  done
  local assignee
  for assignee in "${assignees[@]}"; do
    gh pr edit "${pr_number}" --repo "${REPO}" --add-assignee "${assignee}"
  done
  if [[ -n "${milestone}" ]]; then
    gh pr edit "${pr_number}" --repo "${REPO}" --milestone "${milestone}"
  fi
}

find_or_create_issue() {
  local issues_json
  issues_json=$(gh issue list --repo "${REPO}" --state open --limit 100 --json number,title)
  local issue_number
  issue_number=$(ISSUES_JSON="${issues_json}" ISSUE_TITLE="${ISSUE_TITLE}" /usr/bin/python3 - <<'PYCODE'
import json
import os

for issue in json.loads(os.environ["ISSUES_JSON"]):
    if issue.get("title") == os.environ["ISSUE_TITLE"]:
        print(issue["number"])
        break
PYCODE
)
  if [[ -n "${issue_number}" ]]; then
    echo "${issue_number}"
    return
  fi

  local body_file
  body_file=$(mktemp)
  cat > "${body_file}" <<EOF
## Goal
Keep this repository synchronized with the managed central-agent baseline.

## Scope
- Track automated central-agent sync pull requests.
- Preserve repo-local policy and metadata files.
- Confirm PR metadata, documentation review, CI, and Codex review before merge.

## Acceptance Criteria
- Sync PRs link this issue.
- Sync PRs include labels, assignees, and configured milestone or project metadata.
- Sync PRs merge only after the repository merge gate is clear.
EOF
  local created_url
  created_url=$(gh issue create --repo "${REPO}" --title "${ISSUE_TITLE}" --body-file "${body_file}")
  rm -f "${body_file}"
  echo "${created_url##*/}"
}

create_pr_body() {
  local issue_number=$1
  local body_file=$2
  cat > "${body_file}" <<EOF
## Summary
- Sync the managed repo-agent baseline from \`${CENTRAL_REPO}\` at \`${CENTRAL_REF}\`.
- Upstream central-agent commit: \`${CENTRAL_SHA}\`.

Managed paths:
- \`AGENTS.md\`
- \`.agents/skills/\`
- \`.central-agent/source.json\`
- \`config/central-agent-sync-consumers.txt\`
- \`docs/central-agent-design.md\`
- \`scripts/check_pr_merge_ready.sh\`
- \`scripts/check_pr_metadata_ready.sh\`
- \`scripts/test_maintain_repo_milestones.sh\`
- \`scripts/ensure_repo_labels.sh\`
- \`scripts/ensure_repo_milestones.sh\`
- \`scripts/audit_repo_metadata.sh\`
- \`scripts/maintain_repo_milestones.sh\`
- \`scripts/ensure_main_branch_ruleset.sh\`
- \`scripts/create_or_update_sync_pr.sh\`
- \`scripts/provision_sync_token_secret.sh\`

Existing \`.central-agent/repo-policy.yml\` and \`.central-agent/repo-metadata.yml\` files are preserved because they are repo-local contracts.

## Issue Link
Tracks #${issue_number}

## Validation
- The sync helper created or updated this branch with the central-agent-owned PR script.
- The helper applied configured PR metadata before requesting review.
- Local merge validation is available via \`bash scripts/ci-central-agent-verify.sh\` and \`bash scripts/check_pr_merge_ready.sh <pr_number>\`; agents must run it locally and report results in the PR comments/body.
- This section is required by PR metadata policy and must be retained for each generated sync PR.

## Documentation
- Reviewed managed central-agent instructions and \`docs/central-agent-design.md\` as part of this sync.

## Follow-up Work
- None.
EOF
}

request_codex_review() {
  local pr_number=$1
  gh pr comment "${pr_number}" --repo "${REPO}" --body "@codex review"
}

if [[ -n "${GH_TOKEN:-}" ]]; then
  git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
fi

git config user.name "${CENTRAL_AGENT_GIT_NAME:-github-actions[bot]}"
git config user.email "${CENTRAL_AGENT_GIT_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"

git checkout -B "${BRANCH}"
git rm -f --ignore-unmatch .github/workflows/central-agent-dev.yml
git rm -f --ignore-unmatch .github/workflows/sync-central-agent.yml
git add \
  AGENTS.md \
  .agents \
  .central-agent \
  docs/central-agent-design.md \
  scripts/check_pr_merge_ready.sh \
  scripts/check_pr_metadata_ready.sh \
  scripts/test_maintain_repo_milestones.sh \
  scripts/ensure_repo_labels.sh \
  scripts/ensure_repo_milestones.sh \
  scripts/audit_repo_metadata.sh \
  scripts/maintain_repo_milestones.sh \
  scripts/ensure_main_branch_ruleset.sh \
  scripts/create_or_update_sync_pr.sh \
  scripts/provision_sync_token_secret.sh

if [[ -e .github/workflows/validate.yml ]] \
  || git ls-files --error-unmatch .github/workflows/validate.yml >/dev/null 2>&1; then
  git add -A -- .github/workflows/validate.yml
fi
git add -f -- config/central-agent-sync-consumers.txt

for optional_managed_hook in scripts/check_docs.sh scripts/ci-central-agent-verify.sh; do
  git add -A -- "${optional_managed_hook}"
done

if git diff --cached --quiet --exit-code; then
  existing_pr=$(gh pr list --repo "${REPO}" --head "${BRANCH}" --state open --json number --jq '.[0].number // empty')
  if [[ -z "${existing_pr}" ]]; then
    echo "No managed central-agent changes to commit."
    write_output pr_number ""
    write_output pr_url ""
    exit 0
  fi

  echo "No new managed central-agent changes, but sync PR #${existing_pr} is open. Refreshing governance metadata."
  project_metadata_failed=false
  issue_number=$(find_or_create_issue)
  edit_issue_metadata "${issue_number}"
  issue_url="https://github.com/${REPO}/issues/${issue_number}"
  if ! add_projects "${issue_url}" "issue #${issue_number}"; then
    project_metadata_failed=true
  fi
  ensure_linked_branch "${issue_number}"

  body_file=$(mktemp)
  create_pr_body "${issue_number}" "${body_file}"
  gh pr edit "${existing_pr}" --repo "${REPO}" --title "${TITLE}" --body-file "${body_file}"
  rm -f "${body_file}"

  edit_pr_metadata "${existing_pr}"
  pr_url="https://github.com/${REPO}/pull/${existing_pr}"
  if ! add_projects "${pr_url}" "PR #${existing_pr}"; then
    project_metadata_failed=true
  fi

  if [[ "${project_metadata_failed}" == true ]]; then
    echo "Warning: unable to apply all configured project metadata; metadata gate will report remaining blockers." >&2
  fi
  bash scripts/check_pr_metadata_ready.sh "${existing_pr}" "${REPO}"
  request_codex_review "${existing_pr}"
  write_output pr_number "${existing_pr}"
  write_output pr_url "${pr_url}"
  echo "Managed sync PR metadata is ready for review: ${pr_url}"
  exit 0
fi

issue_number=$(find_or_create_issue)
edit_issue_metadata "${issue_number}"
issue_url="https://github.com/${REPO}/issues/${issue_number}"
ensure_linked_branch "${issue_number}"

git commit -m "${COMMIT_MESSAGE}"
remote_branch_sha=$(git ls-remote --heads origin "${BRANCH}" | awk '{ print $1 }')
if [[ -n "${remote_branch_sha}" ]]; then
  git push -u origin "${BRANCH}" --force-with-lease="refs/heads/${BRANCH}:${remote_branch_sha}"
else
  git push -u origin "${BRANCH}" --force-with-lease
fi

body_file=$(mktemp)
create_pr_body "${issue_number}" "${body_file}"

existing_pr=$(gh pr list --repo "${REPO}" --head "${BRANCH}" --state open --json number --jq '.[0].number // empty')
if [[ -n "${existing_pr}" ]]; then
  pr_number=${existing_pr}
  gh pr edit "${pr_number}" --repo "${REPO}" --title "${TITLE}" --body-file "${body_file}"
else
  pr_url=$(gh pr create --repo "${REPO}" --base "${BASE}" --head "${BRANCH}" --title "${TITLE}" --body-file "${body_file}")
  pr_number=${pr_url##*/}
fi
rm -f "${body_file}"

edit_pr_metadata "${pr_number}"
pr_url="https://github.com/${REPO}/pull/${pr_number}"
project_metadata_failed=false
if ! add_projects "${issue_url}" "issue #${issue_number}"; then
  project_metadata_failed=true
fi
if ! add_projects "${pr_url}" "PR #${pr_number}"; then
  project_metadata_failed=true
fi

if [[ "${project_metadata_failed}" == true ]]; then
  echo "Warning: unable to apply all configured project metadata; metadata gate will report remaining blockers." >&2
fi
bash scripts/check_pr_metadata_ready.sh "${pr_number}" "${REPO}"
request_codex_review "${pr_number}"

write_output pr_number "${pr_number}"
write_output pr_url "${pr_url}"
echo "Managed sync PR is ready for review: ${pr_url}"
