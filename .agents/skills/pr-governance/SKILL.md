---
name: pr-governance
description: Use before opening, updating, reviewing, or merging a pull request.
---

Apply this workflow:

1. Ensure the PR links the governing issue explicitly.
2. Use closing keywords only when the PR fully resolves the issue; otherwise use a non-closing issue reference.
3. Read `.central-agent/repo-policy.yml` and apply `repository_profile.role` before opening, updating, or merging.
4. For `dev` repos, confirm issue/PR linkage, local validation, release-candidate metadata when relevant, and Codex review only when requested or required by policy.
5. For `official` repos, confirm complete documentation, changelog entries, release assets, semantic versioning, stable-release metadata, and that direct development is intentionally limited.
6. Treat feature-branch pushes as allowed after local verification; do not require project metadata to be complete before preserving branch work.
7. Before opening or updating a non-trivial PR, confirm configured labels, milestone, assignees, project metadata, issue linkage, and documentation review are current.
8. When configured labels do not exist in GitHub, run `bash scripts/ensure_repo_labels.sh OWNER/REPO` before continuing.
9. When configured milestones do not exist in GitHub, run `bash scripts/ensure_repo_milestones.sh OWNER/REPO` before continuing.
10. Confirm the PR milestone matches every linked governing issue milestone; move issues out of the triage/planning milestone before PR creation or update.
11. When admin access is available, run `bash scripts/ensure_main_branch_ruleset.sh OWNER/REPO` to create or update the active `main` ruleset using the repo-local `branch_ruleset.required_status_check` from `.central-agent/repo-policy.yml`: PR required with zero approvals, required checks only when policy configures them, conversation resolution, signed commits, linear history, deletion blocked, and non-fast-forward updates blocked. Pass an explicit status-check argument only when intentionally overriding policy.
12. If ruleset enforcement cannot be updated because access, repo capabilities, or the required-check name is unclear, record the blocker in the PR and create a follow-up issue before merge.
13. Add a detailed PR body with summary, issue link, validation, documentation review, metadata changes, release impact, and follow-up work.
14. If configured metadata or documentation checks cannot be updated because of missing access or missing config, record the blocker in the PR body and create a follow-up issue before merge.
15. Confirm local verification and documentation review before requesting review.
16. Request `@codex review` when the user asks for it or when repo policy requires it.
17. Interact with requested reviewers in the PR until actionable comments are satisfied.
18. Keep monitoring the PR after requesting review: poll policy-required checks when enabled, requested Codex review state, and unresolved review threads until the gates pass or a concrete blocker is recorded.
19. Before manual merge, run `bash scripts/check_pr_metadata_ready.sh PR_NUMBER OWNER/REPO`; stop if configured labels, assignees, milestones, Projects v2 items, PR body sections, linked-issue metadata, or milestone alignment are missing.
20. Before manual merge, run `bash scripts/check_pr_merge_ready.sh PR_NUMBER OWNER/REPO`; stop if the metadata gate fails, policy-required checks are not passing, or any policy-required/requested Codex review is incomplete.
21. Confirm the PR is linked to the governing issue through GitHub Development metadata when the platform supports it.
22. For multi-PR work, confirm this PR closes or directly references the correct child issue and references the parent issue when relevant.
23. Before merge, recheck that the issue, PR body, labels, milestone, project metadata, Issue Type, Development linkage, documentation, release metadata, and follow-up issues match the shipped scope.
24. Sweep open, closed, and merged PRs with `bash scripts/audit_repo_metadata.sh OWNER/REPO`; if mutable metadata is missing, rerun with `--fix` or repair labels, assignees, milestones, Projects, Issue Type, and Development linkage manually.
25. Merge to `main` promptly once required checks pass and reviewer comments are satisfied; do not wait after the merge gates are clear.
