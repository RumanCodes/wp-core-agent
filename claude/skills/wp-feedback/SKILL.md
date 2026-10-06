---
name: wp-feedback
description: Check submitted WordPress Core PRs and their Trac tickets for new reviews, comments, CI failures, merges or commits; classify each item and draft responses or follow-up fixes. Use when the user asks about review status, feedback, or what changed on their Core PRs.
argument-hint: "[ticket-number | all]"
arguments: ticket
allowed-tools: Bash(${CLAUDE_PROJECT_DIR}/.claude/wp-tools/*) Bash(.claude/wp-tools/*) Bash(gh pr view *) Bash(gh pr checks *) Bash(gh pr diff *)
---

# Review feedback tracker

!`${CLAUDE_PROJECT_DIR}/.claude/wp-tools/context.sh $ticket`

Scope: ticket "$ticket" if given, otherwise every ledger entry in `submitted`,
`changes-requested` or `approved-by-reviewer`.

## 1. Collect (read-only)
For each ticket (with PR number `n` from the ledger):
- `gh pr view <n> -R WordPress/wordpress-develop --json state,mergedAt,closedAt,reviewDecision,reviews,comments,latestReviews,commits,updatedAt`
- Inline review comments: `gh api repos/WordPress/wordpress-develop/pulls/<n>/comments` (GET only).
- `gh pr checks <n> -R WordPress/wordpress-develop`
- Trac: `.claude/wp-tools/fetch-trac.sh ticket <id>`; new items are those after the ledger's
  `last_checked`.
Save everything new to `.wp-contrib/<id>/feedback/<UTC date>.md` with links.

## 2. Classify each new item
- **Committed / closed**: ticket closed as fixed with a changeset, or PR closed by a committer
  referencing a changeset → `ledger.sh set <id> committed changeset=<n>`. Congratulate briefly.
- **Change request**: concrete code change asked by a reviewer.
- **Question**: needs an answer, not code.
- **CI failure**: read the failing job log (`gh run view <id> --log-failed`); decide if caused
  by this PR or pre-existing/flaky (check the same job on trunk).
- **Approval / testing report**: note it.
- **Direction change**: a committer suggests a different approach, closing, or punting →
  NEEDS HUMAN; do not argue or rework without the human.

## 3. Act
- Change requests and PR-caused CI failures: set `changes-requested`, then run the `/wp-fix`
  loop phases 5-8 on the existing branch (minimal change, verify, reviewer). Do not push;
  tell the human to run `/wp-submit <id>` when ready.
- Questions: draft a reply in `.wp-contrib/<id>/feedback/reply-draft.md`, grounded in code
  and evidence. Posting it (`gh pr comment`) needs the human's approval in the permission
  prompt; Trac replies are pasted by the human.
- Never resolve reviewer threads, dismiss reviews, or re-request review on the human's behalf.

## 4. Learn
For every change request that reflects a general rule (not ticket-specific), add one line:
`.claude/wp-tools/ledger.sh lesson "<rule in imperative form>" "<comment URL>"`.
Skip it if an equivalent lesson already exists. These lessons are injected into every
future `/wp-fix` run and the reviewer checks them.

## 5. Report
Then `ledger.sh set <id> <state> last_checked=<now>` for each ticket and reply with a table:

| Ticket | PR | State | New since last check | Action taken | Needs you? |
