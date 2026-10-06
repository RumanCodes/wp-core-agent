#!/usr/bin/env bash
# PreToolUse guard for Bash. Exit 2 = block (stderr is shown to Claude). Exit 0 = continue
# to the normal permission flow (allow/ask/deny rules in settings still apply).
#
# This is defence in depth, not a sandbox: it pattern-matches command text. The real
# human gate is the "ask" permission prompt on git push / gh pr create.
set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$root" 2>/dev/null || exit 0

block() { echo "BLOCKED by wp-core guard: $*" >&2; exit 2; }

# Normalise whitespace for matching.
c="$(printf '%s' "$cmd" | tr '\n' ' ' | tr -s ' ')"

# --- Staging hygiene: never sweep unrelated files into a patch.
if printf '%s' "$c" | grep -Eq '(^|[;&| ])git add (-A|--all|\.( |$)|-u( |$)|--update)'; then
	block "stage explicit paths only (no 'git add -A/./-u')."
fi
if printf '%s' "$c" | grep -Eq '(^|[;&| ])git commit( [^;&|]*)? (-a|--all|-am)( |$)'; then
	block "no 'git commit -a'; stage explicit paths."
fi

# --- Never push to WordPress upstream, never plain-force-push.
if printf '%s' "$c" | grep -Eq '(^|[;&| ])git push'; then
	if printf '%s' "$c" | grep -Eqi 'git push[^;&|]*(upstream|wordpress/wordpress-develop)'; then
		block "pushing to upstream WordPress/wordpress-develop is not allowed."
	fi
	if printf '%s' "$c" | grep -Eq 'git push[^;&|]*( -f( |$)|--force( |$))'; then
		block "use --force-with-lease (to your fork's fix branch), never --force."
	fi
	if printf '%s' "$c" | grep -Eq 'git push[^;&|]*[ :](trunk|master|main)( |$)'; then
		block "never push trunk; push fix/<ticket>-<slug> branches only."
	fi
	# Only ever push to 'origin', and only if origin is the contributor's fork.
	printf '%s' "$c" | grep -Eq 'git push( +-[^ ]+)* +origin( |$)' ||
		block "push must name the 'origin' remote (your fork) explicitly, e.g. git push --force-with-lease -u origin HEAD."
	o_url="$(git remote get-url origin 2>/dev/null)"
	if [ -z "$o_url" ] || printf '%s' "$o_url" | grep -Eqi '[:/]wordpress/wordpress-develop(\.git)?$'; then
		block "'origin' ($o_url) is not your fork. Point origin at <you>/wordpress-develop."
	fi
fi

# --- Never write to Trac programmatically. Drafts only; the human posts.
if printf '%s' "$c" | grep -Eqi 'trac\.wordpress\.org' &&
	printf '%s' "$c" | grep -Eq '(-X *(POST|PUT|PATCH|DELETE)|--data|(^| )-d |(^| )-F |--form|xmlrpc)'; then
	block "writing to Trac is not allowed; draft trac-comment.txt for the human to post."
fi

# --- Read-only gh api unless it is a GET.
if printf '%s' "$c" | grep -Eq '(^|[;&| ])gh api' &&
	printf '%s' "$c" | grep -Eq '(-X|--method) *(POST|PUT|PATCH|DELETE)|(^| )(-f|-F|--field|--raw-field|--input) '; then
	block "gh api writes are not allowed from the agent; use gh pr comment via /wp-feedback."
fi

# --- Submission gate: push / PR create / PR edit require fresh verification + human approval.
if printf '%s' "$c" | grep -Eq '(^|[;&| ])(git push|gh pr create|gh pr edit)'; then
	branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
	ticket="$(printf '%s' "$branch" | sed -nE 's#^fix/([0-9]+)-.*#\1#p')"
	[ -z "$ticket" ] && block "current branch '$branch' is not fix/<ticket>-<slug>."
	head="$(git rev-parse HEAD)"
	dir=".wp-contrib/$ticket"
	ver="$dir/verification.json"
	[ -f "$ver" ] || block "no $ver. Run .claude/wp-tools/verify-patch.sh $ticket first."
	vstatus="$(jq -r '.status' "$ver")"
	vhead="$(jq -r '.head' "$ver")"
	[ "$vstatus" = "pass" ] || block "verification status is '$vstatus', not 'pass'."
	[ "$vhead" = "$head" ] || block "verification is for $vhead but HEAD is $head. Re-run verify-patch.sh."
	[ -n "$(git status --porcelain --untracked-files=no)" ] && block "working tree has uncommitted changes."
	appr="$dir/approval.txt"
	[ -f "$appr" ] && [ "$(head -n1 "$appr")" = "$head" ] ||
		block "no human approval recorded for $head. Use /wp-submit $ticket."
fi

exit 0
