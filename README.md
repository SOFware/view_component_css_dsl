# view_component_css_dsl

A small declarative DSL for defining CSS classes on
[ViewComponent](https://viewcomponent.org/) components — designed to pair with
[Tailwind CSS](https://tailwindcss.com/).

Declare base styles, variants, and conditional classes at the top of your
component class, and let the DSL smart-merge them with caller-provided
overrides. Especially handy for Tailwind, because the merge understands
spacing axes, border axes, modifier prefixes (`hover:`, `md:`, `group/`,
`data-[...]`, etc.), and category overrides (e.g. caller's `bg-blue-500`
replaces the component's default `bg-white`).

## Requirements

- Ruby 3.1+
- [`view_component`](https://github.com/ViewComponent/view_component) `>= 4.0`
- [Tailwind CSS](https://tailwindcss.com/) `>= 3.0` (the merge logic targets
  Tailwind's class-name syntax)

Tailwind v4 is supported — the DSL parses class names, it doesn't generate
them, and Tailwind v4 kept the class-name syntax compatible.

## Installation

```sh
bundle add view_component_css_dsl
```

## Setup

Create a base component class that includes the concern, and inherit your
components from it:

```ruby
# app/components/application_component.rb
class ApplicationComponent < ViewComponent::Base
  include ViewComponentCssDsl
end
```

```ruby
# app/components/button_component.rb
class ButtonComponent < ApplicationComponent
  css "inline-flex items-center rounded px-4 py-2"
  css variant: :primary, style: "bg-blue-500 text-white"
  css variant: :secondary, style: "bg-gray-200 text-gray-900"

  def initialize(text, variant: :primary, **html_attrs)
    @text = text
    @variant = variant
    @html_attrs = html_attrs
  end

  attr_reader :text
end
```

```erb
<%# app/components/button_component.html.erb %>
<button class="<%= css %>">
  <%= text %>
</button>
```

To opt out for a single component (e.g. you need vanilla ViewComponent
behavior), just inherit from `ViewComponent::Base` directly instead of from
your `ApplicationComponent`.

## Why

Before this DSL, conditional component classes looked something like this:

```ruby
class FooComponent < ApplicationComponent
  SIZES = %i[sm default lg].freeze
  VARIANTS = %i[success danger].freeze

  def initialize(text, size: :default, variant: :success, **html_attrs)
    raise "Invalid size" unless size.in?(SIZES)
    raise "Invalid variant" unless variant.in?(VARIANTS)

    @text = text
    @variant = variant
    @size = size
    @html_attrs = html_attrs
  end

  private

  attr_reader :size, :text, :variant

  def classes
    class_names(
      "bg-blue-500 rounded shadow",
      custom_css,
      "text-green-800 bg-green-200": variant == :success,
      "text-red-800 bg-red-200": variant == :danger,
      "p-2": size == :sm,
      "p-4": size == :default,
      "p-6": size == :lg,
      "font-bold": variant == :success && size == :lg,
      "border-2 border-blue-700": active?
    )
  end

  def active?
    @html_attrs.key?(:active)
  end
end
```

With the DSL the same component becomes:

```ruby
class FooComponent < ApplicationComponent
  css "bg-blue-500 rounded shadow"

  css variant: :success, style: "text-green-800 bg-green-200"
  css variant: :danger,  style: "text-red-800 bg-red-200"

  css size: :sm,      style: "p-2"
  css size: :default, style: "p-4"
  css size: :lg,      style: "p-6"

  css variant: :success, size: :lg, style: "font-bold"

  css :active?, style: "border-2 border-blue-700"

  def initialize(text, size: :default, variant: :success, **html_attrs)
    @text = text
    @size = size
    @variant = variant
    @html_attrs = html_attrs
  end

  private

  attr_reader :size, :text, :variant

  def active?
    @html_attrs.key?(:active)
  end
end
```

Notable differences:

- No hand-rolled validation — passing an unknown variant raises an
  `ArgumentError` with the list of valid values.
- No `class_names` boilerplate. Conditions are declarative.
- Caller customization (`<%= render FooComponent.new(..., class: "bg-red-500") %>`)
  is smart-merged automatically; no `custom_css` call needed.
- Components can still override or extend behavior via standard Ruby:
  inheritance, instance methods, etc.

## The four `css` patterns

### 1. Base CSS

Always applied. Inherited and smart-merged into child components.

```ruby
css "rounded border shadow p-4 bg-white"
```

### 2. Axis-based variants

Applied when one or more matching instance variables equal the given values.
The DSL reads `@<axis>` from the instance.

```ruby
css variant: :primary, style: "bg-blue-500 text-white"
css variant: :danger,  style: "bg-red-500 text-white"

css size: :sm, style: "px-2 py-1 text-sm"
css size: :lg, style: "px-6 py-3 text-lg"

# Multi-axis rule — applied only when ALL axes match
css variant: :primary, size: :lg, style: "font-bold ring-2"
```

Passing an axis value that no rule covers raises `ArgumentError`:

```ruby
MyComponent.new(variant: :unknown).css
# => ArgumentError: Unknown variant :unknown for MyComponent.
#    Valid values: :primary, :danger
```

### 3. Method-based conditionals

Applied when the method returns truthy on the instance.

```ruby
css :disabled?, style: "opacity-50 cursor-not-allowed"
css :active?,   style: "ring-2 ring-blue-500"

def disabled? = @disabled
def active?   = @active
```

### 4. Proc-based dynamic CSS

Evaluated at render time in the instance's context. Use when the class can't
be known statically (e.g. depends on an instance variable's value).

```ruby
css "base"
css -> { "pl-#{@indent * 4}" }
```

Procs returning `nil` are dropped. Procs participate in smart_merge so they
can override base classes.

## Caller customization

The DSL reads `@html_attrs[:class]` as the caller's custom CSS. Any class
the caller passes via `class:` is smart-merged with the component's base +
variant classes — caller wins on category collisions.

```ruby
def initialize(**html_attrs)
  @html_attrs = html_attrs
end
```

```erb
<%# Caller %>
<%= render ButtonComponent.new(class: "bg-red-500 mt-4") %>
```

```ruby
# Inside the component:
css            # => "inline-flex items-center rounded px-4 py-2 bg-red-500 mt-4"
                  # (caller's bg-red-500 replaced component's bg-blue-500;
                  #  mt-4 added since margin wasn't in the base)
```

## Smart merge behavior

Smart-merge handles Tailwind's conventions so caller and component CSS can
coexist sensibly:

| Scenario                                     | Result                          |
| -------------------------------------------- | ------------------------------- |
| `"bg-white"` + `"bg-blue-500"`               | `"bg-blue-500"` (category win)  |
| `"p-4"` + `"p-8"`                            | `"p-8"` (all-padding override)  |
| `"px-4"` + `"py-2"`                          | `"px-4 py-2"` (different axes)  |
| `"p-4"` + `"pb-6"`                           | `"p-4 pb-6"` (specific extends) |
| `"pl-2"` + `"px-5"`                          | `"px-5"` (broader axis wins)    |
| `"border-t"` + `"border-t-2"`                | `"border-t-2"`                  |
| `"border-2 border-red-600"`                  | both kept (width vs color)      |
| `"bg-white"` + `"hover:bg-blue-500"`         | both kept (modifier namespace)  |
| `"hover:bg-blue-500"` + `"hover:bg-red-500"` | `"hover:bg-red-500"`            |
| `"bg-white"` + `"data-[open]:bg-gray-100"`   | both kept                       |

Modifier prefixes (`hover:`, `md:`, `dark:`, `group/`, `peer-checked:`,
`aria-*`, arbitrary `[…]` values, etc.) form their own merge namespace, so
`hover:bg-blue-500` never conflicts with a base `bg-white`.

## Inheritance

A child component's `css "..."` declaration is smart-merged with its parent's
base CSS:

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

## Reading the rendered class string

Use the instance method `css` in the template:

```erb
<%= tag.div class: css do %>
  <%= content %>
<% end %>
```

If you want zero-config `class:` plumbing (so callers can pass `class: "..."`
and have it merged automatically without touching `initialize`), see the
recipe below.

## Recipe: auto-extract `html_attrs` in your base class

Many projects pair this DSL with a base class that auto-captures any HTML
attributes from the caller and merges them into the rendered element. Here's
a minimal version:

```ruby
class ApplicationComponent < ViewComponent::Base
  include ViewComponentCssDsl

  HTML_ATTR_KEYS = Set[
    :alt, :aria, :class, :data, :href, :id, :role,
    :style, :target, :title, :type, :value
    # ...extend as needed
  ].freeze

  def self.new(*args, **kwargs, &block)
    extractable = HTML_ATTR_KEYS.intersection(kwargs.keys)
    html_attrs  = kwargs.extract!(*extractable)

    instance = allocate
    instance.instance_variable_set(:@html_attrs, html_attrs)
    instance.send(:initialize, *args, **kwargs, &block)
    instance
  end

  private

  def html_attrs
    return {} unless @html_attrs

    result = @html_attrs.except(:class)
    rendered = css
    result[:class] = rendered if rendered.present?
    result
  end
end
```

Then component templates become:

```erb
<%= tag.div **html_attrs do %>
  <%= content %>
<% end %>
```

…and callers can pass any HTML attribute (`class:`, `data:`, `id:`, etc.)
without the component declaring it explicitly.

## Development

```sh
bin/setup       # bundle install
bundle exec rspec
bundle exec standardrb
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
