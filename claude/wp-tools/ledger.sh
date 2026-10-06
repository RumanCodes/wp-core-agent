#!/usr/bin/env bash
# Ticket ledger: one JSON file tracking every ticket's lifecycle state.
# Usage:
#   ledger.sh get <ticket>
#   ledger.sh set <ticket> <state> [key=value ...]   # appends to history
#   ledger.sh list [state]
#   ledger.sh coverage                               # per-release contribution coverage
#   ledger.sh lesson "<one-line lesson>" "<source url>"
# Always pass milestone=<release> when setting a ticket for the first time.
# States: candidate, skipped, investigating, needs-input, ready-for-review, submitted,
#         changes-requested, approved-by-reviewer, committed, closed
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
mkdir -p "$root/.wp-contrib"
L="$root/.wp-contrib/ledger.json"
[ -f "$L" ] || echo '{}' >"$L"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

case "${1:-}" in
get)
	jq --arg t "$2" '.[$t] // empty' "$L"
	;;
set)
	t="$2"; s="$3"; shift 3
	tmp="$(mktemp)"
	jq --arg t "$t" --arg s "$s" --arg now "$now" \
		'.[$t] = ((.[$t] // {ticket: $t}) + {state: $s, updated: $now})
		 | .[$t].history = ((.[$t].history // []) + [{state: $s, at: $now}])' "$L" >"$tmp"
	for kv in "$@"; do
		k="${kv%%=*}"; v="${kv#*=}"
		jq --arg t "$t" --arg k "$k" --arg v "$v" '.[$t][$k] = $v' "$tmp" >"$tmp.2" && mv "$tmp.2" "$tmp"
	done
	mv "$tmp" "$L"
	jq --arg t "$t" '.[$t]' "$L"
	;;
list)
	if [ -n "${2:-}" ]; then
		jq -r --arg s "$2" 'to_entries[] | select(.value.state == $s) | "\(.key)\t\(.value.state)\t\(.value.pr // "-")\t\(.value.updated)"' "$L"
	else
		jq -r 'to_entries[] | "\(.key)\t\(.value.state)\t\(.value.pr // "-")\t\(.value.updated)"' "$L"
	fi
	;;
coverage)
	# Per-release contribution coverage. Releases come from releases.json (open) plus any
	# milestone recorded on a ledger entry (past). Shows which releases have no contribution yet.
	R="$root/.wp-contrib/releases.json"; [ -f "$R" ] || echo '[]' >"$R"
	python3 - "$L" "$R" <<'PY'
import json, sys
led = json.load(open(sys.argv[1])); rel = json.load(open(sys.argv[2]))
open_names = [r['name'] for r in rel]
names = sorted(set(open_names) | {v.get('milestone') for v in led.values() if v.get('milestone')},
               key=lambda n: [int(x) if x.isdigit() else 0 for x in n.split('.')])
active = {'candidate', 'investigating', 'needs-input', 'ready-for-review'}
sub = {'submitted', 'changes-requested', 'approved-by-reviewer'}
print('Release\tPhase\tCandidates\tIn progress\tSubmitted\tCommitted\tStatus')
for n in names:
    t = [v for v in led.values() if v.get('milestone') == n]
    c = lambda states: sum(1 for v in t if v.get('state') in states)
    phase = next((r['phase'] for r in rel if r['name'] == n), 'past')
    cand, prog, s, done = c({'candidate'}), c(active - {'candidate'}), c(sub), c({'committed'})
    status = 'CONTRIBUTED' if done else 'submitted' if s else 'in progress' if prog else ('NOT COVERED' if n in open_names else 'none')
    print(f'{n}\t{phase}\t{cand}\t{prog}\t{s}\t{done}\t{status}')
PY
	;;
lesson)
	f="$root/.wp-contrib/lessons.md"
	[ -f "$f" ] || printf '# Lessons from WordPress Core reviews\n\nOne line each, with source. Newest last. Prune duplicates.\n\n' >"$f"
	printf -- '- %s (%s, %s)\n' "$2" "${3:-no source}" "${now%%T*}" >>"$f"
	tail -n 1 "$f"
	;;
*)
	sed -n '2,9p' "$0"; exit 1
	;;
esac
