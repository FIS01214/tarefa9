---
name: pr-hygiene
description: Use before opening or merging a pull request.
---

Apply this workflow:

1. Recheck the relevant issue list and reuse the best matching issue, or create a new issue when the work from the prompt should be tracked and is not tracked yet.
2. Refine the active issue when needed so the problem statement, scope, reproduction details, acceptance criteria, and implementation context are clear.
3. Label the issue with tags that reflect the work's meaning, such as type, area, priority, and status when those labels exist in the repo.
4. Run `bash scripts/ensure_repo_labels.sh OWNER/REPO` when configured labels are missing from GitHub.
5. Make sure the active issue is linked explicitly from the branch or PR context.
6. Label the PR with tags that reflect the work's meaning, using the repo's existing label vocabulary.
7. Confirm configured assignees, milestones, and Projects v2 items on both the PR and linked issue.
8. Confirm the smallest relevant validation was run.
9. Summarize what changed and what was validated in the PR body.
10. Add an issue comment summarizing the investigation findings before implementation is finalized.
11. Add an issue comment describing the chosen fix before the PR closes the issue.
12. Request `@codex review` explicitly on non-trivial PRs.
