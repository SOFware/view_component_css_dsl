# frozen_string_literal: true

require "view_component_css_dsl"

# Static checks over a component's DSL declarations. Catches the mistakes the DSL
# itself can't surface until render time (or surfaces silently): hallucinated
# Tailwind classes, self-conflicting declarations, rules referencing undefined
# methods, axes no initializer sets, and templates that forget the html_attrs
# splat. Designed to be fast enough to run on every edit.
#
#   verifier = ViewComponentCssDsl::Verifier.new(known_classes: oracle)
#   findings = verifier.verify(ButtonComponent)
#
# Verify every class in the component hierarchy: declaration-shape checks
# (class validity, self-conflicts) only inspect declarations the class itself
# added, so a parent's declarations are checked on the parent, not re-reported
# on every child.
class ViewComponentCssDsl::Verifier
  Finding = Struct.new(
    :component, :check, :severity, :message, keyword_init: true
  ) do
    def to_s
      "#{component.name || component.inspect} [#{check}] #{severity}: #{message}"
    end

    def error? = severity == :error
  end

  TEMPLATE_EXTENSIONS = %w[erb haml slim].freeze

  # Safety cap for pathological axis cartesian products.
  VARIANT_MATRIX_CAP = 256

  # Source file of the DSL itself, for classifying smoke-test backtraces.
  DSL_SOURCE_FILE = File.expand_path("../view_component_css_dsl.rb", __dir__)

  # known_classes: anything responding to include?(String) — a Set, or a
  # CompiledCssOracle built from your app's compiled Tailwind output. When nil,
  # the class-validity check is skipped.
  def initialize(known_classes: nil)
    @known_classes = known_classes
  end

  def verify(component)
    check_class_validity(component) +
      check_self_conflicts(component) +
      check_method_rules(component) +
      check_axes_settable(component) +
      check_variant_matrix(component) +
      check_template_splat(component)
  end

  private

  # Every statically-declared class must exist in the known-classes oracle.
  # Hallucinated or typo'd classes produce no CSS at all under Tailwind's JIT —
  # no error, no warning — so this is the check that catches them.
  def check_class_validity(component)
    return [] unless @known_classes

    own_declared_styles(component).flat_map do |label, styles|
      styles.split.reject { |cls| @known_classes.include?(cls) }.map do |cls|
        finding(component, :class_validity, :error,
          "#{label}: unknown class \"#{cls}\" (not in the compiled Tailwind output)")
      end
    end
  end

  # A single declaration whose classes conflict with each other (e.g. "block flex")
  # is almost always a mistake — smart_merge silently keeps only the last.
  def check_self_conflicts(component)
    own_declared_styles(component).flat_map do |label, styles|
      tokens = styles.split
      survivors = component.smart_merge(styles).split
      results = []

      duplicates = tokens.tally.select { |_cls, count| count > 1 }.keys
      if duplicates.any?
        results << finding(component, :self_conflicts, :error,
          "#{label}: duplicate class(es) #{quote_list(duplicates)}")
      end

      dropped = tokens.uniq - survivors
      if dropped.any?
        results << finding(component, :self_conflicts, :error,
          "#{label}: #{quote_list(dropped)} conflict with later classes in the " \
          "same declaration and would be silently dropped")
      end

      results
    end
  end

  # Symbols in css/data/aria/attribute rules are method references; each must
  # resolve on the component. The DSL only raises for these at render time.
  def check_method_rules(component)
    method_references(component).filter_map do |label, method_name|
      next if resolves?(component, method_name)

      finding(component, :method_rules, :error,
        "#{label} references undefined method `#{method_name}`")
    end
  end

  # Each axis with css rules must be settable: an initialize param of the same
  # name, or an @ivar assignment somewhere in the component's source. An axis
  # nothing sets means its rules can never fire.
  def check_axes_settable(component)
    component._css_defined_axes.keys.filter_map do |axis|
      next if initialize_param?(component, axis)
      next if ivar_assigned_in_source?(component, axis)

      finding(component, :axes_settable, :error,
        "axis :#{axis} has css rules, but initialize has no #{axis} param and " \
        "no @#{axis} assignment was found")
    end
  end

  # Smoke test: build the css string for every combination of axis values
  # (including unset) on a bare instance. Exercises validate_axes!, the merge
  # caches, and method/proc rules end-to-end without rendering.
  def check_variant_matrix(component)
    combos = axis_combinations(component)
    findings = []

    if combos.size > VARIANT_MATRIX_CAP
      findings << finding(component, :variant_matrix, :warning,
        "#{combos.size} axis combinations; only the first #{VARIANT_MATRIX_CAP} " \
        "were smoke-tested")
      combos = combos.first(VARIANT_MATRIX_CAP)
    end

    combos.each do |combo|
      error = smoke_css(component, combo)
      next unless error

      findings << finding(component, :variant_matrix, smoke_severity(error),
        "#{combo_label(combo)}: #{error.class}: #{error.message}")
    end

    findings
  end

  # Every template must reference html_attrs — that splat is what carries the
  # DSL's classes and attributes to the DOM. Covers sidecar files, inline
  # templates (erb_template "..."), and hand-written #call methods.
  def check_template_splat(component)
    sources = template_sources(component)
    if sources.empty?
      return [finding(component, :template_splat, :warning,
        "no template found (no sidecar file, inline template, or #call method)")]
    end

    sources.filter_map do |label, source|
      next if source.match?(/\bhtml_attrs\b/)

      finding(component, :template_splat, :error,
        "#{label} does not reference html_attrs; DSL classes and attributes " \
        "will not reach the DOM")
    end
  end

  ##################################################################################
  # Declaration collection
  ##################################################################################

  # [label, styles] pairs for declarations this class itself added. Inherited
  # declarations are checked on the ancestor that declared them.
  def own_declared_styles(component)
    parent = component.superclass
    base = own_rules(component, parent, :_css_base_declarations)
      .map { |styles| ["css \"#{styles}\"", styles] }
    axis = own_rules(component, parent, :_css_axis_rules)
      .map { |rule| [axis_label(rule[:axes]), rule[:styles]] }
    methods = own_rules(component, parent, :_css_method_rules)
      .map { |rule| ["css :#{rule[:method]}", rule[:styles]] }
    base + axis + methods
  end

  def own_rules(component, parent, attr)
    inherited = parent.respond_to?(attr) ? parent.public_send(attr) : []
    component.public_send(attr) - inherited
  end

  def axis_label(axes) = "css #{axes.map { |k, v| "#{k}: :#{v}" }.join(", ")}"

  # [label, method_name] for every Symbol the rules will send to the instance.
  # Inherited rules are included: they run on this class, so they must resolve
  # on this class (a child may legitimately define the method a parent's rule
  # references).
  def method_references(component)
    refs = component._css_method_rules
      .map { |rule| ["css :#{rule[:method]}", rule[:method]] }

    {data: :_data_rules, aria: :_aria_rules, attribute: :_attribute_rules}
      .each do |namespace, attr|
        component.public_send(attr).each do |rule|
          if rule[:predicate].is_a?(Symbol)
            refs << ["#{namespace} :#{rule[:predicate]} predicate", rule[:predicate]]
          end
          rule[:attrs].each do |key, value|
            refs << ["#{namespace} #{key}: :#{value}", value] if value.is_a?(Symbol)
          end
        end
      end

    refs
  end

  def resolves?(component, method_name)
    component.method_defined?(method_name) ||
      component.private_method_defined?(method_name)
  end

  ##################################################################################
  # Axis settability
  ##################################################################################

  def initialize_param?(component, axis)
    params = component.instance_method(:initialize).parameters
    params.any? { |_type, name| name == axis }
  end

  def ivar_assigned_in_source?(component, axis)
    source_paths(component).any? do |path|
      File.read(path).match?(/@#{axis}\b\s*(\|\|)?=[^=~]/)
    end
  end

  # Source files of the component and its DSL-including ancestors. Stops before
  # ViewComponent::Base — framework internals aren't where axes get assigned.
  def source_paths(component)
    component.ancestors
      .take_while { |mod| !view_component_base?(mod) }
      .filter_map { |mod| mod.identifier if mod.respond_to?(:identifier) }
      .uniq
      .select { |path| File.exist?(path) }
  end

  def view_component_base?(mod)
    defined?(ViewComponent::Base) && mod == ViewComponent::Base
  end

  ##################################################################################
  # Variant matrix
  ##################################################################################

  # Cartesian product over defined axes, each axis taking every declared value
  # plus nil (axis unset). [{}] when no axes — base/method/proc paths still get
  # one smoke run.
  def axis_combinations(component)
    component._css_defined_axes.reduce([{}]) do |combos, (axis, values)|
      combos.flat_map do |combo|
        (values.to_a + [nil]).map { |value| combo.merge(axis => value) }
      end
    end
  end

  def smoke_css(component, combo)
    instance = component.allocate
    instance.instance_variable_set(:@html_attrs, {})
    combo.each { |axis, value| instance.instance_variable_set(:"@#{axis}", value) }
    instance.css
    nil
  rescue => error
    error
  end

  # Errors raised inside the DSL are real failures. Errors raised in component
  # code usually mean a method/proc rule needs initialize state a bare instance
  # doesn't have — report those as warnings, not failures.
  def smoke_severity(error)
    first_frame = error.backtrace&.first.to_s
    first_frame.start_with?("#{DSL_SOURCE_FILE}:") ? :error : :warning
  end

  def combo_label(combo)
    return "with no axes set" if combo.compact.empty?

    "with #{combo.compact.map { |axis, value| "#{axis}: :#{value}" }.join(", ")}"
  end

  ##################################################################################
  # Templates
  ##################################################################################

  def template_sources(component)
    sources = []

    if component.respond_to?(:__vc_inline_template)
      inline = component.__vc_inline_template
      sources << ["inline template", inline.source] if inline
    end

    if component.respond_to?(:sidecar_files)
      component.sidecar_files(TEMPLATE_EXTENSIONS).each do |path|
        sources << [File.basename(path), File.read(path)]
      end
    end

    if sources.empty? && (call_path = manual_call_path(component))
      sources << ["#call (#{File.basename(call_path)})", File.read(call_path)]
    end

    sources
  end

  # Path of a hand-written #call, if the component (or a DSL ancestor) defines
  # one. ViewComponent compiles templates into #call too, but only at render
  # time — run the verifier in a fresh process and only manual ones exist.
  def manual_call_path(component)
    return nil unless component.method_defined?(:call)

    owner = component.instance_method(:call).owner
    return nil if !owner.is_a?(Class) || view_component_base?(owner)
    return nil unless owner.respond_to?(:_css_base)

    path = component.instance_method(:call).source_location&.first
    path if path && File.exist?(path)
  end

  def finding(component, check, severity, message)
    Finding.new(component:, check:, severity:, message:)
  end

  def quote_list(classes) = classes.map { |cls| "\"#{cls}\"" }.join(", ")
end

require_relative "verifier/compiled_css_oracle"
