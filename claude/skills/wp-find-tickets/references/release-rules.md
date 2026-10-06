# Release phases and what each one accepts

Source: Core handbook, release cycle
https://make.wordpress.org/core/handbook/about/release-cycle/ (re-read each cycle; it wins
over this summary). Exact dates for a release are posted on https://make.wordpress.org/core/
(search "<version> release schedule"); check them when a deadline matters.

| Phase (from version.php) | Accepts | Agent rule |
|---|---|---|
| alpha (`x.y-alpha-*`) | Bugs, enhancements, approved features | All types; feature requests need a product decision first |
| beta (`x.y-beta*`) | "No more commits for new enhancements or feature requests" | Defects only. Enhancements belong in the next major |
| RC (`x.y-RC*`) | "Regressions (introduced during the current cycle) only"; string freeze | Only `regression` tickets or critical severity. No new or changed strings |
| minor (`x.y.z`) | "Bugfixes and enhancements that do not add new deployed files", at the release lead's discretion | Prefer regressions and high-impact bugs. No new files. Expect punting |
| next major (no branch yet) | Early work for the next cycle | Fine for larger fixes that missed the current window |

## How releases map to git
- `upstream/trunk` `version.php` → the major in development and its phase.
- An upstream branch `x.y` with no `x.y*` tag → that major is in beta/RC (phase from the branch's version.php).
- The newest tag `x.y.z` → the next minor is `x.y.(z+1)`, fixed on trunk and backported to branch `x.y` by committers.

## Notes for contributors
- PRs always target `trunk`. Committers handle backports to release branches; mention in the
  Trac comment if you believe a fix should be backported (e.g. "suggest backport to 7.1").
- Only committers and bug gardeners set milestones. If a good ticket sits in the wrong
  milestone, say so in the Trac comment draft; do not ask the agent to "move" it.
- Near a deadline, small and well-tested beats complete: a minimal fix plus a test that
  reproduces the regression is what gets committed during RC.
