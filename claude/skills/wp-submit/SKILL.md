---
name: wp-submit
description: Human-approved submission of a verified WordPress Core fix - push the fix branch to the contributor's fork and open (or update) the PR against WordPress/wordpress-develop, then hand over the Trac comment to paste.
argument-hint: <ticket-number>
arguments: ticket
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PROJECT_DIR}/.claude/wp-tools/*) Bash(.claude/wp-tools/*)
---

# Submit #$ticket (human-initiated)

!`${CLAUDE_PROJECT_DIR}/.claude/wp-tools/context.sh $ticket`

This skill only runs when {{WPORG_USER}} types `/wp-submit`. Every public action still goes
through the permission prompt. Never bypass the guard hook; if it blocks, report why.

## 1. Preconditions (stop on the first failure and say which)
- On branch `fix/$ticket-*`, tree clean, ledger state `ready-for-review` or `changes-requested`.
- `.wp-contrib/$ticket/verification.json` has `status: pass` and `head` equal to `git rev-parse HEAD`.
  If HEAD moved, re-run `.claude/wp-tools/verify-patch.sh $ticket` with the same flags as before.
- `.wp-contrib/$ticket/review.md` exists for this HEAD with no open blocking items.
- `pr-description.md` has the AI assistance section; drafts contain no placeholder `<...>` text.
- Branch is rebased on current `upstream/trunk` (if not: rebase, re-verify, and restart here).

## 2. Show the human what will go public
Print, in this order: the `git diff --stat upstream/trunk...HEAD`, the commit messages, the
verification table, the reviewer verdict, the "Not tested" list, and the PR title + body.
Then ask with AskUserQuestion:
"Have you read every line of the diff and checked the PR description is accurate?"
Options: "Yes, submit" / "Not yet". Anything but an explicit yes → stop.

On yes: write `git rev-parse HEAD` as the first line of `.wp-contrib/$ticket/approval.txt`
(second line: UTC timestamp), and remove the HUMAN CHECKLIST comment block from
`pr-description.md`.

## 3. Publish (each command triggers a permission prompt)
Flow: one ticket = one branch `fix/$ticket-<slug>` = one PR. The branch is pushed to your
fork (`origin`) only; the PR goes from `<fork-owner>:fix/$ticket-<slug>` into
`WordPress/wordpress-develop:trunk`. Nothing is ever pushed to WordPress/wordpress-develop.
- Fork owner: parse it from `git remote get-url origin` (e.g. `git@github.com:ruman/wordpress-develop.git` → `ruman`).
- Push the ticket branch to your fork: `git push --force-with-lease -u origin HEAD`
- New PR: `gh pr create -R WordPress/wordpress-develop --base trunk --head <fork-owner>:<branch> --title "<title from pr-description.md>" --body-file .wp-contrib/$ticket/pr-description.md`
- Existing PR (ledger has `pr`): the push updates it. Only run `gh pr edit` if the
  description changed materially.
Record: `ledger.sh set $ticket submitted pr=<url> head=<sha>`.

## 4. Hand over the Trac step
Fill the PR URL into `trac-comment.txt` and print it in a code block. Tell {{WPORG_USER}} to
paste it on https://core.trac.wordpress.org/ticket/$ticket and apply the suggested keywords.
(PRs whose description contains the Trac ticket URL are normally linked on the ticket
automatically; check the ticket shows it.) Remind them that `/wp-feedback $ticket` tracks
reviews from here.
