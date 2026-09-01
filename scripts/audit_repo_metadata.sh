#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/audit_repo_metadata.sh OWNER/REPO [--fix]

Sweep open and closed issues plus open, closed, and merged PRs for configured
mutable metadata:
- labels
- assignees
- milestone
- Projects v2 membership
- native GitHub Issue Type when configured and exposed
- issue-to-branch Development linkage when configured and exposed

Without --fix, report missing metadata and exit non-zero when gaps exist.
With --fix, apply missing mutable metadata through GitHub.

For tests, set CENTRAL_AGENT_REPO_AUDIT_JSON.
USAGE
}

if [[ ${1:-} == "--help" || $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit $([[ ${1:-} == "--help" ]] && echo 0 || echo 1)
fi

REPO=$1
FIX=false
if [[ ${2:-} == "--fix" ]]; then
  FIX=true
elif [[ $# -eq 2 ]]; then
  usage
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
POLICY_FILE=${CENTRAL_AGENT_REPO_POLICY_FILE:-"${ROOT_DIR}/.central-agent/repo-policy.yml"}

REPO="${REPO}" FIX="${FIX}" POLICY_FILE="${POLICY_FILE}" AUDIT_JSON="${CENTRAL_AGENT_REPO_AUDIT_JSON:-}" /usr/bin/python3 - <<'PYCODE'
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
        "milestone": "",
        "configured_milestones": [],
        "require_milestone": None,
        "projects": [],
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
                if value:
                    policy["configured_milestones"].append(value)
            elif stack == ["milestones", "definitions"] and key.strip() == "title":
                if value:
                    policy["configured_milestones"].append(value)
            elif stack in (["issue_policy"], ["pull_request_policy"]) and key.strip() == "require_development_linkage_when_available":
                policy["require_development_linkage"] = policy["require_development_linkage"] or value == "true"
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


def gh_json(*args):
    return json.loads(subprocess.check_output(["gh", *args], text=True))


def gh_run(*args):
    if os.environ.get("AUDIT_JSON"):
        return
    subprocess.check_call(["gh", *args])


def load_items(repo):
    fixture = os.environ.get("AUDIT_JSON")
    if fixture:
        return json.loads(fixture)
    owner, repo_name = repo.split("/", 1)
    issues = []
    pull_requests = []
    issue_cursor = ""
    pr_cursor = ""
    has_next_issues = True
    has_next_prs = True
    query = (
        "query($owner: String!, $repo: String!, $issueCursor: String, $prCursor: String) {"
        "  repository(owner: $owner, name: $repo) {"
        "    owner { __typename ... on Organization { issueTypes(first: 20) { nodes { name isEnabled } } } }"
        "    issues(first: 100, after: $issueCursor, states: [OPEN, CLOSED], orderBy: {field: CREATED_AT, direction: DESC}) {"
        "      pageInfo { hasNextPage endCursor }"
        "      nodes { number state title url issueType { name } linkedBranches(first: 20) { nodes { ref { name } } } labels(first: 50) { nodes { name } } milestone { title } assignees(first: 20) { nodes { login } } projectItems(first: 50) { nodes { project { number title owner { __typename ... on User { login } ... on Organization { login } } } } } }"
        "    }"
        "    pullRequests(first: 100, after: $prCursor, states: [OPEN, CLOSED, MERGED], orderBy: {field: CREATED_AT, direction: DESC}) {"
        "      pageInfo { hasNextPage endCursor }"
        "      nodes { number state title url body labels(first: 50) { nodes { name } } milestone { title } assignees(first: 20) { nodes { login } } projectItems(first: 50) { nodes { project { number title owner { __typename ... on User { login } ... on Organization { login } } } } } closingIssuesReferences(first: 20) { nodes { number repository { nameWithOwner } } } }"
        "    }"
        "  }"
        "}"
    )
    while has_next_issues or has_next_prs:
        args = [
            "gh", "api", "graphql",
            "-f", f"owner={owner}",
            "-f", f"repo={repo_name}",
            "-f", f"query={query}",
        ]
        if issue_cursor:
            args.extend(["-f", f"issueCursor={issue_cursor}"])
        if pr_cursor:
            args.extend(["-f", f"prCursor={pr_cursor}"])
        raw = subprocess.check_output(args, text=True)
        repository = json.loads(raw).get("data", {}).get("repository", {})
        issue_page = repository.get("issues", {})
        pr_page = repository.get("pullRequests", {})
        owner_info = repository.get("owner", {})
        if has_next_issues:
            issues.extend(issue_page.get("nodes", []))
            issue_info = issue_page.get("pageInfo", {})
            has_next_issues = bool(issue_info.get("hasNextPage"))
            issue_cursor = issue_info.get("endCursor") or ""
        if has_next_prs:
            pull_requests.extend(pr_page.get("nodes", []))
            pr_info = pr_page.get("pageInfo", {})
            has_next_prs = bool(pr_info.get("hasNextPage"))
            pr_cursor = pr_info.get("endCursor") or ""
    return {"issues": issues, "pullRequests": pull_requests, "owner": owner_info}


def names(nodes):
    if isinstance(nodes, dict):
        nodes = nodes.get("nodes", [])
    return {node.get("name") for node in nodes if node.get("name")}


def logins(nodes):
    if isinstance(nodes, dict):
        nodes = nodes.get("nodes", [])
    return {node.get("login") for node in nodes if node.get("login")}


def project_keys(nodes):
    if isinstance(nodes, dict):
        nodes = nodes.get("nodes", [])
    keys = set()
    for node in nodes:
        if node.get("title"):
            keys.add(("", node["title"]))
        project = node.get("project") or {}
        owner = project.get("owner") or {}
        owner_login = owner.get("login") or ""
        number = project.get("number")
        if owner_login and number is not None:
            keys.add((owner_login, int(number)))
        if project.get("title"):
            keys.add(("", project["title"]))
    return keys


def project_missing_key(project):
    owner = project.get("owner") or ""
    number = project.get("number")
    title = project.get("title") or ""
    if owner and number is not None:
        return f"{owner}#{number}"
    return title


def issue_type_name(item):
    issue_type = item.get("issueType") or {}
    return issue_type.get("name") or ""


def linked_branch_names(item):
    linked = item.get("linkedBranches")
    if not isinstance(linked, dict):
        return None
    branch_names = []
    for node in linked.get("nodes", []):
        ref = node.get("ref") or {}
        if ref.get("name"):
            branch_names.append(ref["name"])
    return branch_names


def issue_matches_repo(issue, repo):
    issue_repo = (issue.get("repository") or {}).get("nameWithOwner")
    return issue_repo is None or issue_repo.lower() == repo.lower()


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


def expected_issue_type(item, policy):
    if not policy["issue_types_enabled"]:
        return ""
    label_names = names(item.get("labels", []))
    for label, issue_type in policy["issue_type_label_map"].items():
        if label in label_names:
            return issue_type
    return policy["issue_type_default"]


def available_issue_type_names(items):
    owner = items.get("owner")
    if not isinstance(owner, dict):
        return None
    if owner.get("__typename") and owner.get("__typename") != "Organization":
        return set()
    issue_types = owner.get("issueTypes")
    if not isinstance(issue_types, dict):
        return None
    return {node.get("name") for node in issue_types.get("nodes", []) if node.get("name") and node.get("isEnabled", True)}


def active_issue_numbers_from_prs(items, repo):
    active = set()
    for pr in items.get("pullRequests", []):
        if pr.get("state") != "OPEN":
            continue
        for issue in (pr.get("closingIssuesReferences") or {}).get("nodes", []):
            if issue.get("number") is not None and issue_matches_repo(issue, repo):
                active.add(int(issue["number"]))
        for number in issue_numbers_from_body(issue_link_section(pr.get("body", "")), repo):
            active.add(number)
    return active


def audit_item(item, required_labels, policy):
    missing = []
    label_names = names(item.get("labels", []))
    for label in required_labels:
        if label not in label_names:
            missing.append(("label", label))
    assignees = logins(item.get("assignees", []))
    for assignee in policy["required_assignees"]:
        if assignee not in assignees:
            missing.append(("assignee", assignee))
    milestone = item.get("milestone") or {}
    milestone_title = milestone.get("title") or ""
    configured_milestones = set(policy["configured_milestones"])
    if policy["require_milestone"] and configured_milestones and not milestone_title:
        missing.append(("milestone", policy["milestone"]))
    elif configured_milestones and milestone_title and milestone_title not in configured_milestones:
        missing.append(("milestone", policy["milestone"]))
    actual_projects = project_keys(item.get("projectItems", []))
    for project in policy["projects"]:
        owner = project.get("owner") or ""
        number = project.get("number")
        title = project.get("title") or ""
        found = False
        if owner and number is not None:
            found = (owner, int(number)) in actual_projects
        elif title:
            found = ("", title) in actual_projects
        if not found:
            missing.append(("project", project_missing_key(project)))
    return missing


def audit_issue_metadata(item, policy, available_issue_types, active_issue_numbers):
    missing = []
    expected_type = expected_issue_type(item, policy)
    if available_issue_types is not None and expected_type not in available_issue_types:
        expected_type = ""
    if expected_type and "issueType" in item:
        actual_type = issue_type_name(item)
        if not actual_type:
            missing.append(("issue type", expected_type))
        elif actual_type != expected_type:
            missing.append(("issue type", f"{expected_type} (currently {actual_type})"))
    linked_names = linked_branch_names(item)
    if (
        policy["require_development_linkage"]
        and item.get("state") == "OPEN"
        and item.get("number") in active_issue_numbers
        and linked_names is not None
        and not linked_names
    ):
        missing.append(("development linkage", "linked branch"))
    return missing


def fix_item(repo, kind, item, missing, policy):
    edit_cmd = "issue" if kind == "issue" else "pr"
    edit_args = [edit_cmd, "edit", str(item["number"]), "--repo", repo]
    needs_edit = False
    for missing_type, value in missing:
        if missing_type == "label":
            edit_args.extend(["--add-label", value])
            needs_edit = True
        elif missing_type == "assignee":
            edit_args.extend(["--add-assignee", value])
            needs_edit = True
        elif missing_type == "milestone":
            edit_args.extend(["--milestone", value])
            needs_edit = True
    if needs_edit:
        gh_run(*edit_args)
    for missing_type, value in missing:
        if missing_type != "project":
            continue
        for project in policy["projects"]:
            if project_missing_key(project) == value and project.get("owner") and project.get("number") is not None:
                gh_run("project", "item-add", str(project["number"]), "--owner", str(project["owner"]), "--url", item["url"])


def append_metadata_node(item, field, node):
    value = item.get(field)
    if isinstance(value, dict):
        nodes = value.setdefault("nodes", [])
        if isinstance(nodes, list):
            nodes.append(node)
        else:
            value["nodes"] = [node]
    elif isinstance(value, list):
        value.append(node)
    else:
        item[field] = [node]


def apply_fixable_metadata_to_item(item, missing, policy):
    for missing_type, value in missing:
        if missing_type == "label":
            append_metadata_node(item, "labels", {"name": value})
        elif missing_type == "assignee":
            append_metadata_node(item, "assignees", {"login": value})
        elif missing_type == "milestone":
            item["milestone"] = {"title": value}
        elif missing_type == "project":
            for project in policy["projects"]:
                if project_missing_key(project) == value:
                    append_metadata_node(item, "projectItems", {"project": project})
                    break


FIXABLE_METADATA_TYPES = {"label", "assignee", "milestone", "project"}


repo = os.environ["REPO"]
fix = os.environ["FIX"] == "true"
policy = parse_policy(os.environ["POLICY_FILE"])
items = load_items(repo)
problems = []
available_issue_types = available_issue_type_names(items)
active_issue_numbers = active_issue_numbers_from_prs(items, repo)

for item in items.get("issues", []):
    missing = audit_item(item, policy["required_issue_labels"], policy)
    if fix and missing:
        fix_item(repo, "issue", item, missing, policy)
        apply_fixable_metadata_to_item(item, missing, policy)
    missing.extend(audit_issue_metadata(item, policy, available_issue_types, active_issue_numbers))
    for missing_type, value in missing:
        problems.append(("issue", item["number"], item.get("state", ""), item.get("title", ""), missing_type, value))

for item in items.get("pullRequests", []):
    missing = audit_item(item, policy["required_pr_labels"], policy)
    for missing_type, value in missing:
        problems.append(("pull request", item["number"], item.get("state", ""), item.get("title", ""), missing_type, value))
    if fix and missing:
        fix_item(repo, "pull request", item, missing, policy)

if problems:
    print("Repository metadata audit found gaps:")
    for kind, number, state, title, missing_type, value in problems:
        print(f"- {kind} #{number} [{state}] missing {missing_type}: {value} ({title})")
    if fix:
        fixable_count = sum(1 for problem in problems if problem[4] in FIXABLE_METADATA_TYPES)
        unfixable_count = len(problems) - fixable_count
        if fixable_count:
            print(f"Applied fixes for {fixable_count} metadata gaps.")
        if unfixable_count:
            print(f"{unfixable_count} metadata gaps require manual repair after --fix.")
            sys.exit(1)
    else:
        sys.exit(1)
else:
    print("Repository metadata audit passed.")
PYCODE
