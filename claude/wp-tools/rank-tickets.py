#!/usr/bin/env python3
"""Rank Trac tickets per release so every open release gets candidates.

Inputs : .wp-contrib/releases.json, .wp-contrib/triage/<milestone>.csv, .wp-contrib/ledger.json
Outputs: .wp-contrib/triage/shortlist.json and shortlist.md (grouped by release)

Usage: rank-tickets.py [--top N] [--only MILESTONE]

Deterministic and offline: it only reads CSV exported from Trac. Ticket pages are read
later by the researcher subagent. Phase rules follow the Core handbook release cycle:
https://make.wordpress.org/core/handbook/about/release-cycle/
"""
import csv, json, os, re, subprocess, sys
from datetime import datetime, timezone, timedelta

root = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True).stdout.strip() or '.'
W = os.path.join(root, '.wp-contrib')
args = sys.argv[1:]
top = int(args[args.index('--top') + 1]) if '--top' in args else 5
only = args[args.index('--only') + 1] if '--only' in args else None
now = datetime.now(timezone.utc)

def load(path, default):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except (OSError, ValueError):
        return default

releases = load(os.path.join(W, 'releases.json'), [])
ledger = load(os.path.join(W, 'ledger.json'), {})
if not releases:
    sys.exit('No .wp-contrib/releases.json. Run .claude/wp-tools/releases.sh first.')

DECISION_KW = {'needs-design', 'needs-design-feedback', 'needs-dev-feedback', 'close',
               'reporter-feedback', '2nd-opinion', 'needs-copy-review', 'needs-privacy-review'}
DONE_STATES = {'submitted', 'changes-requested', 'approved-by-reviewer', 'committed', 'closed'}
PRIORITY = {'lowest': -2, 'low': -1, 'normal': 0, 'high': 1, 'highest omg bbq': 2}
SEVERITY = {'trivial': -1, 'minor': 0, 'normal': 0, 'major': 1, 'critical': 2, 'blocker': 2}

def field(row, *names):
    for n in names:
        for k in row:
            if k.strip().lower().lstrip('_') == n:
                return (row[k] or '').strip()
    return ''

def parse_date(s):
    s = s.strip()
    if not s:
        return None
    try:
        d = datetime.fromisoformat(s.replace('Z', '+00:00'))
        return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
    except ValueError:
        pass
    for fmt in ('%m/%d/%Y %H:%M:%S', '%m/%d/%y %H:%M:%S', '%m/%d/%Y', '%m/%d/%y'):
        try:
            return datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return None

def contribution(kw):
    if 'has-patch' in kw:
        if 'needs-refresh' in kw: return 'refresh'
        if 'needs-unit-tests' in kw: return 'add-tests'
        return 'test-patch'
    return 'fix'

def phase_gate(phase, ttype, kw, severity, priority):
    """Return (gate, reason). gate: ok | risk | blocked."""
    regression = 'regression' in kw
    if ttype.startswith('task (blessed)'):
        return 'blocked', 'blessed task: maintainer-owned'
    if phase == 'beta' and ttype in ('enhancement', 'feature request'):
        return 'blocked', 'Beta: no new enhancements/features for this release'
    if phase == 'rc' and not regression and SEVERITY.get(severity, 0) < 2:
        return 'blocked', 'RC: regressions from this cycle only'
    if phase == 'minor':
        if ttype in ('enhancement', 'feature request'):
            return 'risk', "minor release: enhancements at release lead's discretion, no new files"
        if not regression and SEVERITY.get(severity, 0) < 1 and PRIORITY.get(priority, 0) < 1:
            return 'risk', 'minor release: low-impact bugs are often punted'
    if phase == 'alpha' and ttype == 'feature request':
        return 'risk', 'feature request: needs product agreement'
    return 'ok', ''

