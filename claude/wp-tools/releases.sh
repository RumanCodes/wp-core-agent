#!/usr/bin/env bash
# Discover every open WordPress release milestone and its phase, so no release is skipped.
# Sources (unioned):
#   git   - upstream trunk version.php, release branches and tags (always available offline-ish)
#   trac  - https://core.trac.wordpress.org/roadmap (authoritative names; may be bot-blocked)
# Output: .wp-contrib/releases.json  [{name, kind, phase, sources[], note}]
#   kind:  major | minor
#   phase: alpha | beta | rc | minor | unknown
# Usage: releases.sh
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; cd "$root"
mkdir -p .wp-contrib
UA="wp-core-contrib-agent/1.0 (human-supervised; low-volume)"
tmp="$(mktemp)"; : >"$tmp"
emit() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >>"$tmp"; } # name kind phase source note

phase_of() { # version string from version.php -> phase
	case "$1" in
	*-alpha* | *-src) echo alpha ;;
	*-beta*) echo beta ;;
	*-RC* | *-rc*) echo rc ;;
	'') echo unknown ;;
	*) echo release ;;
	esac
}
ver_at() { git show "$1:src/wp-includes/version.php" 2>/dev/null | sed -nE "s/^\\\$wp_version = '([^']+)'.*/\\1/p"; }

# ---- git source
git fetch -q upstream "refs/heads/trunk:refs/remotes/upstream/trunk" 2>/dev/null || echo "NOTE: could not fetch upstream/trunk; using cached refs" >&2
trunk_ver="$(ver_at upstream/trunk)"
trunk_base="$(printf '%s' "$trunk_ver" | grep -Eo '^[0-9]+\.[0-9]+')"
# Portable to macOS bash 3.2: no mapfile, and guard empty arrays under 'set -u'.
branches=(); while IFS= read -r l; do [ -n "$l" ] && branches+=("$l"); done < <(git ls-remote --heads upstream 2>/dev/null | sed -nE 's#.*refs/heads/([0-9]+\.[0-9]+)$#\1#p' | sort -t. -k1,1n -k2,2n)
tags=(); while IFS= read -r l; do [ -n "$l" ] && tags+=("$l"); done < <(git ls-remote --tags upstream 2>/dev/null | sed -nE 's#.*refs/tags/([0-9]+\.[0-9]+(\.[0-9]+)?)$#\1#p' | sort -u -t. -k1,1n -k2,2n -k3,3n)

latest_released=""
for b in ${branches[@]+"${branches[@]}"}; do
	rel=""; for t in ${tags[@]+"${tags[@]}"}; do [[ "$t" == "$b" || "$t" == "$b".* ]] && rel="$t"; done
	if [ -z "$rel" ]; then
		# Branched but not released yet: a major in beta/RC.
		git fetch -q upstream "refs/heads/$b:refs/remotes/upstream/$b" 2>/dev/null
		v="$(ver_at "upstream/$b")"
		emit "$b" major "$(phase_of "$v")" git "branch $b at $v"
	else
		latest_released="$b"; latest_tag="$rel"
	fi
done
if [ -n "$latest_released" ]; then
	n="${latest_tag#"$latest_released"}"; n="${n#.}"; n="${n:-0}"
	emit "$latest_released.$((n + 1))" minor minor git "next minor after $latest_tag"
fi
if [ -n "$trunk_base" ] && ! printf '%s\n' ${branches[@]+"${branches[@]}"} | grep -qx "$trunk_base"; then
	emit "$trunk_base" major "$(phase_of "$trunk_ver")" git "trunk at $trunk_ver"
fi
if [ -n "$trunk_base" ]; then
	maj="${trunk_base%%.*}"; min="${trunk_base#*.}"
	nxt="$maj.$((min + 1))"; [ "$min" -ge 9 ] && nxt="$((maj + 1)).0"
	emit "$nxt" major alpha git "next major after trunk (tickets here may be early-punted work)"
fi

# ---- trac source (best effort)
html="$(mktemp)"
code="$(curl -sS -L -A "$UA" -o "$html" -w '%{http_code}' https://core.trac.wordpress.org/roadmap 2>/dev/null)" || true
if [ "${code:-000}" = "200" ] && grep -q '/milestone/' "$html"; then
	grep -Eo '/milestone/[0-9]+\.[0-9]+(\.[0-9]+)?"' "$html" | sed -E 's#/milestone/##; s#"##' | sort -u | while read -r m; do
		if [[ "$m" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then emit "$m" minor minor trac "listed on roadmap"
		else emit "$m" major unknown trac "listed on roadmap"; fi
	done
	trac_ok=true
else
	trac_ok=false
	echo "NOTE: Trac roadmap not reachable (HTTP ${code:-000}); using git-derived releases only. Ask the human to confirm against https://core.trac.wordpress.org/roadmap" >&2
fi
rm -f "$html"

# ---- merge: one row per name; git phase wins over 'unknown'; sources unioned
python3 - "$tmp" "$trac_ok" <<'PY' >.wp-contrib/releases.json
import sys, json
rows = {}
for line in open(sys.argv[1]):
    name, kind, phase, src, note = line.rstrip('\n').split('\t')
    r = rows.setdefault(name, {'name': name, 'kind': kind, 'phase': phase, 'sources': [], 'notes': []})
    if r['phase'] in ('unknown', '') and phase not in ('unknown', ''):
        r['phase'] = phase
    if src not in r['sources']: r['sources'].append(src)
    if note not in r['notes']: r['notes'].append(note)
trac_ok = sys.argv[2] == 'true'
for r in rows.values():
    if r['phase'] == 'unknown' and r['kind'] == 'major':
        r['phase'] = 'alpha'; r['notes'].append('phase assumed alpha (no branch yet)')
    if trac_ok and 'trac' not in r['sources']:
        r['notes'].append('not on Trac roadmap: milestone may not exist yet')
key = lambda r: [int(x) for x in r['name'].split('.')]
print(json.dumps(sorted(rows.values(), key=key), indent=2))
PY
rm -f "$tmp"
jq -r '.[] | "\(.name)\t\(.kind)\t\(.phase)\t\(.sources|join(","))\t\(.notes|join("; "))"' .wp-contrib/releases.json
