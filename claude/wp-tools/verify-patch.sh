#!/usr/bin/env bash
# Verify a fix branch and write sha-bound evidence. This is the ONLY accepted proof that
# a patch is tested. Output: .wp-contrib/<ticket>/verification.json + evidence/*.log
#
# Usage: verify-patch.sh <ticket> [--also-group <g>]... [--multisite]
#                                 [--manual-evidence <file>]   # for JS/CSS/UI-only fixes
#
# Checks (required unless noted):
#   clean_tree        all changes committed (so the sha describes what was tested)
#   regression_test   tests/ diff contains "@ticket <ticket>"   (or --manual-evidence)
#   fails_before      ticket tests FAIL with src/ reverted to the merge-base
#   passes_after      ticket tests PASS at HEAD (and >0 tests ran)
#   related_groups    each --also-group passes at HEAD
#   multisite         ticket tests pass under multisite config (with --multisite)
#   phpcs             PHPCS clean on changed PHP files
#   phpcompat         PHPCompatibility clean on changed src PHP files (if ruleset exists)
#   whitespace        git diff --check clean
#   scope (info)      file counts + sensitive-area flags
# Status: pass | fail | incomplete (a required check was skipped).
set -uo pipefail
t="${1:-}"; shift || true
[[ "$t" =~ ^[0-9]+$ ]] || { echo "usage: verify-patch.sh <ticket> [...]" >&2; exit 1; }
also=(); multisite=false; manual=""
while [ $# -gt 0 ]; do
	case "$1" in
	--also-group) also+=("$2"); shift 2 ;;
	--multisite) multisite=true; shift ;;
	--manual-evidence) manual="$2"; shift 2 ;;
	*) echo "unknown arg $1" >&2; exit 1 ;;
	esac
done

root="$(git rev-parse --show-toplevel)"; cd "$root"
dir=".wp-contrib/$t"; ev="$dir/evidence"; mkdir -p "$ev"
results="$(mktemp)"; echo '[]' >"$results"
add() { # name status detail [log]
	jq --arg n "$1" --arg s "$2" --arg d "$3" --arg l "${4:-}" '. + [{name:$n,status:$s,detail:$d,log:$l}]' "$results" >"$results.t" && mv "$results.t" "$results"
	printf '%-16s %-8s %s\n' "$1" "$2" "$3"
}

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" =~ ^fix/$t- ]] || { echo "on '$branch'; expected fix/$t-<slug>" >&2; exit 1; }
git fetch -q upstream trunk 2>/dev/null || true
head="$(git rev-parse HEAD)"
base="$(git merge-base HEAD upstream/trunk)"

# clean tree
if [ -z "$(git status --porcelain --untracked-files=no)" ]; then add clean_tree pass "all changes committed"
else add clean_tree fail "uncommitted changes present; commit first"; fi

git diff --name-status "$base" "$head" >"$ev/changed-files.txt"
src_files=(); while IFS= read -r l; do [ -n "$l" ] && src_files+=("$l"); done < <(git diff --name-only "$base" "$head" -- src/)
php_files=(); while IFS= read -r l; do [ -n "$l" ] && php_files+=("$l"); done < <(git diff --name-only --diff-filter=ACMR "$base" "$head" -- '*.php')
src_php=(); while IFS= read -r l; do [ -n "$l" ] && src_php+=("$l"); done < <(git diff --name-only --diff-filter=ACMR "$base" "$head" -- 'src/*.php')
nontest=$(git diff --name-only "$base" "$head" | grep -vc '^tests/' || true)
sensitive=$(git diff --name-only "$base" "$head" | grep -E 'rest-api|class-wp-rest|upgrade\.php|schema\.php|wp-db|class-wpdb|capabilities|pluggable\.php|user\.php|kses\.php|src/wp-includes/js/dist|packages/' || true)
add scope info "non-test files: $nontest; sensitive: ${sensitive:-none}"
[ "$nontest" -gt 3 ] && echo "WARNING: more than 3 non-test files changed -> stop condition; ask the human."
[ -n "$sensitive" ] && echo "WARNING: sensitive area touched -> stop condition; ask the human."

# regression test present
has_ticket_test=false
git diff "$base" "$head" -- tests/ | grep -Eq "^\+.*@ticket[[:space:]]+$t([^0-9]|$)" && has_ticket_test=true
run_php() { # label log args...
	local label="$1" log="$2"; shift 2
	npm run test:php -- "$@" >"$log" 2>&1
}
ran_tests() { grep -Eq 'OK \(([1-9][0-9]*) tests?|Tests: [1-9]' "$1"; }

