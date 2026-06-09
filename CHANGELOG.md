# Changelog



## [0.1.6] - Unreleased

## [0.1.5] - 2026-06-09

### Added

- ViewComponentCssDsl::Verifier cross_declaration_conflicts check — warns when a class declared in one place (e.g. a base `leading-snug`) is silently dropped because a *different* declaration merged on top of it (e.g. a size axis's `text-sm`, since Tailwind font-size utilities also set line-height). Suppresses intentional same-family overrides (`p-2` → `p-8`) and surfaces only cross-family drops.
- Verifier cross_declaration_conflicts check warning on classes silently dropped when separate DSL declarations merge (168a79e)

### Fixed

- CHANGELOG.md retains the full release history (old entries were trimmed on every version bump) (793d53e)

## [0.1.4] - 2026-06-04

### Added

- ViewComponentCssDsl::Verifier — six static checks for component declarations: Tailwind class validity (via a compiled-CSS oracle), self-conflicting declarations, method-rule resolution, axis settability, variant-matrix smoke, and template html_attrs splat coverage (4be2024)

## [0.1.3] - 2026-05-18

### Changed

- `smart_merge` now delegates to the `tailwind_merge` gem. The public API is unchanged, but conflict resolution now matches upstream tailwind-merge semantics across every Tailwind utility group (previously only spacing, sizing, colors, display, justify, align, font-weight, rounded, and position were handled — shadow, ring, gap, space, divide, z, opacity, leading, tracking, transition, transform, blur, etc. now merge correctly too).

### Breaking

- `hidden` is now treated as part of the display-class conflict group. Strings like `"flex hidden"` collapse to `"hidden"` rather than keeping both. Previous behavior was non-standard — `tailwind-merge` (JS) and `tailwind_merge` (Ruby) have always treated `hidden` as a display utility. For JS-toggle visibility patterns, use the HTML5 `hidden` attribute (e.g., `attribute hidden: -> { … }` or pass `hidden: true` as an html_attr) and toggle it with `element.toggleAttribute('hidden')` instead of relying on the class merger.

## [0.1.2] - 2026-05-15

### Added

- data, aria, and attribute DSL declarators for first-class HTML attribute declarations (cf37050)

## [0.1.1] - 2026-05-15

### Changed

- `view_component` dependency pinned to `~> 4.0` (was `>= 4.0`) — RubyGems-recommended SemVer-aware constraint
- Minimum Ruby version raised to 3.2 (was 3.1), matching the floor for `view_component >= 4.0`

## [0.1.0] - 2026-05-15

### Added

- Initial release. Extracted from SOFware/forge.
