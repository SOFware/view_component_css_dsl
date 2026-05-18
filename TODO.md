# view_component_css_dsl — TODO

Working notes for follow-up improvements. Likely deleted once items land.

## 1. Eliminate the template splat boilerplate

Even with first-class declarations, templates still need `<%= tag.div **html_attrs do %>`. One direction worth researching: a helper that takes just the tag name and injects attrs automatically:

```erb
<%= top_level_element :button do %>
  <%= content %>
<% end %>
```

Defaulting to `div` when no tag is given. Open question whether there are real cases where the dev needs to intervene between the helper and the splat.

## 2. Lightweight in-template styling for sub-elements — decided: NOT doing this (2026-05-18)

**Decision:** The DSL stays scoped to the top-level component element. No `sub_css`, `icon_css`, `*_html_attrs`, or inline-slot styling shortcut. Sub-elements that need dynamic CSS get extracted into their own ViewComponent.

**Reason:** API stickiness is a one-way door. Shipping a sub-element API now and removing it later is a breaking change requiring caller migration; adding it later is purely additive and breaks nothing. Combined with thin sample data — only one real-world case examined (`PerceptionResponseButtonComponent` in FORGE) and even that one was ambiguous (drag-handle wants extraction, comment-button is wrapper-shaped) — conservative is correct.

**May revisit if:** the same "trivial sub-element reacting to one parent prop" pattern recurs 3+ times across real components with the same shape. At that point we'd have enough data to design the narrowest possible API (strict `base:` + `when: :predicate?`, no `variant:`/axes) with confidence the shape fits.

**Counter-arguments to expect when this resurfaces:**

- *"Components are over-ceremonious for trivial cases."* True cost, but the right fix is scaffold/generator tooling, not a parallel styling DSL.
- *"Refactoring sub-elements back to components is easy."* Refactor cost is roughly symmetric in both directions; the real asymmetry is API commitment, which is one-way.
- *"A sub-element DSL would be cleaner than today's `class_names` methods."* True, but milder than the original messiness argument and not enough by itself to justify the one-way door.

**Follow-up:** add a short "when to extract a sub-component" note to README so library users understand the discipline is intentional, not an oversight.
