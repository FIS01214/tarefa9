# AGENTS.md

## Objective
Use this repository as the FIS01214 course template for LHE analysis projects,
with repo-level agent behavior copied from `FIS01214/template-with-agent`.

## Repository context
- Keep the physics assignment content in Brazilian Portuguese unless the user asks otherwise.
- Preserve the template role of this repository: changes should improve the reusable student workdir baseline, not add group-specific analysis outputs.
- Keep notebooks, generated plots, and LHE inputs out of this repository unless they are intentional reusable examples.
- Keep the agent baseline files aligned with `FIS01214/template-with-agent` when updating `AGENTS.md`, `.agents/skills`, `.central-agent`, `.github/PULL_REQUEST_TEMPLATE.md`, `scripts`, or `docs/central-agent-design.md`.

## Repository agent policy
- When the user asks for a change, proceed with the full implementation workflow: make the change, commit it, push a branch, and open a PR for merge; ask first only when the requested change is unclear or blocked by a concrete decision point.
- Treat each meaningful code, workflow, or documentation change as issue-tracked work.
- Reuse the best existing issue when one already describes the change; otherwise create a clear tracking issue before implementation.
- Normalize short or vague issue descriptions into a useful problem statement, scope, acceptance criteria, and implementation context.
- Keep changes minimal, reversible, and aligned with the target repository's local style.
- Keep user-facing documentation, docstrings, examples, generated docs, and workflow documentation aligned with shipped behavior.
- Run the target repository's configured local verification before opening or updating a PR.
- When the operator has a global Codex `RTK` profile installed, prefer prefixing shell commands with `rtk` to reduce token usage during interactive CLI work.
- Keep all central-agent validation/checking local-first: run the local verification command in this repo and avoid using GitHub Actions for merge gates.
- Treat `central-agent` as the upstream source repo where reusable agent behavior is investigated and produced; treat `FIS01214/template-with-agent` as the baseline source for agent files copied into this course template.
- When the agent baseline changes upstream, sync the relevant managed files into this repository on a dedicated branch before merging into `main`.
- Report local validation results in the governing issue or PR body/comment; do not rely on GitHub Actions as validation evidence.
- Give every non-trivial PR a detailed body with issue linkage, scope, validation, documentation review, release impact, and follow-up work.
- Add labels, milestone, assignee, project metadata, and repository metadata when the target repository's policy config defines them.
- Apply `.central-agent/repo-policy.yml` `repository_profile.role` before planning work: `dev` repos emphasize issue/PR development, local validation, Codex review when requested, and release candidates; `official` repos emphasize complete documentation, stable releases, changelog entries, release assets, semantic versioning, and limited direct development.
- Ensure configured milestones exist before assigning them; run `bash scripts/ensure_repo_milestones.sh OWNER/REPO` when milestone policy declares required milestones.
- Assign every non-trivial issue to a milestone before implementation begins; use the configured triage/planning milestone only while the delivery milestone is still unknown.
- When GitHub supports it, set the native Issue Type (`Bug`, `Feature`, or `Task`) and keep it aligned with labels and issue scope.
- Do not block feature-branch pushes on project metadata; before opening or updating a non-trivial PR, confirm configured labels, milestone, project metadata, documentation, and issue linkage are current.
- Keep issue, branch, and PR Development linkage current when the platform exposes it; use a closing keyword only when the PR fully resolves the governing issue, and use a non-closing reference for partial work.
- Do not add central-agent GitHub workflow automation; keep checks local and report results in issues or PRs.
- Split multi-PR work into child issues before implementation continues; each child issue needs its own labels, milestone/project metadata, branch, and PR linkage.
- Before merge, recheck that issue scope, PR description, milestone/project status, documentation, and follow-up issues match what actually shipped.
- Before merge, confirm the PR milestone matches every linked governing issue milestone; do not merge if any linked issue or PR is still on the triage/planning milestone.
- Regularly sweep open and closed issues plus open, closed, and merged PRs with `bash scripts/audit_repo_metadata.sh OWNER/REPO`; when configured metadata is missing, rerun with `--fix` or repair the gaps before opening new dependent work.
- Maintain milestone lifecycle explicitly with `bash scripts/maintain_repo_milestones.sh OWNER/REPO --close-complete`; close milestones only when they have no open issues and no open PRs.
- Before merge, run `bash scripts/check_pr_metadata_ready.sh PR_NUMBER OWNER/REPO` and resolve any missing configured labels, assignees, milestones, Projects v2 items, PR body sections, or linked-issue metadata.
- When configured labels are missing from GitHub, run `bash scripts/ensure_repo_labels.sh OWNER/REPO` before opening or updating the PR.
- When admin access is available, ensure the repository has an active `main` branch ruleset by running `bash scripts/ensure_main_branch_ruleset.sh OWNER/REPO`; the helper reads `.central-agent/repo-policy.yml` for the repo-local required status check and only requires status checks when policy configures them. The ruleset must require PRs with zero approvals, resolved conversations, signed commits, linear history, and block deletions and force pushes.
- If branch-ruleset creation or update is blocked by missing admin access, missing GitHub support, or a repo-specific status-check name, record the blocker in the PR and create a follow-up issue before merge.
- If configured labels, milestone, project metadata, or documentation checks cannot be updated because of missing access or config, record the blocker in the PR body and create a follow-up issue before merge.
- Request `@codex review` when the user asks for it or when the repository policy requires it.
- Address actionable Codex review feedback on the same PR before merge when Codex review is requested or required.
- Interact with requested reviewers in the PR until comments are satisfied.
- After opening or updating a PR, keep monitoring requested Codex review, unresolved review threads, and local merge gates until the PR is merged or a concrete blocker is recorded in the PR.
- Merge to `main` promptly once local verification and reviewer comments are satisfied; do not wait after merge gates are clear.
- Before manually merging a PR, run `bash scripts/check_pr_merge_ready.sh PR_NUMBER OWNER/REPO` and do not merge unless it passes.
- Check repository About metadata with `bash scripts/check_repo_about_metadata.sh OWNER/REPO` before opening or merging non-trivial repo governance PRs, for both personal and organization-owned repos.
- Update repository About metadata when `.central-agent/repo-metadata.yml` says the repo description, homepage, topics, or label-derived topic representation should change.
- Keep repository descriptions as clear one-sentence purpose statements; represent governance labels through GitHub labels and configured topics unless `.central-agent/repo-metadata.yml` explicitly defines a description prefix or suffix.
- If live About metadata is missing or stale and the current PR is not already scoped to repository metadata, create a dedicated metadata issue and PR before continuing unrelated work.

