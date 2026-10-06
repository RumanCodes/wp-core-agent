#!/usr/bin/env bash
# Install the WordPress Core contribution agent into an existing wordpress-develop checkout.
# Everything installed is local-only: added to .git/info/exclude, never committed.
#
# Usage: ./install.sh /path/to/wordpress-develop <wporg-username>
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
target="${1:?usage: install.sh /path/to/wordpress-develop <wporg-username>}"
user="${2:?usage: install.sh /path/to/wordpress-develop <wporg-username>}"
target="$(cd "$target" && pwd)"

for bin in git jq python3 curl; do command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 1; }; done
command -v gh >/dev/null || echo "WARNING: gh (GitHub CLI) not found; needed for PR lookups and /wp-submit."
[ -f "$target/src/wp-includes/version.php" ] || { echo "$target is not a wordpress-develop checkout" >&2; exit 1; }
git -C "$target" rev-parse --git-dir >/dev/null

ts="$(date +%Y%m%d%H%M%S)"
copy() { # src dst
	mkdir -p "$(dirname "$2")"
	if [ -f "$2" ] && ! cmp -s "$1" "$2"; then cp "$2" "$2.bak.$ts"; echo "backed up $2"; fi
	cp "$1" "$2"
}

c="$target/.claude"
for d in skills/wp-find-tickets skills/wp-fix skills/wp-submit skills/wp-feedback; do
	(cd "$here/claude/$d" && find . -type f) | while read -r f; do copy "$here/claude/$d/$f" "$c/$d/$f"; done
done
# /wp-triage was replaced by /wp-find-tickets; move an old copy aside so both don't load.
if [ -d "$c/skills/wp-triage" ]; then
	mv "$c/skills/wp-triage" "$c/wp-triage.removed.bak.$ts"; echo "moved old wp-triage skill to $c/wp-triage.removed.bak.$ts"
fi
for f in agents/wp-ticket-researcher.md agents/wp-patch-reviewer.md \
	hooks/guard-bash.sh hooks/precommit-phpcs.sh \
	wp-tools/ledger.sh wp-tools/fetch-trac.sh wp-tools/env-check.sh wp-tools/context.sh wp-tools/verify-patch.sh \
	wp-tools/releases.sh wp-tools/rank-tickets.py; do
	copy "$here/claude/$f" "$c/$f"
done
copy "$here/claude/CLAUDE.local.md" "$c/wp-core-agent.md"
chmod +x "$c"/hooks/*.sh "$c"/wp-tools/*.sh "$c"/wp-tools/*.py

# Personalise.
grep -rl '{{WPORG_USER}}' "$c/skills" "$c/agents" "$c/wp-core-agent.md" | while read -r f; do
	sed -i.tmp "s/{{WPORG_USER}}/$user/g" "$f" && rm -f "$f.tmp"
done

# Settings: merge into settings.local.json (union of permission lists, append our hooks once).
s="$c/settings.local.json"
if [ -f "$s" ]; then
	cp "$s" "$s.bak.$ts"
	jq -s '
	  def uniq_concat(a; b): ((a // []) + (b // [])) | unique;
	  .[0] as $old | .[1] as $new |
	  $old
	  | .permissions.allow = uniq_concat($old.permissions.allow; $new.permissions.allow)
	  | .permissions.ask   = uniq_concat($old.permissions.ask;   $new.permissions.ask)
	  | .permissions.deny  = uniq_concat($old.permissions.deny;  $new.permissions.deny)
	  | .hooks.PreToolUse  = (($old.hooks.PreToolUse // [])
	        | map(select((.hooks // []) | map(.command) | any(test("guard-bash|precommit-phpcs")) | not))
	        ) + $new.hooks.PreToolUse
	' "$s.bak.$ts" "$here/claude/settings.local.json" >"$s"
	echo "merged settings into $s (backup: $s.bak.$ts)"
else
	cp "$here/claude/settings.local.json" "$s"
fi

# Import the agent context from CLAUDE.local.md (personal, auto-loaded, not committed).
cl="$target/CLAUDE.local.md"
grep -qs '@.claude/wp-core-agent.md' "$cl" || printf '\n@.claude/wp-core-agent.md\n' >>"$cl"

# Workspace + lessons.
mkdir -p "$target/.wp-contrib/triage"
[ -f "$target/.wp-contrib/lessons.md" ] ||
	printf '# Lessons from WordPress Core reviews\n\nOne line each, with source. Newest last. Prune duplicates.\n\n' >"$target/.wp-contrib/lessons.md"

# Keep all of it out of git without touching tracked .gitignore.
ex="$(git -C "$target" rev-parse --git-path info/exclude)"
case "$ex" in /*) ;; *) ex="$target/$ex" ;; esac
mkdir -p "$(dirname "$ex")"
for p in '/.wp-contrib/' '/CLAUDE.local.md' '/.claude/wp-core-agent.md' '/.claude/settings.local.json' \
	'/.claude/skills/wp-*/' '/.claude/agents/wp-*.md' '/.claude/hooks/' '/.claude/wp-tools/' \
	'/.claude/agent-memory/' '/.claude/agent-memory-local/' '*.bak.[0-9]*' '/.claude/wp-triage.removed.bak.*/'; do
	grep -qxF "$p" "$ex" 2>/dev/null || echo "$p" >>"$ex"
done

echo
echo "Installed into $target"
echo "Next:"
echo "  1. cd $target && .claude/wp-tools/env-check.sh --smoke"
echo "  2. git status   # should show nothing from the agent"
echo "  3. claude       # accept the workspace trust prompt, then run /wp-find-tickets or /wp-fix <ticket>"
