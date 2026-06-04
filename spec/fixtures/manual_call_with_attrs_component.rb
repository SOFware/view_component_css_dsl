# frozen_string_literal: true

# Fixture: a component with a hand-written #call that references html_attrs.
class ManualCallWithAttrsComponent < TestComponent
  css "rounded p-4"

  def call
    tag.div(**html_attrs) { "content" }
  end
end