if [ "$has_ticket_test" = true ]; then
	add regression_test pass "tests/ adds @ticket $t"
	# passes_after
	if run_php after "$ev/phpunit-after.log" --group "$t" && ran_tests "$ev/phpunit-after.log"; then
		add passes_after pass "--group $t passes at ${head:0:10}" "$ev/phpunit-after.log"
	else
		add passes_after fail "--group $t fails or ran 0 tests at HEAD" "$ev/phpunit-after.log"
	fi
	# fails_before: revert src/ to base, keep new tests
	if [ "${#src_files[@]}" -eq 0 ]; then
		add fails_before n/a "test-only change (no src/ changes)"
	else
		restore() {
			git checkout -q "$head" -- src/ 2>/dev/null
			git diff --name-only --diff-filter=D "$base" "$head" -- src/ | while IFS= read -r f; do git rm -q -f -- "$f" 2>/dev/null; done
		}
		trap restore EXIT
		git checkout -q "$base" -- src/
		git diff --name-only --diff-filter=A "$base" "$head" -- src/ | while IFS= read -r f; do rm -f -- "$f"; done
		if run_php before "$ev/phpunit-before.log" --group "$t"; then
			add fails_before fail "tests PASS without the fix: they do not reproduce the bug" "$ev/phpunit-before.log"
		elif grep -Eqi 'FAILURES!|ERRORS!|Failures: [1-9]|Errors: [1-9]' "$ev/phpunit-before.log"; then
			add fails_before pass "tests fail on base ${base:0:10} (bug reproduced)" "$ev/phpunit-before.log"
		else
			add fails_before fail "test run failed for a non-assertion reason; inspect log" "$ev/phpunit-before.log"
		fi
		restore; trap - EXIT
		if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
			echo "ERROR: working tree not restored cleanly after fails_before; inspect 'git status'." >&2
			add restore fail "tree dirty after revert/restore"
		fi
	fi
	if [ "$multisite" = true ]; then
		if run_php ms "$ev/phpunit-multisite.log" -c tests/phpunit/multisite.xml --group "$t"; then
			add multisite pass "multisite --group $t" "$ev/phpunit-multisite.log"
		else add multisite fail "multisite run failed" "$ev/phpunit-multisite.log"; fi
	fi
elif [ -n "$manual" ] && [ -s "$manual" ]; then
	cp "$manual" "$ev/manual-verification.md"
	add regression_test manual "no PHPUnit test; manual/E2E evidence: $ev/manual-verification.md" "$ev/manual-verification.md"
else
	add regression_test fail "no '@ticket $t' test added and no --manual-evidence given"
fi

for g in ${also[@]+"${also[@]}"}; do
	if run_php "g-$g" "$ev/phpunit-group-$g.log" --group "$g"; then add "group:$g" pass "related group passes" "$ev/phpunit-group-$g.log"
	else add "group:$g" fail "related group fails (check if pre-existing on trunk)" "$ev/phpunit-group-$g.log"; fi
done

# Lint
PHPCS="${PHPCS_CMD:-vendor/bin/phpcs}"
if [ "${#php_files[@]}" -eq 0 ]; then
	add phpcs n/a "no PHP files changed"; add phpcompat n/a "no PHP files changed"
elif { [ -n "${PHPCS_CMD:-}" ] || { [ -x vendor/bin/phpcs ] && command -v php >/dev/null; }; }; then
	if $PHPCS --standard=phpcs.xml.dist -q "${php_files[@]}" >"$ev/phpcs.log" 2>&1; then add phpcs pass "WPCS clean on ${#php_files[@]} file(s)" "$ev/phpcs.log"
	else add phpcs fail "WPCS violations" "$ev/phpcs.log"; fi
	if [ -f phpcompat.xml.dist ] && [ "${#src_php[@]}" -gt 0 ]; then
		if $PHPCS --standard=phpcompat.xml.dist -q "${src_php[@]}" >"$ev/phpcompat.log" 2>&1; then add phpcompat pass "PHPCompatibility clean" "$ev/phpcompat.log"
		else add phpcompat fail "PHPCompatibility violations" "$ev/phpcompat.log"; fi
	else add phpcompat n/a "no ruleset or no src PHP changes"; fi
else
	add phpcs skipped "PHPCS unavailable on host (install PHP + composer install, or set PHPCS_CMD)"
	add phpcompat skipped "PHPCS unavailable"
fi

if git diff --check "$base" "$head" >"$ev/whitespace.log" 2>&1; then add whitespace pass "no whitespace errors"
else add whitespace fail "whitespace errors" "$ev/whitespace.log"; fi

git log --format='%s' "$base..$head" | grep -Ev '^[A-Z][A-Za-z0-9 /_-]+: .+\.$' >"$ev/commit-subjects.log" &&
	echo "NOTE: commit subjects not in 'Component: Summary.' form (see $ev/commit-subjects.log)"

git diff "$base" "$head" >"$ev/patch.diff"
status="$(jq -r 'if any(.[]; .status=="fail") then "fail" elif any(.[]; .status=="skipped") then "incomplete" else "pass" end' "$results")"
jq -n --arg t "$t" --arg head "$head" --arg base "$base" --arg branch "$branch" --arg status "$status" \
	--arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --slurpfile checks "$results" \
	'{ticket:$t, branch:$branch, head:$head, base:$base, verified_at:$at, status:$status, checks:$checks[0]}' >"$dir/verification.json"
rm -f "$results"
echo; echo "STATUS: $status  (evidence: $dir/verification.json)"
[ "$status" = "pass" ]
