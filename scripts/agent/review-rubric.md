# Review rubric

The rules a reviewer — a person, `/review`, or the manual CI review (`REVIEW_MODEL`,
`REVIEW_EFFORT`) — holds a change to. The gates already proved the mechanics; a review says
whether the change is the right one, small enough, and explains itself. Findings are comments on
exact lines, split into **Must fix** and **Worth a look**; at most 20 lines; no praise, no restating
the diff.

1. **Why, not what.** A comment exists only where the reader cannot infer the reason; at most
   2 lines. A directive is one line: `// eslint-disable-next-line <rule> -- <why>`.
2. **One change.** Files the ticket does not need, a second change riding on the first, a refactor
   mixed with a fix: ask for the split.
3. **The design system first.** A hand-rolled control, a colour, a theme or a brand in app code:
   point at the DS token or component. A new component, hook or helper that another project could
   use is built in the design system (components · hooks · utils), and every new one is listed in
   `docs/COMPONENTS.md`.
4. **Helpers, not literals.** Routes through the helper, API paths through the routes file, copy
   through the catalog, storage/env/location/axios through their one helper each.
5. **Render stability.** Selectors stable, no object or array literals as props, stable keys,
   effects that read what they list.
6. **Tests prove behaviour.** A test that mirrors the implementation, or none where a bug fix
   landed, is a Must fix.
7. **Docs move with the code.** The module doc changed, or the commit carries a `Docs-skip:` trailer
   that is true.
8. **Dependencies cost.** A new package says why in a `Deps:` trailer, its size is known
   (`DEP_MAX_KB`), and nothing already in the tree does the job.
9. **Security.** No secret, no `dangerouslySetInnerHTML`, no unvalidated URL parameter or
   `postMessage` origin.
10. **Accessibility.** Labels, focus order, contrast through tokens; an icon-only control has a name.

Report shape:

    ## review — <range | PR #n> · <n> files · <n> findings
    Must fix
      <file>:<line>  <what is wrong> → <the fix>
    Worth a look
      <file>:<line>  <the question or the smaller way>
    Next
      /task <prompt that fixes the Must fix lines> | nothing to fix
