# frozen_string_literal: true

require "view_component_css_dsl/verifier"
require "tmpdir"

RSpec.describe ViewComponentCssDsl::Verifier do
  let(:verifier) { described_class.new }

  def findings_for(component, check)
    verifier.verify(component).select { |f| f.check == check }
  end

  describe "class validity" do
    let(:oracle) { Set["rounded", "p-4", "bg-blue-500", "opacity-50"] }
    let(:verifier) { described_class.new(known_classes: oracle) }

    it "flags classes missing from the oracle" do
      component = Class.new(TestComponent) { css "rounded p-4 bg-blurple" }

      findings = findings_for(component, :class_validity)
      expect(findings.size).to eq(1)
      expect(findings.first.severity).to eq(:error)
      expect(findings.first.message).to include("bg-blurple")
    end

    it "checks axis and method rule styles too" do
      component = Class.new(TestComponent) do
        css variant: :primary, style: "bg-blu-500"
        css :disabled?, style: "opcity-50"

        def disabled? = false
      end

      messages = findings_for(component, :class_validity).map(&:message)
      expect(messages).to include(a_string_including("bg-blu-500"))
      expect(messages).to include(a_string_including("opcity-50"))
    end

    it "passes when every class is known" do
      component = Class.new(TestComponent) { css "rounded bg-blue-500" }

      expect(findings_for(component, :class_validity)).to be_empty
    end

    it "is skipped when no oracle is provided" do
      component = Class.new(TestComponent) { css "totally-made-up" }

      no_oracle = described_class.new
      expect(no_oracle.verify(component).select { |f| f.check == :class_validity })
        .to be_empty
    end

    it "does not re-flag inherited declarations on the child" do
      parent = Class.new(TestComponent) { css "bg-blurple" }
      child = Class.new(parent) { css "rounded" }

      expect(findings_for(child, :class_validity)).to be_empty
    end
  end

  describe "self conflicts" do
    it "flags classes silently dropped within one declaration" do
      component = Class.new(TestComponent) { css "block flex rounded" }

      findings = findings_for(component, :self_conflicts)
      expect(findings.size).to eq(1)
      expect(findings.first.message).to include("\"block\"")
      expect(findings.first.message).to include("silently dropped")
    end

    it "flags duplicate classes" do
      component = Class.new(TestComponent) { css "p-4 rounded p-4" }

      findings = findings_for(component, :self_conflicts)
      expect(findings.size).to eq(1)
      expect(findings.first.message).to include("duplicate")
      expect(findings.first.message).to include("\"p-4\"")
    end

    it "flags conflicts inside an axis rule's styles" do
      component = Class.new(TestComponent) do
        css variant: :loud, style: "bg-red-500 bg-blue-500"
      end

      findings = findings_for(component, :self_conflicts)
      expect(findings.size).to eq(1)
      expect(findings.first.message).to include("variant: :loud")
    end

    it "passes clean declarations" do
      component = Class.new(TestComponent) { css "rounded border p-4 bg-white" }

      expect(findings_for(component, :self_conflicts)).to be_empty
    end

    it "does not flag a child overriding its parent's base" do
      parent = Class.new(TestComponent) { css "bg-white" }
      child = Class.new(parent) { css "bg-blue-500" }

      expect(findings_for(child, :self_conflicts)).to be_empty
    end
  end

  describe "cross declaration conflicts" do
    it "warns when a base class is dropped by an axis rule's class" do
      component = Class.new(TestComponent) do
        css "leading-snug rounded"
        css size: :sm, style: "text-sm"

        def initialize(size: :sm)
          @size = size
        end
      end

      findings = findings_for(component, :cross_declaration_conflicts)
      expect(findings.size).to eq(1)
      expect(findings.first.severity).to eq(:warning)
      expect(findings.first.message).to include("leading-snug")
      expect(findings.first.message).to include("text-sm")
    end

    it "does not flag a same-family override (intentional)" do
      component = Class.new(TestComponent) do
        css "p-2"
        css size: :lg, style: "p-8"

        def initialize(size: :lg)
          @size = size
        end
      end

      expect(findings_for(component, :cross_declaration_conflicts)).to be_empty
    end

    it "does not double-report a single-declaration conflict" do
      component = Class.new(TestComponent) { css "block flex" }

      expect(findings_for(component, :cross_declaration_conflicts)).to be_empty
      expect(findings_for(component, :self_conflicts)).not_to be_empty
    end

    it "passes a clean component" do
      component = Class.new(TestComponent) do
        css "rounded p-4"
        css size: :sm, style: "min-h-6"

        def initialize(size: :sm)
          @size = size
        end
      end

      expect(findings_for(component, :cross_declaration_conflicts)).to be_empty
    end
  end

  describe "method rules resolve" do
    it "flags a css rule referencing an undefined method" do
      component = Class.new(TestComponent) { css :missing?, style: "opacity-50" }

      findings = findings_for(component, :method_rules)
      expect(findings.size).to eq(1)
      expect(findings.first.message).to include("`missing?`")
    end

    it "accepts private methods" do
      component = Class.new(TestComponent) do
        css :quiet?, style: "opacity-50"

        private

        def quiet? = true
      end

      expect(findings_for(component, :method_rules)).to be_empty
    end

    it "flags Symbol predicates and values in data/aria/attribute rules" do
      component = Class.new(TestComponent) do
        data :missing_predicate?, foo: "bar"
        aria label: :missing_label_method
        attribute role: :missing_role_method
      end

      messages = findings_for(component, :method_rules).map(&:message)
      expect(messages).to include(a_string_including("missing_predicate?"))
      expect(messages).to include(a_string_including("missing_label_method"))
      expect(messages).to include(a_string_including("missing_role_method"))
    end

    it "checks inherited rules against the child" do
      parent = Class.new(TestComponent) { css :fancy?, style: "shadow-lg" }
      child = Class.new(parent) do
        def fancy? = true
      end

      expect(findings_for(parent, :method_rules).size).to eq(1)
      expect(findings_for(child, :method_rules)).to be_empty
    end
  end

  describe "axes settable" do
    it "passes when initialize accepts a matching kwarg" do
      component = Class.new(TestComponent) do
        css variant: :primary, style: "bg-blue-500"

        def initialize(variant: :primary)
          @variant = variant
        end
      end

      expect(findings_for(component, :axes_settable)).to be_empty
    end

    it "passes when the ivar is assigned in the component source" do
      component = Class.new(TestComponent) do
        css tone: :warm, style: "bg-orange-100"

        def initialize(mood)
          @tone = mood
        end
      end

      expect(findings_for(component, :axes_settable)).to be_empty
    end

    it "flags an axis nothing sets" do
      component = Class.new(TestComponent) do
        css zorp: :high, style: "bg-purple-500"
      end

      findings = findings_for(component, :axes_settable)
      expect(findings.size).to eq(1)
      expect(findings.first.message).to include(":zorp")
    end
  end

  describe "variant matrix smoke" do
    it "passes a healthy component across all axis combinations" do
      component = Class.new(TestComponent) do
        css "rounded p-4"
        css variant: :info, style: "bg-gray-100"
        css variant: :danger, style: "bg-red-100"
        css size: :sm, style: "text-sm"

        def initialize(variant: :info, size: :sm)
          @variant = variant
          @size = size
        end
      end

      expect(findings_for(component, :variant_matrix)).to be_empty
    end

    it "reports DSL-raised errors as errors" do
      component = Class.new(TestComponent) { css :vanished?, style: "opacity-50" }

      findings = findings_for(component, :variant_matrix)
      expect(findings).not_to be_empty
      expect(findings.first.severity).to eq(:error)
      expect(findings.first.message).to include("NoMethodError")
    end

    it "reports component-code errors on a bare instance as warnings" do
      component = Class.new(TestComponent) do
        css "rounded"
        css -> { "pl-#{@indent * 4}" }
      end

      findings = findings_for(component, :variant_matrix)
      expect(findings.size).to eq(1)
      expect(findings.first.severity).to eq(:warning)
    end
  end

  describe "template splat" do
    it "passes an inline template referencing html_attrs" do
      component = Class.new(TestComponent) do
        css "rounded"
        erb_template <<~ERB
          <%= tag.div **html_attrs do %>hi<% end %>
        ERB
      end

      expect(findings_for(component, :template_splat)).to be_empty
    end

    it "flags an inline template missing html_attrs" do
      component = Class.new(TestComponent) do
        css "rounded"
        erb_template "<div>hi</div>"
      end

      findings = findings_for(component, :template_splat)
      expect(findings.size).to eq(1)
      expect(findings.first.severity).to eq(:error)
      expect(findings.first.message).to include("inline template")
    end

    it "warns when no template can be found" do
      component = Class.new(TestComponent) { css "rounded" }

      findings = findings_for(component, :template_splat)
      expect(findings.size).to eq(1)
      expect(findings.first.severity).to eq(:warning)
    end

    it "checks sidecar template files" do
      Dir.mktmpdir do |dir|
        File.write("#{dir}/sidecar_spec_component.html.erb", "<div>no attrs</div>")
        stub_const("SidecarSpecComponent", Class.new(TestComponent))
        SidecarSpecComponent.identifier = "#{dir}/sidecar_spec_component.rb"

        findings = findings_for(SidecarSpecComponent, :template_splat)
        expect(findings.size).to eq(1)
        expect(findings.first.message).to include("sidecar_spec_component.html.erb")
      end
    end

    it "passes a sidecar template referencing html_attrs" do
      Dir.mktmpdir do |dir|
        File.write(
          "#{dir}/sidecar_ok_component.html.erb",
          "<%= tag.div **html_attrs do %>hi<% end %>"
        )
        stub_const("SidecarOkComponent", Class.new(TestComponent))
        SidecarOkComponent.identifier = "#{dir}/sidecar_ok_component.rb"

        expect(findings_for(SidecarOkComponent, :template_splat)).to be_empty
      end
    end

    context "with hand-written #call methods" do
      before do
        require_relative "fixtures/manual_call_with_attrs_component"
        require_relative "fixtures/manual_call_without_attrs_component"
      end

      it "passes a #call that references html_attrs" do
        findings = findings_for(ManualCallWithAttrsComponent, :template_splat)
        expect(findings).to be_empty
      end

      it "flags a #call that does not reference html_attrs" do
        findings = findings_for(ManualCallWithoutAttrsComponent, :template_splat)
        expect(findings.size).to eq(1)
        expect(findings.first.message).to include("#call")
      end
    end
  end

  describe ViewComponentCssDsl::Verifier::CompiledCssOracle do
    it "parses plain, modifier-prefixed, escaped, and hex-escaped class selectors" do
      css = <<~CSS
        .bg-blue-500{background-color:#3b82f6}
        .hover\\:bg-blue-500:hover{background-color:#3b82f6}
        .w-1\\/2{width:50%}
        .\\32 xl\\:grid{display:grid}
        .data-\\[open\\]\\:bg-gray-100[data-open]{background-color:#f3f4f6}
      CSS

      Dir.mktmpdir do |dir|
        path = "#{dir}/build.css"
        File.write(path, css)
        oracle = described_class.new(path)

        expect(oracle.include?("bg-blue-500")).to be(true)
        expect(oracle.include?("hover:bg-blue-500")).to be(true)
        expect(oracle.include?("w-1/2")).to be(true)
        expect(oracle.include?("2xl:grid")).to be(true)
        expect(oracle.include?("data-[open]:bg-gray-100")).to be(true)
        expect(oracle.include?("bg-blurple")).to be(false)
      end
    end
  end
end
