# frozen_string_literal: true

require "tmpdir"
require "yaml"

require_relative "../derive_index_v1"

# Absolute path to the repo root, so an example can reach the real committed
# `index-v1.yaml` from inside a temporary working directory.
REPO_ROOT = File.expand_path("..", __dir__)

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random

  # `Relaton::Index` keeps its Types in a process-wide pool, and it reuses a
  # Type on a matching file name alone. An example that writes an index in a
  # temporary directory would otherwise hand the next example a stale Type,
  # holding rows and a path from a directory that no longer exists.
  config.after do
    Relaton::Index.close :ECMA
    Relaton::Index.close :ECMA_V1
  end
end
