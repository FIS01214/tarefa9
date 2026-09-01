---
name: repo-metadata
description: Use when repository purpose, public surface, docs, or positioning changed.
---

Apply this workflow:

1. Compare the shipped change with `.central-agent/repo-metadata.yml`.
2. Run `bash scripts/check_repo_about_metadata.sh OWNER/REPO` when GitHub access is available to compare the live About metadata against the repo metadata contract.
3. Update description, homepage, and topics when they no longer describe the repository clearly.
4. Keep the repository description as a clear one-sentence purpose statement; do not append raw issue or PR labels to it unless the repo metadata file explicitly defines a description prefix or suffix.
5. Represent governance label taxonomy through GitHub labels and configured repository topics when the labels are part of the public positioning.
6. Keep metadata updates in the same PR when they are caused by the code or documentation change.
7. If live About metadata is missing or stale and the active PR is not already scoped to repository metadata, create a dedicated metadata issue and PR.
8. When admin access is available, keep the active `main` branch ruleset aligned with the central-agent baseline by running `bash scripts/ensure_main_branch_ruleset.sh OWNER/REPO`, which reads the repo-local required-check name from `.central-agent/repo-policy.yml`.
9. Avoid destructive settings such as archive, delete, visibility changes, or permission changes unless a human explicitly requests them.
10. Mention repository metadata changes in the PR body.
