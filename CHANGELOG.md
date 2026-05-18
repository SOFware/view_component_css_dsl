# Changelog



## [0.1.4] - Unreleased

## [0.1.3] - 2026-05-18

### Changed

- `smart_merge` now delegates to the `tailwind_merge` gem. The public API is unchanged, but conflict resolution now matches upstream tailwind-merge semantics across every Tailwind utility group (previously only spacing, sizing, colors, display, justify, align, font-weight, rounded, and position were handled — shadow, ring, gap, space, divide, z, opacity, leading, tracking, transition, transform, blur, etc. now merge correctly too).

### Breaking

- `hidden` is now treated as part of the display-class conflict group. Strings like `"flex hidden"` collapse to `"hidden"` rather than keeping both. Previous behavior was non-standard — `tailwind-merge` (JS) and `tailwind_merge` (Ruby) have always treated `hidden` as a display utility. For JS-toggle visibility patterns, use the HTML5 `hidden` attribute (e.g., `attribute hidden: -> { … }` or pass `hidden: true` as an html_attr) and toggle it with `element.toggleAttribute('hidden')` instead of relying on the class merger.
