# frozen_string_literal: true

require_relative "lib/view_component_css_dsl/version"

Gem::Specification.new do |spec|
  spec.name = "view_component_css_dsl"
  spec.version = ViewComponentCssDsl::VERSION
  spec.authors = ["Jeff Lange"]
  spec.email = ["jeff.lange@sofwarellc.com"]

  spec.summary = "Declarative CSS class DSL for ViewComponent + Tailwind"
  spec.description = <<~MSG
    A small concern you mix into your base ViewComponent class to declare
    base styles, variants, and conditional CSS classes declaratively.
    Smart-merges Tailwind utility classes (spacing, modifier prefixes,
    arbitrary values) so callers can safely override per-instance styles.
  MSG
  spec.homepage = "https://github.com/SOFware/view_component_css_dsl"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib}/**/*", "LICENSE.txt", "CHANGELOG.md", "README.md"]
  end
  spec.require_paths = ["lib"]

  ###################################################################################
  # Dependencies
  ###################################################################################

  spec.add_dependency "activesupport", ">= 7.0", "< 9"

  # https://github.com/gjtorikian/tailwind_merge
  spec.add_dependency "tailwind_merge", "~> 1.0"

  # https://github.com/ViewComponent/view_component
  # https://viewcomponent.org/
  spec.add_dependency "view_component", "~> 4.0"

  # Development dependencies
  spec.add_development_dependency "reissue", "~> 0.4"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "standard", "~> 1.0"
end
