# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/except"
require "active_support/core_ext/hash/slice"
require "active_support/core_ext/object/inclusion"

require_relative "view_component_css_dsl/version"

module ViewComponentCssDsl
  extend ActiveSupport::Concern

  HTML_ATTR_KEYS = Set[
    :alt, :aria, :autofocus,
    :class, :colspan, :contenteditable,
    :data, :dir, :disabled, :download, :draggable,
    :enterkeyhint,
    :formaction,
    :headers, :hidden, :href,
    :id, :inputmode,
    :lang, :loading, :low,
    :media,
    :onclick, :open, :optimum,
    :popover, :popovertarget, :popovertargetaction, :preload,
    :readonly, :rel, :role, :rowspan,
    :spellcheck, :src, :srcset, :style,
    :tabindex, :target, :title, :type, :value
  ].freeze

  # Single combined regex for padding/margin spacing (replaces 14 separate patterns)
  # Captures: type (p/m), axis (x/y/t/r/b/l or nil for all), value
  SPACING_REGEX = /\b(p|m)(x|y|t|r|b|l)?-(\d+)\b/

  # Maps axis character to Set of affected sides
  SPACING_AXIS_MAP = {
    nil => Set[:t, :r, :b, :l],  # p-4, m-4 = all sides
    "x" => Set[:l, :r],
    "y" => Set[:t, :b],
    "t" => Set[:t],
    "r" => Set[:r],
    "b" => Set[:b],
    "l" => Set[:l]
  }.freeze

  # Border width patterns (kept separate due to anchoring requirements)
  BORDER_REGEX = /^border(?:-(x|y|t|r|b|l))?(?:-\d+)?$/

  # Other category patterns (non-spacing, simple override by category)
  # IMPORTANT: Use anchored patterns (^/$) to avoid matching substrings within
  # compound classes (e.g., `h-8` within `min-h-8`, `flex` within `inline-flex`)
  CATEGORIES = {
    background: /^bg-/,
    text_color: /^text-((\w+-\d+)|white|black|transparent|current|inherit|action|success|danger|warning|brand)(\/\d+)?$/,
    text_size: /^text-(xs|sm|base|lg|xl|\d*xl)$/,
    border_color: /^border-(?!t|r|b|l|x|y|\d)(\w+-\d+|\w+)(\/\d+)?$/,
    width: /^w-/,
    height: /^h-/,
    min_width: /^min-w-/,
    min_height: /^min-h-/,
    max_width: /^max-w-/,
    max_height: /^max-h-/,
    # Display classes - note: `hidden` is intentionally excluded because it's
    # commonly used as a visibility toggle alongside other display classes
    # (e.g., "inline-flex hidden" where JS removes "hidden" to show element)
    display: /^(block|inline-block|inline-flex|inline-grid|inline|flex|grid|table-cell|table-row|table|contents|flow-root|list-item)$/,
    justify: /^justify-/,
    align: /^items-/,
    font_weight: /^font-(thin|extralight|light|normal|medium|semibold|bold|extrabold|black)$/,
    rounded: /^rounded(-none|-sm|-md|-lg|-xl|-2xl|-3xl|-full)?$/,
    position: /^(static|relative|absolute|fixed|sticky)$/
  }.freeze

  # Known Tailwind modifiers (prefixes like hover:, md:, first:, etc.)
  # Classes with different modifiers should NOT conflict with each other
  KNOWN_MODIFIERS = Set[
    # Responsive
    "sm", "md", "lg", "xl", "2xl",
    "max-sm", "max-md", "max-lg", "max-xl", "max-2xl",
    # Interactive state
    "hover", "focus", "focus-within", "focus-visible", "active", "visited", "target",
    # Structural
    "first", "last", "only", "odd", "even",
    "first-of-type", "last-of-type", "only-of-type", "empty",
    # Form state
    "disabled", "enabled", "checked", "indeterminate", "default",
    "required", "valid", "invalid", "in-range", "out-of-range",
    "placeholder-shown", "autofill", "read-only",
    # Pseudo-elements
    "before", "after", "first-letter", "first-line",
    "marker", "selection", "file", "backdrop", "placeholder",
    # Media/Preference
    "dark", "print", "portrait", "landscape",
    "motion-safe", "motion-reduce", "contrast-more", "contrast-less",
    "forced-colors",
    # Direction
    "rtl", "ltr",
    # Attribute
    "open",
    # Direct children
    "*"
  ].freeze

  # Patterns that match dynamic modifiers (with optional names/arbitrary values)
  # These use flexible regex to match ANY valid Tailwind modifier syntax
  MODIFIER_PATTERNS = [
    /^group(?:\/\w+)?$/,                    # group, group/<any-name>
    /^group-\w+(?:\/\w+)?$/,                # group-hover, group-<state>/<any-name>
    /^peer(?:\/\w+)?$/,                     # peer, peer/<any-name>
    /^peer-\w+(?:\/\w+)?$/,                 # peer-checked, peer-<state>/<any-name>
    /^aria-\w+$/,                           # aria-checked, aria-<any-attr>
    /^aria-\[.+\]$/,                        # aria-[<arbitrary>]
    /^data-\[.+\]$/,                        # data-[<arbitrary>]
    /^supports-\[.+\]$/,                    # supports-[<arbitrary>]
    /^has-\[.+\]$/,                         # has-[<arbitrary>]
    /^group-has-\[.+\]$/,                   # group-has-[<arbitrary>]
    /^peer-has-\[.+\]$/,                    # peer-has-[<arbitrary>]
    /^min-\[.+\]$/,                         # min-[<arbitrary>]
    /^max-\[.+\]$/                          # max-[<arbitrary>]
  ].freeze

  included do
    class_attribute :_css_base, instance_writer: false, default: ""
    class_attribute :_css_axis_rules, instance_writer: false, default: []
    class_attribute :_css_method_rules, instance_writer: false, default: []
    class_attribute :_css_proc_rules, instance_writer: false, default: []
    # Track which axis names are used in rules (for cache key generation)
    class_attribute :_css_axis_names, instance_writer: false, default: Set.new
    # Precomputed map of axis -> valid values for validation (built at class definition time)
    class_attribute :_css_defined_axes, instance_writer: false, default: {}
    # Lazy cache for precomputed base + axis CSS combinations
    class_attribute :_css_cache, instance_writer: false, default: nil
    # Memoization cache for smart_merge results (axis + method + proc combinations)
    class_attribute :_css_merge_cache, instance_writer: false, default: nil
    # Rules for the data/aria/attribute DSLs. Each entry: {predicate:, attrs:}
    class_attribute :_data_rules, instance_writer: false, default: []
    class_attribute :_aria_rules, instance_writer: false, default: []
    class_attribute :_attribute_rules, instance_writer: false, default: []
  end

  class_methods do
    # Unified css class method supporting multiple patterns:
    # - css "string"                           -> base CSS, always applied
    # - css :method?, style: "string"          -> applied when method? returns truthy
    # - css axis: :value, style: "string"      -> applied when @axis == :value
    # - css axis: :val, other: :val, style: "string" -> applied when ALL axes match
    # - css -> { dynamic_css }                 -> proc evaluated at render time
    def css(*args, **options)
      case args.first
      when Proc
        # Proc-based: css -> { "pl-#{@indent * 4}" }
        self._css_proc_rules = _css_proc_rules.dup
        _css_proc_rules << args.first
        self._css_merge_cache = nil
      when Symbol
        # Method-based: css :disabled?, style: "opacity-50"
        method_name = args.first
        styles = options[:style]
        raise ArgumentError, "css :#{method_name} requires style: keyword" unless styles

        self._css_method_rules = _css_method_rules.dup
        _css_method_rules << {method: method_name, styles: styles}
        self._css_merge_cache = nil
      when String
        if options.empty?
          # Base CSS: css "rounded p-4"
          parent_base_css = superclass.respond_to?(:_css_base) ? superclass._css_base : ""
          self._css_base = if parent_base_css.present?
            smart_merge(parent_base_css, args.first)
          else
            args.first
          end
          # Invalidate caches when base changes
          self._css_cache = nil
          self._css_merge_cache = nil
        else
          raise ArgumentError, "css with String and options not supported. " \
                               "Use: css variant: :name, style: \"classes\""
        end
      when nil
        if (styles = options[:style])
          # Axis-based: css variant: :primary, style: "bg-blue-500"
          axes = options.except(:style)
          self._css_axis_rules = _css_axis_rules.dup
          _css_axis_rules << {axes:, styles:}
          # Track axis names for cache key generation
          self._css_axis_names = _css_axis_names.dup.merge(axes.keys)
          # Precompute valid values per axis for validation
          self._css_defined_axes = _css_defined_axes.transform_values(&:dup)
          axes.each do |axis, value|
            (_css_defined_axes[axis] ||= Set.new) << value
          end
          # Invalidate caches when rules change
          self._css_cache = nil
          self._css_merge_cache = nil
        else
          raise ArgumentError, "css requires style: when using axis conditions"
        end
      else
        raise ArgumentError, "Unknown css argument type: #{args.first.class}"
      end
    end

    # Declares one or more `data-*` attributes on the top-level element.
    #
    #   data controller: "modal"                      # static
    #   data variant: :variant                        # Symbol value -> calls instance method
    #   data foo: -> { computed_value }               # Proc value -> instance_exec'd
    #   data :auto_dismiss?, timeout_value: "5000"    # Symbol predicate
    #   data -> { complex_check? }, foo: "bar"        # Proc predicate
    def data(*args, **kwargs)
      self._data_rules = _data_rules.dup
      _data_rules << _build_attr_rule(:data, *args, **kwargs)
    end

    # Declares one or more `aria-*` attributes on the top-level element.
    # See `data` for the full pattern.
    def aria(*args, **kwargs)
      self._aria_rules = _aria_rules.dup
      _aria_rules << _build_attr_rule(:aria, *args, **kwargs)
    end

    # Declares one or more top-level HTML attributes (`target`, `role`, `tabindex`,
    # etc.) on the rendered element. See `data` for the full pattern.
    def attribute(*args, **kwargs)
      self._attribute_rules = _attribute_rules.dup
      _attribute_rules << _build_attr_rule(:attribute, *args, **kwargs)
    end

    private

    # Builds the rule entry used by `data`, `aria`, and `attribute`.
    # Returns {predicate:, attrs:} where predicate is nil, Symbol, or Proc and
    # attrs is the hash of attribute key -> (literal | Symbol | Proc).
    def _build_attr_rule(namespace, *args, **kwargs)
      if args.size > 1
        raise ArgumentError,
          "#{namespace} accepts at most one positional arg (a predicate Symbol or Proc)"
      end

      predicate = args.first
      if predicate && !predicate.is_a?(Symbol) && !predicate.is_a?(Proc)
        raise ArgumentError,
          "#{namespace} positional predicate must be a Symbol or Proc " \
          "(got #{predicate.class})"
      end

      if kwargs.empty?
        raise ArgumentError,
          "#{namespace} requires at least one attribute kwarg"
      end

      {predicate:, attrs: kwargs}
    end

    public

    # Override `new` to auto-extract HTML attributes from kwargs into @html_attrs,
    # so components don't need to declare **html_attrs in their initialize signature.
    # Anything in HTML_ATTR_KEYS that wasn't declared as a kwarg is captured.
    #
    # These can then be referenced in the component's template as `html_attrs`.
    #
    # Why?
    # - DX: All components can accept arbitrary html attrs for free. Dev can pass
    #   arbitrary html attrs in at any caller and have it output at the component's
    #   top-level element.
    # - Removes boilerplate of putting `**html_attrs` as the last argument in every
    #   single component's initialize signature, and then having to set the same as an
    #   ivar within the initialize body.
    # - Requires following a pattern of declaring `**html_attrs` in the top level
    #   element of every single component's template.
    # - Example template definition:
    #
    #     # html_attrs contains :class, :data, etc defined either in the component
    #     # or passed in by the caller.
    #     <%= tag.my_component **html_attrs do %>
    #       <%= content %>
    #     <% end %>
    #
    # Example caller:
    #
    #   render MyComponent.new(text: "Hello", class: "custom", data: {foo: "bar"})
    #
    # - :text goes to component's #initialize method, as normal
    # - :class, :data, etc are captured and merged into @html_attrs automatically
    # - The component's initialize method will look like:
    #
    #     def initialize(text)
    #       @text = text
    #     end
    #
    # To opt out of this behavior, inherit from ViewComponent::Base directly instead of
    # ApplicationComponent.
    #
    def new(*args, **kwargs, &block)
      info = initialize_params_info
      html_attrs = {}

      # Only extract HTML attrs if the component uses **html_attrs pattern.
      # Components with other keyrest names (like **options) should receive all kwargs.
      if info[:uses_html_attrs_keyrest]
        # Extract HTML attrs, but NOT if they're declared component params
        extractable = HTML_ATTR_KEYS.intersection(kwargs.keys) - info[:declared_kwargs]
        html_attrs = kwargs.extract!(*extractable)
      end

      instance = allocate
      # Set @html_attrs BEFORE initialize so components can access it there
      instance.instance_variable_set(:@html_attrs, html_attrs)
      instance.send(:initialize, *args, **kwargs, &block)

      # Merge with any @html_attrs set by initialize (old pattern components).
      # Caller-provided values (html_attrs) take precedence over component defaults.
      existing = instance.instance_variable_get(:@html_attrs) || {}
      instance.instance_variable_set(:@html_attrs, existing.merge(html_attrs))
      instance
    end

    # Analyzes the initialize signature once and caches the result. Auto-extraction
    # happens unless the component declares a non-html_attrs keyrest (like **options),
    # in which case the component wants to receive everything itself.
    def initialize_params_info
      @initialize_params_info ||= begin
        declared_kwargs = Set.new
        keyrest_name = nil
        instance_method(:initialize).parameters.each do |type, name|
          case type
          when :key, :keyreq
            declared_kwargs << name
          when :keyrest
            keyrest_name = name
          end
        end

        {
          declared_kwargs:,
          uses_html_attrs_keyrest: keyrest_name == :html_attrs || keyrest_name.nil?
        }
      end
    end

    # Overwrites base css with custom css from the caller, but only if they actually
    # interfere with each other. Modifier prefixes (hover:, md:, first:, etc.) create
    # separate "namespaces" so they don't conflict with base classes.
    # Examples:
    # - base: "pt-2", custom: "pt-4", result => "pt-4"
    # - base: "pb-2", custom: "pt-4", result => "pb-2 pt-4"
    # - base: "pb-2", custom: "p-4", result => "p-4"
    # - base: "block", custom: "first:hidden", result => "block first:hidden"
    def smart_merge(*css_strings)
      categorized = {}
      uncategorized = []
      # Store spacing classes grouped by modifier prefix
      # {prefix => [{class: "p-4", info: {type: :padding, axes: Set[:t,:r,:b,:l]}}, ...]}
      spacing_by_prefix = Hash.new { |h, k| h[k] = [] }

      css_strings.compact.each do |str|
        str.to_s.split.each do |cls|
          prefix, base_class = extract_modifier_prefix(cls)

          spacing = spacing_info(base_class)
          if spacing
            # Remove any existing spacing classes that overlap on same type and axes
            # within the same modifier prefix
            spacing_by_prefix[prefix].reject! do |existing|
              existing[:info][:type] == spacing[:type] &&
                existing[:info][:axes].subset?(spacing[:axes])
            end
            spacing_by_prefix[prefix] << {class: cls, info: spacing}
          else
            category = detect_category(base_class)
            if category
              key = "#{prefix}:#{category}"
              categorized[key] = cls
            else
              uncategorized << cls unless uncategorized.include?(cls)
            end
          end
        end
      end

      spacing_classes = spacing_by_prefix.values.flatten.map { |s| s[:class] }
      (uncategorized + spacing_classes + categorized.values).join(" ")
    end

    def spacing_info(css_class)
      # Check padding/margin with single regex (replaces 14 pattern checks)
      if (match = css_class.match(SPACING_REGEX))
        type = (match[1] == "p") ? :padding : :margin
        axes = SPACING_AXIS_MAP[match[2]]
        return {type:, axes:}
      end

      # Check border width (needs separate handling due to anchoring)
      if (match = css_class.match(BORDER_REGEX))
        axes = SPACING_AXIS_MAP[match[1]]
        return {type: :border, axes:}
      end

      nil
    end

    def detect_category(css_class)
      CATEGORIES.find { |_name, pattern| css_class.match?(pattern) }&.first
    end

    # Extracts the modifier prefix from a Tailwind class
    # e.g., "md:hover:bg-blue-500" → ["md:hover", "bg-blue-500"]
    # e.g., "bg-white" → ["", "bg-white"]
    def extract_modifier_prefix(css_class)
      # Fast path: most classes don't have modifiers
      return ["", css_class] unless css_class.include?(":")

      parts = css_class.split(":")
      return ["", css_class] if parts.size == 1

      # Find where modifiers end and the actual class begins
      modifier_parts = []
      parts.each_with_index do |part, i|
        if known_modifier?(part) && i < parts.size - 1
          modifier_parts << part
        else
          base_class = parts[i..].join(":")
          return [modifier_parts.join(":"), base_class]
        end
      end

      # Fallback (shouldn't reach here)
      ["", css_class]
    end

    def known_modifier?(str)
      return true if KNOWN_MODIFIERS.include?(str)
      MODIFIER_PATTERNS.any? { |pattern| str.match?(pattern) }
    end
  end

  # Instance method: generates final CSS string
  def css
    build_classes
  end

  # Returns caller's custom classes from html_attrs
  def custom_css
    return "" unless @html_attrs

    @html_attrs.fetch(:class, "")
  end

  # Returns the hash to splat onto the top-level element of a component template:
  #
  #   <%= tag.div **html_attrs do %> ... <% end %>
  #
  # Includes the smart-merged `:class`, merged `:data` and `:aria` (from any
  # component-defined defaults + caller overrides), and every other caller-passed
  # HTML attribute (`id:`, `role:`, etc.) forwarded to the rendered element.
  def html_attrs
    return {} unless @html_attrs

    # Start with DSL-declared top-level attrs; caller's html_attrs layer on top
    # (caller wins on collision, mirroring the css behavior).
    dsl_attrs = resolved_attr_rules(:attribute)
    result = dsl_attrs.merge(@html_attrs.except(:aria, :class, :data))

    # Only include aria/data if they have content, otherwise they'd override
    # inline attrs in templates like: tag.div data: {foo: "bar"}, **html_attrs
    aria = final_aria_attrs
    data = final_data_attrs
    result[:aria] = aria if aria.present?
    result[:data] = data if data.present?

    css_value = css
    result[:class] = css_value if css_value.present?
    result
  end

  # Overwrite in component subclass to set default data-attrs. They will be merged
  # into html_attrs.
  #
  # Example:
  #
  # def data_attrs
  #   {
  #     controller: "some-stimulus-controller",
  #     action: "click->some-stimulus-controller#someAction",
  #     active: active?
  #   }
  # end
  #
  def data_attrs
    {}
  end

  DATA_MERGE_KEYS = %i[controller action].freeze

  # Loop through data-attrs and merge values from DATA_MERGE_KEYS. Overwrite any
  # others.
  #
  # Ensures the caller doesn't wipe out e.g. data-controller or data-action values
  # defined by the dev in #data_attrs
  #
  # Example:
  #
  # Assuming MyComponent with #data_attrs defined as:
  #
  # def data_attrs
  #   {
  #     controller: "foo",
  #     label: "Hello world"
  #   }
  # end
  #
  # MyComponent.new(data: {controller: "bar", label: "Goodbye"})
  #
  # Will output the following data-attrs:
  #
  # <div data-controller="foo bar" data-label="Goodbye">
  #
  # Notice:
  # - data-controller from the caller is set alongside "foo" instead of overwriting
  # - In contrast, data-label from the caller overwrites the default
  #
  def final_data_attrs
    # Merge in order: DSL declarations -> method override -> caller's :data.
    # Each layer uses DATA_MERGE_KEYS semantics (controller/action concatenate,
    # everything else replaces).
    combined = merge_data_layer(resolved_attr_rules(:data), data_attrs)
    merge_data_layer(combined, @html_attrs.fetch(:data, {}))
  end

  # Overwrite in subclass to define default aria-attrs
  def aria_attrs
    {}
  end

  # Merge in order: DSL declarations -> method override -> caller's :aria.
  # Hash#merge throughout — caller wins on collision (no additive semantics).
  def final_aria_attrs
    resolved_attr_rules(:aria).merge(aria_attrs).merge(@html_attrs.fetch(:aria, {}))
  end

  private

  # Walks the DSL rules for the given namespace (:data, :aria, :attribute),
  # evaluates each predicate, resolves each value, and returns a hash. For
  # the :data namespace, DATA_MERGE_KEYS keys accumulate space-separated when
  # the same key appears in multiple included rules.
  def resolved_attr_rules(namespace)
    rules = case namespace
    when :data then self.class._data_rules
    when :aria then self.class._aria_rules
    when :attribute then self.class._attribute_rules
    end

    rules.each_with_object({}) do |rule, result|
      next unless predicate_met?(rule[:predicate])

      rule[:attrs].each do |key, value|
        resolved = resolve_attr_value(value)
        next if resolved.nil?

        result[key] = if namespace == :data && DATA_MERGE_KEYS.include?(key) && result.key?(key)
          "#{result[key]} #{resolved}"
        else
          resolved
        end
      end
    end
  end

  # Layers `addition` on top of `base` using DATA_MERGE_KEYS semantics: keys
  # in DATA_MERGE_KEYS concatenate space-separated, every other key replaces.
  def merge_data_layer(base, addition)
    addition.each_with_object(base.dup) do |(key, value), result|
      result[key] = if DATA_MERGE_KEYS.include?(key)
        [result[key], value].compact.join(" ")
      else
        value
      end
    end
  end

  # Resolves a predicate. nil predicate -> always true. Symbol -> call instance
  # method. Proc -> instance_exec.
  def predicate_met?(predicate)
    case predicate
    when nil then true
    when Symbol then send(predicate)
    when Proc then instance_exec(&predicate)
    end
  end

  # Resolves a value for a DSL-declared attribute. Symbols become method calls
  # on the instance; Procs are instance_exec'd; literals pass through. Result
  # is stringified unless nil (which drops the attribute).
  def resolve_attr_value(value)
    resolved = case value
    when Symbol then send(value)
    when Proc then instance_exec(&value)
    else value
    end
    resolved&.to_s
  end

  def build_classes
    validate_axes!

    # Get cached base + axis CSS (computed once per axis combination)
    base_with_axes = cached_base_axis_css

    # Check for dynamic elements that require runtime smart_merge
    method_css = collect_matching_method_css
    proc_css = collect_proc_css
    custom = custom_css

    # Fast path: no dynamic elements, return cached result directly
    if method_css.blank? && proc_css.blank? && custom.blank?
      return base_with_axes
    end

    # Memoize smart_merge results when no custom CSS (bounded cache)
    # Custom CSS from callers would create unbounded cache entries
    if custom.blank?
      cache = self.class._css_merge_cache ||= {}
      cache_key = [current_axis_key, method_css, proc_css].join("|")
      return cache[cache_key] ||= self.class.smart_merge(base_with_axes, method_css, proc_css)
    end

    # Custom CSS present - can't memoize, run full smart_merge
    self.class.smart_merge(base_with_axes, method_css, proc_css, custom)
  end

  # Returns cached CSS for base + current axis values
  # Lazy-computes and caches on first access for each axis combination
  def cached_base_axis_css
    cache = self.class._css_cache ||= {}
    axis_key = current_axis_key

    cache[axis_key] ||= compute_base_axis_css
  end

  # Builds a cache key from current axis instance variable values
  def current_axis_key
    self.class._css_axis_names.map { |name| instance_variable_get(:"@#{name}") }
  end

  # Computes smart_merge of base + matching axis rules (no caching)
  def compute_base_axis_css
    base = self.class._css_base
    axis_css = collect_matching_axis_css
    return base if axis_css.blank?

    self.class.smart_merge(base, axis_css)
  end

  def collect_matching_axis_css
    self.class._css_axis_rules.filter_map do |rule|
      matches = rule[:axes].all? do |axis, expected_value|
        actual = instance_variable_get(:"@#{axis}")
        actual == expected_value
      end
      rule[:styles] if matches
    end.join(" ")
  end

  def validate_axes!
    defined_axes = self.class._css_defined_axes
    return if defined_axes.empty?

    # Check each axis has a matching rule for its current value
    defined_axes.each do |axis, valid_values|
      current = instance_variable_get(:"@#{axis}")
      next if current.nil? # Axis not set, skip validation

      unless valid_values.include?(current)
        valid_list = valid_values.map { |v| ":#{v}" }.join(", ")
        raise ArgumentError,
          "Unknown #{axis} :#{current} for #{self.class.name}. Valid values: #{valid_list}"
      end
    end
  end

  def collect_matching_method_css
    self.class._css_method_rules.filter_map do |rule|
      method_name = rule[:method]
      unless respond_to?(method_name, true)
        raise NoMethodError,
          "ViewComponentCssDsl method rule references undefined method `#{method_name}` in #{self.class.name}"
      end
      result = send(method_name)
      rule[:styles] if result
    end.join(" ")
  end

  def collect_proc_css
    self.class._css_proc_rules.filter_map do |proc|
      instance_exec(&proc)
    end.join(" ")
  end
end
