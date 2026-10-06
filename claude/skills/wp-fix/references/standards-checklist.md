# WordPress Core change checklist

Authoritative sources (open them when unsure; do not rely on memory):
- PHP standards: https://developer.wordpress.org/coding-standards/wordpress-coding-standards/php/
- Inline docs: https://developer.wordpress.org/coding-standards/inline-documentation-standards/php/
- JS standards: https://developer.wordpress.org/coding-standards/wordpress-coding-standards/javascript/
- The repo's own `phpcs.xml.dist` wins over anything written here.

## Formatting (PHPCS catches most; the rest is on you)
- [ ] Tabs for indentation; spaces only for mid-line alignment.
- [ ] Spaces inside parentheses of control structures and function calls with arguments.
- [ ] Yoda conditions for comparisons against literals/constants: `if ( 'value' === $var )`.
- [ ] Strict comparisons (`===`, `in_array( $x, $list, true )`) unless loose is intended and commented.
- [ ] Long array syntax `array()` in PHP files that use it (Core convention).
- [ ] Braces on every control structure; `elseif`, not `else if`.
- [ ] No unrelated whitespace or alignment changes on untouched lines.

## Documentation
- [ ] New function/method/class/hook: full DocBlock, `@since <current trunk version>`.
- [ ] Changed behaviour/params of existing code: extra `@since x.y.z Description.` line, oldest first.
- [ ] `@param` types and names match the signature; `@return` accurate.
- [ ] Every new `apply_filters()`/`do_action()` has a hook DocBlock directly above it.
- [ ] Inline comments explain why, not what. No ticket numbers in code comments unless Core does so nearby.

## Security
- [ ] Escape late, at output: `esc_html()`, `esc_attr()`, `esc_url()`, `wp_kses_post()`...
- [ ] Sanitize/validate early, at input. Unslash superglobals: `wp_unslash( $_POST['x'] )`.
- [ ] State-changing requests check capability (`current_user_can()`) and nonce.
- [ ] SQL through `$wpdb->prepare()` with placeholders; no interpolated input.
- [ ] No new direct file includes from user input; no `eval`/`extract` on input.

## Compatibility and back-compat
- [ ] Code runs on the minimum PHP in `src/wp-includes/version.php` (`$required_php_version`).
- [ ] No signature changes to public functions without defaults; no changed return types.
- [ ] Hook names, argument order and counts unchanged; filter results still pass through.
- [ ] Output markup changes considered for themes/plugins that target it.
- [ ] Multisite, RTL, i18n (strings wrapped with `__()` etc., no text domain in Core), and
      non-default permalink structures considered where relevant.

## Performance
- [ ] No new queries inside loops; use existing caches/priming functions.
- [ ] No new autoloaded options; no unbounded queries.

## Scope
- [ ] Every changed line is needed for this ticket.
- [ ] Bundled package code (`src/wp-includes/js/dist`, block library) is not edited here; those
      changes belong upstream in Gutenberg.
