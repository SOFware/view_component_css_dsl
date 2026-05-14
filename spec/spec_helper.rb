# frozen_string_literal: true

require "view_component"
require "view_component_css_dsl"

# A test base class used throughout the specs. In a real consumer
# application this would be your `ApplicationComponent < ViewComponent::Base`.
class TestComponent < ViewComponent::Base
  include ViewComponentCssDsl
end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
end
