---
name: codex-review-loop
description: Use after requesting Codex review on a pull request.
---

Apply this workflow:

1. Read active Codex review comments and unresolved review threads.
2. Classify each item as actionable, stale, ambiguous, or out of scope.
3. Fix actionable feedback on the same branch and same PR.
4. Rerun the smallest relevant validation after changes.
5. Request another Codex review after the fix when needed.
6. Keep monitoring the PR after each review request: poll policy-required checks when enabled, current-head Codex review state, and unresolved review threads until the gates pass or a concrete blocker is recorded in the PR.
7. Merge to `main` promptly once policy-required checks pass when enabled and reviewer comments are satisfied; do not wait after the merge gates are clear.
8. Stop without merging if feedback is ambiguous, conflicting, or cannot be verified.
9. Do not open replacement PRs for the same issue unless the original branch cannot be recovered.
