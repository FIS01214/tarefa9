# central-agent design

`central-agent` is the personal account source for repo-level GitHub agent behavior. It is meant to populate template repositories and keep their managed agent files current over time.

## Design boundary

`central-agent` owns repository behavior only:

- issue creation and normalization
- issue, branch, and PR linkage
- labels, milestones, and PR metadata when configured by the target repo
- local verification before branch work is pushed
- documentation and configured metadata review before PR open/update and again before merge
- Codex review requests and review-feedback repair loops
- merge gating after checks and review are clear
- repository About metadata when configured
- repository `main` branch rulesets when admin access is available

Organization-wide behavior belongs in `agentic-standards`, which can install this repo-level baseline into many repositories.

## Generated template repositories

A generated template repo receives:

- `AGENTS.md`
- `.agents/skills/`
- `.central-agent/source.json`
- seeded `.central-agent/repo-policy.yml` when missing
- seeded `.central-agent/repo-metadata.yml` when missing
- `.github/PULL_REQUEST_TEMPLATE.md`
- starter `README.md`

The generated repo should be marked as a GitHub template repository in GitHub settings.

## Repo-local policy

`.central-agent/repo-policy.yml` is the target repo's local contract. It defines the repository profile, labels, milestone behavior, verification commands, documentation checks, Codex review policy, release posture, and merge policy. The central baseline seeds this file only when it is missing; later syncs preserve local policy so repository-specific validation and exceptions are not overwritten.

Repository profiles specialize the shared baseline without forking the whole directive set. A `dev` profile is for active implementation repositories: issues and PRs are the normal unit of work, validation stays local, Codex review is requested only when the user or repo policy asks for it, and release work is tracked as release candidates until promoted. An `official` profile is for stable user-facing repositories: agents should minimize direct development, require complete documentation, maintain changelog and version references, attach or verify release assets, and publish stable semantic-versioned releases.

Feature-branch pushes are allowed after local verification so work can be preserved and reviewed. Configured labels, milestones, project metadata, issue linkage, documentation review, and follow-up tracking are required before opening or updating a non-trivial PR, then rechecked before merge against the scope that actually shipped. When GitHub exposes native Issue Type and Development metadata, issues should be typed as `Bug`, `Feature`, or `Task`, active work should link issue -> branch -> PR, and multi-PR work should be split into child issues rather than hidden in one umbrella checklist. If the agent lacks access or config to update required metadata or documentation checks, the PR body must record the blocker and a follow-up issue must exist before merge.

The metadata rule is enforced by `scripts/check_pr_metadata_ready.sh`. The script checks configured PR and linked-issue labels, assignees, milestones, Projects v2 membership, required PR body sections, validation summary, documentation review, and closing issue linkage. `scripts/check_pr_merge_ready.sh` runs that metadata gate before the check/Codex merge gate so advisory metadata rules cannot be bypassed during manual merges. `scripts/ensure_repo_labels.sh` creates or updates the label vocabulary declared in `.central-agent/repo-policy.yml`.

Milestones are managed metadata, not passive labels. `scripts/ensure_repo_milestones.sh` creates or updates configured milestones before agents assign them to issues or PRs. Every non-trivial issue and PR should be milestone-tracked, and implementation should not begin until the governing issue has moved from the configured triage milestone to the correct delivery or release milestone. `scripts/check_pr_metadata_ready.sh` blocks PRs whose milestone differs from any linked governing issue milestone, and it blocks PRs or linked issues that are still assigned to the triage milestone. Completed milestones are closed only through explicit local maintenance with `scripts/maintain_repo_milestones.sh OWNER/REPO --close-complete`, after no open issues and no open PRs remain.

Historical metadata is covered by `scripts/audit_repo_metadata.sh`. Agents use it to sweep open and closed issues plus open, closed, and merged PRs for configured mutable metadata, then rerun it with `--fix` to apply missing labels, assignees, milestones, and Projects v2 items. The sweep deliberately does not rewrite historical PR bodies; PR body sections, documentation notes, Development linkage, native Issue Type, and validation summaries remain current-PR merge-gate requirements when GitHub exposes them.

