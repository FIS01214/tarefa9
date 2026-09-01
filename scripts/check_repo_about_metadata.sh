#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/check_repo_about_metadata.sh OWNER/REPO [--fix]

Compare live GitHub repository About metadata with .central-agent/repo-metadata.yml:
- non-empty description matching the configured purpose statement
- homepage when configured
- configured topics
- label-derived topic representation when enabled

Without --fix, report gaps and exit non-zero. With --fix, apply safe About
metadata updates through GitHub. For tests, set CENTRAL_AGENT_REPO_ABOUT_JSON.
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
METADATA_FILE=${CENTRAL_AGENT_REPO_METADATA_FILE:-"${ROOT_DIR}/.central-agent/repo-metadata.yml"}
POLICY_FILE=${CENTRAL_AGENT_REPO_POLICY_FILE:-"${ROOT_DIR}/.central-agent/repo-policy.yml"}

REPO="${REPO}" FIX="${FIX}" METADATA_FILE="${METADATA_FILE}" POLICY_FILE="${POLICY_FILE}" ABOUT_JSON="${CENTRAL_AGENT_REPO_ABOUT_JSON:-}" PRINT_ONLY="${CENTRAL_AGENT_REPO_ABOUT_PRINT_ONLY:-false}" /usr/bin/python3 - <<'PYCODE'
import json
import os
import re
import subprocess
import sys


def clean(value):
    value = value.strip()
    if not value:
        return ""
    if value[0:1] in ("'", '"') and value[-1:] == value[0]:
        return value[1:-1]
    if " #" in value:
        value = value.split(" #", 1)[0].rstrip()
    return value


def parse_metadata(path):
    data = {
        "description": "",
        "homepage": "",
        "topics": [],
        "label_topics_enabled": False,
        "label_topics_source": ".central-agent/repo-policy.yml",
        "allow_label_prefix": False,
        "allow_label_suffix": False,
    }
    stack = []
    if not os.path.exists(path):
        raise SystemExit(f"repo metadata file not found: {path}")
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
                continue
            if text.startswith("- "):
                value = clean(text[2:])
                if stack == ["topics"] and value:
                    data["topics"].append(value)
                continue
            if ":" not in text:
                continue
            key, raw_value = text.split(":", 1)
            key = key.strip()
            value = clean(raw_value)
            if stack == [] and key == "description":
                data["description"] = value
            elif stack == [] and key == "homepage":
                data["homepage"] = value
            elif stack == ["label_topics"] and key == "include_governance_labels":
                data["label_topics_enabled"] = value.lower() == "true"
            elif stack == ["label_topics"] and key == "source":
                data["label_topics_source"] = value or data["label_topics_source"]
            elif stack == ["description_policy"] and key == "allow_label_prefix":
                data["allow_label_prefix"] = value.lower() == "true"
            elif stack == ["description_policy"] and key == "allow_label_suffix":
                data["allow_label_suffix"] = value.lower() == "true"
    return data


def parse_policy_labels(path):
    labels = []
    if not os.path.exists(path):
        return labels
    stack = []
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
                continue
            if text.startswith("- "):
                value = clean(text[2:])
                if stack in (["labels", "apply_when_present"], ["labels", "required_for_issues"], ["labels", "required_for_pull_requests"]):
                    labels.append(value)
                elif stack == ["labels", "definitions"] and value.startswith("name:"):
                    labels.append(clean(value.split(":", 1)[1]))
                continue
            if ":" not in text:
                continue
            key, raw_value = text.split(":", 1)
            if stack == ["labels", "definitions"] and key.strip() == "name":
                labels.append(clean(raw_value))
    seen = set()
    result = []
    for label in labels:
        if label and label not in seen:
            seen.add(label)
            result.append(label)
    return result


def label_to_topic(label):
    topic = label.lower()
    topic = re.sub(r"[^a-z0-9-]+", "-", topic)
    topic = re.sub(r"-+", "-", topic).strip("-")
    return topic


def load_live(repo):
    fixture = os.environ.get("ABOUT_JSON")
    if fixture:
        return json.loads(fixture)
    raw = subprocess.check_output([
        "gh", "repo", "view", repo,
        "--json", "description,homepageUrl,repositoryTopics,url"
    ], text=True)
    return json.loads(raw)


def live_topics(live):
    topics = live.get("repositoryTopics") or []
    result = set()
    for item in topics:
        if isinstance(item, str):
            result.add(item)
        elif item.get("name"):
            result.add(item["name"])
    return result


repo = os.environ["REPO"]
fix = os.environ["FIX"] == "true"
print_only = os.environ.get("PRINT_ONLY", "false").lower() == "true"
metadata = parse_metadata(os.environ["METADATA_FILE"])
policy_path = os.environ["POLICY_FILE"]
if "CENTRAL_AGENT_REPO_POLICY_FILE" not in os.environ:
    source = metadata["label_topics_source"]
    if os.path.isabs(source):
        policy_path = source
    else:
        policy_path = os.path.normpath(os.path.join(os.path.dirname(os.environ["METADATA_FILE"]), "..", source))

expected_description = metadata["description"].strip()
expected_homepage = metadata["homepage"].strip()
expected_topics = set(metadata["topics"])
if metadata["label_topics_enabled"]:
    expected_topics.update(filter(None, (label_to_topic(label) for label in parse_policy_labels(policy_path))))

problems = []
if not expected_description or expected_description.lower().startswith("replace with"):
    problems.append(("metadata file missing description", "set .central-agent/repo-metadata.yml description to a clear one-sentence purpose"))

live = load_live(repo)
live_description = (live.get("description") or "").strip()
live_homepage = (live.get("homepageUrl") or "").strip()
live_topic_names = live_topics(live)

if expected_description and not expected_description.lower().startswith("replace with"):
    if not live_description:
        problems.append(("repo missing About description", expected_description))
    elif live_description != expected_description:
        problems.append(("repo About description differs", f"expected: {expected_description}; actual: {live_description}"))

if expected_homepage and live_homepage != expected_homepage:
    problems.append(("repo About homepage differs", f"expected: {expected_homepage}; actual: {live_homepage or '<empty>'}"))

for topic in sorted(expected_topics):
    if topic not in live_topic_names:
        problems.append(("repo missing topic", topic))

if problems:
    print("Repository About metadata check found gaps:")
    for kind, detail in problems:
        print(f"- {kind}: {detail}")
    print("If this is not already the active PR scope, open a dedicated repository-metadata issue and PR before unrelated work continues.")
    if fix:
        if expected_description and not expected_description.lower().startswith("replace with"):
            cmd = ["gh", "repo", "edit", repo, "--description", expected_description]
            if expected_homepage:
                cmd.extend(["--homepage", expected_homepage])
            for topic in sorted(expected_topics - live_topic_names):
                cmd.extend(["--add-topic", topic])
            if print_only:
                print("Would run:", " ".join(cmd))
            else:
                subprocess.check_call(cmd)
                print("Applied safe repository About metadata fixes.")
        else:
            print("Cannot apply fixes until .central-agent/repo-metadata.yml has a concrete description.")
            sys.exit(1)
    else:
        sys.exit(1)
else:
    print("Repository About metadata check passed.")
PYCODE
