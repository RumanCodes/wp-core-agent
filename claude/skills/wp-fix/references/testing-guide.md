# Testing guide for Core fixes

Check conventions against neighbouring tests in the same directory before writing; match them.

## PHPUnit
- Location: `tests/phpunit/tests/<component>/...`. Prefer adding a method to the existing test
  class for the function under test; create a new file only when none fits (one class per
  function is the common Core pattern, e.g. `tests/phpunit/tests/functions/<name>.php`).
- Class: `Tests_<Component>_<Thing> extends WP_UnitTestCase`. Use snake_case fixtures
  (`set_up()`, `tear_down()`, `wpSetUpBeforeClass( WP_UnitTest_Factory $factory )`).
- Annotate every new test method:
  ```php
  /**
   * Tests that <behaviour>.
   *
   * @ticket 12345
   *
   * @covers ::function_name
   */
  public function test_<behaviour_in_words>() {
  ```
  `@ticket` doubles as a PHPUnit group, which is how `verify-patch.sh` finds your tests.
- Use factories (`self::factory()->post->create()`), not raw inserts. Clean up anything the
  framework does not roll back (options added with `add_filter` are reset; files and
  globals may not be).
- Data providers: `data_<name>()` returning named cases; `@dataProvider data_<name>`.
- Multisite-only: `@group ms-required`; single-site-only: `@group ms-excluded`. Run multisite
  with `npm run test:php -- -c tests/phpunit/multisite.xml --group <ticket>`.
- Assert behaviour (return values, stored data, output), not internals. Include the
  failing edge case from the ticket plus at least one "unchanged behaviour" case.
- Deterministic: no network, no real time dependence (`time()` deltas), no ordering
  assumptions from unsorted queries.

## The red/green proof
A test only counts if it fails on unpatched trunk for the reason in the ticket.
`verify-patch.sh` proves this automatically (fails_before / passes_after). Read
`phpunit-before.log`: the failure message should describe the bug, not a fatal error from
a missing function you introduced.

## JS, CSS and UI
- Look at `package.json` / `Gruntfile.js` for the available JS test and lint tasks; do not
  assume names. E2E tests live in `tests/e2e/` (`npm run test:e2e -- <spec>`).
- For changes without automated coverage, write `.wp-contrib/<t>/evidence/manual.md`:
  environment (browser, WP version, theme, plugins), numbered steps, expected vs actual on
  trunk, and result on the branch. Ask the human for screenshots; do not describe images
  you have not seen.

## Capturing evidence
Always `| tee .wp-contrib/<t>/evidence/<descriptive-name>.log`. A result that is not in a log
file did not happen as far as the deliverables are concerned.