out = []
missing = []
for rel in releases:
    ms = rel['name']
    if only and ms != only:
        continue
    path = os.path.join(W, 'triage', f'{ms}.csv')
    if not os.path.exists(path):
        missing.append(ms)
        continue
    with open(path, encoding='utf-8-sig') as f:
        rows = list(csv.DictReader(f))
    cands = []
    for r in rows:
        tid = field(r, 'id', 'ticket').lstrip('#')
        if not tid.isdigit():
            continue
        ttype = field(r, 'type').lower()
        kw = set(field(r, 'keywords').lower().split())
        owner = field(r, 'owner')
        priority = field(r, 'priority').lower()
        severity = field(r, 'severity').lower()
        changed = parse_date(field(r, 'changetime', 'modified', 'changed'))
        days = (now - changed).days if changed else None
        flags, skip = [], None
        led = ledger.get(tid, {})
        if led.get('state') in DONE_STATES:
            skip = f"already {led['state']}"
        elif led.get('state') == 'skipped':
            upd = parse_date(led.get('updated', ''))
            if upd and now - upd < timedelta(days=30):
                skip = f"skipped recently: {led.get('reason', '')}"
        if not skip and kw & DECISION_KW:
            skip = 'needs decision: ' + ' '.join(sorted(kw & DECISION_KW))
        if not skip and owner and days is not None and days <= 30:
            skip = f'active owner {owner} ({days}d ago)'
        if owner and days is None:
            flags.append(f'owner {owner}: activity date unknown, researcher must check')
        gate, why = phase_gate(rel['phase'], ttype, kw, severity, priority)
        if not skip and gate == 'blocked':
            skip = why
        if gate == 'risk':
            flags.append(why)
        score = 0
        score += 3 if ttype == 'defect (bug)' else 1 if ttype == 'enhancement' else 0
        score += 3 if 'regression' in kw else 0
        score += 3 if {'has-patch'} <= kw and kw & {'needs-refresh', 'needs-unit-tests', 'needs-testing'} else 0
        score += 2 if 'good-first-bug' in kw else 0
        score += 2 if not owner else 0
        score += PRIORITY.get(priority, 0) + SEVERITY.get(severity, 0)
        score += 2 if rel['phase'] in ('beta', 'rc') else 0   # release is close: help land it
        score -= 2 if gate == 'risk' else 0
        cands.append({
            'id': tid, 'summary': field(r, 'summary'), 'milestone': ms, 'type': ttype,
            'component': field(r, 'component'), 'owner': owner, 'keywords': ' '.join(sorted(kw)),
            'days_since_change': days, 'contribution': contribution(kw), 'score': score,
            'gate': gate, 'flags': flags, 'skip': skip,
            'url': f'https://core.trac.wordpress.org/ticket/{tid}',
        })
    eligible = sorted([c for c in cands if not c['skip']], key=lambda c: (-c['score'], int(c['id'])))
    out.append({'release': rel, 'total_open': len(cands), 'eligible_count': len(eligible),
                'top': eligible[:top], 'skipped': [c for c in cands if c['skip']]})

json.dump({'generated_at': now.isoformat(), 'missing_exports': missing, 'releases': out},
          open(os.path.join(W, 'triage', 'shortlist.json'), 'w'), indent=2)

lines = [f'# Ticket shortlist by release ({now:%Y-%m-%d %H:%M} UTC)', '']
for block in out:
    rel = block['release']
    lines += [f"## {rel['name']} ({rel['kind']}, phase: {rel['phase']}) "
              f"- {block['eligible_count']} eligible of {block['total_open']} open", '']
    if block['top']:
        lines += ['| Ticket | Score | Contribution | Type | Component | Owner | Keywords | Flags |',
                  '|---|---|---|---|---|---|---|---|']
        for c in block['top']:
            lines.append(f"| [#{c['id']}]({c['url']}) {c['summary'][:60]} | {c['score']} | {c['contribution']} | "
                         f"{c['type']} | {c['component']} | {c['owner'] or '-'} | {c['keywords']} | {'; '.join(c['flags'])} |")
    else:
        reasons = {}
        for c in block['skipped']:
            reasons[c['skip'].split(':')[0]] = reasons.get(c['skip'].split(':')[0], 0) + 1
        lines.append('No eligible tickets. Skip reasons: ' + (', '.join(f'{k} ({v})' for k, v in reasons.items()) or 'milestone empty'))
    lines.append('')
if missing:
    lines += ['## Missing exports', '', 'No CSV for: ' + ', '.join(missing) +
              '. These releases are NOT covered yet.', '']
open(os.path.join(W, 'triage', 'shortlist.md'), 'w').write('\n'.join(lines))
print('\n'.join(lines))
