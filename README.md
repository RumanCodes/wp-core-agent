# WordPress Core Contribution Agent for Claude Code

A reusable, human-supervised agent for contributing to WordPress Core from a local
`wordpress-develop` checkout: triage → research → reproduce → root cause → minimal fix →
regression test → verification → independent review → PR → Trac → reviewer feedback.

## Architecture

| Layer | File(s) | Loaded | Holds |
|---|---|---|---|
| Always-on rules | `.claude/wp-core-agent.md` (imported by `CLAUDE.local.md`) | every session | identity, non-negotiables, stop conditions, commands. Short on purpose. |
| Workflows (skills) | `skills/wp-find-tickets`, `wp-fix`, `wp-submit`, `wp-feedback` | on demand | step-by-step procedures, gates, output shapes |
| Reference | `wp-fix/references/*.md`, `wp-fix/templates/*` | when the skill reads them | standards checklist, testing guide, deliverable templates |
| Isolated workers (subagents) | `agents/wp-ticket-researcher.md` (Sonnet), `agents/wp-patch-reviewer.md` (Opus, read-only, project memory) | when delegated | long ticket threads; an independent second opinion that never saw the author's reasoning |
| Deterministic tools | `wp-tools/*.sh` | called by skills | fetching Trac, env checks, the ticket ledger, and `verify-patch.sh` (the evidence engine) |
| Hard guardrails | `hooks/guard-bash.sh`, `hooks/precommit-phpcs.sh`, `settings.local.json` | every tool call | rules that must never depend on the model remembering them |

Rule of thumb used to split things: anything that must hold every time is a **hook or
permission**; anything that must be computed is a **script**; anything that needs judgment
is a **skill**; anything that would flood context or needs fresh eyes is a **subagent**;
only the few rules that apply everywhere live in **always-on context**.

### What changed versus the original prompt
- The single prompt became 4 skills, so each phase loads only when needed and survives
  compaction better; the always-on part is ~40 lines.
- "Never fabricate test results" is enforced, not requested: `verify-patch.sh` runs the
  new tests against trunk with your `src/` changes reverted (must fail) and at HEAD (must
  pass), runs PHPCS/PHPCompatibility on changed files, and writes `verification.json`
  bound to the commit SHA. Missing lint makes the status `incomplete`, never `pass`.
- Push and PR creation are blocked by a hook unless verification is `pass` for the
  current HEAD **and** you approved that exact HEAD in `/wp-submit`. Each push/PR still
  needs your click in the permission prompt. Pushing to `upstream`, `--force`, pushing
  `trunk`, `git add -A`, `gh api` writes and any write to Trac are blocked outright.
- An independent reviewer subagent checks the diff with no access to the author's reasoning.
- A ledger tracks every ticket's state; `/wp-feedback` turns review comments into
  `lessons.md`, which is injected into every future fix and checked by the reviewer.
- AI disclosure follows the current WordPress AI Guidelines format
  (`AI assistance / Tool(s) / Used for`).

## Install

Works on macOS with its stock tools (bash 3.2, BSD sed/grep/date, Apple Python 3) and on
Linux. Every script is tested under bash 3.2. On Windows, use WSL.

Requirements on your machine: Claude Code, git, jq, python3, curl, `gh` (authenticated),
Node/npm + Docker for `wordpress-develop`, and **PHP + `composer install`** in the checkout so
PHPCS can run on the host.

```bash
unzip wp-core-agent.zip && cd wp-core-agent
tests/test-hooks.sh                                  # guard tests, should all pass
./install.sh ~/path/to/wordpress-develop <your-wporg-username>
cd ~/path/to/wordpress-develop
.claude/wp-tools/env-check.sh --smoke                # fix any PROBLEM lines
git status                                           # must show nothing from the agent
claude                                               # accept the trust prompt (needed for hooks)
```

Everything installs as local-only files listed in `.git/info/exclude`, so nothing reaches
your commits. Existing `settings.local.json` is merged (with a backup), not overwritten.

## Use

