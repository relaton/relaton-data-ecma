# frozen_string_literal: true

require "pubid"
require "relaton/index"
require "relaton/ecma"

#
# The legacy `index-v1`, derived from the pubid-backed `index-v2`.
#
# `Relaton::Ecma::DataFetcher` writes only `index-v2` now: its rows are
# `Pubid::Ecma::Identifier` objects serialized to a `_type: pubid:ecma:*` hash.
# Released relaton v2 consumers still fetch `index-v1.zip` from this repository,
# so this repository has to keep producing it.
#
# It is DERIVED, never crawled a second time. One crawl, one pass, and the two
# published files cannot drift apart. relaton-data-w3c, relaton-data-iana and
# relaton-data-bipm carry the same arrangement.
#
# Nothing here zips. relaton/support's shared `crawler.yml` zips every
# `index*.yaml` that changed and commits the yaml and the zip together.
#
module IndexV1
  FILE = "index-v1.yaml"
  V2_FILE = "index-v2.yaml"

  # The value `Relaton::Ecma::INDEXFILE` holds once the fetcher writes v2.
  V2_INDEXFILE = "index-v2"

  # A pool key of its own, so these plain hashes never land in the pubid-typed
  # `:ECMA` pool the fetcher fills.
  POOL_KEY = :ECMA_V1

  class << self
    #
    # Convert one `index-v2` identifier into its `index-v1` row id.
    #
    # v1 splits what v2 renders into one string: the `:id` is the BARE printed
    # form, and the edition and volume are separate keys beside it. Both render
    # flags have to be opted out of -- `Pubid::Ecma::Identifier#to_s` includes
    # them by default, because the v2 index keys on a bare `to_s` and needs them
    # to tell 740 edition-bearing rows apart.
    #
    # `.compact` is load-bearing. v1 omits an absent `:ed`/`:vol` entirely
    # rather than storing nil, so without it all 64 memento rows change shape.
    #
    # @param [Pubid::Ecma::Identifier] pubid an `index-v2` row identifier
    #
    # @return [Hash] the `index-v1` row id
    #
    def row_id(pubid)
      { id: pubid.to_s(with_edition: false, with_volume: false),
        ed: pubid.edition,
        vol: pubid.volume }.compact
    end

    #
    # Write `index-v1.yaml` from the `index-v2` the fetcher just wrote.
    #
    # Declines unless there is a real v2 index to derive from; see {.source}.
    #
    # @return [Integer, nil] rows written, or nil if it declined
    #
    def write
      rows = source or return nil

      index = Relaton::Index.find_or_create(POOL_KEY, file: FILE)
      # Build from scratch. `crawler.rb` deletes the index files before a crawl,
      # but a pooled Type outlives that, and `add_or_update` would otherwise
      # merge this crawl's rows into a previous crawl's.
      index.remove_all
      rows.each { |row| index.add_or_update row_id(row[:id]), row[:file] }
      index.save

      written = index.index.size
      if written < rows.size
        Relaton::Index::Util.warn "#{rows.size - written} of #{rows.size} " \
                                  "index-v2 rows collapsed into an existing " \
                                  "index-v1 row"
      end
      written
    end

    private

    #
    # The `index-v2` rows to derive from, or nil to decline.
    #
    # Deriving when the fetcher did not write a v2 index is destructive, not
    # merely useless: `crawler.rb` removes the index files before every crawl,
    # so an installed relaton that still writes `index-v1` leaves no
    # `index-v2.yaml` behind, and saving an empty index would replace the
    # published `index-v1.yaml` with `--- []`. Declining keeps `crawler.rb`
    # correct against both an installed relaton that writes v2 and one that
    # does not.
    #
    # @return [Array<Hash>, nil] `index-v2` rows, or nil
    #
    def source
      return nil unless Relaton::Ecma::INDEXFILE == V2_INDEXFILE
      return nil unless File.exist?(V2_FILE)

      # Read the file, not the fetcher's in-memory index. `crawler.rb` fetches
      # and derives in one process, and `Relaton::Index` pools its Types by
      # name and file, so `find_or_create` would otherwise hand back the very
      # object the fetcher filled -- deriving `index-v1` from rows that were
      # never compared against what `save` actually wrote. Closing it forces the
      # reload, so the two published files are derived from one another rather
      # than from a shared object, and every row goes through `Relaton::Index`'s
      # own deserialization checks on the way.
      Relaton::Index.close :ECMA

      rows = Relaton::Index.find_or_create(
        :ECMA, file: V2_FILE, pubid_class: ::Pubid::Ecma::Identifier
      ).index
      rows.empty? ? nil : rows
    end
  end
end
