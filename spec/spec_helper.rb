# frozen_string_literal: true

require "English"
require "feels"
require "json"
require "webmock/rspec"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |path| require path }

WebMock.disable_net_connect!

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.order = :random
  Kernel.srand config.seed

  config.before do
    Jev.reset_configuration!
    Jev.reset_definitions!
  end

  config.around(:example, :live) do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!
  end
end
