# frozen_string_literal: true

module Jev
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class UndefinedDefinition < Error; end
  class RequestError < Error; end
  class AuthenticationError < RequestError; end
  class RateLimitError < RequestError; end
  class InvalidResponseError < Error; end
  class ReplayError < Error; end
end
