---
name: wp-find-tickets
description: Find the WordPress Core Trac tickets worth contributing to across every open release (current major, its beta/RC, upcoming minor releases, next major) so no release is skipped; ranks fixable candidates per release with the right contribution type and asks which to start. Use when the user asks what to work on, to find or triage tickets, or to plan contributions for a release.
argument-hint: "[all | milestone] [candidates per release, default 5]"
arguments: scope per_release
allowed-tools: Bash(${CLAUDE_PROJECT_DIR}/.claude/wp-tools/*) Bash(.claude/wp-tools/*)
---

# Find tickets to contribute, covering every open release

!`${CLAUDE_PROJECT_DIR}/.claude/wp-tools/context.sh`

Scope: "$scope" (empty or `all` = every open release). Candidates per release: "$per_release" (default 5).
Goal: every open release gets at least one realistic contribution from {{WPORG_USER}}. Read
`references/release-rules.md` before ranking.

## 1. Discover releases
Run `.claude/wp-tools/releases.sh`. It writes `.wp-contrib/releases.json` (name, major/minor,
phase alpha/beta/rc/minor). If it reports that Trac's roadmap was unreachable, show the list
and ask {{WPORG_USER}} to confirm it against https://core.trac.wordpress.org/roadmap (add or
remove names by editing `releases.json`). Never silently drop a release.

## 2. Export tickets for each release
For each release: `.claude/wp-tools/fetch-trac.sh query <name>`. On exit 3 (Trac blocked the
request), collect the printed URLs for **all** blocked releases into one message and ask the
human to save each CSV (Trac page → "Download in other formats: Comma-delimited Text") to
the given path. If a browser tool is available in this session, you may open the URLs there
and download them instead. Continue once the files exist; a release without a CSV stays
listed as "NOT COVERED".

## 3. Rank deterministically
Run `.claude/wp-tools/rank-tickets.py --top <per_release>` (add `--only <name>` for a single
milestone). It applies phase gates, skips decision-blocked/active-owner/already-handled
tickets, assigns a contribution type (fix | refresh | add-tests | test-patch) and writes
`.wp-contrib/triage/shortlist.md`. Do not re-score by hand; if a rule looks wrong, say so.

## 4. Research the shortlist
Delegate each top candidate to **wp-ticket-researcher** ("Research ticket <id>"), up to 4 in
parallel, nearest release first (rc → beta → minor → alpha). Stop researching a release once
it has 2 ELIGIBLE tickets, to save effort. For each verdict:
`ledger.sh set <id> candidate milestone=<release> contribution=<type>` or
`ledger.sh set <id> skipped milestone=<release> reason="..."`.

## 5. Guarantee coverage
For every release with no ELIGIBLE ticket after research, look for lighter contributions in
this order and research one:
1. `test-patch`: a ticket with `has-patch needs-testing` (a written test report earns props).
2. `add-tests`: `has-patch needs-unit-tests`.
3. Reviewing an open PR linked to a ticket in that release.
If there is still nothing, write the concrete reason (e.g. "7.1.3: 2 open tickets, both owned
and active"). That is a reported gap, not a silent skip.

## 6. Write the plan and ask
Write `.wp-contrib/triage/plan.md`:

| Release | Phase | Ticket | Contribution | Effort S/M/L | Why now | Deadline pressure |

Then run `ledger.sh coverage` and show it. Present the recommended pick **per release**
with AskUserQuestion (one question per release, max 4; options = top 2-3 tickets plus
"Skip this release for now"). Releases in rc/beta come first because their window closes
soonest. Then tell the human to run `/wp-fix <id>` for each pick (or start the first if they
asked you to continue).

Never pad: if a release has one good option, offer one. Never mark a release covered until
a ticket for it reaches `submitted`.
