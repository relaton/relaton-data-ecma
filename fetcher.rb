# frozen_string_literal: true

require 'English'
# require 'yaml'
# require 'json'
require 'mechanize'
require 'relaton_ecma'

module RelatonEcma
  class DataFetcer
    URL = 'https://www.ecma-international.org/publications-and-standards/'
    AGENT = Mechanize.new

    # @param code [String]
    # @return [Array<RelatonBib::DocumentIdentifier>]
    def fetch_docid(code)
      [RelatonBib::DocumentIdentifier.new(type: 'ECMA', id: code, primary: true)]
    end

    # @param doc [Nokogiri::HTML::Document]
    # @return [Array<Hash>]
    def fetch_title(doc)
      doc.xpath('//p[@class="ecma-item-short-description"]').map do |t|
        { content: t.text.strip, language: 'en', script: 'Latn' }
      end
    end

    # @param doc [Nokogiri::HTML::Document]
    # @return [Array<RelatonBib::BibliographicDate>]
    def fetch_date(doc)
      doc.xpath('//p[@class="ecma-item-edition"]').map do |d|
        date = d.text.split(', ').last
        RelatonBib::BibliographicDate.new type: 'published', on: date
      end
    end

    # @param doc [Nokogiri::HTML::Document]
    # @return [String]
    def fetch_edition(doc)
      cnt = doc.at('//p[@class="ecma-item-edition"]')&.text&.match(/^\d+(?=th)/)&.to_s
      [RelatonBib::Edition.new(content: cnt)]
    end

    # @param doc [Nokogiri::HTML::Document]
    # @return [Array<Hash>]
    def fetch_relation(doc) # rubocop:disable Metrics/AbcSize
      doc.xpath("//ul[@class='ecma-item-archives']/li").map do |rel|
        ref, ed, on = rel.at('span').text.split ', '
        fref = RelatonBib::FormattedRef.new content: ref, language: 'en', script: 'Latn'
        date = []
        date << RelatonBib::BibliographicDate.new(type: 'published', on: on) if on
        link = rel.xpath('span/a').map { |l| RelatonBib::TypedUri.new type: 'doi', content: l[:href] }
        bibitem = RelatonBib::BibliographicItem.new formattedref: fref, edition: ed&.match(/^\d+/).to_s, link: link
        { type: 'updates', bibitem: bibitem }
      end
    end

    # @param doc [Nokogiri::HTM::Document]
    # @param url [String, nil]
    # @return [Array<RelatonBib::TypedUri>]
    def fetch_link(doc, url = nil)
      link = []
      link << RelatonBib::TypedUri.new(type: 'src', content: url) if url
      ref = doc.at('//div[@class="ecma-item-content-wrapper"]/span/a',
                   '//div[@class="ecma-item-content-wrapper"]/a',
                   '//div/p/a')
      link << RelatonBib::TypedUri.new(type: 'doi', content: ref[:href]) if ref
      link
    end

    # @param doc [Nokogiri::HTML::Document]
    # @return [Array<RelatonBib::FormattedString>]
    def fetch_abstract(doc)
      content = doc.xpath('//div[@class="ecma-item-content"]/p').map do |a|
        a.text.strip.squeeze(' ').gsub(/\r\n/, '')
      end.join "\n"
      return [] if content.empty?

      [RelatonBib::FormattedString.new(content: content, language: 'en', script: 'Latn')]
    end

    # @param hit [Nokogiri::HTML::Element]
    # @return [Array<RelatonBib::DocumentIdentifier>]
    def fetch_mem_docid(hit)
      code = 'ECMA MEM/' + hit.at('div[1]//p').text
      fetch_docid code
    end

    def fetch_mem_title(hit)
      year = hit.at('div[1]//p').text
      content = '"Memento ' + year + '" for year' + year
      [{ content: content, language: 'en', script: 'Latn' }]
    end

    def fetch_mem_date(hit)
      date = hit.at('div[2]//p').text
      on = Date.strptime(date, '%B %Y').strftime '%Y-%m'
      [RelatonBib::BibliographicDate.new(type: 'published', on: on)]
    end

    def contributor
      org = RelatonBib::Organization.new name: 'Ecma International'
      [{ entity: org, role: [{ type: 'publisher' }] }]
    end

    # @param bib [RelatonItu::ItuBibliographicItem]
    def write_file(bib)
      id = bib.docidentifier[0].id.gsub(%r{[/\s]}, '_')
      file = "data/#{id}.yaml"
      File.write file, bib.to_hash.to_yaml, encoding: 'UTF-8'
    end

    # @param hit [Nokogiri::HTML::Element]
    def parse_page(hit) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      bib = { fetched: Date.today.to_s, type: 'standard', language: ['en'], script: ['Latn'],
              contributor: contributor, place: ['Geneva'], doctype: 'document' }
      if hit[:href]
        AGENT.user_agent_alias = Mechanize::AGENT_ALIASES.keys[rand(21)]
        AGENT.cookie_jar.clear!
        doc = get_page hit[:href]
        bib[:docid] = fetch_docid(hit.text)
        bib[:link] = fetch_link(doc, hit[:href])
        bib[:title] = fetch_title(doc)
        bib[:abstract] = fetch_abstract(doc)
        bib[:date] = fetch_date(doc)
        bib[:relation] = fetch_relation(doc)
        bib[:edition] = fetch_edition(doc)
      else
        bib[:docid] = fetch_mem_docid(hit)
        bib[:link] = fetch_link(hit)
        bib[:title] = fetch_mem_title(hit)
        bib[:date] = fetch_mem_date(hit)
      end
      item = RelatonBib::BibliographicItem.new(**bib)
      write_file item
    end

    def get_page(url)
      3.times do |n|
        sleep n
        doc = AGENT.get url
        return doc
      rescue Net::HTTPLoopDetected, Net::HTTPInternalServerError => e
        puts e.message
      end
    end

    # @param type [String]
    def html_index(type) # rubocop:disable Metrics/MethodLength
      AGENT.user_agent_alias = Mechanize::AGENT_ALIASES.keys[rand(21)]
      result = AGENT.get "#{URL}#{type}/"
      # @last_call_time = Time.now
      result.xpath(
        '//li/span[1]/a',
        "//div[contains(@class, 'entry-content-wrapper')][.//a[.='Download']]"
      ).each do |hit|
        # workers << hit
        parse_page(hit)
      rescue StandardError => e
        warn e.message
        warn e.backtrace
      end
    end

    def fetch
      t1 = Time.now
      puts "Started at: #{t1}"

      html_index 'standards'
      html_index 'technical-reports'
      html_index 'mementos'

      t2 = Time.now
      puts "Stopped at: #{t2}"
      puts "Done in: #{(t2 - t1).round} sec."
    end
  end
end

RelatonEcma::DataFetcer.new.fetch