| Command | What happens | Who triggers |
|---|---|---|
| `/wp-find-tickets [all\|milestone] [n]` | Discovers every open release, exports and ranks tickets per release with phase rules, researches the best, guarantees each release gets a candidate (or a stated reason), asks you to pick per release | you or Claude |
| `/wp-fix <ticket>` | Full investigation-to-package loop with gates; stops and asks on any stop condition | you or Claude |
| `/wp-submit <ticket>` | Shows the diff, evidence and PR text, asks for your explicit approval, pushes to your fork, opens/updates the PR, prints the Trac comment to paste | **you only** |
| `/wp-feedback [ticket]` | Reads PR reviews, inline comments, CI and Trac; classifies; drafts replies or fixes locally; records lessons | you or Claude |

To keep checking reviews automatically, schedule `/wp-feedback` daily with Claude Code's
scheduled tasks or `/loop` (it is read-only apart from local drafts).

### Contributing to every release

`/wp-find-tickets` never works from a single hard-coded milestone. `releases.sh` derives the
open releases from your checkout and unions them with the Trac roadmap when Trac answers:

- the major in development (from `upstream/trunk`'s `version.php`), with its phase (alpha/beta/RC)
- any release branch not yet tagged (a major in beta/RC)
- the next minor after the newest tag (e.g. `7.1.2` → `7.1.3`)
- the next major after trunk, for larger work that misses the current window

`rank-tickets.py` applies the handbook's phase rules: no enhancements after Beta 1, only
regressions in RC, no new files in minors. Nearer releases rank higher because their window
closes first. When a release has nothing fixable, the skill drops to lighter contributions:
testing a `needs-testing` patch, adding unit tests to `has-patch` tickets, or reviewing a
linked PR. If nothing fits, it says why; a release is never dropped silently.

`ledger.sh coverage` shows per release: candidates, in progress, submitted, committed,
and **NOT COVERED** for any open release with no work yet. Running `/wp-find-tickets` weekly
(as a scheduled task on your computer) picks up new milestones as soon as they open, such
as a new minor right after a release.

Trac posting stays manual: Trac has no supported write API for this, and the WordPress AI
Guidelines make you accountable for every comment, so the agent drafts and you paste.

## Testing the agent itself

1. **Unit tests** — `tests/test-hooks.sh` covers every guard rule (run after any hook edit).
2. **Behaviour evals** — `evals/scenarios.md` has 10 scenarios (golden path on your 3 already
   committed fixes, cannot-reproduce, active owner, security report, pressure to skip tests,
   weak test, lint unavailable, feedback loop, scope creep). Run each in a fresh session.
   For the golden path, check out the commit before the real Core fix so the committed
   changeset is the answer key.
3. Optional: the `skill-creator` plugin can run these as A/B evals between skill versions.

## Improving it over time

- **Lessons loop**: every general review comment becomes one line in `.wp-contrib/lessons.md`
  (via `/wp-feedback`). Prune it monthly; promote recurring items into
  `references/standards-checklist.md`.
- **Reviewer memory**: `wp-patch-reviewer` keeps project memory in
  `.claude/agent-memory/wp-patch-reviewer/`. Skim it occasionally for wrong lessons.
- **Failure → guardrail**: when the agent does something wrong once, add a line to the skill.
  When it does it twice, make it a hook or a check in `verify-patch.sh`, then add a case to
  `tests/test-hooks.sh` or `evals/scenarios.md`.
- **Metrics** from the ledger: tickets attempted vs. ready vs. committed, review rounds per
  PR, and how often `fails_before` caught a weak test. Falling acceptance means tighten triage.
- **Keep it current**: re-read the WordPress AI Guidelines and Core handbook each release
  cycle; update `@since` handling when trunk's version changes (it is read from `version.php`).

## Known limits

- The guard hook matches command text; it is a safety net, not a sandbox. The permission
  `ask` prompt on push/PR is the real gate, so read those prompts.
- `approval.txt` is written by the agent after you answer "Yes, submit"; it records your
  answer, it does not prove you read the diff. That part is on you, as the guidelines require.
- Trac may block scripted requests. `fetch-trac.sh` detects this and tells you how to export
  the CSV from your browser; the researcher subagent falls back to WebFetch.
- PHPCS runs on the host. Without PHP + `composer install`, verification stays `incomplete`.
# wp-core-agent
