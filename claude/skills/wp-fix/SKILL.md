---
name: wp-fix
description: Investigate and fix one WordPress Core Trac ticket end to end in the local wordpress-develop checkout - research, reproduce on trunk, root cause, minimal fix, regression tests, verification, independent review, and PR/Trac drafts. Use when the user says to work on, fix, refresh or investigate a specific ticket number.
argument-hint: <ticket-number>
arguments: ticket
allowed-tools: Bash(${CLAUDE_PROJECT_DIR}/.claude/wp-tools/*) Bash(.claude/wp-tools/*)
effort: high
---

# Fix WordPress Core ticket #$ticket

!`${CLAUDE_PROJECT_DIR}/.claude/wp-tools/context.sh $ticket`

Work directory for this ticket: `.wp-contrib/$ticket/`. Track progress with a task list
(one task per phase below). Keep narration short; put findings in files.

## Ground rules for this run

- Every claim you make later must point to a file in `.wp-contrib/$ticket/evidence/` or a
  URL you actually opened. Capture command output with `| tee .wp-contrib/$ticket/evidence/<name>.log`.
- Phases are gates. Do not edit `src/` before Phase 4 is written. Do not package before
  `verify-patch.sh` reports `pass` and the reviewer has run.
- On any STOP: set the ledger (`.claude/wp-tools/ledger.sh set $ticket needs-input reason="..."`),
  write what you found and what you need, and end the run. Do not work around a STOP.

## Phase 1 — Research and eligibility

1. If `env.json` is missing or older than a day, run `.claude/wp-tools/env-check.sh`. Fix
   NOTE items you can (start env, fast-forward trunk); report PROBLEM items and STOP.
2. Delegate to the **wp-ticket-researcher** subagent: "Research ticket $ticket." It writes
   `.wp-contrib/$ticket/ticket.md`. Read that file.
3. Verdict SKIP → `ledger.sh set $ticket skipped reason="..."`, report, end.
   Verdict NEEDS-HUMAN or security-looking → STOP.
4. `ledger.sh set $ticket investigating milestone=<milestone from summary.json>`.
5. Release phase check: look up the milestone in `.wp-contrib/releases.json` (run
   `.claude/wp-tools/releases.sh` if missing) and apply
   `.claude/skills/wp-find-tickets/references/release-rules.md`. Beta → no enhancements;
   RC → regressions from this cycle only, no string changes; minor → no new files. A
   ticket that fails its release's gate → STOP and suggest the next major instead.
   Note the phase in `report.md`; for minor-release tickets, the Trac comment suggests a
   backport to the `x.y` branch.

## Phase 2 — Existing work first

If a patch or PR exists: review it before writing anything. Prefer refreshing it (rebase on
trunk, address reviewer feedback, add missing tests) over a new approach. Keep the original
author's commits or credit them in props. Record your assessment in `ticket.md` under
"Existing work assessment". If the existing PR is active (updated < 30 days, author
responsive), STOP and suggest reviewing or testing it instead of competing.

## Phase 3 — Reproduce on current trunk

1. `git switch trunk && git merge --ff-only upstream/trunk`, then
   `git switch -c fix/$ticket-<short-slug>` (or switch to the existing branch).
2. Reproduce in the running env with the smallest possible steps, e.g. a WP-CLI eval:
   `npm run env:cli -- eval '<php>' | tee .wp-contrib/$ticket/evidence/repro-trunk.log`.
   For UI bugs, describe the exact clicks and capture what you observed; ask the human for a
   screenshot if one is needed.
3. Write the regression test now (see `references/testing-guide.md`), run it, and confirm it
   fails for the reason described in the ticket:
   `npm run test:php -- --group $ticket | tee .wp-contrib/$ticket/evidence/test-first-run.log`.
4. Cannot reproduce after a reasonable attempt (different PHP version, multisite, specific
   plugin/theme state, data shape)? Record each attempt and STOP. Never claim reproduction
   you did not observe.

## Phase 4 — Root cause (write before editing src/)

Use `git log -S'<symbol>' --oneline -- <file>`, `git blame -L`, and the changeset/ticket that
introduced the code to understand intent. Fill `templates/root-cause.md` into
`.wp-contrib/$ticket/root-cause.md`. Mark each statement **Confirmed** (evidence file named)
or **Inferred**. The fix must target a Confirmed cause.

STOP if the right fix requires a public API or behaviour decision, more than ~3 non-test
files, or a sensitive area (REST API, DB schema, upgrade routines, auth/caps/security,
bundled Block Editor packages — those usually belong in the Gutenberg repo).

## Phase 5 — Minimal fix

- Change only what the root cause requires. No reformatting of untouched lines.
- Apply `references/standards-checklist.md` to every changed line.
- New functions/params/hooks: DocBlocks with `@since 7.2.0` (or the current trunk version from
  `env.json`). Changed behaviour of an existing function: add an `@since x.y.z <what changed>` line.
- Commit with explicit paths: `git add <paths>`, write the message to
  `.wp-contrib/$ticket/commit-msg.txt`, then `git commit -F .wp-contrib/$ticket/commit-msg.txt`:
  ```
  <Component>: <Imperative summary>.

  <Why, in 1-3 lines.>

  Props {{WPORG_USER}}[, original-patch-author].
  See #$ticket.
  ```
  (Committers add `Fixes #` when they commit; do not add it.)

## Phase 6 — Verify (evidence engine)

Run `.claude/wp-tools/verify-patch.sh $ticket` adding `--also-group <component-group>` for
the related test group(s) and `--multisite` if the code path can run on multisite. UI/JS-only
fix with no PHPUnit test: write manual/E2E evidence first, then pass `--manual-evidence <file>`.

- `fail` → read the logs, fix, commit, re-run. After 3 failed iterations, STOP and report.
- `fails_before: fail` means your test does not reproduce the bug. Fix the test, not the check.
- A related group failing: check whether it also fails on clean trunk (everything is
  committed, so `git switch trunk`, run the group, `git switch -` back). Pre-existing
  failure → record it in `report.md` and STOP to ask.
- `incomplete` (lint skipped) → report exactly which check could not run. Do not call it tested.

## Phase 7 — Independent review

Delegate to **wp-patch-reviewer** with only: "Review ticket $ticket." Do not pass your
reasoning. Then:
- CHANGES REQUIRED → address each blocking item (or write why you disagree), commit, re-run
  Phase 6, and run the reviewer again. Max 2 rounds, then STOP with the open items.
- NEEDS HUMAN DECISION → STOP.

## Phase 8 — Package for the human

Fill from `templates/` into `.wp-contrib/$ticket/`:
- `pr-description.md` — every statement backed by evidence; test commands copied from
  `verification.json`; AI disclosure filled truthfully; leave the human-review checkbox unticked.
- `trac-comment.txt` — Trac wiki markup, under ~12 lines.
- `report.md` — what was tested, what was NOT tested, risks, open questions.

Re-read both drafts against `verification.json` and `review.md`; delete any sentence you
cannot back. Then `ledger.sh set $ticket ready-for-review branch=<branch> head=<sha>`.

## Final message to the human (exact shape)

- Ticket: #$ticket, <title> — <ticket URL>
- Outcome: Ready for review | Needs input (<question>) | Skipped (<reason>)
- Files changed: `<path>` — <one line each>
- Verification: <status> @ <short sha>; each check name → pass/fail/n/a
- Reviewer verdict: <verdict>, <n> blocking resolved, <n> open
- Not tested: <list>
- Next: read the diff (`git diff upstream/trunk...HEAD`), then `/wp-submit $ticket`

## Supporting files

- `references/standards-checklist.md` — WPCS + security + docs checklist
- `references/testing-guide.md` — PHPUnit conventions, multisite, E2E, evidence capture
- `templates/root-cause.md`, `templates/pr-description.md`, `templates/trac-comment.txt`, `templates/report.md`
