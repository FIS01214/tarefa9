#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/check_pr_metadata_ready.sh PR_NUMBER [REPO]

Verify configured PR and linked-issue metadata before merge:
- required PR body sections
- linked issue
- configured labels
- configured assignees
- configured milestone
- PR milestone matches every governing issue milestone
- configured Projects v2 membership
- native GitHub Issue Type when configured and exposed
- issue-to-branch Development linkage when configured and exposed

For tests, set CENTRAL_AGENT_PR_METADATA_JSON.
USAGE
}

if [[ ${1:-} == "--help" || $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit $([[ ${1:-} == "--help" ]] && echo 0 || echo 1)
fi

PR_NUMBER=$1
REPO=${2:-${GITHUB_REPOSITORY:-}}
if [[ -z "${REPO}" ]]; then
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
POLICY_FILE=${CENTRAL_AGENT_REPO_POLICY_FILE:-"${ROOT_DIR}/.central-agent/repo-policy.yml"}

if [[ -n "${CENTRAL_AGENT_PR_METADATA_JSON:-}" ]]; then
  metadata_json=${CENTRAL_AGENT_PR_METADATA_JSON}
else
  owner=${REPO%%/*}
  repo_name=${REPO##*/}
  metadata_json=$(gh api graphql     -f owner="${owner}"     -f repo="${repo_name}"     -F number="${PR_NUMBER}"     -f query='
      query($owner: String!, $repo: String!, $number: Int!) {
        repository(owner: $owner, name: $repo) {
          owner {
            __typename
            ... on Organization {
              issueTypes(first: 20) { nodes { name isEnabled } }
            }
          }
          pullRequest(number: $number) {
            number
            headRefOid
            headRefName
            body
            labels(first: 50) { nodes { name } }
            milestone { title }
            assignees(first: 20) { nodes { login } }
            projectItems(first: 50) { nodes { project { number title owner { __typename ... on User { login } ... on Organization { login } } } } }
            closingIssuesReferences(first: 20) {
              nodes {
                number
                title
                repository { nameWithOwner }
                issueType { name }
                linkedBranches(first: 20) { nodes { ref { name target { oid } } } }
                labels(first: 50) { nodes { name } }
                milestone { title }
                assignees(first: 20) { nodes { login } }
                projectItems(first: 50) { nodes { project { number title owner { __typename ... on User { login } ... on Organization { login } } } } }
              }
            }
          }
        }
      }
    ')
fi

REPO="${REPO}" POLICY_FILE="${POLICY_FILE}" METADATA_JSON="${metadata_json}" /usr/bin/python3 - <<'PYCODE'
import json
import os
import re
import subprocess
import sys


def parse_policy(path):
    policy = {
        "required_issue_labels": [],
        "required_pr_labels": [],
        "required_assignees": [],
        "required_sections": [],
        "milestone": "",
        "configured_milestones": [],
        "triage_milestone": "",
        "require_milestone": None,
        "allow_milestone_mismatch": False,
        "projects": [],
        "require_issue_link": False,
        "require_validation_summary": False,
        "require_documentation_review": False,
        "issue_types_enabled": False,
        "issue_type_default": "",
        "issue_type_label_map": {},
        "require_development_linkage": False,
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
                if stack == ["milestones", "definitions"] and ":" in value:
                    item_key, item_value = value.split(":", 1)
                    if item_key.strip() == "title":
                        parsed_value = item_value.strip().strip('"')
                        if parsed_value:
                            policy["configured_milestones"].append(parsed_value)
                    continue
                if stack == ["labels", "required_for_issues"]:
                    policy["required_issue_labels"].append(value)
                elif stack == ["labels", "required_for_pull_requests"]:
                    policy["required_pr_labels"].append(value)
                elif stack == ["assignees", "required"]:
                    policy["required_assignees"].append(value)
                elif stack == ["pull_request_policy", "pr_body_sections"]:
                    policy["required_sections"].append(value)
                elif stack == ["projects", "required"]:
                    current_project = {}
                    policy["projects"].append(current_project)
                    if ":" in value:
                        key, raw_value = value.split(":", 1)
                        current_project[key.strip()] = raw_value.strip().strip('"')
                continue
            if ":" not in text:
                continue
            if stack == ["issue_types", "label_map"] and text.startswith('"') and '":' in text:
                parsed_key, raw_value = text[1:].split('":', 1)
                policy["issue_type_label_map"][parsed_key] = raw_value.strip().strip('"')
                continue
            key, raw_value = text.split(":", 1)
            parsed_key = key.strip().strip('"')
            value = raw_value.strip().strip('"')
            if stack == ["milestones"] and key.strip() == "default_title":
                policy["milestone"] = value
                if value:
                    policy["configured_milestones"].append(value)
            elif stack == ["milestones"] and key.strip() in ("require_for_non_trivial_work", "require_for_major_work"):
                policy["require_milestone"] = value == "true"
            elif stack == ["milestones"] and key.strip() == "triage_title":
                policy["triage_milestone"] = value
                if value:
                    policy["configured_milestones"].append(value)
            elif stack == ["milestones"] and key.strip() == "allow_pr_issue_mismatch":
                policy["allow_milestone_mismatch"] = value == "true"
            elif stack == ["milestones", "definitions"] and key.strip() == "title":
                if value:
                    policy["configured_milestones"].append(value)
            elif stack == ["pull_request_policy"]:
                if key.strip() == "require_issue_link":
                    policy["require_issue_link"] = value == "true"
                elif key.strip() == "require_development_linkage_when_available":
                    policy["require_development_linkage"] = value == "true"
                elif key.strip() == "require_validation_summary":
                    policy["require_validation_summary"] = value == "true"
                elif key.strip() == "require_documentation_review":
                    policy["require_documentation_review"] = value == "true"
            elif stack == ["issue_types"]:
                if key.strip() == "enabled":
                    policy["issue_types_enabled"] = value == "true"
                elif key.strip() == "default":
                    policy["issue_type_default"] = value
            elif stack == ["issue_types", "label_map"]:
                policy["issue_type_label_map"][parsed_key] = value
            elif stack == ["projects", "required"] and current_project is not None:
                parsed = value
                if key.strip() == "number":
                    try:
                        parsed = int(value)
                    except ValueError:
                        pass
                current_project[key.strip()] = parsed
    if policy["require_milestone"] is None:
        policy["require_milestone"] = bool(policy["configured_milestones"])
    return policy


def names(nodes):
    return {node.get("name") for node in nodes if node.get("name")}


def logins(nodes):
    return {node.get("login") for node in nodes if node.get("login")}


def project_keys(nodes):
    keys = set()
    for item in nodes:
        project = item.get("project") or {}
        owner = project.get("owner") or {}
        owner_login = owner.get("login") or ""
        number = project.get("number")
        title = project.get("title") or ""
        if owner_login and number is not None:
            keys.add((owner_login, int(number)))
        if title:
            keys.add(("", title))
    return keys


def issue_numbers_from_body(body, repo=None):
    text = body or ""
    numbers = {int(number) for number in re.findall(r"(?<![\w/])#([0-9]+)", text)}
    current_repo = repo.lower() if repo else None
    for owner, repo_name, number in re.findall(r"(?<![\w.-])([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)#([0-9]+)", text):
        if current_repo and f"{owner}/{repo_name}".lower() != current_repo:
            continue
        numbers.add(int(number))
    for owner, repo_name, number in re.findall(r"https?://github\.com/([^/\s]+)/([^/\s]+)/issues/([0-9]+)", text):
        if current_repo and f"{owner}/{repo_name}".lower() != current_repo:
            continue
        numbers.add(int(number))
    return sorted(numbers)


def issue_link_section(body):
    match = re.search(r"(?ims)^##+\s+Issue Link\s*$([\s\S]*?)(?=^##+\s+|\Z)", body or "")
    return match.group(1) if match else body


def fetch_issue(repo, number):
    owner, repo_name = repo.split("/", 1)
    raw = subprocess.check_output([
        "gh", "api", "graphql",
        "-f", f"owner={owner}",
        "-f", f"repo={repo_name}",
        "-F", f"number={number}",
        "-f", "query="
        "query($owner: String!, $repo: String!, $number: Int!) {"
        "  repository(owner: $owner, name: $repo) {"
        "    issue(number: $number) {"
        "      number"
        "      title"
        "      repository { nameWithOwner }"
        "      issueType { name }"
        "      linkedBranches(first: 20) { nodes { ref { name target { oid } } } }"
        "      labels(first: 50) { nodes { name } }"
        "      milestone { title }"
        "      assignees(first: 20) { nodes { login } }"
        "      projectItems(first: 50) { nodes { project { number title owner { __typename ... on User { login } ... on Organization { login } } } } }"
        "    }"
        "  }"
        "}",
    ], text=True)
    return json.loads(raw).get("data", {}).get("repository", {}).get("issue")


def missing_project_messages(actual_nodes, required_projects, target_name):
    actual = project_keys(actual_nodes)
    missing = []
    for project in required_projects:
        owner = project.get("owner") or ""
        number = project.get("number")
        title = project.get("title") or ""
        found = False
        if owner and number is not None:
            found = (owner, int(number)) in actual
        elif title and ("", title) in actual:
            found = True
        if not found:
            label = f"{owner}#{number}" if owner and number is not None else title
            missing.append(f"{target_name} missing project: {label}")
    return missing


def has_section(body, section):
    return re.search(rf"(?im)^##+\s+{re.escape(section)}\s*$", body or "") is not None


def issue_matches_repo(issue, repo):
    issue_repo = (issue.get("repository") or {}).get("nameWithOwner")
    return issue_repo is None or issue_repo.lower() == repo.lower()


def issue_type_name(issue):
    issue_type = issue.get("issueType") or {}
    return issue_type.get("name") or ""


def linked_branch_refs(issue):
    linked = issue.get("linkedBranches")
    if not isinstance(linked, dict):
        return None
    branches = []
    for node in linked.get("nodes", []):
        ref = node.get("ref") or {}
        if ref.get("name"):
            branches.append({
                "name": ref["name"],
                "oid": (ref.get("target") or {}).get("oid") or "",
            })
    return branches


def cli_linked_branch_refs(repo, issue_number):
    if issue_number is None:
        return []
    try:
        raw = subprocess.check_output([
            "gh", "issue", "develop", "--list", str(issue_number), "--repo", repo,
        ], stderr=subprocess.DEVNULL, text=True)
    except (OSError, subprocess.CalledProcessError):
        return []
    branches = []
    for line in raw.splitlines():
        parts = line.split()
        if parts:
            branches.append({"name": parts[0], "oid": ""})
    return branches


def linked_branch_matches_head(linked_ref, head_ref_name, head_ref_oid):
    if not head_ref_name and not head_ref_oid:
        return True
    if head_ref_name and linked_ref.get("name") == head_ref_name:
        return True
    return bool(head_ref_oid and linked_ref.get("oid") == head_ref_oid)


def expected_issue_type(issue, policy):
    if not policy["issue_types_enabled"]:
        return ""
    issue_label_names = names(issue.get("labels", {}).get("nodes", []))
    for label, issue_type in policy["issue_type_label_map"].items():
        if label in issue_label_names:
            return issue_type
    return policy["issue_type_default"]


def available_issue_type_names(repository):
    owner = repository.get("owner")
    if not isinstance(owner, dict):
        return None
    if owner.get("__typename") and owner.get("__typename") != "Organization":
        return set()
    issue_types = owner.get("issueTypes")
    if not isinstance(issue_types, dict):
        return None
    return {node.get("name") for node in issue_types.get("nodes", []) if node.get("name") and node.get("isEnabled", True)}


root = json.loads(os.environ["METADATA_JSON"])
repository = root.get("data", {}).get("repository", {})
pull = repository.get("pullRequest", root.get("pullRequest", {}))
policy = parse_policy(os.environ["POLICY_FILE"])
errors = []
available_issue_types = available_issue_type_names(repository)

body = pull.get("body") or ""
issues_by_number = {}
current_repo = os.environ["REPO"]
for issue in pull.get("closingIssuesReferences", {}).get("nodes", []):
    if issue.get("number") is not None and issue_matches_repo(issue, current_repo):
        issues_by_number[int(issue["number"])] = issue
for issue in pull.get("referencedIssues", {}).get("nodes", []):
    if issue.get("number") is not None and issue_matches_repo(issue, current_repo):
        issues_by_number.setdefault(int(issue["number"]), issue)
if not os.environ.get("CENTRAL_AGENT_PR_METADATA_JSON"):
    for number in issue_numbers_from_body(issue_link_section(body), current_repo):
        if number in issues_by_number:
            continue
        issue = fetch_issue(current_repo, number)
        if issue is not None:
            issues_by_number[number] = issue

if policy["require_issue_link"] and not issues_by_number:
    errors.append("PR does not close or reference a governing issue")
for section in policy["required_sections"]:
    if not has_section(body, section):
        errors.append(f"PR body missing section: {section}")
if policy["require_validation_summary"] and not has_section(body, "Validation"):
    errors.append("PR body missing validation summary")
if policy["require_documentation_review"] and not has_section(body, "Documentation"):
    errors.append("PR body missing documentation review")

pr_labels = names(pull.get("labels", {}).get("nodes", []))
for label in policy["required_pr_labels"]:
    if label not in pr_labels:
        errors.append(f"PR missing label: {label}")

pr_assignees = logins(pull.get("assignees", {}).get("nodes", []))
for assignee in policy["required_assignees"]:
    if assignee not in pr_assignees:
        errors.append(f"PR missing assignee: {assignee}")

required_milestone = policy["milestone"]
configured_milestones = set(policy["configured_milestones"])
require_milestone = policy["require_milestone"]
pr_milestone = (pull.get("milestone") or {}).get("title") or ""
if require_milestone and configured_milestones and not pr_milestone:
    errors.append(f"PR missing configured milestone: {', '.join(sorted(configured_milestones))}")
elif configured_milestones and pr_milestone and pr_milestone not in configured_milestones:
    errors.append(f"PR milestone is not configured: {pr_milestone}")
if policy["triage_milestone"] and pr_milestone == policy["triage_milestone"]:
    errors.append(f"PR is still assigned to triage milestone: {policy['triage_milestone']}")

errors.extend(missing_project_messages(
    pull.get("projectItems", {}).get("nodes", []),
    policy["projects"],
    "PR",
))

issues = list(issues_by_number.values())
head_ref_name = pull.get("headRefName") or ""
head_ref_oid = pull.get("headRefOid") or ""
for issue in issues:
    issue_label_names = names(issue.get("labels", {}).get("nodes", []))
    for label in policy["required_issue_labels"]:
        if label not in issue_label_names:
            errors.append(f"issue #{issue.get('number')} missing label: {label}")
    expected_type = expected_issue_type(issue, policy)
    if available_issue_types is not None and expected_type not in available_issue_types:
        expected_type = ""
    if expected_type and "issueType" in issue:
        actual_type = issue_type_name(issue)
        if not actual_type:
            errors.append(f"issue #{issue.get('number')} missing issue type: {expected_type}")
        elif actual_type != expected_type:
            errors.append(f"issue #{issue.get('number')} issue type {actual_type} does not match expected {expected_type}")
    linked_refs = linked_branch_refs(issue)
    if policy["require_development_linkage"] and linked_refs is not None:
        if not linked_refs:
            linked_refs = cli_linked_branch_refs(current_repo, issue.get("number"))
        if not linked_refs:
            errors.append(f"issue #{issue.get('number')} missing linked development branch for current PR branch: {head_ref_name}")
        elif (head_ref_name or head_ref_oid) and not any(linked_branch_matches_head(ref, head_ref_name, head_ref_oid) for ref in linked_refs):
            errors.append(f"issue #{issue.get('number')} missing linked development branch for current PR branch: {head_ref_name}")
    issue_assignees = logins(issue.get("assignees", {}).get("nodes", []))
    for assignee in policy["required_assignees"]:
        if assignee not in issue_assignees:
            errors.append(f"issue #{issue.get('number')} missing assignee: {assignee}")
    issue_milestone = (issue.get("milestone") or {}).get("title") or ""
    if require_milestone and configured_milestones and not issue_milestone:
        errors.append(f"issue #{issue.get('number')} missing configured milestone: {', '.join(sorted(configured_milestones))}")
    elif configured_milestones and issue_milestone and issue_milestone not in configured_milestones:
        errors.append(f"issue #{issue.get('number')} milestone is not configured: {issue_milestone}")
    if policy["triage_milestone"] and issue_milestone == policy["triage_milestone"]:
        errors.append(f"issue #{issue.get('number')} is still assigned to triage milestone: {policy['triage_milestone']}")
    if (
        not policy["allow_milestone_mismatch"]
        and pr_milestone
        and issue_milestone
        and issue_milestone != pr_milestone
    ):
        errors.append(
            f"issue #{issue.get('number')} milestone {issue_milestone} does not match PR milestone {pr_milestone}"
        )
    errors.extend(missing_project_messages(
        issue.get("projectItems", {}).get("nodes", []),
        policy["projects"],
        f"issue #{issue.get('number')}",
    ))

if errors:
    print("PR metadata gate failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("PR metadata gate passed.")
PYCODE
