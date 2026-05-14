# frozen_string_literal: true

RSpec.describe ViewComponentCssDsl do
  # Test component classes
  let(:base_component_class) do
    Class.new(TestComponent) do
      css "rounded border shadow p-4 bg-white"
    end
  end

  let(:component_with_variants_class) do
    Class.new(TestComponent) do
      css "inline-block rounded text-xs font-medium py-2 px-3"
      css variant: :info, style: "text-gray-600 bg-gray-100"
      css variant: :success, style: "text-success-dark bg-success-light"
      css variant: :danger, style: "text-danger-dark bg-danger-light"

      def initialize(variant: :info, **html_attrs)
        @variant = variant
        @html_attrs = html_attrs
      end
    end
  end

  describe ".css" do
    it "sets base classes" do
      result = base_component_class._css_base
      expect(result).to include("rounded")
      expect(result).to include("border")
      expect(result).to include("shadow")
      expect(result).to include("p-4")
      expect(result).to include("bg-white")
    end

    it "inherits and merges parent base classes via smart_merge" do
      # When a child calls css(), it merges parent_base with new classes
      parent_base = "rounded border shadow p-4 bg-white"
      child_additions = "hover:shadow-lg transition-all bg-blue-50"

      result = TestComponent.smart_merge(parent_base, child_additions)

      # Should keep non-conflicting classes from parent
      expect(result).to include("rounded")
      expect(result).to include("border")
      expect(result).to include("shadow")
      expect(result).to include("p-4")

      # Should add child's new classes
      expect(result).to include("hover:shadow-lg")
      expect(result).to include("transition-all")

      # bg-blue-50 should override bg-white (same category)
      expect(result).to include("bg-blue-50")
      expect(result).not_to include("bg-white")
    end
  end

  describe ".smart_merge" do
    it "combines non-conflicting classes" do
      result = TestComponent.smart_merge("rounded border", "shadow p-4")
      expect(result).to include("rounded")
      expect(result).to include("border")
      expect(result).to include("shadow")
      expect(result).to include("p-4")
    end

    it "later values override earlier for same category" do
      result = TestComponent.smart_merge("bg-white", "bg-blue-500")
      expect(result).to eq("bg-blue-500")
      expect(result).not_to include("bg-white")
    end

    it "handles complex merge scenarios" do
      result = TestComponent.smart_merge(
        "rounded p-4 text-gray-500 bg-white",
        "text-success bg-success-light",
        "p-8 bg-red-500"
      )
      expect(result).to include("rounded")
      expect(result).to include("p-8")
      expect(result).not_to include("p-4")
      expect(result).to include("text-success")
      expect(result).not_to include("text-gray-500")
      expect(result).to include("bg-red-500")
      expect(result).not_to include("bg-white")
      expect(result).not_to include("bg-success-light")
    end

    context "padding axis overlap" do
      it "same side overrides same side (pl-5 overrides pl-2)" do
        result = TestComponent.smart_merge("pl-2", "pl-5")
        expect(result).to include("pl-5")
        expect(result).not_to include("pl-2")
      end

      it "specific side keeps broader axis (px-2 pl-5 keeps both)" do
        result = TestComponent.smart_merge("px-2", "pl-5")
        expect(result).to include("pl-5")
        expect(result).to include("px-2")
      end

      it "x-axis overrides left side (px-5 overrides pl-2)" do
        result = TestComponent.smart_merge("pl-2", "px-5")
        expect(result).to include("px-5")
        expect(result).not_to include("pl-2")
      end

      it "x-axis overrides right side (px-5 overrides pr-2)" do
        result = TestComponent.smart_merge("pr-2", "px-5")
        expect(result).to include("px-5")
        expect(result).not_to include("pr-2")
      end

      it "all-padding overrides left side (p-5 overrides pl-2)" do
        result = TestComponent.smart_merge("pl-2", "p-5")
        expect(result).to include("p-5")
        expect(result).not_to include("pl-2")
      end

      it "all-padding overrides y-axis (p-5 overrides py-2)" do
        result = TestComponent.smart_merge("py-2", "p-5")
        expect(result).to include("p-5")
        expect(result).not_to include("py-2")
      end

      it "all-padding overrides all specific paddings" do
        result = TestComponent.smart_merge("pt-1 pr-2 pb-3 pl-4 px-5 py-6", "p-8")
        expect(result).to eq("p-8")
      end

      it "left side does NOT override right side (pl-5 keeps pr-2)" do
        result = TestComponent.smart_merge("pr-2", "pl-5")
        expect(result).to include("pl-5")
        expect(result).to include("pr-2")
      end

      it "left side does NOT override y-axis (pl-5 keeps py-2)" do
        result = TestComponent.smart_merge("py-2", "pl-5")
        expect(result).to include("pl-5")
        expect(result).to include("py-2")
      end

      it "x-axis does NOT override y-axis (px-5 keeps pt-2)" do
        result = TestComponent.smart_merge("pt-2", "px-5")
        expect(result).to include("px-5")
        expect(result).to include("pt-2")
      end

      it "keeps different padding axes independent (px-4 and py-2)" do
        result = TestComponent.smart_merge("px-4", "py-2")
        expect(result).to include("px-4")
        expect(result).to include("py-2")
      end

      it "keeps different padding sides independent (pl-2 and pr-5)" do
        result = TestComponent.smart_merge("pl-2", "pr-5")
        expect(result).to include("pl-2")
        expect(result).to include("pr-5")
      end

      it "keeps base padding when specific side is overridden (p-4 pb-6)" do
        result = TestComponent.smart_merge("p-4", "pb-6")
        expect(result).to include("p-4")
        expect(result).to include("pb-6")
      end

      it "keeps base padding when y-axis is overridden (p-4 py-6)" do
        result = TestComponent.smart_merge("p-4", "py-6")
        expect(result).to include("p-4")
        expect(result).to include("py-6")
      end
    end

    context "margin axis overlap" do
      it "same side overrides same side (ml-5 overrides ml-2)" do
        result = TestComponent.smart_merge("ml-2", "ml-5")
        expect(result).to include("ml-5")
        expect(result).not_to include("ml-2")
      end

      it "x-axis overrides left side (mx-5 overrides ml-2)" do
        result = TestComponent.smart_merge("ml-2", "mx-5")
        expect(result).to include("mx-5")
        expect(result).not_to include("ml-2")
      end

      it "all-margin overrides specific margins (m-5 overrides mx-2)" do
        result = TestComponent.smart_merge("mx-2", "m-5")
        expect(result).to include("m-5")
        expect(result).not_to include("mx-2")
      end

      it "keeps different margin axes independent (mx-4 and my-2)" do
        result = TestComponent.smart_merge("mx-4", "my-2")
        expect(result).to include("mx-4")
        expect(result).to include("my-2")
      end

      it "keeps base margin when specific side is overridden (m-4 mt-6)" do
        result = TestComponent.smart_merge("m-4", "mt-6")
        expect(result).to include("m-4")
        expect(result).to include("mt-6")
      end
    end

    context "padding does not affect margin" do
      it "padding does not override margin on same axis" do
        result = TestComponent.smart_merge("ml-2", "pl-5")
        expect(result).to include("pl-5")
        expect(result).to include("ml-2")
      end

      it "all-padding does not override all-margin" do
        result = TestComponent.smart_merge("m-2", "p-5")
        expect(result).to include("p-5")
        expect(result).to include("m-2")
      end
    end

    context "border axis overlap" do
      it "same side overrides same side (border-t-2 overrides border-t)" do
        result = TestComponent.smart_merge("border-t", "border-t-2")
        expect(result).to eq("border-t-2")
      end

      it "x-axis overrides left side (border-x overrides border-l)" do
        result = TestComponent.smart_merge("border-l", "border-x")
        expect(result).to include("border-x")
        expect(result).not_to include("border-l")
      end

      it "all-border overrides specific borders (border-2 overrides border-t)" do
        result = TestComponent.smart_merge("border-t", "border-2")
        expect(result).to include("border-2")
        expect(result).not_to include("border-t")
      end

      it "all-border overrides all axis borders" do
        result = TestComponent.smart_merge("border-t border-r border-b border-l border-x border-y", "border")
        expect(result).to eq("border")
      end

      it "keeps different border axes independent (border-x and border-y)" do
        result = TestComponent.smart_merge("border-x", "border-y")
        expect(result).to include("border-x")
        expect(result).to include("border-y")
      end

      it "border does not affect padding or margin" do
        result = TestComponent.smart_merge("pt-2 mt-2", "border-t")
        expect(result).to include("border-t")
        expect(result).to include("pt-2")
        expect(result).to include("mt-2")
      end

      it "border-width does not conflict with border-color (border-2 border-red-600)" do
        result = TestComponent.smart_merge("border-2 border-red-600")
        expect(result).to include("border-2")
        expect(result).to include("border-red-600")
      end

      it "border-1 and border-gray-200 both remain" do
        result = TestComponent.smart_merge("border-1 border-gray-200")
        expect(result).to include("border-1")
        expect(result).to include("border-gray-200")
      end
    end

    context "modifier prefixes" do
      it "keeps base and modified classes separate (block vs first:hidden)" do
        result = TestComponent.smart_merge("block", "first:hidden")
        expect(result).to include("block")
        expect(result).to include("first:hidden")
      end

      it "keeps different responsive variants (p-4 vs md:p-8)" do
        result = TestComponent.smart_merge("p-4", "md:p-8")
        expect(result).to include("p-4")
        expect(result).to include("md:p-8")
      end

      it "overwrites same modifier same category (hover:bg-blue-500 vs hover:bg-red-500)" do
        result = TestComponent.smart_merge("hover:bg-blue-500", "hover:bg-red-500")
        expect(result).to include("hover:bg-red-500")
        expect(result).not_to include("hover:bg-blue-500")
      end

      it "handles stacked modifiers (md:hover:bg-blue-500)" do
        result = TestComponent.smart_merge("bg-white", "md:hover:bg-blue-500")
        expect(result).to include("bg-white")
        expect(result).to include("md:hover:bg-blue-500")
      end

      it "handles group modifiers" do
        result = TestComponent.smart_merge("bg-white", "group-hover:bg-blue-500")
        expect(result).to include("bg-white")
        expect(result).to include("group-hover:bg-blue-500")
      end

      it "handles named group modifiers" do
        result = TestComponent.smart_merge("hidden", "group-hover/nav:block")
        expect(result).to include("hidden")
        expect(result).to include("group-hover/nav:block")
      end

      it "handles peer modifiers" do
        result = TestComponent.smart_merge("hidden", "peer-checked:block")
        expect(result).to include("hidden")
        expect(result).to include("peer-checked:block")
      end

      it "handles arbitrary data attributes" do
        result = TestComponent.smart_merge("bg-white", "data-[state=open]:bg-gray-100")
        expect(result).to include("bg-white")
        expect(result).to include("data-[state=open]:bg-gray-100")
      end

      it "handles spacing with modifiers (p-4 vs hover:p-8)" do
        result = TestComponent.smart_merge("p-4", "hover:p-8")
        expect(result).to include("p-4")
        expect(result).to include("hover:p-8")
      end

      it "overwrites same modifier same spacing axis (hover:p-4 vs hover:p-8)" do
        result = TestComponent.smart_merge("hover:p-4", "hover:p-8")
        expect(result).to include("hover:p-8")
        expect(result).not_to include("hover:p-4")
      end
    end
  end

  describe "#css" do
    context "without variants" do
      it "returns base classes" do
        component = base_component_class.new
        result = component.css
        expect(result).to include("rounded")
        expect(result).to include("border")
        expect(result).to include("shadow")
        expect(result).to include("p-4")
        expect(result).to include("bg-white")
      end

      it "merges custom_css from html_attrs" do
        component = base_component_class.new
        component.instance_variable_set(:@html_attrs, {class: "m-2"})
        expect(component.css).to include("rounded")
        expect(component.css).to include("m-2")
      end

      it "custom_css overrides base for same category" do
        component = base_component_class.new
        component.instance_variable_set(:@html_attrs, {class: "bg-red-500"})
        expect(component.css).to include("bg-red-500")
        expect(component.css).not_to include("bg-white")
      end
    end

    context "with variants" do
      it "applies variant classes" do
        component = component_with_variants_class.new(variant: :success)
        expect(component.css).to include("text-success-dark")
        expect(component.css).to include("bg-success-light")
      end

      it "custom_css overrides variant" do
        component = component_with_variants_class.new(variant: :success)
        component.instance_variable_set(:@html_attrs, {class: "bg-red-500"})
        expect(component.css).to include("bg-red-500")
        expect(component.css).not_to include("bg-success-light")
      end

      it "raises ArgumentError for undefined variants" do
        # With validation, undefined variants raise an error
        expect {
          component_with_variants_class.new(variant: :unknown).css
        }.to raise_error(ArgumentError, /Unknown variant :unknown/)
      end
    end
  end

  describe "#custom_css" do
    it "returns empty string when no html_attrs" do
      component = base_component_class.new
      expect(component.custom_css).to eq("")
    end

    it "returns class from html_attrs" do
      component = base_component_class.new
      component.instance_variable_set(:@html_attrs, {class: "custom-class"})
      expect(component.custom_css).to eq("custom-class")
    end
  end

  describe "multi-axis variants" do
    let(:multi_axis_component_class) do
      Class.new(TestComponent) do
        css "base-class"
        css variant: :primary, style: "bg-blue-500 text-white"
        css variant: :danger, style: "bg-red-500 text-white"
        css size: :sm, style: "text-sm px-2 py-1"
        css size: :default, style: "text-base px-4 py-2"
        css size: :lg, style: "text-lg px-6 py-3"

        def initialize(variant: :primary, size: :default, **html_attrs)
          @variant = variant
          @size = size
          @html_attrs = html_attrs
        end
      end
    end

    it "applies base styles" do
      component = multi_axis_component_class.new
      expect(component.css).to include("base-class")
    end

    it "applies single axis match (variant)" do
      component = multi_axis_component_class.new(variant: :danger)
      expect(component.css).to include("bg-red-500")
      expect(component.css).not_to include("bg-blue-500")
    end

    it "applies single axis match (size)" do
      component = multi_axis_component_class.new(size: :lg)
      expect(component.css).to include("text-lg")
      expect(component.css).to include("px-6")
    end

    it "applies multiple axes independently" do
      component = multi_axis_component_class.new(variant: :danger, size: :sm)
      expect(component.css).to include("bg-red-500")
      expect(component.css).to include("text-sm")
      expect(component.css).to include("px-2")
    end

    it "does not apply non-matching axis rules" do
      component = multi_axis_component_class.new(variant: :primary, size: :default)
      expect(component.css).not_to include("bg-red-500")
      expect(component.css).not_to include("text-lg")
    end
  end

  describe "multi-axis combos" do
    let(:combo_component_class) do
      Class.new(TestComponent) do
        css "base"
        css variant: :primary, style: "primary-base"
        css variant: :secondary, style: "secondary-base"
        css size: :sm, style: "small-base"
        css size: :lg, style: "large-base"
        css variant: :primary, size: :lg, style: "primary-large-combo"

        def initialize(variant: :primary, size: :sm)
          @variant = variant
          @size = size
        end
      end
    end

    it "applies combo only when all axes match" do
      component = combo_component_class.new(variant: :primary, size: :lg)
      expect(component.css).to include("primary-large-combo")
    end

    it "applies individual axis rules even when combo matches" do
      component = combo_component_class.new(variant: :primary, size: :lg)
      expect(component.css).to include("primary-base")
      expect(component.css).to include("large-base")
    end

    it "does not apply combo when only some axes match" do
      component = combo_component_class.new(variant: :primary, size: :sm)
      expect(component.css).to include("primary-base")
      expect(component.css).not_to include("primary-large-combo")
    end
  end

  describe "method-based conditionals" do
    let(:method_conditional_component_class) do
      Class.new(TestComponent) do
        css "base"
        css :disabled?, style: "opacity-50 cursor-not-allowed"
        css :active?, style: "ring-2 ring-blue-500"

        def initialize(disabled: false, active: false)
          @disabled = disabled
          @active = active
        end

        def disabled?
          @disabled
        end

        def active?
          @active
        end
      end
    end

    it "applies CSS when method returns truthy" do
      component = method_conditional_component_class.new(disabled: true)
      expect(component.css).to include("opacity-50")
      expect(component.css).to include("cursor-not-allowed")
    end

    it "does not apply CSS when method returns falsy" do
      component = method_conditional_component_class.new(disabled: false)
      expect(component.css).not_to include("opacity-50")
    end

    it "applies multiple method conditionals independently" do
      component = method_conditional_component_class.new(disabled: true, active: true)
      expect(component.css).to include("opacity-50")
      expect(component.css).to include("ring-2")
    end

    it "applies only matching method conditionals" do
      component = method_conditional_component_class.new(disabled: true, active: false)
      expect(component.css).to include("opacity-50")
      expect(component.css).not_to include("ring-2")
    end
  end

  describe "numeric axis values (levels)" do
    let(:level_component_class) do
      Class.new(TestComponent) do
        css "base"
        css level: 0, style: "pl-2"
        css level: 1, style: "pl-6"
        css level: 2, style: "pl-10"
        css level: 3, style: "pl-14"

        def initialize(level: 0)
          @level = level
        end
      end
    end

    it "applies correct level styles" do
      expect(level_component_class.new(level: 0).css).to include("pl-2")
      expect(level_component_class.new(level: 1).css).to include("pl-6")
      expect(level_component_class.new(level: 2).css).to include("pl-10")
      expect(level_component_class.new(level: 3).css).to include("pl-14")
    end

    it "does not apply other level styles" do
      component = level_component_class.new(level: 1)
      expect(component.css).to include("pl-6")
      expect(component.css).not_to include("pl-2")
      expect(component.css).not_to include("pl-10")
    end
  end

  describe "combined axis and method conditionals" do
    let(:combined_component_class) do
      Class.new(TestComponent) do
        css "base"
        css variant: :primary, style: "bg-blue-500"
        css variant: :danger, style: "bg-red-500"
        css :disabled?, style: "opacity-50"

        def initialize(variant: :primary, disabled: false)
          @variant = variant
          @disabled = disabled
        end

        def disabled?
          @disabled
        end
      end
    end

    it "applies both axis rules and method conditionals" do
      component = combined_component_class.new(variant: :danger, disabled: true)
      expect(component.css).to include("bg-red-500")
      expect(component.css).to include("opacity-50")
    end

    it "applies axis rules without method conditionals" do
      component = combined_component_class.new(variant: :danger, disabled: false)
      expect(component.css).to include("bg-red-500")
      expect(component.css).not_to include("opacity-50")
    end
  end

  describe "proc-based dynamic CSS" do
    let(:proc_component_class) do
      Class.new(TestComponent) do
        css "base"
        css -> { "pl-#{@indent * 4}" }

        def initialize(indent: 1)
          @indent = indent
        end
      end
    end

    it "evaluates proc at render time" do
      component = proc_component_class.new(indent: 2)
      expect(component.css).to include("pl-8")
    end

    it "produces different results for different instances" do
      component1 = proc_component_class.new(indent: 1)
      component2 = proc_component_class.new(indent: 3)

      expect(component1.css).to include("pl-4")
      expect(component2.css).to include("pl-12")
    end

    context "proc accessing instance methods" do
      let(:method_access_component_class) do
        Class.new(TestComponent) do
          css "base"
          css -> { icon_class }

          def initialize(icon: "star")
            @icon = icon
          end

          def icon_class
            "fa-#{@icon}"
          end
        end
      end

      it "can call instance methods from proc" do
        component = method_access_component_class.new(icon: "heart")
        expect(component.css).to include("fa-heart")
      end
    end

    context "proc returning nil" do
      let(:nil_proc_component_class) do
        Class.new(TestComponent) do
          css "base"
          css -> { @optional_class }

          def initialize(optional_class: nil)
            @optional_class = optional_class
          end
        end
      end

      it "handles nil return value gracefully" do
        component = nil_proc_component_class.new(optional_class: nil)
        expect(component.css).to include("base")
        expect(component.css.split.size).to eq(1)
      end

      it "includes value when not nil" do
        component = nil_proc_component_class.new(optional_class: "extra-class")
        expect(component.css).to include("base")
        expect(component.css).to include("extra-class")
      end
    end

    context "multiple procs" do
      let(:multi_proc_component_class) do
        Class.new(TestComponent) do
          css "base"
          css -> { "width-#{@width}" }
          css -> { "height-#{@height}" }

          def initialize(width: 100, height: 50)
            @width = width
            @height = height
          end
        end
      end

      it "evaluates all procs and merges results" do
        component = multi_proc_component_class.new(width: 200, height: 100)
        expect(component.css).to include("width-200")
        expect(component.css).to include("height-100")
      end
    end

    context "proc with smart_merge" do
      let(:merge_proc_component_class) do
        Class.new(TestComponent) do
          css "p-4 bg-white"
          css -> { @override_padding ? "p-8" : nil }

          def initialize(override_padding: false, **html_attrs)
            @override_padding = override_padding
            @html_attrs = html_attrs
          end
        end
      end

      it "proc result participates in smart_merge" do
        component = merge_proc_component_class.new(override_padding: true)
        expect(component.css).to include("p-8")
        expect(component.css).not_to include("p-4")
      end

      it "base remains when proc returns nil" do
        component = merge_proc_component_class.new(override_padding: false)
        expect(component.css).to include("p-4")
      end

      it "custom_css can still override proc result" do
        component = merge_proc_component_class.new(override_padding: true)
        component.instance_variable_set(:@html_attrs, {class: "p-12"})
        expect(component.css).to include("p-12")
        expect(component.css).not_to include("p-8")
      end
    end
  end

  describe ".new HTML attr extraction" do
    context "with component that has no keyrest" do
      let(:component_class) do
        Class.new(TestComponent) do
          def initialize(text:)
            @text = text
          end

          attr_reader :text
        end
      end

      it "extracts HTML attrs before initialize" do
        component = component_class.new(text: "Hello", class: "custom", id: "my-id")

        expect(component.instance_variable_get(:@html_attrs)).to include(
          class: "custom",
          id: "my-id"
        )
        expect(component.text).to eq("Hello")
      end

      it "extracts data attrs" do
        component = component_class.new(text: "Hello", data: {controller: "foo"})

        expect(component.instance_variable_get(:@html_attrs)).to include(
          data: {controller: "foo"}
        )
      end

      it "extracts aria attrs" do
        component = component_class.new(text: "Hello", aria: {label: "My label"})

        expect(component.instance_variable_get(:@html_attrs)).to include(
          aria: {label: "My label"}
        )
      end
    end

    context "with component that uses **html_attrs keyrest" do
      let(:component_class) do
        Class.new(TestComponent) do
          def initialize(text:, **html_attrs)
            @text = text
            @html_attrs = html_attrs
          end

          attr_reader :text
        end
      end

      it "extracts HTML attrs" do
        component = component_class.new(text: "Hello", class: "custom", id: "my-id")

        expect(component.instance_variable_get(:@html_attrs)).to include(
          class: "custom",
          id: "my-id"
        )
      end
    end

    context "with component that uses **options (not **html_attrs)" do
      let(:component_class) do
        Class.new(TestComponent) do
          def initialize(text:, **options)
            @text = text
            @options = options
          end

          attr_reader :text, :options
        end
      end

      it "does NOT extract HTML attrs - passes all kwargs to initialize" do
        component = component_class.new(
          text: "Hello",
          class: "custom",
          id: "my-id",
          custom_option: "foo"
        )

        # HTML attrs should NOT be extracted
        expect(component.instance_variable_get(:@html_attrs)).to eq({})

        # All kwargs should be passed through to **options
        expect(component.options).to include(
          class: "custom",
          id: "my-id",
          custom_option: "foo"
        )
      end
    end

    context "with component that declares an HTML attr as explicit kwarg" do
      let(:component_class) do
        Class.new(TestComponent) do
          def initialize(id:, text:)
            @id = id
            @text = text
          end

          attr_reader :id, :text
        end
      end

      it "does NOT extract declared kwargs even if they're HTML attr names" do
        component = component_class.new(id: "explicit-id", text: "Hello", class: "custom")

        # id should NOT be extracted (it's a declared kwarg)
        expect(component.instance_variable_get(:@html_attrs)).not_to have_key(:id)
        expect(component.instance_variable_get(:@html_attrs)).to include(class: "custom")

        # id should be passed to initialize normally
        expect(component.id).to eq("explicit-id")
      end
    end
  end

  describe "HTML_ATTR_KEYS constant" do
    it "includes common HTML attributes" do
      expect(ViewComponentCssDsl::HTML_ATTR_KEYS).to include(:class, :id, :style, :title)
    end

    it "includes link/navigation attributes" do
      expect(ViewComponentCssDsl::HTML_ATTR_KEYS).to include(:href, :target, :rel)
    end

    it "includes form-related attributes" do
      expect(ViewComponentCssDsl::HTML_ATTR_KEYS).to include(
        :disabled, :readonly, :required, :value, :type
      )
    end

    it "includes accessibility attributes" do
      expect(ViewComponentCssDsl::HTML_ATTR_KEYS).to include(:aria, :role, :tabindex)
    end
  end

  describe "#html_attrs with unified CSS" do
    let(:unified_component_class) do
      Class.new(TestComponent) do
        css "rounded p-4 bg-white"

        def initialize(**html_attrs)
          @html_attrs = html_attrs
        end
      end
    end

    it "returns empty hash when no html_attrs set" do
      component = unified_component_class.allocate
      # Don't set @html_attrs at all
      expect(component.html_attrs).to eq({})
    end

    it "includes merged CSS in :class key" do
      component = unified_component_class.new(data: {foo: "bar"})
      result = component.html_attrs
      expect(result[:class]).to include("rounded")
      expect(result[:class]).to include("p-4")
      expect(result[:class]).to include("bg-white")
      expect(result[:data]).to eq({foo: "bar"})
    end

    it "smart-merges caller's class with component CSS" do
      component = unified_component_class.new(class: "bg-blue-500", target: "_blank")
      result = component.html_attrs
      # Caller's bg-blue-500 should override component's bg-white
      expect(result[:class]).to include("bg-blue-500")
      expect(result[:class]).not_to include("bg-white")
      # But keeps other classes
      expect(result[:class]).to include("rounded")
      expect(result[:class]).to include("p-4")
      expect(result[:target]).to eq("_blank")
    end

    it "excludes :class when css returns empty string" do
      component = Class.new(TestComponent) do
        # No css defined
        def initialize(**html_attrs)
          @html_attrs = html_attrs
        end
      end.new(data: {foo: "bar"})

      result = component.html_attrs
      expect(result).not_to have_key(:class)
      expect(result[:data]).to eq({foo: "bar"})
    end

    context "with method conditionals that read @html_attrs" do
      let(:method_conditional_class) do
        Class.new(TestComponent) do
          css "base-class"
          css :disabled?, style: "opacity-50"

          def initialize(**html_attrs)
            @html_attrs = html_attrs
          end

          def disabled?
            # IMPORTANT: Must use @html_attrs, not html_attrs, to avoid recursion
            @html_attrs[:disabled] == true
          end
        end
      end

      it "works without infinite recursion" do
        component = method_conditional_class.new(disabled: true)
        result = component.html_attrs
        expect(result[:class]).to include("base-class")
        expect(result[:class]).to include("opacity-50")
      end
    end
  end
end
