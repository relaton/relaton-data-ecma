# frozen_string_literal: true

require 'relaton_ecma'

# relaton_ci_pat = ARGV.shift

# Remoeve old files
FileUtils.rm_rf('data')
FileUtils.rm Dir.glob('index.*')

# Run fetcher
RelatonEcma::DataFetcher.fetch

# Zip index
system('zip index.zip index.yaml')

# Stage index
system('git add index.yaml index.zip')
