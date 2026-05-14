# frozen_string_literal: true

require "set"
require "active_support/concern"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/except"
require "active_support/core_ext/hash/slice"

require_relative "view_component_css_dsl/version"

module ViewComponentCssDsl
  extend ActiveSupport::Concern

  # HTML attributes auto-extracted from kwargs at construction time. Anything in
  # this set is captured into @html_attrs instead of being passed to initialize,
  # so callers can pass `class:`, `data:`, `aria:`, etc. without the component
  # declaring them. To opt out, accept a kwarg with the same name in initialize
  # (e.g. `def initialize(class:)`) or use a keyrest name other than html_attrs.
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
    :readonly, :rel, :required, :role, :rowspan,
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

    # Override `new` to auto-extract HTML attributes from kwargs into @html_attrs,
    # so components don't need to declare **html_attrs in their initialize signature.
    # Anything in HTML_ATTR_KEYS that wasn't declared as a kwarg is captured.
    def new(*args, **kwargs, &block)
      info = _vc_css_dsl_initialize_info
      html_attrs = {}
      if info[:auto_extract]
        extractable = HTML_ATTR_KEYS.intersection(kwargs.keys) - info[:declared_kwargs]
        html_attrs = kwargs.extract!(*extractable)
      end

      instance = allocate
      instance.instance_variable_set(:@html_attrs, html_attrs)
      instance.send(:initialize, *args, **kwargs, &block)

      # Merge with any @html_attrs the component set inside initialize (older
      # components that still declare **html_attrs). Caller-provided values win.
      existing = instance.instance_variable_get(:@html_attrs) || {}
      instance.instance_variable_set(:@html_attrs, existing.merge(html_attrs))
      instance
    end

    # Analyzes the initialize signature once and caches the result. Auto-extraction
    # happens unless the component declares a non-html_attrs keyrest (like **options),
    # in which case the component wants to receive everything itself.
    def _vc_css_dsl_initialize_info
      @_vc_css_dsl_initialize_info ||= begin
        declared_kwargs = Set.new
        keyrest_name = nil
        instance_method(:initialize).parameters.each do |type, name|
          case type
          when :key, :keyreq then declared_kwargs << name
          when :keyrest then keyrest_name = name
          end
        end
        auto_extract = keyrest_name.nil? || keyrest_name == :html_attrs
        {declared_kwargs:, auto_extract:}
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
  # Includes the smart-merged `:class` and forwards every other caller-passed
  # HTML attribute (`data:`, `id:`, `aria:`, etc.) to the rendered element.
  def html_attrs
    return {} unless @html_attrs

    attrs = @html_attrs.except(:class)
    rendered_css = css
    attrs[:class] = rendered_css if rendered_css.present?
    attrs
  end

  private

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
