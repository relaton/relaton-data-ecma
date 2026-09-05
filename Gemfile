# frozen_string_literal: true

source 'https://rubygems.org'

# The ECMA flavor lives in the combined `relaton` gem now, not in a
# `relaton-ecma` gem of its own. `crawler.rb`'s `require "relaton/ecma/
# data_fetcher"` is the correct path there.
#
# Pin `main` explicitly, for the reason relaton-data-bipm documents: an unpinned
# `github:` freezes whatever branch was current into Gemfile.lock, and relaton's
# remote churns many transient feature branches, so a later `bundle update` can
# fail fetching a branch that has since been deleted.
#
# NOTE: `main` does not carry the ECMA index-v2 work yet. While that is true,
# `Relaton::Ecma::INDEXFILE` is "index-v1", the gem writes that file itself, and
# `IndexV1.write` correctly declines -- so no `index-v2.yaml` is produced and the
# committed `index-v2.yaml`/`.zip` are not refreshed by a crawl. Repointing this
# at `relaton/relaton@feat/ecma-index-v2-producer`, once that branch is pushed
# and merged, is what turns the derivation on.
gem 'relaton', git: 'https://github.com/relaton/relaton.git', branch: 'main'

# This repo has to pin pubid itself: bundler reads a git gem's gemspec, never
# its Gemfile, so relaton's own pubid pin does not reach this bundle and a
# released pubid would be resolved instead. `Gemfile.lock` is git-ignored, so CI
# resolves fresh on every crawl. Verify with `bundle list | grep pubid` before
# trusting a generated index.
#
# `pubid/pubid`, not `metanorma/pubid`: the repo was renamed. GitHub still
# redirects the old path, but only until someone creates a new repo at the old
# name -- at which point the pin would silently resolve to a different
# repository instead of failing.
#
# NOTE: `main` does not carry `Pubid::Ecma::Identifier#volume` yet (it lives on
# `feat/ecma-edition-and-volume`, commit 49adb773). Until that merges,
# `spec/derive_index_v1_spec.rb` fails on the volume examples, and a v2 index
# built without it keys 421 distinct ids instead of 804.
gem 'pubid', git: 'https://github.com/pubid/pubid.git', branch: 'main'

group :development, :test do
  gem 'rspec', '~> 3.13'
end
