# relaton-data-ecma

The ECMA bibliographic corpus, crawled daily from ecma-international.org by
`crawler.rb`, which drives the ECMA flavor of the `relaton` gem.

## Two index files

| File | Rows | Written by | Read by |
|---|---|---|---|
| `index-v2.yaml` / `.zip` | `Pubid::Ecma::Identifier`, `_type: pubid:ecma:*` | `Relaton::Ecma::DataFetcher` | relaton, once the consumer half lands |
| `index-v1.yaml` / `.zip` | bespoke hash -- `:id`, `:ed`, `:vol` | `derive_index_v1.rb`, here | released relaton v2 clients |

`index-v1` is **derived, never crawled**. The fetcher upstream stopped writing
it. Released relaton v2 consumers still fetch `index-v1.zip` from this
repository, so this repository has to keep producing it, from the `index-v2` the
fetcher just wrote.

`.zip` companions are built by `relaton/support`'s shared `crawler.yml`, which
zips any changed `index*.yaml` and commits both. Nothing here zips.

## The v1 row shape

804 rows: 740 carry `:ed`, 4 carry `:vol`, and the 64 `ECMA MEM/` rows carry
neither. An absent key is **absent**, never nil, which is why `IndexV1.row_id`
ends in `.compact`.

`:id` is the **bare** printed form (`ECMA-269`), so `to_s` has to opt out of
both render flags. `Pubid::Ecma::Identifier#to_s` includes the edition and the
volume by default -- deliberately, because `Relaton::Index::Type#add_or_update`
keys on a bare `to_s` and cannot pass options, and without the edition 383 of
the 804 rows collapse onto another row's key and vanish silently.

The four `ECMA-269` edition-3 volumes share a docidentifier **and** a title, so
the volume is the only thing telling them apart. If they ever collapse to one
row, the derive or the pubid volume attribute is wrong.

## `IndexV1.write` declines by design

`crawler.rb` deletes the index files before every crawl. An installed relaton
that still writes `index-v1` leaves no `index-v2.yaml` behind, and saving an
empty index would replace the published `index-v1.yaml` with `--- []`. So
`IndexV1.write` runs only when `Relaton::Ecma::INDEXFILE` names `index-v2`
*and* a non-empty `index-v2.yaml` exists.

It also calls `Relaton::Index.close :ECMA` before reading. `Relaton::Index`
pools its Types by name and file, and `crawler.rb` fetches and derives in one
process, so `find_or_create` would otherwise hand back the object the fetcher
filled -- deriving v1 from rows never compared against what `save` wrote.

## Do not name a file `index*`

`crawler.rb` removes `index-v*.{yaml,zip}` before a crawl. A bare `index*` glob
also matches the Ruby files beside it, and relaton-data-bipm deleted its own
crawler source that way. Keep the Ruby files verb-named --
`derive_index_v1.rb` -- and keep the glob narrow.
`spec/crawler_sources_spec.rb` guards both.

## Specs

`bundle exec rspec`. There is no Rakefile and no CI workflow for the specs; the
sibling data repos (iana, bipm, w3c) are the same.

`spec/spec_helper.rb` requires `derive_index_v1.rb`, never `crawler.rb` --
`crawler.rb` deletes `data/` on load. It also closes the `:ECMA` and `:ECMA_V1`
pool entries after every example, because the pool is process-wide and keyed on
the file name alone.

The acceptance test is the corpus round trip: it rebuilds the `index-v2` rows
the crawl would produce from the committed `index-v1.yaml`, derives `index-v1`
back, and requires all 804 rows to match. Any change to `row_id` has to keep it
green.

## Dependency pins

`Gemfile` pins both `relaton` and `pubid` to `main`. **Neither `main` carries the
ECMA index-v2 work yet**, so as it stands:

* `Relaton::Ecma::INDEXFILE` is `index-v1`; the gem writes that file and
  `IndexV1.write` declines every crawl. The committed `index-v2.yaml`/`.zip` are
  a snapshot from a run against `feat/ecma-index-v2-producer` and a crawl will
  not refresh them.
* `Pubid::Ecma::Identifier#volume` does not exist, so the volume examples in
  `spec/derive_index_v1_spec.rb` fail.

To turn the derivation on, pin `relaton` to `feat/ecma-index-v2-producer` (push
it first -- it is not on the remote) and `pubid` to
`feat/ecma-edition-and-volume`, or wait for both to merge.
