# frozen_string_literal: true

require_relative "lib/jev/version"

Gem::Specification.new do |spec|
  spec.name = "jev-feels"
  spec.version = Jev::VERSION
  spec.authors = ["Maxim Veysgeym"]
  spec.email = ["Qew7@users.noreply.github.com"]
  spec.summary = "Ruby-like semantic predicates via Jev"
  spec.description = <<~DESC
    Tiny Ruby API for semantic text checks. Jev.feels?(:urgent) is an ordinary
    condition, not an SDK session. Jev stays an implementation detail.
  DESC
  spec.homepage = "https://github.com/Qew7/jev-feels"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/README.md"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md", "context7.json"]
  spec.require_paths = ["lib"]
end
