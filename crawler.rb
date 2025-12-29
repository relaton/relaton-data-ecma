# frozen_string_literal: true

require 'relaton/ecma/data_fetcher'

# relaton_ci_pat = ARGV.shift

# Remoeve old files
FileUtils.rm_rf('data')
FileUtils.rm Dir.glob('index*')

# Run fetcher
Relaton::Ecma::DataFetcher.fetch
