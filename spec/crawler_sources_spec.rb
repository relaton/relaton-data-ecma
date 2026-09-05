# frozen_string_literal: true

# `crawler.rb` deletes `data/` on load, so it cannot be required. Read it as
# source text instead, the way relaton-data-iana and relaton-data-bipm guard
# their own crawlers.
RSpec.describe "crawler.rb" do
  let(:source) { File.read(File.join(REPO_ROOT, "crawler.rb")) }

  # A bare `index*` glob also matches a Ruby file named index*.rb beside it, and
  # the crawler would delete the very source it requires. relaton-data-bipm hit
  # this exact bug, and `index_builder.rb` is the name the sibling repos use --
  # so guard the name a future session is most likely to add, not only the one
  # here today.
  it "removes the generated index files, not a Ruby source beside them" do
    globs = source.scan(/Dir\.glob\(["']([^"']+)["']\)/).flatten
    expect(globs).not_to be_empty
    %w[derive_index_v1.rb index_builder.rb crawler.rb].each do |ruby|
      globs.each do |glob|
        expect(File.fnmatch(glob, ruby, File::FNM_EXTGLOB))
          .to be(false), "glob #{glob.inspect} matches #{ruby}"
      end
    end
    %w[index-v1.yaml index-v1.zip index-v2.yaml index-v2.zip].each do |file|
      expect(globs.any? { |g| File.fnmatch(g, file, File::FNM_EXTGLOB) })
        .to be(true), "no glob matches #{file}"
    end
  end

  # Order is the contract: `IndexV1.write` reads the `index-v2.yaml` the fetch
  # wrote. Run first, it would find nothing and decline.
  it "derives index-v1 after the fetch" do
    fetch = source.index("Relaton::Ecma::DataFetcher.fetch")
    derive = source.index("IndexV1.write")
    expect(fetch).not_to be_nil
    expect(derive).not_to be_nil
    expect(derive).to be > fetch
  end
end