`central-agent` is the source repository for investigation and production of reusable agent behavior. `template-with-agent` is the product template: relevant changes to managed directives, skills, policy contracts, docs, or rollout scripts should land in `central-agent` first, then receive a dedicated issue, branch, and PR in `template-with-agent` before broader downstream rollout.

Managed downstream sync PRs are created by the central-agent-owned `scripts/create_or_update_sync_pr.sh` helper, not by a generic pull-request action. The helper commits the managed-file diff, removes old central-agent seeded workflow files when applicable, creates or updates the sync PR, creates or reuses a standing `Track central-agent baseline sync` issue, ensures configured milestones exist, applies configured labels, assignees, milestones, and Projects v2 metadata to the issue and PR, writes the required PR body sections, and runs `scripts/check_pr_metadata_ready.sh` before requesting Codex review. If the target repo has not configured required PR labels or assignees, the sync helper still applies safe governance defaults: `area:governance`, `area:workflow`, `type:docs`, and the repository owner as assignee. Repositories without validation workflows do not receive GitHub Actions from central-agent; agents run local validation commands and report the evidence in the issue or PR.

Use `scripts/ci-central-agent-verify.sh` only when the target repo provides that hook. Otherwise use the verification command declared in `.central-agent/repo-policy.yml` or the repo's documented local validation command.

## Review and merge model

Agents open or update a PR and post `@codex review`. They should interact with the reviewer on the PR until comments are satisfied and keep monitoring current-head Codex review state, unresolved review threads, and local merge gates until the PR is merged or a concrete blocker is recorded. Local validation is run outside GitHub Actions and summarized in the PR body or comments. Clean Codex PR comments only count as current-head evidence when the PR timeline shows the current head commit before the request and clean response; timestamp-only evidence is ambiguous. If review state is ambiguous, the PR stays open.

## Account-wide rollout orchestration

`config/managed-repositories.json` records the account owner, central-agent source, selection rules, rollout settings, and auditable per-repository state. Selection is allowlist-first for the first pass, with denylist support and explicit skip flags for archived, forked, and template repositories. `template-with-agent` is intentionally allowlisted even though it is a template repository, so it can stay synchronized with this baseline.

Discovery is read-only through `scripts/discover_account_repos.sh`. Rollout through `scripts/rollout_account_repos.sh --apply` clones selected repositories, applies the managed baseline, and opens PRs from rollout branches instead of writing to default branches. `scripts/dispatch_account_sync.sh --apply` is intentionally disabled because downstream sync no longer runs through GitHub Actions.

Write-capable rollout requires an explicit local token with access to downstream repositories. `scripts/provision_sync_token_secret.sh` can still provision downstream `CENTRAL_AGENT_SYNC_TOKEN` repository secrets when needed; the value is sent to `gh secret set` over stdin, not stored in the template repository or passed as a command argument.

## Repository metadata and rulesets

`.central-agent/repo-metadata.yml` records the desired public About metadata for the repository. Like repo policy, it is seeded only when missing and then preserved by sync. The shared policy tells agents to update description, homepage, topics, label-derived topic representation, and merge settings when repository purpose, public surface, or governance label taxonomy changes. Repository descriptions stay clear one-sentence purpose statements by default; agents should represent governance labels through GitHub labels and configured topics instead of appending raw issue or PR labels to the description unless the repo metadata file explicitly opts into a description prefix or suffix. `scripts/check_repo_about_metadata.sh OWNER/REPO` compares the live GitHub About metadata with this contract for both personal and organization-owned repositories. If the live description, homepage, or topics are missing or stale, agents should fix that through a dedicated metadata issue and PR unless the current PR is already scoped to repository metadata. Destructive settings such as archive, delete, or visibility changes are outside this baseline.

Managed repos should also have an active repository ruleset for `refs/heads/main` when the agent has admin access. The baseline helper `scripts/ensure_main_branch_ruleset.sh OWNER/REPO` creates or updates a `Main branch protection` ruleset that requires pull requests with zero approvals, conversation resolution, signed commits, linear history, blocks deletions and non-fast-forward updates, and only requires status checks when `.central-agent/repo-policy.yml` configures `branch_ruleset.required_status_check`. If the required check name is unclear or the agent lacks admin access, the agent records the blocker in the PR and opens a follow-up issue before merge.
