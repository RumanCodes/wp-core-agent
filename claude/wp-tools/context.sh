#!/usr/bin/env bash
# Prints session context for skills (injected via !`...`). Always exits 0.
# Usage: context.sh [ticket]
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "(not in a git repo)"; exit 0; }
cd "$root" || exit 0
t="${1:-}"
echo "## Repo state"
echo "- branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
echo "- HEAD: $(git log -1 --format='%h %s' 2>/dev/null)"
echo "- uncommitted files: $(git status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')"
echo "- behind upstream/trunk: $(git rev-list --count HEAD..upstream/trunk 2>/dev/null || echo '?')"
if [ -f .wp-contrib/env.json ]; then
	echo "- env (checked $(jq -r .checked_at .wp-contrib/env.json)): WP $(jq -r .wp_version .wp-contrib/env.json), min PHP $(jq -r .required_php .wp-contrib/env.json), env_running=$(jq -r .env_running .wp-contrib/env.json), host_phpcs=$(jq -r .host_phpcs .wp-contrib/env.json)"
else
	echo "- env: never checked. Run .claude/wp-tools/env-check.sh"
fi
if [ -n "$t" ]; then
	echo; echo "## Ledger entry for #$t"
	jq --arg t "$t" '.[$t] // "none"' .wp-contrib/ledger.json 2>/dev/null || echo "none"
	if [ -d ".wp-contrib/$t" ]; then
		echo; echo "## Existing artifacts for #$t"
		(cd ".wp-contrib/$t" && find . -maxdepth 2 -type f | sort | head -n 40)
	fi
else
	echo; echo "## Ledger"
	jq -r 'to_entries[] | "- #\(.key): \(.value.state) \(.value.pr // "")"' .wp-contrib/ledger.json 2>/dev/null || echo "(empty)"
fi
if [ -f .wp-contrib/releases.json ]; then
	echo; echo "## Open releases (from releases.json)"
	jq -r '.[] | "- \(.name) (\(.kind), \(.phase))"' .wp-contrib/releases.json
fi
echo; echo "## Lessons from past reviews (apply these)"
if [ -f .wp-contrib/lessons.md ]; then tail -n 40 .wp-contrib/lessons.md; else echo "(none yet)"; fi
exit 0
