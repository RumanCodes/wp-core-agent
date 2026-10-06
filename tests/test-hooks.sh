#!/usr/bin/env bash
# Unit tests for the guard hooks. Runs in a throwaway git repo; no network, no WordPress needed.
# Usage: tests/test-hooks.sh
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
guard="$here/claude/hooks/guard-bash.sh"
pre="$here/claude/hooks/precommit-phpcs.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q -b trunk repo && cd repo
git config user.email t@example.com && git config user.name t
git remote add upstream https://github.com/WordPress/wordpress-develop.git
git remote add origin https://github.com/someone/wordpress-develop.git
echo a >a.txt && git add a.txt && git commit -qm "Init."
git switch -qc fix/12345-some-bug
echo b >>a.txt && git add a.txt && git commit -qm "Comp: Fix it."
export CLAUDE_PROJECT_DIR="$PWD"

pass=0; fail=0
expect() { # want_exit description command
	local want="$1" desc="$2" cmd="$3" got
	jq -n --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}' | "$guard" >/dev/null 2>"$tmp/err"; got=$?
	if [ "$got" = "$want" ]; then pass=$((pass+1)); printf 'ok    %s\n' "$desc"
	else fail=$((fail+1)); printf 'FAIL  %s (want %s got %s): %s\n' "$desc" "$want" "$got" "$(cat "$tmp/err")"; fi
}

expect 0 "plain read command allowed"          "git status"
expect 2 "git add -A blocked"                  "git add -A"
expect 2 "git add . blocked"                   "git add ."
expect 0 "explicit git add allowed"            "git add src/wp-includes/foo.php"
expect 2 "git commit -a blocked"               "git commit -a -m x"
expect 2 "git commit -am blocked"              "git commit -am x"
expect 0 "git commit -F allowed"               "git commit -F .wp-contrib/12345/commit-msg.txt"
expect 2 "push to upstream blocked"            "git push upstream fix/12345-some-bug"
expect 2 "push --force blocked"                "git push --force origin HEAD"
expect 2 "push trunk blocked"                  "git push origin trunk"
expect 2 "push without verification blocked"   "git push --force-with-lease -u origin HEAD"
expect 2 "gh pr create without verification"   "gh pr create -R WordPress/wordpress-develop --base trunk"
expect 2 "curl POST to Trac blocked"           "curl -X POST https://core.trac.wordpress.org/ticket/12345 -d comment=hi"
expect 0 "curl GET from Trac allowed"          "curl -s https://core.trac.wordpress.org/ticket/12345?format=csv"
expect 2 "gh api write blocked"                "gh api -X POST repos/WordPress/wordpress-develop/issues/1/comments -f body=x"
expect 0 "gh api GET allowed by hook"          "gh api repos/WordPress/wordpress-develop/pulls/1/comments"

head="$(git rev-parse HEAD)"
mkdir -p .wp-contrib/12345
jq -n --arg h "$head" '{status:"pass",head:$h}' >.wp-contrib/12345/verification.json
expect 2 "verified but not approved blocked"   "git push --force-with-lease -u origin HEAD"
echo "$head" >.wp-contrib/12345/approval.txt
expect 0 "verified + approved push allowed"    "git push --force-with-lease -u origin HEAD"
expect 0 "verified + approved PR allowed"      "gh pr create -R WordPress/wordpress-develop --base trunk --head someone:fix/12345-some-bug"
expect 2 "push to a non-origin remote blocked" "git push --force-with-lease -u myother HEAD"
expect 2 "push with no remote named blocked"   "git push"
git remote set-url origin https://github.com/WordPress/wordpress-develop.git
expect 2 "origin pointing at WordPress blocked" "git push --force-with-lease -u origin HEAD"
git remote set-url origin https://github.com/someone/wordpress-develop.git
echo c >>a.txt && git add a.txt && git commit -qm "Comp: More." >/dev/null
expect 2 "stale verification blocked"          "git push --force-with-lease -u origin HEAD"
jq -n --arg h "$(git rev-parse HEAD)" '{status:"fail",head:$h}' >.wp-contrib/12345/verification.json
expect 2 "failed verification blocked"         "git push --force-with-lease -u origin HEAD"
git switch -q trunk
expect 2 "push from non-fix branch blocked"    "git push origin HEAD"

# precommit hook: no PHP staged -> passes; non-commit command ignored.
jq -n '{tool_input:{command:"git commit -F x"}}' | "$pre" >/dev/null 2>&1 && { pass=$((pass+1)); echo "ok    precommit with no staged PHP passes"; } || { fail=$((fail+1)); echo "FAIL  precommit no PHP"; }

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
