#!/usr/bin/env bash
# Tests releases.sh, rank-tickets.py and ledger coverage against a fake upstream.
# No network: curl is stubbed to fail so only the git source is used.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
T="$here/claude/wp-tools"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"; printf '#!/bin/sh\nexit 6\n' >"$tmp/bin/curl"; chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
pass=0; fail=0
check() { if eval "$2"; then pass=$((pass+1)); echo "ok    $1"; else fail=$((fail+1)); echo "FAIL  $1"; fi; }

setver() { mkdir -p src/wp-includes; printf "<?php\n\$wp_version = '%s';\n" "$1" >src/wp-includes/version.php; git add src; git commit -qm "v $1"; }

git init -q --bare "$tmp/up.git"
git init -q -b trunk "$tmp/w"; cd "$tmp/w"
git config user.email t@e && git config user.name t
git config "url.$tmp/up.git.insteadOf" https://github.com/WordPress/wordpress-develop.git
git remote add upstream https://github.com/WordPress/wordpress-develop.git
git remote add origin https://github.com/me/wordpress-develop.git

# Scenario A: 7.1 released twice, trunk 7.2 in alpha.
setver 7.1; git tag 7.1; git branch 7.1; git tag 7.1.1
setver 7.2-alpha-60000
git push -q upstream refs/heads/trunk refs/heads/7.1 --tags 2>/dev/null
"$T/releases.sh" >/dev/null 2>&1
R=.wp-contrib/releases.json
check "A: next minor 7.1.2"          "jq -e '.[] | select(.name==\"7.1.2\" and .kind==\"minor\")' $R >/dev/null"
check "A: trunk 7.2 major alpha"     "jq -e '.[] | select(.name==\"7.2\" and .phase==\"alpha\")' $R >/dev/null"
check "A: next major 7.3"            "jq -e '.[] | select(.name==\"7.3\")' $R >/dev/null"
check "A: no released 7.1 milestone" "! jq -e '.[] | select(.name==\"7.1\")' $R >/dev/null"

# Scenario B: 7.2 branched at RC1 (not tagged), trunk moved to 7.3.
git switch -qc 7.2; setver 7.2-RC1; git switch -q trunk; setver 7.3-alpha-61000
git push -q upstream refs/heads/trunk refs/heads/7.2 2>/dev/null
"$T/releases.sh" >/dev/null 2>&1
check "B: 7.2 is rc"                 "jq -e '.[] | select(.name==\"7.2\" and .phase==\"rc\")' $R >/dev/null"
check "B: 7.1.2 still listed"        "jq -e '.[] | select(.name==\"7.1.2\")' $R >/dev/null"
check "B: trunk 7.3 alpha"           "jq -e '.[] | select(.name==\"7.3\" and .phase==\"alpha\")' $R >/dev/null"
check "B: next major 7.4"            "jq -e '.[] | select(.name==\"7.4\")' $R >/dev/null"

# Ranking with phase rules.
ago() { python3 -c "import datetime as d,sys; print((d.datetime.now(d.timezone.utc)-d.timedelta(days=int(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$1"; }  # GNU and BSD date differ
old="$(ago 90)"; new="$(ago 3)"
mkdir -p .wp-contrib/triage
H='id,summary,status,owner,type,priority,severity,component,keywords,milestone,changetime'
printf '%s\n101,Regressed thing,new,,defect (bug),normal,normal,Media,regression has-patch needs-testing,7.2,%s\n102,Plain bug,new,,defect (bug),normal,normal,Media,,7.2,%s\n103,Shiny,new,,enhancement,normal,normal,Media,,7.2,%s\n' "$H" "$old" "$old" "$old" >.wp-contrib/triage/7.2.csv
printf '%s\n201,Minor enh,new,,enhancement,normal,normal,General,,7.1.2,%s\n202,Minor regression,new,,defect (bug),normal,normal,General,regression,7.1.2,%s\n' "$H" "$old" "$old" >.wp-contrib/triage/7.1.2.csv
printf '%s\n301,Needs feedback,new,,defect (bug),normal,normal,Posts,needs-dev-feedback,7.3,%s\n302,Owned active,assigned,bob,defect (bug),normal,normal,Posts,,7.3,%s\n303,Good one,new,,defect (bug),normal,normal,Posts,has-patch needs-refresh,7.3,%s\n304,Owned stale,assigned,carol,defect (bug),normal,normal,Posts,,7.3,%s\n' "$H" "$old" "$new" "$old" "$old" >.wp-contrib/triage/7.3.csv
"$T/rank-tickets.py" >/dev/null
S=.wp-contrib/triage/shortlist.json
top() { jq -r --arg m "$1" '.releases[] | select(.release.name==$m) | .top[].id' $S | tr '\n' ' '; }
skip() { jq -r --arg m "$1" --arg i "$2" '.releases[] | select(.release.name==$m) | .skipped[] | select(.id==$i) | .skip' $S; }
check "RC: regression kept"                  "[[ '$(top 7.2)' == *101* ]]"
check "RC: plain bug blocked"                "[[ '$(skip 7.2 102)' == RC:* ]]"
check "RC: enhancement blocked"              "[ -n '$(skip 7.2 103)' ]"
check "RC regression = test-patch type"      "jq -e '.releases[] | .top[] | select(.id==\"101\" and .contribution==\"test-patch\")' $S >/dev/null"
check "minor: regression ranked above enh"   "[[ '$(top 7.1.2)' == '202 201 ' ]]"
check "alpha: needs-dev-feedback skipped"    "[[ '$(skip 7.3 301)' == needs\ decision* ]]"
check "alpha: active owner skipped"          "[[ '$(skip 7.3 302)' == active\ owner* ]]"
check "alpha: stale owner kept"              "[[ '$(top 7.3)' == *304* ]]"
check "alpha: refresh type"                  "jq -e '.releases[] | .top[] | select(.id==\"303\" and .contribution==\"refresh\")' $S >/dev/null"
check "missing export reported (7.4)"        "jq -e '.missing_exports | index(\"7.4\")' $S >/dev/null"
check "shortlist.md marks not covered"       "grep -q 'NOT covered' .wp-contrib/triage/shortlist.md"

# Ledger skip + coverage.
"$T/ledger.sh" set 303 submitted milestone=7.3 >/dev/null
"$T/rank-tickets.py" >/dev/null
check "ledger: submitted ticket not re-proposed" "[[ '$(skip 7.3 303)' == already* ]]"
cov="$("$T/ledger.sh" coverage)"
check "coverage: 7.3 submitted"              "echo \"\$cov\" | grep -E '^7\.3[[:space:]]' | grep -q submitted"
check "coverage: 7.2 NOT COVERED"            "echo \"\$cov\" | grep -E '^7\.2[[:space:]]' | grep -q 'NOT COVERED'"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
