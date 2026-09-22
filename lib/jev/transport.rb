# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"
require_relative "http_pool"

module Jev
  class Transport
    PATH = "v1/systemone"

    def initialize(configuration)
      @configuration = configuration
      @pool = HTTPPool.new
    end

    def call(payload)
      handle_response(post(payload))
    rescue Timeout::Error
      raise RequestError, "Jev request timed out"
    rescue SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError => e
      raise RequestError, redact("Jev request failed: #{e.message}")
    end

    private

    def close
      @pool.close
    end

    def post(payload)
      uri = endpoint
      request = build_request(uri, payload)
      @pool.with_connection(uri) do |http|
        apply_timeouts(http)
        http.start unless http.started?
        http.request(request)
      end
    end

    def apply_timeouts(http)
      timeout = @configuration.timeout
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.write_timeout = timeout if http.respond_to?(:write_timeout=)
    end

    def build_request(uri, payload)
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request["User-Agent"] = "jev-feels/#{VERSION}"
      request.body = JSON.generate(payload)
      request
    end

    def api_key
      key = @configuration.api_key
      raise ConfigurationError, "Jev API key is missing" if key.nil? || key.empty?

      key
    end

    def endpoint
      base = @configuration.base_url
      cached = @endpoint_cache
      return cached.last if cached && cached.first == base

      base = base.dup.freeze
      uri = URI.join(base.end_with?("/") ? base : "#{base}/", PATH)
      @endpoint_cache = [base, uri].freeze
      uri
    end

    def handle_response(response)
      code = response.code.to_i
      raw = response.body.to_s
      return parse_success(raw) if code == 200

      raise_http_error(code, raw)
    end

    def parse_success(raw)
      body = JSON.parse(raw)
      raise InvalidResponseError, "Jev response is not a JSON object" unless body.is_a?(Hash)

      body
    rescue JSON::ParserError
      raise InvalidResponseError, "Jev response is not valid JSON"
    end

    def raise_http_error(code, raw)
      raise AuthenticationError, "Jev authentication failed" if code == 401

      detail = error_detail(raw)
      case code
      when 429
        raise RateLimitError, join_detail("Jev rate limit exceeded", detail)
      else
        raise RequestError, join_detail("Jev request failed with HTTP #{code}", detail)
      end
    end

    def error_detail(raw)
      text = extract_error_message(raw)
      return if text.nil? || text.empty?

      redact(text)[0, 200]
    end

    def extract_error_message(raw)
      parsed = JSON.parse(raw)
      return raw.strip unless parsed.is_a?(Hash)

      message = parsed.values_at("error", "message", "detail").compact.first
      message = message["message"] if message.is_a?(Hash)
      message.to_s
    rescue JSON::ParserError
      raw.strip
    end

    def join_detail(prefix, detail)
      detail ? "#{prefix}: #{detail}" : prefix
    end

    def redact(text)
      key = @configuration.api_key
      return text.to_s if key.nil? || key.empty?

      text.to_s.gsub(key, "[FILTERED]")
    end
  end
end
