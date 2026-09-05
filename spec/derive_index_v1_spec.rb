# frozen_string_literal: true

RSpec.describe IndexV1 do
  # One `index-v2` identifier, built the way `DataFetcher#index_id` builds it:
  # parse the bare docidentifier, then set the edition and the volume from the
  # model. Never parse the rendered form -- that is the crawl's own rule.
  def pubid(id, ed = nil, vol = nil)
    ::Pubid::Ecma::Identifier.parse(id).tap do |p|
      p.edition = ed if ed
      p.volume = vol if vol
    end
  end

  # Write an `index-v2.yaml` holding +rows+, and leave the Type pooled and open,
  # the way `crawler.rb` leaves the fetcher's.
  def write_index_v2(rows)
    index = Relaton::Index.find_or_create(
      :ECMA, file: "index-v2.yaml", pubid_class: ::Pubid::Ecma::Identifier
    )
    index.remove_all
    rows.each { |id, file| index.add_or_update id, file }
    index.save
  end

  describe ".row_id" do
    # Each pair is an `index-v2` identifier and the `index-v1` row id it has to
    # derive to. The expectations are lifted from the published `index-v1.yaml`,
    # so they pin the real published shape rather than a guess.
    {
      # The common shape: 740 of the 804 rows carry an edition.
      ["ECMA-434", "1"] => { id: "ECMA-434", ed: "1" },
      ["ECMA TR/114", "1"] => { id: "ECMA TR/114", ed: "1" },
      # A part stays inside the printed id; it is not a separate v1 key.
      ["ECMA-418-1", "1"] => { id: "ECMA-418-1", ed: "1" },
      # Editions are not all integers.
      ["ECMA-402", "5.1"] => { id: "ECMA-402", ed: "5.1" },
      # The 64 memento rows carry no edition. The `:ed` key is ABSENT, not nil.
      ["ECMA MEM/2026"] => { id: "ECMA MEM/2026" },
      # The only four rows in the whole index that carry a volume.
      ["ECMA-269", "3", "1"] => { id: "ECMA-269", ed: "3", vol: "1" },
      ["ECMA-269", "3", "4"] => { id: "ECMA-269", ed: "3", vol: "4" },
    }.each do |args, expected|
      it "derives #{expected} from #{args.join ' '}" do
        expect(described_class.row_id(pubid(*args))).to eq expected
      end
    end

    # `.compact` is what does this, and a naive hash would not: v1 omits an
    # absent `:ed`/`:vol` entirely rather than storing nil, so a nil value would
    # change the shape of all 64 edition-less rows at once.
    it "omits an absent :ed and :vol rather than storing nil" do
      expect(described_class.row_id(pubid("ECMA MEM/2026")).keys).to eq [:id]
    end

    # The index form is `ECMA-269 ed3 vol2`; the document's own printed id is
    # bare. v1's `:id` is the bare one, with the edition and volume split out.
    it "renders the bare document form, not the index form" do
      expect(described_class.row_id(pubid("ECMA-269", "3", "2"))[:id])
        .to eq "ECMA-269"
    end
  end

  describe ".write" do
    around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } } }

    # Pin the behaviour, not the installed relaton. A relaton whose INDEXFILE is
    # still `index-v1` would make every example here pass by taking the
    # declining branch.
    before { stub_const "Relaton::Ecma::INDEXFILE", "index-v2" }

    it "derives index-v1.yaml from the index-v2 the fetcher wrote" do
      write_index_v2 [[pubid("ECMA-434", "1"), "data/ecma-434-1.yaml"],
                      [pubid("ECMA MEM/2026"), "data/ecma-mem-2026.yaml"]]

      expect(described_class.write).to eq 2
      expect(YAML.unsafe_load_file("index-v1.yaml")).to contain_exactly(
        { id: { id: "ECMA-434", ed: "1" }, file: "data/ecma-434-1.yaml" },
        { id: { id: "ECMA MEM/2026" }, file: "data/ecma-mem-2026.yaml" },
      )
    end

    # The path `crawler.rb` actually takes. The fetcher's `:ECMA` Type is still
    # pooled, holding rows that were never saved, and `Relaton::Index` reuses a
    # Type on a matching file name alone. Deriving from that object instead of
    # the file would publish an `index-v1` that does not match the `index-v2`
    # beside it.
    it "derives from the saved file, not from a pooled in-memory index" do
      write_index_v2 [[pubid("ECMA-434", "1"), "data/ecma-434-1.yaml"]]
      stale = Relaton::Index.find_or_create(
        :ECMA, file: "index-v2.yaml", pubid_class: ::Pubid::Ecma::Identifier
      )
      stale.remove_all
      stale.add_or_update pubid("ECMA-6", "1"), "data/ecma-6-1.yaml"

      expect(described_class.write).to eq 1
      expect(YAML.unsafe_load_file("index-v1.yaml").map { |r| r[:file] })
        .to eq ["data/ecma-434-1.yaml"]
    end

    # The four ECMA-269 edition-3 volumes share a docidentifier AND a title, so
    # the volume is the only thing telling them apart. If they collapse to one
    # row, either the derive or the pubid volume attribute is wrong.
    it "keeps the four ECMA-269 edition-3 volumes as four distinct rows" do
      write_index_v2 (1..4).map { |v|
        [pubid("ECMA-269", "3", v.to_s), "data/ecma-269-3-#{v}.yaml"]
      }

      expect(described_class.write).to eq 4
      expect(YAML.unsafe_load_file("index-v1.yaml").map { |r| r[:id][:vol] })
        .to contain_exactly("1", "2", "3", "4")
    end

    # Two v2 rows can only collapse into one v1 row if they differ in something
    # v1 does not record. Nothing does today -- v1 keeps the id, the edition and
    # the volume, which is everything v2 holds -- so the count is a tripwire for
    # a future pubid attribute that v1 would silently drop.
    it "reports the row count that actually reached index-v1" do
      write_index_v2 [[pubid("ECMA-6", "1"), "data/ecma-6-1.yaml"],
                      [pubid("ECMA-6", "2"), "data/ecma-6-2.yaml"]]

      expect(described_class.write).to eq 2
    end

    # The guard. `crawler.rb` deletes the index files before every crawl, so a
    # derivation that ran anyway would `save` a Type that was never loaded --
    # writing `--- []` over the index every released relaton v2 consumer reads.
    it "declines, and writes nothing, when index-v2.yaml is absent" do
      expect(described_class.write).to be_nil
      expect(File).not_to exist("index-v1.yaml")
    end

    it "declines when index-v2.yaml holds no rows" do
      File.write "index-v2.yaml", [].to_yaml

      expect(described_class.write).to be_nil
      expect(File).not_to exist("index-v1.yaml")
    end

    it "declines when the installed relaton still writes index-v1 itself" do
      write_index_v2 [[pubid("ECMA-434", "1"), "data/ecma-434-1.yaml"]]
      stub_const "Relaton::Ecma::INDEXFILE", "index-v1"

      expect(described_class.write).to be_nil
      expect(File).not_to exist("index-v1.yaml")
    end
  end

  # The acceptance test. Take the published `index-v1.yaml`, rebuild the
  # `index-v2` rows the crawl would produce from it, derive `index-v1` back, and
  # require the result to be the published file's row set. Nothing smaller
  # proves that all 804 rows survive the round trip.
  describe "the published corpus" do
    around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } } }

    before { stub_const "Relaton::Ecma::INDEXFILE", "index-v2" }

    let(:published) do
      YAML.safe_load(File.read(File.join(REPO_ROOT, "index-v1.yaml")),
                     permitted_classes: [Symbol])
    end

    # What `DataFetcher#index_id` builds for each published row: the bare id
    # parsed, then the edition and volume set from the model fields.
    let(:v2_rows) do
      published.map do |row|
        id = row[:id]
        [pubid(id[:id], id[:ed], id[:vol]), row[:file]]
      end
    end

    def derived
      write_index_v2 v2_rows
      described_class.write
      YAML.unsafe_load_file("index-v1.yaml")
    end

    it "round-trips every published row unchanged" do
      # Sorted rather than `contain_exactly`, which compares 804 rows pairwise
      # and reports an unreadable diff on failure.
      by_file = ->(rows) { rows.sort_by { |r| r[:file] } }
      expect(by_file.call(derived)).to eq by_file.call(published)
    end

    it "keeps the published key counts" do
      rows = derived
      expect(rows.size).to eq 804
      expect(rows.count { |r| r[:id].key?(:ed) }).to eq 740
      expect(rows.count { |r| r[:id].key?(:vol) }).to eq 4
      expect(rows.count { |r| r[:id].values.any?(&:nil?) }).to eq 0
    end
  end
end
