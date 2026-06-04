# view_component_css_dsl

[![CI](https://github.com/SOFware/view_component_css_dsl/actions/workflows/ci.yml/badge.svg)](https://github.com/SOFware/view_component_css_dsl/actions/workflows/ci.yml)

A declarative DSL for styling [ViewComponent](https://viewcomponent.org/) components with [Tailwind CSS](https://tailwindcss.com/).

```ruby
class ButtonComponent < ApplicationComponent
  css "inline-flex rounded px-4 py-2"
  css variant: :primary, style: "bg-blue-500 text-white"
  css variant: :danger,  style: "bg-red-500 text-white"
  css :disabled?,        style: "opacity-50"
end
```

Replaces hand-rolled styling boilerplate with declarative one-liners for base styles, variants, and conditionals. Callers override per-instance via `class:` — smart-merge handles the rest.

## Why

Without this DSL, a ViewComponent with a few variants and a disabled state usually looks something like:

```ruby
class ButtonComponent < ViewComponent::Base
  VARIANTS = %i[primary danger].freeze

  def initialize(variant: :primary, disabled: false, extra_class: nil)
    raise ArgumentError, "invalid variant" unless VARIANTS.include?(variant)
    @variant = variant
    @disabled = disabled
    @extra_class = extra_class
  end

  private

  def css_class
    [
      "inline-flex rounded px-4 py-2",
      variant_class,
      ("opacity-50" if @disabled),
      @extra_class
    ].compact.join(" ")
  end

  def variant_class
    case @variant
    when :primary then "bg-blue-500 text-white"
    when :danger  then "bg-red-500 text-white"
    end
  end

  def data_attrs
    {variant: @variant, controller: "button-component"}
  end
end
```

With the DSL:

```ruby
class ButtonComponent < ApplicationComponent
  css "inline-flex rounded px-4 py-2"
  css variant: :primary, style: "bg-blue-500 text-white"
  css variant: :danger,  style: "bg-red-500 text-white"
  css :disabled?,        style: "opacity-50"

  data variant: :variant, controller: "button-component"

  def initialize(variant: :primary, disabled: false)
    @variant = variant
    @disabled = disabled
  end

  private

  attr_reader :variant
  def disabled? = @disabled
end
```

- Variant validation is automatic; passing `:unknown` raises an `ArgumentError`.
- Declarations are easy to scan, easy to extend.
- A caller's `class: "..."` is smart-merged with the component's defaults: `bg-black` from the caller wins over the component's `bg-blue-500`, but `rounded` and `px-4` stick.
- Data attributes get the same declarative treatment — see [Declaring data, aria, and HTML attributes](#declaring-data-aria-and-html-attributes) below for the full pattern.

## Philosophy

A handful of opinions are baked into this DSL. It still works if you ignore them, but it's a lot nicer if you don't.

### Styling lives with the component

Not in external stylesheets. Open the component file and you see exactly what it looks like. No grepping for selectors. No cascade surprises.

### Significant styling lives on the top-level element

A component renders one semantic block; that block is where its appearance lives. The DSL's `css` declarations describe that block.

### Caller customization targets the top-level element

When a caller passes `class: "..."`, the DSL smart-merges those classes onto the top-level element. Predictable surface, predictable override.

### Sub-element styling = sub-component

When a piece of your component needs its own styling decisions, promote it to its own ViewComponent (typically as a slot). Pass the shared semantic prop down; each component owns its own style table:

```ruby
class CardComponent < ApplicationComponent
  css "rounded border p-4"
  css type: :success, style: "border-green-200 bg-green-50 text-green-900"
  css type: :danger,  style: "border-red-200 bg-red-50 text-red-900"

  renders_one :card_header, ->(**html_attrs, &block) {
    Card::HeaderComponent.new(type:, **html_attrs, &block)
  }

  def initialize(type:)
    @type = type
  end

  private

  attr_reader :type
end

class Card::HeaderComponent < ApplicationComponent
  css "font-medium"
  css type: :success, style: "text-sm"
  css type: :danger,  style: "text-lg font-bold"

  def initialize(type:)
    @type = type
  end
end
```

The card renders the header as a slot, passing `type:` through. Without the DSL, this is typically a `case` statement or `class_names` block in both components — duplicated logic, more places for the style decision to drift. With it, each component reacts declaratively to the same shared prop.

If you find yourself reaching inside a component to customize a sub-element, especially with dynamic styling, the sub-element wants to be its own component.

## Requirements

- Ruby 3.2+ (matches the floor for `view_component >= 4.0`)
- [`view_component`](https://github.com/ViewComponent/view_component) `>= 4.0`
- [Tailwind CSS](https://tailwindcss.com/) `>= 3.0` (the merge logic targets Tailwind's class-name syntax; v4 works — the syntax is compatible)

## Installation

```sh
bundle add view_component_css_dsl
```

## Setup

Include the concern in your base class, and inherit your components from it.

`html_attrs` is automatically passed to all components; no declaration needed.

The one piece of boilerplate: you must splat `**html_attrs` onto the top-level element of each component template.

Main setup:
```ruby
# app/components/application_component.rb
class ApplicationComponent < ViewComponent::Base
  include ViewComponentCssDsl
end
```

Component inherits from ApplicationComponent, gaining access to CssDsl
```ruby
# app/components/button_component.rb
class ButtonComponent < ApplicationComponent
  css "rounded px-4 py-2 bg-blue-500 text-white"

  css variant: :success, style: "text-green-600"
  css variant: :danger,  style: "text-lg font-bold text-red-600"

  def initialize(variant: :primary)
    @variant = variant
  end
end
```

Splat `**html_attrs` onto the top-level element.
```erb
<%# app/components/button_component.html.erb %>
<%= tag.button **html_attrs do %>
  <%= content %>
<% end %>
```

Two conventions to follow:

1. **`include ViewComponentCssDsl`** in your base component class. To opt out for one component, inherit from `ViewComponent::Base` directly.
2. **Splat `**html_attrs`** onto the top-level element. This is what makes caller-passed attributes (`class:`, `data:`, `id:`, `aria:`, etc.) reach the DOM. A future version may automate this away.

## The four `css` patterns

### Base CSS

Always applied. Inherited and smart-merged into child components.

```ruby
css "rounded border shadow p-4 bg-white"
```

### Axis-based variants

Applied when the named instance variable matches. The DSL reads `@<axis>` from the instance.

```ruby
css variant: :primary, style: "bg-blue-500 text-white"
css variant: :danger,  style: "bg-red-500 text-white"

css size: :sm, style: "px-2 py-1 text-sm"
css size: :lg, style: "px-6 py-3 text-lg"

# Multi-axis rule — applied only when ALL axes match
css variant: :primary, size: :lg, style: "font-bold ring-2"
```

Passing an axis value with no matching rule raises `ArgumentError`:

```ruby
MyComponent.new(variant: :unknown).css
# => ArgumentError: Unknown variant :unknown for MyComponent.
#    Valid values: :primary, :danger
```

### Method-based conditionals

Applied when the method returns truthy on the instance.

```ruby
css :disabled?, style: "opacity-50 cursor-not-allowed"
css :active?,   style: "ring-2 ring-blue-500"
```

### Proc-based dynamic CSS

Evaluated at render time in the instance's context. Use when the class can't be known statically.

```ruby
css "base"
css -> { "pl-#{@indent * 4}" }
```

Procs returning `nil` are dropped. Procs participate in smart_merge.

## Declaring `data`, `aria`, and HTML attributes

The gem provides three sibling declarators that mirror `css`'s shape: `data`, `aria`, and `attribute`. Use them to declare attributes alongside your styles instead of overriding methods.

```ruby
class ButtonComponent < ApplicationComponent
  css "rounded px-4 py-2 bg-blue-500 text-white"

  data variant: :variant, size: :size
  aria label: "Submit"
  attribute target: "_blank"

  def initialize(variant: :primary, size: :default)
    @variant = variant
    @size = size
  end

  attr_reader :variant, :size
end
```

All three declarators share the same patterns. The only difference is *where* the attribute lands in the rendered HTML — `data` produces `data-*`, `aria` produces `aria-*`, and `attribute` produces a top-level attribute.

### Static values

Always emitted. Stringified at render time (booleans, integers, etc. all become strings; `nil` drops the attribute).

```ruby
data controller: "modal"
aria label: "Close dialog"
attribute target: "_blank"
```

### Symbol values — call an instance method

When the value is a Symbol, the DSL calls that instance method at render time and uses the result. Standard pattern for streaming an ivar or computed value into a data attribute.

```ruby
data variant: :variant       # calls #variant; renders as data-variant="<value>"
attribute tabindex: :tab_index

def tab_index
  focusable? ? 0 : -1
end
```

If the method returns `nil`, the attribute is dropped.

### Proc values — inline computation

For one-off computed values that don't deserve a named method:

```ruby
aria label: -> { "#{@variant} Notification".titleize }
data turbo_permanent: -> { true if turbo_permanent? }
```

Procs are `instance_exec`'d at render time, so they see instance state. Procs returning `nil` drop the attribute.

### Conditional inclusion via positional predicate

Mirrors the `css :method?, style: "..."` pattern — a positional Symbol or Proc as the first argument acts as a predicate. When truthy, the declaration applies; when falsy, it's skipped entirely.

```ruby
data :auto_dismiss?, timeout: "5000", animation: "fade"
aria :loud?, label: "Important"
attribute -> { @disabled }, disabled: true
```

The Symbol form calls the named instance method; the Proc form is `instance_exec`'d.

### Multiple attributes per declaration

Each declaration accepts a hash of attributes. All share the same predicate (if any).

```ruby
data controller: "modal",
     modal_dismiss_action: "click->modal#dismiss"
```

### Multiple declarations: how they compose

For `aria` and `attribute`, repeated keys across declarations *replace* — the last declaration wins.

For `data`, **the keys `:controller` and `:action` accumulate** (they're space-separated lists in HTML), and everything else replaces. This matches how the gem already merges component defaults with caller-passed values.

```ruby
data :modal?,        controller: "modal"
data :trap_focus?,   controller: "trap-focus"
# Both predicates true → data-controller="modal trap-focus"
# Only :modal? true   → data-controller="modal"
# Neither true        → data-controller attribute is omitted
```

### Caller customization

Whatever a caller passes for `class:`, `data:`, `aria:`, or any HTML attribute layers on top of your declarations using the same rules:

- `class:` smart-merged (see Smart merge behavior below)
- `data:` controller/action keys concatenate, others replace
- `aria:` and other attrs: caller wins

### Inheritance

Subclass declarations stack on top of parent declarations using the same rules. `data controller:` declarations in a child class concatenate with the parent's; `data role:` in a child class replaces the parent's. `aria` and `attribute` keys in a child class replace the parent's.

```ruby
class CardComponent < ApplicationComponent
  data controller: "card"
  data role: "region"
end

class HighlightedCardComponent < CardComponent
  data controller: "highlighted"   # appends → data-controller="card highlighted"
  data role: "alert"                # replaces → data-role="alert"
end
```

## Caller customization

Callers can pass `class:` (smart-merged with the component's defaults), plus any other HTML attribute (`data:`, `id:`, `aria:`, etc.) — they all land on the top-level element without the component having to opt each one in.

### Vanilla call

```ruby
class ButtonComponent < ApplicationComponent
  css "rounded px-4 py-2 bg-blue-500 text-white"
end

render ButtonComponent.new
```

Renders:

```html
<button class="rounded px-4 py-2 bg-blue-500 text-white"></button>
```

### Call with overrides

```ruby
render ButtonComponent.new(
  class: "mt-4 bg-red-500",
  data: {id: "submit-btn"},
  aria: {label: "Submit form"}
)
```

Renders:

```html
<button
  class="rounded px-4 py-2 mt-4 bg-red-500 text-white"
  data-id="submit-btn"
  aria-label="Submit form">
</button>
```

- `bg-red-500` from the caller replaced `bg-blue-500` from the component (same category).
- `mt-4` was added (no margin in the base).
- `rounded`, `px-4`, `py-2`, `text-white` retained from the base.
- `data-id` and `aria-label` flow through to the DOM untouched.

## Smart merge behavior

Smart-merge handles Tailwind's conventions so caller and component CSS can coexist sensibly. Under the hood it delegates to the [`tailwind_merge`](https://github.com/gjtorikian/tailwind_merge) gem, which mirrors [tailwind-merge](https://github.com/dcastil/tailwind-merge) (JS) semantics. In every row below, the **Component** column is what the component declared via `css`, and the **Caller** column is what was passed in `class:` at the call site.

| Component | Caller | Final classes | Why |
| --- | --- | --- | --- |
| `bg-white` | `bg-blue-500` | `bg-blue-500` | Same category (background) — caller wins |
| `p-4` | `p-8` | `p-8` | All-padding overrides all-padding |
| `px-4` | `py-2` | `px-4 py-2` | Different spacing axes — both kept |
| `p-4` | `pb-6` | `p-4 pb-6` | Specific side extends the all-side base |
| `pl-2` | `px-5` | `px-5` | Broader axis (`x`) absorbs the narrower (`l`) |
| `border-t` | `border-t-2` | `border-t-2` | Same side, more specific width — caller wins |
| `border-2` | `border-red-600` | `border-2 border-red-600` | Width and color are independent |
| `bg-white` | `hover:bg-blue-500` | `bg-white hover:bg-blue-500` | Modifier prefix is its own namespace |
| `hover:bg-blue-500` | `hover:bg-red-500` | `hover:bg-red-500` | Caller wins within the modifier namespace |
| `bg-white` | `data-[open]:bg-gray-100` | `bg-white data-[open]:bg-gray-100` | Arbitrary modifier is its own namespace |

Modifier prefixes (`hover:`, `md:`, `dark:`, `group/`, `peer-checked:`, `aria-*`, arbitrary `[…]` values, etc.) form their own merge namespace, so `hover:bg-blue-500` never conflicts with a base `bg-white`.

### JS-toggle visibility — use the `hidden` attribute, not the class

`hidden` is treated as part of the display group, so `"flex hidden"` collapses to `"hidden"` (the same as upstream tailwind-merge). If you need to toggle visibility from JavaScript while preserving a base display class, use the HTML5 `hidden` attribute via the `attribute` DSL:

```ruby
class PaneComponent < ApplicationComponent
  css "block"
  attribute hidden: -> { collapsed? }
end
```

Then toggle from JS with `element.toggleAttribute('hidden')` or `element.hidden = true/false`. The class merger stays out of the way and the element retains its `block`/`flex`/etc. layout when shown.

## Inheritance

A child component's `css "..."` declaration is smart-merged with its parent's:

```ruby
class CardComponent < ApplicationComponent
  css "rounded shadow p-4 bg-white"
end

class HighlightedCardComponent < CardComponent
  css "bg-yellow-50 ring-2 ring-yellow-200"
  # Final base CSS:
  # "rounded shadow p-4 bg-yellow-50 ring-2 ring-yellow-200"
end
```

Axis, method, and proc rules are appended, not overridden.

## Verifier

The DSL's worst failure modes are silent: a typo'd or hallucinated Tailwind class produces no CSS at all under JIT, a self-conflicting declaration quietly drops a class, and a rule referencing a missing method only raises at render time on the code path that hits it. `ViewComponentCssDsl::Verifier` catches all of these statically — fast enough to run on every edit.

```ruby
require "view_component_css_dsl/verifier"

oracle = ViewComponentCssDsl::Verifier::CompiledCssOracle.new(
  "app/assets/builds/tailwind.css"
)
verifier = ViewComponentCssDsl::Verifier.new(known_classes: oracle)

findings = components.flat_map { |component| verifier.verify(component) }
puts findings
abort if findings.any?(&:error?)
```

`verify(component)` returns `Finding` structs (`component`, `check`, `severity`, `message`). Six checks run:

| Check | Asserts | Catches |
| --- | --- | --- |
| `class_validity` | Every declared class exists in the compiled Tailwind output | Typos, hallucinated classes, theme values that don't exist |
| `self_conflicts` | No declaration conflicts with itself | `css "block flex"` silently dropping `block` |
| `method_rules` | Every Symbol in `css`/`data`/`aria`/`attribute` rules resolves to a method | Render-time `NoMethodError`s |
| `axes_settable` | Every axis has an initialize param or `@ivar` assignment | Variant rules that can never fire |
| `variant_matrix` | `#css` builds cleanly for every axis-value combination | Anything the static checks miss, without rendering |
| `template_splat` | Every template references `html_attrs` | Components whose DSL output never reaches the DOM |

Notes:

- **Verify every class in the hierarchy**, abstract bases included. Declaration checks only inspect what each class itself declared, so a parent's mistakes are reported once — on the parent.
- `known_classes:` is anything responding to `include?(String)`. `CompiledCssOracle` parses class selectors out of a compiled Tailwind build; since Tailwind's JIT generates a rule for every valid class found in your content globs, a declared class missing from the output is invalid. Rebuild before verifying — the oracle is only as fresh as the build. Omit `known_classes:` to skip the check.
- `template_splat` covers sidecar files, inline templates (`erb_template "..."`), and hand-written `#call` methods.
- The variant matrix smoke-tests on bare (`allocate`d) instances. Method and proc rules that need `initialize` state report as warnings rather than errors.

## Development

```sh
bundle install
bundle exec rspec
bundle exec standardrb
```

Releases are managed by [reissue](https://github.com/SOFware/reissue). When committing, add Keep-a-Changelog trailers (`Added:`, `Changed:`, `Fixed:`, etc.) and reissue will collate them into `CHANGELOG.md` at release time. To publish a new version, run the "Release gem to RubyGems.org" workflow from GitHub Actions.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
