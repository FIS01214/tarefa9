---
name: develop-repo
description: Use for normal implementation work in a GitHub repository.
---

Apply this workflow:

1. Read the relevant code, config, docs, and issue context before editing.
2. Read `.central-agent/repo-policy.yml` and identify `repository_profile.role` before choosing a workflow.
3. For `dev` repos, use issue/PR development, local validation, Codex review when requested, and release-candidate tracking when releases are involved.
4. For `official` repos, prefer smaller stabilization PRs, complete documentation, changelog updates, release assets, semantic versioning, and limited direct development.
5. Treat each user prompt as a potential new GitHub issue; if the work should be tracked and is not already tracked, prepare and create the issue before implementation continues.
6. Refine user-opened issues when needed to improve clarity, scope, reproduction details, acceptance criteria, and implementation context.
7. Keep the scope limited to the requested behavior.
8. Prefer minimal changes that fit the existing repo patterns.
9. Run the smallest relevant local validation before stopping.
10. Open or update the PR with the issue and branch linked, interact with requested reviewers until comments are satisfied, keep monitoring policy-required checks when enabled and requested Codex review status, and merge to `main` promptly once the merge gates are clear.
11. Make sure the issue captures both the investigation findings and the chosen solution before the PR closes it.