## Skills to use
- Use `issue-governance` before implementation and before PR creation.
- Use `pr-governance` before opening, updating, or merging a PR.
- Use `docs-sync` whenever code, config, CLI, public API, workflow, or user-visible behavior changes.
- Use `codex-review-loop` after requesting Codex review.
- Use `repo-metadata` after a PR changes the purpose, public surface, governance label taxonomy, or positioning of the repository.

## Dependency supply-chain policy
- Use npm `min-release-age` to enforce a minimum 30-day window for newly published npm packages, reducing the risk of installing compromised versions immediately after release.
- Do not treat this as complete protection: always combine it with `package-lock.json` and `npm ci` for reproducible builds.
- Review dependency changes before updating the lockfile, especially for new or lesser-known packages.
- When possible, restrict or disable `postinstall`, `preinstall`, `install`, and `prepare` to reduce the attack surface from dependency lifecycle scripts.
- Treat `min-release-age` as an additional defense layer, not as a substitute for review, pinning, and supply-chain verification.

## Local overrides
- Keep project-specific commands, paths, framework details, and exceptions in repo-local policy files or directory-level `AGENTS.md` overrides.
- Do not put project-specific commands into the shared managed baseline unless they apply to every generated template repository.
- Keep user-specific Codex includes such as `@/Users/.../RTK.md` in the operator's global Codex instructions, not in this shared repository baseline.
