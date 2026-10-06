#!/usr/bin/env bash
# Verify the local wordpress-develop setup and record what tooling is available.
# Writes .wp-contrib/env.json. Exit 1 if a blocking problem is found.
# Usage: env-check.sh [--smoke]   (--smoke also runs one tiny PHPUnit test)
set -uo pipefail
root="$(git rev-parse --show-toplevel)" || { echo "not a git repo"; exit 1; }
cd "$root"
mkdir -p .wp-contrib
problems=(); notes=()

up="$(git remote get-url upstream 2>/dev/null || true)"
og="$(git remote get-url origin 2>/dev/null || true)"
[[ "$up" == *WordPress/wordpress-develop* ]] || problems+=("remote 'upstream' must point to WordPress/wordpress-develop (is: ${up:-missing})")
[[ -n "$og" && "$og" != *WordPress/wordpress-develop* ]] || problems+=("remote 'origin' must be your fork (is: ${og:-missing})")
[ -f src/wp-includes/version.php ] || problems+=("src/wp-includes/version.php missing: not a wordpress-develop checkout?")

git fetch -q upstream trunk 2>/dev/null || notes+=("could not fetch upstream/trunk")
behind="$(git rev-list --count trunk..upstream/trunk 2>/dev/null || echo '?')"
[ "$behind" = "0" ] || notes+=("local trunk is $behind commits behind upstream/trunk (run: git switch trunk && git merge --ff-only upstream/trunk)")

wp_version="$(sed -nE "s/^\\\$wp_version = '([^']+)'.*/\\1/p" src/wp-includes/version.php 2>/dev/null)"
req_php="$(sed -nE "s/^\\\$required_php_version = '([^']+)'.*/\\1/p" src/wp-includes/version.php 2>/dev/null)"

have() { command -v "$1" >/dev/null 2>&1 && echo true || echo false; }
docker_up=false
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qi 'wordpress'; then docker_up=true; fi
[ "$docker_up" = true ] || notes+=("local env not running (npm run env:start)")

phpcs=false; [ -x vendor/bin/phpcs ] && [ "$(have php)" = true ] && phpcs=true
[ "$phpcs" = true ] || notes+=("host PHPCS unavailable: install PHP + run 'composer install' so lint can run")
[ -f phpcompat.xml.dist ] && compat=true || compat=false

gh_ok=false; gh auth status >/dev/null 2>&1 && gh_ok=true
[ "$gh_ok" = true ] || notes+=("gh not authenticated (needed for PR lookups and /wp-submit)")
[ "$(have jq)" = true ] || problems+=("jq is required")

npm_scripts="$(jq -c '.scripts | keys' package.json 2>/dev/null || echo '[]')"
composer_scripts="$(jq -c '.scripts | keys' composer.json 2>/dev/null || echo '[]')"

smoke="not run"
if [ "${1:-}" = "--smoke" ] && [ "$docker_up" = true ]; then
	# Pick a real, small test class from the checkout rather than guessing a name.
	f="$(ls -S tests/phpunit/tests/formatting/*.php 2>/dev/null | tail -n 1)"
	cls="$(sed -nE 's/^class ([A-Za-z0-9_]+) extends WP_UnitTestCase.*/\1/p' "$f" 2>/dev/null | head -n1)"
	if [ -z "$cls" ]; then smoke="skipped (no test class found)";
	elif npm run test:php -- --filter "$cls" >.wp-contrib/env-smoke.log 2>&1; then smoke="pass ($cls)";
	else smoke="fail ($cls, see .wp-contrib/env-smoke.log)"; problems+=("PHPUnit smoke test failed"); fi
fi

jq -n --arg wp "$wp_version" --arg php "$req_php" --argjson docker "$docker_up" \
	--argjson phpcs "$phpcs" --argjson compat "$compat" --argjson gh "$gh_ok" \
	--arg behind "$behind" --arg smoke "$smoke" --argjson npm "$npm_scripts" --argjson composer "$composer_scripts" \
	--arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	'{checked_at:$at, wp_version:$wp, required_php:$php, env_running:$docker, host_phpcs:$phpcs,
	  phpcompat_ruleset:$compat, gh_authenticated:$gh, trunk_behind_upstream:$behind,
	  phpunit_smoke:$smoke, npm_scripts:$npm, composer_scripts:$composer}' >.wp-contrib/env.json

cat .wp-contrib/env.json
for n in ${notes[@]+"${notes[@]}"}; do echo "NOTE: $n"; done
for p in ${problems[@]+"${problems[@]}"}; do echo "PROBLEM: $p"; done
[ "${#problems[@]}" -eq 0 ]
