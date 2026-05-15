# view_component_css_dsl — TODO

Working notes for follow-up improvements. Likely deleted once items land.

## 1. Investigate replacing `smart_merge` with the `tailwind_merge` gem

Our `smart_merge` reimplements Tailwind class conflict resolution from scratch
— see the `CATEGORIES` table, `spacing_info`, `extract_modifier_prefix`, and
the modifier sets in `lib/view_component_css_dsl.rb`. The gem
`gjtorikian/tailwind_merge` (Ruby port of the well-known JS `tailwind-merge`)
ships an upstream-tracked version of the same logic and stays current with
Tailwind releases.

The DSL itself (`css "..."`, `css :method?`, `css variant:`, axis caching,
inheritance) is **not** up for replacement. Only the internal merge step at
the end is — `smart_merge` is the part that would delegate to the gem.

### Primary concern to verify: shorthand vs longhand spacing parity

This is the case most worth confirming before any other work. Our spacing
logic treats `p-*` (all four sides) as shadowing `px-*`/`py-*`/`pl-*`/etc.
via the axis `subset?` check around line 272 of `view_component_css_dsl.rb`.
tailwind-merge claims to do the same, but we should prove it on concrete
cases:

- `p-4` then `pl-2` → drop `p-4`'s left coverage, keep both classes? Or drop
  `p-4` entirely? Compare both implementations.
- `pl-2` then `p-4` → drop `pl-2`, keep only `p-4`.
- `px-4` then `pl-2` → drop `px-4`'s left coverage.
- Same patterns for `m-*` and `border-*` widths.
- Mixed modifiers: `md:p-4` then `pl-2` should leave both (different prefix
  namespaces); `md:p-4` then `md:pl-2` should follow the rules above within
  the `md:` namespace.

Build a small parity test that runs the same inputs through both mergers
and diffs the outputs. Any divergence is a blocker.

### Coverage gaps to verify the gem closes

Things our `smart_merge` does *not* currently handle but tailwind-merge does:

- **Long-tail utility groups** not in `CATEGORIES`: `shadow-*`, `ring-*`,
  `gap-*`, `space-*`, `divide-*`, `z-*`, `opacity-*`, `leading-*`,
  `tracking-*`, `transition-*`, `transform`, `scale-*`, `rotate-*`,
  `translate-*`, `blur-*`, `backdrop-*`, animation utilities. Today these
  fall through as uncategorized and survive in the final string even when
  they conflict.
- **Arbitrary values**: `bg-[#1da1f2]`, `h-[42px]`, `w-[calc(100%-1rem)]`.
- **Important marker**: `!bg-red-500` is currently grouped with `bg-red-500`.
- **Negative values**: `-m-2` — `SPACING_REGEX` requires a digit immediately
  after the prefix, so this slips through.

### Performance work

The hand-rolled merger is tuned for our patterns and has multiple cache
layers. Before swapping, prove the gem doesn't regress real-world rendering:

- Build a benchmark mirroring actual usage — many components per page, each
  running merge against base + variants + custom. Measure cold-start, warm
  calls on identical inputs, and memory footprint.
- Hold the `Merger` instance once at class level (or in a constant). The gem
  has measurable startup cost to build its conflict-group index — that cost
  should be paid once per process, not per call.
- Preserve `_css_cache` and `_css_merge_cache`. They cache the *result* of
  merging keyed on component instance state, so they sit above whichever
  merger is called internally. Confirm cache hit rates don't change if the
  gem produces different (but equivalent) output orderings.
- If we lose meaningful perf under our caching strategy, that's a stay
  signal.

### Risk and exit plan

- 143-star gem; reasonably maintained but smaller than Rails-core stable.
  Pin to a known version. Because the interface is essentially one method
  (`merge(String) → String`), reverting to the hand-rolled version is
  straightforward if the gem stalls or breaks.
- Confirm the gem's update cadence keeps pace with Tailwind releases we
  rely on.

### Decision criteria

