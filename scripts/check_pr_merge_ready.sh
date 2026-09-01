#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/check_pr_merge_ready.sh PR_NUMBER [REPO]

Verify a manual PR merge is allowed by central-agent governance:
- configured PR and issue metadata is complete
- required checks are successful or skipped when policy requires them
- a completed Codex review exists on the current PR head
- no active unresolved Codex review threads remain

For tests, set CENTRAL_AGENT_SKIP_METADATA_GATE, CENTRAL_AGENT_PR_VIEW_JSON,
CENTRAL_AGENT_PR_CHECKS_JSON, CENTRAL_AGENT_PR_REVIEW_JSON, and
CENTRAL_AGENT_REQUIRE_REQUIRED_CHECKS.
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
POLICY_FILE="${SCRIPT_DIR}/../.central-agent/repo-policy.yml"
require_required_checks=${CENTRAL_AGENT_REQUIRE_REQUIRED_CHECKS:-}
if [[ -z "${require_required_checks}" ]]; then
  require_required_checks=$(
    POLICY_FILE="${POLICY_FILE}" /usr/bin/python3 - <<'PYCODE'
import os

policy_file = os.environ["POLICY_FILE"]
required = "true"
in_merge = False
try:
    with open(policy_file, encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.split("#", 1)[0].rstrip()
            if not line:
                continue
            if not raw_line.startswith((" ", "\t")):
                key = line.split(":", 1)[0].strip()
                in_merge = key == "merge"
                continue
            if in_merge and line.strip().startswith("require_required_checks:"):
                value = line.split(":", 1)[1].strip().lower()
                required = "false" if value in {"false", "no", "0"} else "true"
                break
except FileNotFoundError:
    pass
print(required)
PYCODE
  )
fi

if [[ ${CENTRAL_AGENT_SKIP_METADATA_GATE:-} != "1" ]]; then
  bash "${SCRIPT_DIR}/check_pr_metadata_ready.sh" "${PR_NUMBER}" "${REPO}"
fi

if [[ -n "${CENTRAL_AGENT_PR_VIEW_JSON:-}" ]]; then
  pr_json=${CENTRAL_AGENT_PR_VIEW_JSON}
else
  pr_json=$(gh pr view "${PR_NUMBER}" --repo "${REPO}" --json headRefOid,reviewDecision,mergeStateStatus,mergeable)
fi

if [[ "${require_required_checks}" == "false" ]]; then
  checks_json='[]'
elif [[ -n "${CENTRAL_AGENT_PR_CHECKS_JSON:-}" ]]; then
  checks_json=${CENTRAL_AGENT_PR_CHECKS_JSON}
else
  checks_json=$(gh pr checks "${PR_NUMBER}" --repo "${REPO}" --required --json name,state,bucket,workflow)
fi

if [[ -n "${CENTRAL_AGENT_PR_REVIEW_JSON:-}" ]]; then
  review_json=${CENTRAL_AGENT_PR_REVIEW_JSON}
else
  owner=${REPO%%/*}
  repo_name=${REPO##*/}
  reviews_json=$(gh api graphql --paginate     -f owner="${owner}"     -f repo="${repo_name}"     -F number="${PR_NUMBER}"     -f query='
      query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
        repository(owner: $owner, name: $repo) {
          pullRequest(number: $number) {
            headRefOid
            reviewDecision
            reviews(first: 100, after: $endCursor) {
              nodes {
                author { login }
                commit { oid }
                state
              }
              pageInfo { hasNextPage endCursor }
            }
          }
        }
      }
    ')
  timeline_json=$(gh api graphql --paginate     -f owner="${owner}"     -f repo="${repo_name}"     -F number="${PR_NUMBER}"     -f query='
      query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
        repository(owner: $owner, name: $repo) {
          pullRequest(number: $number) {
            headRefOid
            reviewDecision
            timelineItems(first: 100, after: $endCursor, itemTypes: [PULL_REQUEST_COMMIT, ISSUE_COMMENT]) {
              nodes {
                __typename
                ... on PullRequestCommit {
                  commit { oid }
                }
                ... on IssueComment {
                  author { login }
                  body
                  createdAt
                }
              }
              pageInfo { hasNextPage endCursor }
            }
          }
        }
      }
    ')
  threads_json=$(gh api graphql --paginate     -f owner="${owner}"     -f repo="${repo_name}"     -F number="${PR_NUMBER}"     -f query='
      query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
        repository(owner: $owner, name: $repo) {
          pullRequest(number: $number) {
            headRefOid
            reviewDecision
            reviewThreads(first: 100, after: $endCursor) {
              nodes {
                isResolved
                isOutdated
                comments(first: 20) { nodes { author { login } } }
              }
              pageInfo { hasNextPage endCursor }
            }
          }
        }
      }
    ')
  review_json=$reviews_json$'\n'$timeline_json$'\n'$threads_json
fi

PR_JSON="${pr_json}" CHECKS_JSON="${checks_json}" REVIEW_JSON="${review_json}" REQUIRE_REQUIRED_CHECKS="${require_required_checks}" /usr/bin/python3 - <<'PYCODE'
import json
import os
import sys

pr = json.loads(os.environ["PR_JSON"])
checks = json.loads(os.environ["CHECKS_JSON"])
require_required_checks = os.environ.get("REQUIRE_REQUIRED_CHECKS", "true").lower() != "false"
def load_review_payload(raw):
    decoder = json.JSONDecoder()
    roots = []
    idx = 0
    while idx < len(raw):
        while idx < len(raw) and raw[idx].isspace():
            idx += 1
        if idx >= len(raw):
            break
        obj, idx = decoder.raw_decode(raw, idx)
        roots.append(obj)
    if not roots:
        return {}
    base = roots[0]
    base_pull = base.get("data", {}).get("repository", {}).get("pullRequest", base.get("pullRequest", {}))
    for extra in roots[1:]:
        extra_pull = extra.get("data", {}).get("repository", {}).get("pullRequest", extra.get("pullRequest", {}))
        base_pull.setdefault("reviews", {}).setdefault("nodes", []).extend(extra_pull.get("reviews", {}).get("nodes", []))
        base_pull.setdefault("timelineItems", {}).setdefault("nodes", []).extend(extra_pull.get("timelineItems", {}).get("nodes", []))
        base_pull.setdefault("reviewThreads", {}).setdefault("nodes", []).extend(extra_pull.get("reviewThreads", {}).get("nodes", []))
    return base

review_root = load_review_payload(os.environ["REVIEW_JSON"])
pull = review_root.get("data", {}).get("repository", {}).get("pullRequest", review_root.get("pullRequest", {}))
head = pr.get("headRefOid") or pull.get("headRefOid")
if not head:
    print("missing PR head SHA", file=sys.stderr)
    sys.exit(1)

merge_state = pr.get("mergeStateStatus") or ""
mergeable = pr.get("mergeable") or ""
blocking_merge_states = {"BEHIND", "BLOCKED", "DIRTY", "DRAFT", "UNKNOWN"}
if merge_state in blocking_merge_states:
    print(f"PR merge state blocks merge: {merge_state}", file=sys.stderr)
    sys.exit(1)
if mergeable and mergeable != "MERGEABLE":
    print(f"PR is not mergeable: {mergeable}", file=sys.stderr)
    sys.exit(1)

bad_checks = []
if require_required_checks and not checks:
    print("no required checks reported for the PR branch", file=sys.stderr)
    sys.exit(1)

if require_required_checks:
    for check in checks:
        bucket = check.get("bucket")
        state = check.get("state")
        name = check.get("name") or check.get("workflow") or "unnamed-check"
        if bucket in ("pass", "skipping") or state in ("SUCCESS", "SKIPPED", "NEUTRAL"):
            continue
        bad_checks.append(f"{name}: state={state} bucket={bucket}")

    if bad_checks:
        print("required checks are not clear:", file=sys.stderr)
        for check in bad_checks:
            print(f"- {check}", file=sys.stderr)
        sys.exit(1)

reviews = pull.get("reviews", {}).get("nodes", [])
codex_reviews = [
    review for review in reviews
    if review.get("author", {}).get("login") == "chatgpt-codex-connector"
    and review.get("commit", {}).get("oid") == head
    and review.get("state") in ("APPROVED", "CHANGES_REQUESTED", "COMMENTED")
]

def is_review_request(item):
    return (
        item.get("__typename") == "IssueComment"
        and item.get("author", {}).get("login") != "chatgpt-codex-connector"
        and "@codex review" in (item.get("body") or "")
    )

def is_clean_codex_comment(item):
    body = item.get("body") or ""
    return (
        item.get("__typename") == "IssueComment"
        and item.get("author", {}).get("login") == "chatgpt-codex-connector"
        and "Codex Review:" in body
        and "Didn't find any major issues" in body
    )

clean_codex_comments = []
timeline_items = pull.get("timelineItems", {}).get("nodes", [])
head_timeline_indices = [
    index for index, item in enumerate(timeline_items)
    if item.get("__typename") == "PullRequestCommit"
    and item.get("commit", {}).get("oid") == head
]
if head_timeline_indices:
    head_timeline_index = max(head_timeline_indices)
    review_request_indices = [
        index for index, item in enumerate(timeline_items)
        if index > head_timeline_index and is_review_request(item)
    ]
    if review_request_indices:
        latest_review_request_index = max(review_request_indices)
        clean_codex_comments.extend(
            item for index, item in enumerate(timeline_items)
            if index > latest_review_request_index and is_clean_codex_comment(item)
        )

if not codex_reviews and not clean_codex_comments:
    print("no completed Codex review found for the current PR head", file=sys.stderr)
    sys.exit(1)

if any(review.get("state") == "CHANGES_REQUESTED" for review in codex_reviews):
    print("current-head Codex review requested changes", file=sys.stderr)
    sys.exit(1)

review_decision = pull.get("reviewDecision") or pr.get("reviewDecision") or ""
if review_decision == "CHANGES_REQUESTED":
    print("review decision is CHANGES_REQUESTED", file=sys.stderr)
    sys.exit(1)

threads = pull.get("reviewThreads", {}).get("nodes", [])
unresolved_codex_threads = [
    thread for thread in threads
    if not thread.get("isResolved")
    and not thread.get("isOutdated")
    and any(
        comment.get("author", {}).get("login") == "chatgpt-codex-connector"
        for comment in thread.get("comments", {}).get("nodes", [])
    )
]

if unresolved_codex_threads:
    print("unresolved Codex review threads remain", file=sys.stderr)
    sys.exit(1)

if require_required_checks:
    print("PR merge gate passed: checks are clear and Codex reviewed the current head.")
else:
    print("PR merge gate passed: local-check policy is active and Codex reviewed the current head.")
PYCODE
