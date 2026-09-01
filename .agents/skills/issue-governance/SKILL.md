---
name: issue-governance
description: Use before repo implementation work to create, reuse, normalize, label, and milestone GitHub issues.
---

Apply this workflow:

1. Search relevant open issues before implementation.
2. Reuse the best matching issue when one already covers the work.
3. Create a new issue before implementation when meaningful work is not tracked.
4. Normalize short or vague issue text into goal, scope, acceptance criteria, constraints, and implementation context.
5. Add labels that match the target repo's existing label vocabulary and `.central-agent/repo-policy.yml`.
6. When configured labels do not exist in GitHub, run `bash scripts/ensure_repo_labels.sh OWNER/REPO` before continuing.
7. Ensure configured milestones exist with `bash scripts/ensure_repo_milestones.sh OWNER/REPO` when milestone policy is enabled.
8. Add or confirm milestone metadata for every non-trivial issue before implementation starts; use the configured triage/planning milestone only while the delivery milestone is still unknown.
9. Add or confirm configured assignees and Projects v2 items when `.central-agent/repo-policy.yml` defines them.
10. Set native GitHub Issue Type when available; map bug labels to `Bug`, feature labels to `Feature`, and default governance/task work to `Task`.
11. Link active implementation issues to the branch through GitHub Development metadata when the platform or API supports it.
12. When the work will require multiple meaningful PRs, create child issues before continuing; each child issue needs labels, milestone/project metadata, and its own branch/PR trail.
13. Comment on the issue when investigation changes scope or reveals follow-up work.
14. Sweep open and closed issues with `bash scripts/audit_repo_metadata.sh OWNER/REPO`; if mutable metadata is missing, rerun with `--fix` or repair labels, assignees, milestones, Projects, Issue Type, and Development linkage manually.
