#!/usr/bin/env bash
# Fetch raw Trac + GitHub data and save it as evidence. Never writes to Trac.
# Usage:
#   fetch-trac.sh query <milestone>   -> .wp-contrib/triage/<milestone>.csv
#   fetch-trac.sh ticket <id>         -> .wp-contrib/<id>/raw/{ticket.csv,ticket.rss,attachments.html,prs.json,summary.json}
# Exit 3 = Trac refused or returned non-data (bot protection). Ask the human to export manually.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
TRAC="https://core.trac.wordpress.org"
UA="wp-core-contrib-agent/1.0 (human-supervised; low-volume)"

get() { # url out
	local code
	code="$(curl -sS -L -A "$UA" -o "$2" -w '%{http_code}' "$1")" || true
	code="${code:-000}"
	if [ "$code" != "200" ]; then
		echo "FETCH FAILED ($code): $1" >&2; return 3
	fi
	if head -c 600 "$2" | grep -Eqi '<html|captcha|cf-chl|challenge-platform' && [[ "$2" != *.html ]]; then
		echo "FETCH RETURNED HTML/CHALLENGE instead of data: $1" >&2; return 3
	fi
}

case "${1:-}" in
query)
	ms="${2:?milestone required, e.g. 7.2 or 7.1.3}"
	out="$root/.wp-contrib/triage"; mkdir -p "$out"
	url="$TRAC/query?milestone=$ms&status=accepted&status=assigned&status=new&status=reopened&status=reviewing&order=priority&col=id&col=summary&col=status&col=owner&col=type&col=priority&col=severity&col=component&col=keywords&col=milestone&col=changetime&max=1000&format=csv"
	if ! get "$url" "$out/$ms.csv"; then
		rm -f "$out/$ms.csv"
		cat >&2 <<EOF
Could not fetch milestone $ms automatically. Ask the human to open this URL in a browser,
use "Download in other formats: Comma-delimited Text" and save it as:
  $out/$ms.csv
URL: ${url%&format=csv}
EOF
		exit 3
	fi
	echo "$url" >"$out/$ms.source-url.txt"
	python3 - "$out/$ms.csv" <<'PY'
import csv,sys
rows=list(csv.DictReader(open(sys.argv[1],encoding='utf-8-sig')))
print(f"{len(rows)} tickets saved to {sys.argv[1]}")
PY
	;;
ticket)
	t="$2"; [[ "$t" =~ ^[0-9]+$ ]] || { echo "ticket must be numeric" >&2; exit 1; }
	out="$root/.wp-contrib/$t/raw"; mkdir -p "$out"
	rc=0
	get "$TRAC/ticket/$t?format=csv" "$out/ticket.csv" || rc=3
	get "$TRAC/ticket/$t?format=rss" "$out/ticket.rss" || rc=3
	get "$TRAC/attachment/ticket/$t/" "$out/attachments.html" || true
	if command -v gh >/dev/null 2>&1; then
		gh pr list -R WordPress/wordpress-develop --state all --limit 30 \
			--search "core.trac.wordpress.org/ticket/$t in:body" \
			--json number,title,author,state,isDraft,updatedAt,url >"$out/prs.json" 2>/dev/null || echo '[]' >"$out/prs.json"
	else
		echo '[]' >"$out/prs.json"
	fi
	if [ "$rc" -ne 0 ]; then
		echo "Ask the human to save $TRAC/ticket/$t (page + comments) into $out/ or paste it." >&2
		exit 3
	fi
	python3 - "$out" <<'PY'
import csv, json, sys, os, re
from email.utils import parsedate_to_datetime
from datetime import datetime, timezone
import xml.etree.ElementTree as ET
d = sys.argv[1]
row = next(csv.DictReader(open(os.path.join(d, 'ticket.csv'), encoding='utf-8-sig')))
items = ET.parse(os.path.join(d, 'ticket.rss')).getroot().findall('./channel/item')
comments = []
for it in items:
    pub = it.findtext('pubDate')
    comments.append({
        'author': it.findtext('{http://purl.org/dc/elements/1.1/}creator') or '',
        'date': parsedate_to_datetime(pub).astimezone(timezone.utc).isoformat() if pub else None,
        'title': (it.findtext('title') or '').strip(),
        'link': it.findtext('link'),
    })
dates = [c['date'] for c in comments if c['date']]
last = max(dates) if dates else None
days = None
if last:
    days = (datetime.now(timezone.utc) - datetime.fromisoformat(last)).days
html = open(os.path.join(d, 'attachments.html'), encoding='utf-8', errors='ignore').read() if os.path.exists(os.path.join(d, 'attachments.html')) else ''
attachments = sorted(set(re.findall(r'/attachment/ticket/\d+/([^"?#]+\.(?:diff|patch|php|png|jpg|gif|txt))', html)))
prs = json.load(open(os.path.join(d, 'prs.json')))
summary = {
    'id': row.get('id'), 'summary': row.get('summary'), 'status': row.get('status'),
    'owner': row.get('owner'), 'type': row.get('type'), 'priority': row.get('priority'),
    'severity': row.get('severity'), 'component': row.get('component'),
    'milestone': row.get('milestone'), 'keywords': row.get('keywords'),
    'reporter': row.get('reporter'), 'focuses': row.get('focuses'),
    'comment_count': len(comments), 'last_activity_utc': last, 'days_since_activity': days,
    'attachments': attachments,
    'linked_prs': [dict({k: p[k] for k in ('number', 'title', 'state', 'isDraft', 'updatedAt', 'url')}, author=(p.get('author') or {}).get('login')) for p in prs],
}
json.dump(summary, open(os.path.join(d, 'summary.json'), 'w'), indent=2)
print(json.dumps(summary, indent=2))
PY
	;;
*)
	sed -n '2,6p' "$0"; exit 1
	;;
esac