Swap if **all** hold:
- Spacing parity proven via direct comparison on real inputs.
- Caching survives without measurable regression.
- Audit confirms we hit utility groups the gem covers and we don't (worth
  the swap), or that the maintenance burden of expanding `CATEGORIES`
  ourselves is real and recurring.

Stay hand-rolled if any of:
- Behavior diverges on cases we can't easily reconcile.
- Perf regresses materially even with the existing cache layers.
- Audit shows we don't actually exercise the missing utility groups, so the
  gain is small relative to the dependency cost.

## 2. Promote data/aria/HTML attribute declarations to first-class DSL

Currently `data_attrs` and `aria_attrs` are override methods quietly picked up by `html_attrs` and splatted onto the top-level element. They look like ordinary instance methods, which is bad DX — a reader has to know about the magic to realize they affect rendered output. Goal: declarations sit alongside `css` so the mental model is "everything I declare up here ends up in `html_attrs` and gets spread on the top-level element."

Research, not committed implementation. Difficulties to work through first:

### Conditional logic with ivar / method access

Real-world default-attr methods aren't constant — they call helpers and branch on instance state:

```ruby
def data_attrs
  {
    action: token_list(input_action, ("debounced:input->form#submit" if @auto_submit)).presence,
    controller: (token_list(autofocus: true) if @autofocus),
    turbo_permanent: (true if turbo_permanent?)
  }.compact
end
```

This is trivial in a method body. Translating to class-level declarations is non-obvious. Procs (`instance_exec`'d at render time, like `css -> { ... }`) are the obvious lever, but possibly less elegant, harder to read for non-trivial logic, and maybe less performant. Worth prototyping before committing.

### Scope and syntax

Should the DSL cover *any* HTML attribute, not just `data`/`aria`/`class`? Likely yes — recent real example: a default `target` had to be inlined in the template alongside `**html_attrs`, leaving the caller no override path.

Naming is tricky. The term `html_attrs` already means the rendered hash and the template splat — reusing it for the declaration syntax risks confusion. The existing `css` deliberately doesn't look like it's writing to `html_attrs` even though it is, and grouping declarators by concern (`css`, `data`, `aria`, generic `attr`) probably reads better than a single nested `html_attrs` block. Worth prototyping both.

### Stretch: eliminate the template splat boilerplate

Spitballing, not committed. Even with first-class declarations, templates still need `<%= tag.div **html_attrs do %>`. One direction worth researching: a helper that takes just the tag name and injects attrs automatically:

```erb
<%= top_level_element :button do %>
  <%= content %>
<% end %>
```

Defaulting to `div` when no tag is given. Open question whether there are real cases where the dev needs to intervene between the helper and the splat.

### Research

- Prior art: Phlex, ViewComponentContrib.
- Prototype syntax options on real Forge components with non-trivial conditional logic.
- Benchmark proc-based vs method-based if proc looks viable.

## 3. Lightweight in-template styling for sub-elements

The DSL's discipline today is: top-level element gets `css` declarations; sub-elements that need dynamic styling get promoted to their own ViewComponent. Clean, but can feel out of proportion to the change — especially for "tweener" sub-elements that only react to a single boolean from the parent. Real example: `PerceptionCommentButton` has sub-elements whose CSS is dynamic but trivially derived from parent state; not complex enough to warrant a sub-component, but no DSL-shaped path to express it inline.

Possible directions worth exploring:

- **In-line declarative methods** — class-level declarations the template can call to get a merged class string for a sub-element.
- **DSL extension** like `sub_css :icon, base: "...", variant: {primary: "..."}` returning a merged string.
- **"Inline slot"** — render as a slot without the ceremony of a separate ViewComponent file.

Tension: any of these can scope-creep into a parallel mini-DSL and undermine the discipline that real components are the unit of composition.

Counterpoint to itself: maybe that discipline IS the point, and the right answer is better extraction tooling/guidance rather than making it easier to avoid extraction.

Research goal: find the smallest pattern that handles the "trivial sub-element reacting to a single parent prop" case without enabling sprawl. Or conclude there isn't one and lean in.
