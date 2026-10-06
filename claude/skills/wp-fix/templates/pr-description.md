<!-- Title: <Component>: <Imperative summary>. -->
Trac ticket: https://core.trac.wordpress.org/ticket/<ticket>

## Problem
<1-3 sentences: what users/developers experience, with the conditions that trigger it.>

## Root cause
<1-3 sentences: where and why it happens on trunk (file/function).>

## Solution
<What this PR changes and why it is the minimal fix. Mention any behaviour change.>

## Testing instructions
1. <Setup on trunk>
2. <Action>
3. Observe: <bug>.
4. Apply this PR and repeat: <expected result>.

## Automated tests
- Added: `<test file>::<test method>` (`@ticket <ticket>`)
- `npm run test:php -- --group <ticket>`: fails on trunk, passes with this PR.
- <any --also-group / multisite runs from verification.json, with results>
- PHPCS / PHPCompatibility on changed files: <pass | not run (reason)>

## Not tested / open questions
- <from report.md; write "None known" only if true>

## Screenshots
<UI changes only; provided by the human.>

---

AI assistance: Yes
Tool(s): Claude Code (<model>)
Used for: <truthful list, e.g. ticket research, reproduction script, drafting the fix and tests, drafting this description>. Final implementation and tests were reviewed and edited by me.

<!-- HUMAN CHECKLIST: delete this block before submitting.
[ ] I read every line of the diff and can explain it.
[ ] I ran or observed the tests listed above.
[ ] The "Used for" line is accurate.
-->
