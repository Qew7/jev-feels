# frozen_string_literal: true

RSpec.describe "require 'feels/string'" do
  it "adds feels and feels? to String" do
    lib = File.expand_path("../../lib", __dir__)
    code = <<~RUBY
      require "feels/string"
      Jev.configure { |config| config.transport = Class.new {
        def call(_payload)
          { "answers" => { "feels" => { "type" => "noul", "noul" => 0.94 } } }
        end
      }.new }
      abort "missing feels" unless "".respond_to?(:feels)
      abort "missing feels?" unless "".respond_to?(:feels?)
      abort "wrong feels" unless "x".feels("urgent") == 0.94
      abort "wrong feels?" unless "x".feels?("urgent") == true
      abort "wrong threshold" unless "x".feels?("urgent", threshold: 0.95) == false
      print "ok"
    RUBY

    output = IO.popen({ "RUBYOPT" => nil }, ["ruby", "-I", lib, "-e", code], err: %i[child out], &:read)

    expect(output).to eq("ok")
    expect($CHILD_STATUS).to be_success
  end
end
