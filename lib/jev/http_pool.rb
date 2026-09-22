# frozen_string_literal: true

module Jev
  class HTTPPool
    IDLE_LIMIT = 4

    def initialize
      @mutex = Mutex.new
      @idle = []
      @generation = 0
      @pid = Process.pid
    end

    def with_connection(uri)
      close if @pid != Process.pid
      entry, generation = acquire
      origin = [uri.scheme, uri.host, uri.port]
      if entry && entry.first != origin
        finish(entry.last)
        entry = nil
      end
      entry ||= [origin, build(uri)]
      result = yield entry.last
      reusable = true
      result
    ensure
      release(entry, generation, reusable) if generation
    end

    def close
      idle = @mutex.synchronize do
        connections = @idle
        @idle = []
        @generation += 1
        @pid = Process.pid
        connections
      end
      idle.each { |entry| finish(entry.last) }
    end

    private

    def acquire
      @mutex.synchronize { [@idle.pop, @generation] }
    end

    def release(entry, generation, reusable)
      return unless entry

      retained = @mutex.synchronize do
        @idle.push(entry) if reusable && generation == @generation && @idle.size < IDLE_LIMIT && entry.last.started?
      end
      finish(entry.last) unless retained
    end

    def build(uri)
      Net::HTTP.new(uri.host, uri.port).tap { |http| http.use_ssl = uri.scheme == "https" }
    end

    def finish(http)
      http.finish if http.started?
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
      nil
    end
  end

  private_constant :HTTPPool
end
