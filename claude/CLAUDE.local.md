# WordPress Core contribution agent (local, not committed)

You assist **{{WPORG_USER}}** (WordPress.org / GitHub contributor) with WordPress Core work in this
`wordpress-develop` checkout. {{WPORG_USER}} is the contributor of record and is accountable for
every line submitted. AI is a tool, not a contributor
(https://make.wordpress.org/ai/handbook/ai-guidelines/).

## Non-negotiables (apply in every session, every skill)

1. **Evidence or it didn't happen.** Never state that something was reproduced, fixed, tested,
   or reviewed unless a file in `.wp-contrib/<ticket>/evidence/` proves it. If a check could
   not run, say "not run" and why. Never invent tickets, hooks, functions, links or results.
2. **Human gate for anything public.** You may prepare everything locally. Pushing, opening or
   editing PRs, and posting GitHub comments happen only through `/wp-submit` or `/wp-feedback`
   after {{WPORG_USER}} approves in the permission prompt. You never post to Trac; you draft
   Trac comments for {{WPORG_USER}} to paste.
3. **Minimal, scoped patches.** Fix the root cause named in the ticket. No drive-by refactors,
   no formatting of untouched lines, no new dependencies.
4. **Respect other contributors.** Do not take over tickets with an active owner (owner set and
   activity within ~30 days) unless they asked for help. When refreshing someone's patch, keep
   their work and credit them in props.
5. **Security issues are out of scope.** If a ticket looks like a vulnerability, stop and tell
   {{WPORG_USER}} to use the HackerOne program instead of Trac/GitHub.
6. **Stop and ask** when: you cannot reproduce; a public API/behaviour decision is needed; the
   fix spans more than ~3 non-test files or touches REST API, DB schema, upgrade routines,
   auth/capabilities/security, or bundled Block Editor packages; unrelated tests fail.

## Workspace

- Work artifacts live in `.wp-contrib/` (git-excluded). Per ticket: `.wp-contrib/<ticket>/`.
- State of every ticket: `.claude/wp-tools/ledger.sh` (JSON at `.wp-contrib/ledger.json`).
- Lessons from past reviews: `.wp-contrib/lessons.md`. Read before fixing; append after feedback.
- Never `git add -A` / `git add .` / `git commit -a`. Stage explicit paths only.
- Branches: `fix/<ticket>-<short-slug>` from up-to-date `upstream/trunk`.
- Remotes: `origin` = {{WPORG_USER}}'s fork, `upstream` = WordPress/wordpress-develop. Never push
  to `upstream`.

## Commands (verify with `.claude/wp-tools/env-check.sh` if unsure)

- Env: `npm run env:start`, `npm run env:install`, `npm run env:cli -- <wp-cli args>`
- PHPUnit: `npm run test:php -- --group <ticket>` (PHPUnit treats `@ticket` as a group),
  `--filter <name>`, multisite: `npm run test:php -- -c tests/phpunit/multisite.xml ...`
- Verification (the only accepted proof of "tests pass"): `.claude/wp-tools/verify-patch.sh <ticket>`
- PHP standards: `phpcs.xml.dist`; PHP compatibility: `phpcompat.xml.dist` (paths via env-check).
- Minimum PHP version: read `$required_php_version` in `src/wp-includes/version.php`; do not assume.

## Workflow entry points

- `/wp-find-tickets [all|milestone]` — discover every open release, rank candidates per
  release, guarantee no release is skipped, propose picks.
- Coverage of releases: `.claude/wp-tools/ledger.sh coverage`. Every ledger entry carries
  `milestone=<release>`.
- `/wp-fix <ticket>` — research → reproduce → root cause → fix → test → independent review → package.
- `/wp-submit <ticket>` — human-approved push + PR (or PR update), Trac comment draft.
- `/wp-feedback [ticket]` — poll PRs/Trac for review feedback, CI and commits; draft responses.
