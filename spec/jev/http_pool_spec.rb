# frozen_string_literal: true

RSpec.describe "HTTP pool lifecycle" do
  let(:pool) { Jev.const_get(:HTTPPool).new }
  let(:uri) { URI("https://example.test") }
  let(:connections) { [] }
  let(:connection_class) do
    Class.new do
      attr_accessor :use_ssl

      def start
        @started = true
      end

      def started?
        @started == true
      end

      def finish
        @started = false
      end
    end
  end

  before do
    allow(Net::HTTP).to receive(:new) do
      connection_class.new.tap { |connection| connections << connection }
    end
  end

  after { pool.close }

  it "bounds idle connections without limiting concurrency or sharing busy connections" do
    entered = Queue.new
    release = Queue.new
    threads = Array.new(5) do
      Thread.new do
        pool.with_connection(uri) do |connection|
          connection.start
          entered << connection
          release.pop
        end
      end
    end
    active = Timeout.timeout(5) { Array.new(5) { entered.pop } }
    expect(active.uniq.size).to eq(5)
    5.times { release << true }
    Timeout.timeout(5) { threads.each(&:value) }
    expect(connections.count(&:started?)).to eq(4)
    pool.with_connection(uri, &:start)
    expect(connections.size).to eq(5)
  ensure
    threads&.each(&:kill)
    threads&.each(&:join)
  end

  it "discards active leases returned after the pool has been closed" do
    previous = nil
    pool.with_connection(uri) do |connection|
      previous = connection
      connection.start
      pool.close
      expect(connection).to be_started
    end

    expect(previous).not_to be_started
    pool.with_connection(uri) do |connection|
      expect(connection).not_to equal(previous)
      connection.start
    end
  end

  it "can create a connection after earlier connection attempts fail" do
    allow(Net::HTTP).to receive(:new).and_raise(SocketError, "unavailable")
    5.times do
      expect { Timeout.timeout(5) { pool.with_connection(uri) { |_| nil } } }.to raise_error(SocketError)
    end
    allow(Net::HTTP).to receive(:new) { connection_class.new }

    expect { Timeout.timeout(5) { pool.with_connection(uri, &:start) } }.not_to raise_error
  end

  it "discards connections when the lease raises" do
    expect do
      pool.with_connection(uri) do |connection|
        connection.start
        raise IOError, "disconnected"
      end
    end.to raise_error(IOError)
    expect(connections.first).not_to be_started

    pool.with_connection(uri, &:start)
    expect(connections.size).to eq(2)
  end

  it "does not reuse a connection for another origin" do
    pool.with_connection(uri, &:start)
    previous = connections.first
    pool.with_connection(URI("http://another.example.test"), &:start)

    expect(previous).not_to be_started
    expect(connections.size).to eq(2)
    expect(connections.last.use_ssl).to be false
  end

  it "discards inherited connections when the process changes" do
    pool.with_connection(uri, &:start)
    inherited = connections.first
    allow(Process).to receive(:pid).and_return(Process.pid + 1)

    pool.with_connection(uri, &:start)

    expect(inherited).not_to be_started
    expect(connections.size).to eq(2)
  end
end
