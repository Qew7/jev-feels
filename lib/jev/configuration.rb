# frozen_string_literal: true

module Jev
  class Configuration
    DEFAULT_BASE_URL = "https://api.typesafe.ai"
    DEFAULT_TIMEOUT = 10.0
    DEFAULT_THRESHOLD = 0.5

    attr_accessor :api_key
    attr_reader :base_url, :timeout, :threshold, :transport

    def initialize
      @api_key = nil
      @base_url = DEFAULT_BASE_URL
      @timeout = DEFAULT_TIMEOUT
      @threshold = DEFAULT_THRESHOLD
      @transport = nil
      @transport_mutex = Mutex.new
    end

    def base_url=(value)
      raise ArgumentError, "base_url must be a non-empty String" unless value.is_a?(String) && !value.empty?

      close_transport
      @base_url = value
    end

    def timeout=(value)
      raise ArgumentError, "timeout must be a positive number" unless value.is_a?(Numeric) && value.to_f.positive?

      @timeout = value.to_f
    end

    def transport=(value)
      close_transport
      @transport = value
    end

    def threshold=(value)
      @threshold = Jev.normalize_threshold(value)
    end

    private

    def default_transport
      @transport_mutex.synchronize { @default_transport ||= Transport.new(self) }
    end

    def close_transport
      @transport_mutex.synchronize { @default_transport&.send(:close) }
    end
  end
end
