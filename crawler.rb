# frozen_string_literal: true

require 'fileutils'
require 'relaton/ecma/data_fetcher'
require_relative 'derive_index_v1'

FileUtils.rm_rf('data')
# Narrower than 'index*', which would also match a Ruby file named index*.rb
# next to it -- the crawler would then delete its own source. relaton-data-bipm
# hit that bug; spec/crawler_sources_spec.rb guards it here.
FileUtils.rm Dir.glob('index-v*.{yaml,zip}')

# Writes index-v2.yaml only. Nothing zips here: relaton/support's shared
# crawler.yml zips every index*.yaml that changed and commits both files.
Relaton::Ecma::DataFetcher.fetch

# Released relaton v2 consumers still read index-v1.zip from this branch, so
# derive it from the index-v2 the fetch just wrote. `IndexV1.write` declines if
# the resolved relaton still writes index-v1 itself; see derive_index_v1.rb.
IndexV1.write
