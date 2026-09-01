#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

policy_file=$(mktemp)
cat >"${policy_file}" <<'YAML'
version: 1
milestones:
  triage_title: Planning
  default_title: Central Agent Governance
  definitions:
    - title: Planning
    - title: Central Agent Governance
    - title: Release 1
    - title: Release 2
YAML

maintenance_json='{"milestones":[{"number":1,"title":"Planning","issues":{"totalCount":0},"pullRequests":{"totalCount":0}},{"number":2,"title":"Central Agent Governance","issues":{"totalCount":0},"pullRequests":{"totalCount":0}},{"number":3,"title":"Release 1","issues":{"totalCount":0},"pullRequests":{"totalCount":0}},{"number":4,"title":"Release 2","issues":{"totalCount":1},"pullRequests":{"totalCount":0}}]}'

CENTRAL_AGENT_REPO_POLICY_FILE="${policy_file}" CENTRAL_AGENT_MILESTONE_MAINTENANCE_JSON="${maintenance_json}" bash "${ROOT_DIR}/scripts/maintain_repo_milestones.sh" diemort/central-agent --close-complete >/tmp/maintain-milestones.out
rm -f "${policy_file}"

grep -q "Closed completed milestone: Release 1" /tmp/maintain-milestones.out
if grep -q "Closed completed milestone: Planning" /tmp/maintain-milestones.out; then
  echo "expected Planning to remain open" >&2
  exit 1
fi
if grep -q "Closed completed milestone: Central Agent Governance" /tmp/maintain-milestones.out; then
  echo "expected default milestone to remain open" >&2
  exit 1
fi
if grep -q "Closed completed milestone: Release 2" /tmp/maintain-milestones.out; then
  echo "expected active release milestone to remain open" >&2
  exit 1
fi

echo "Milestone maintenance smoke test passed."
