# frozen_string_literal: true

# Fixture: a component with a hand-written #call that forgets the DSL's
# attributes entirely.
class ManualCallWithoutAttrsComponent < TestComponent
  css "rounded p-4"

  def call
    tag.div { "content" }
  end
end
