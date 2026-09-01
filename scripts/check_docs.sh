#!/usr/bin/env bash

set -euo pipefail

test -f AGENTS.md
test -f .central-agent/repo-policy.yml
test -f .central-agent/repo-metadata.yml
if [[ ! -f docs/design.md && ! -f docs/central-agent-design.md ]]; then
  echo "missing central-agent design documentation" >&2
  exit 1
fi
