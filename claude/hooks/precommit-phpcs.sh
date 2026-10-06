#!/usr/bin/env bash
# PreToolUse hook: before any `git commit`, run PHPCS on staged PHP files.
# Blocks the commit (exit 2) on coding-standard errors. Does not block when PHPCS is
# unavailable; verify-patch.sh then records lint as "skipped" and refuses a "pass".
set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
printf '%s' "$cmd" | grep -Eq '(^|[;&| ])git commit' || exit 0

root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$root" 2>/dev/null || exit 0

files=(); while IFS= read -r l; do [ -n "$l" ] && files+=("$l"); done < <(git diff --cached --name-only --diff-filter=ACMR -- '*.php')
[ "${#files[@]}" -eq 0 ] && exit 0

if [ -x vendor/bin/phpcs ] && command -v php >/dev/null 2>&1; then
	if ! out="$(vendor/bin/phpcs --standard=phpcs.xml.dist --report=summary -q "${files[@]}" 2>&1)"; then
		full="$(vendor/bin/phpcs --standard=phpcs.xml.dist -q "${files[@]}" 2>&1 | head -n 80)"
		echo "BLOCKED: PHPCS errors in staged files. Fix them (vendor/bin/phpcbf may help on touched lines only):" >&2
		echo "$full" >&2
		exit 2
	fi
else
	echo "NOTE: PHPCS not available on host (need php + vendor/bin/phpcs via 'composer install'). Lint NOT run for this commit; report it as not run." >&2
	# exit 0 so the commit proceeds; verify-patch.sh will mark lint as 'skipped' and refuse 'pass'.
fi
exit 0
