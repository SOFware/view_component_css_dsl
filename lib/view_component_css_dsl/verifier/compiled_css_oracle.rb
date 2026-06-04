# frozen_string_literal: true

require_relative "../verifier"

# The class-validity oracle for Verifier, built from a compiled Tailwind CSS file.
# Tailwind's JIT generates a rule for every valid class it finds in your content
# globs — so as long as your component .rb files are in those globs, the compiled
# output contains exactly the valid classes among those you declared. A declared
# class missing from the output is a typo, a hallucination, or a value your theme
# doesn't define.
#
#   oracle = ViewComponentCssDsl::Verifier::CompiledCssOracle.new(
#     "app/assets/builds/tailwind.css"
#   )
#   oracle.include?("bg-blue-500")  # => true
#   oracle.include?("bg-blurple")   # => false
#
# Caveat: the oracle is only as fresh as the build. Rebuild Tailwind before
# verifying, or a just-added valid class will be flagged as unknown.
class ViewComponentCssDsl::Verifier::CompiledCssOracle
  # Class selector: a dot, then word chars / hyphens / CSS escapes. Tailwind
  # escapes special chars with a backslash (`.hover\:bg-blue-500`) and leading
  # digits as hex (`.\32 xl\:grid`).
  CLASS_SELECTOR = /\.((?:\\[0-9a-fA-F]{1,6}\s?|\\.|[\w-])+)/

  def initialize(css_path)
    @classes = parse(File.read(css_path))
  end

  def include?(class_name) = @classes.include?(class_name)

  def size = @classes.size

  private

  def parse(css)
    css.scan(CLASS_SELECTOR).map { |(selector)| unescape(selector) }.to_set
  end

  # Hex escapes first (`\32 ` -> "2"), then simple escapes (`\:` -> ":").
  def unescape(selector)
    selector
      .gsub(/\\([0-9a-fA-F]{1,6})\s?/) { $1.hex.chr(Encoding::UTF_8) }
      .gsub(/\\(.)/, '\1')
  end
end
