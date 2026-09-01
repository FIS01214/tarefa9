---
name: docs-sync
description: Use when code, commands, APIs, workflows, or user-visible behavior changed and documentation may drift.
---

Apply this workflow:

1. Identify public behavior, commands, configuration, workflows, or APIs affected by the change.
2. Update docstrings or equivalent inline API documentation for new or materially changed public surfaces.
3. Check README, docs pages, examples, generated docs, comments, and usage snippets for stale content.
4. Before opening or updating a PR, confirm the proposed diff, docs, docstrings, examples, and workflow documentation describe the same behavior.
5. Run the target repository's documentation validation command when configured.
6. For `official` repo profiles, confirm complete user-facing documentation, changelog entries, release notes, release assets, and version references when a release-facing change ships.
7. State in the PR body what documentation was checked or why no documentation update was needed.
8. Do not leave stale setup instructions, examples, workflow docs, or docstrings behind.
