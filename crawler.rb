# frozen_string_literal: true

require 'English'
# require 'yaml'
# require 'json'
require 'mechanize'
require 'relaton_ecma'

# @param code [String]
# @return [Array<RelatonBib::DocumentIdentifier>]
def fetch_docid(code)
  [RelatonBib::DocumentIdentifier.new(type: 'ECMA', id: code)]
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
  doc.at('//p[@class="ecma-item-edition"]')&.text&.match(/^\d+(?=th)/)&.to_s
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
  ref = doc.at('//div[@class="ecma-item-content-wrapper"]/span/a', '//div/a')
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
  id = bib.docidentifier[0].id.gsub(%r{[\/\s]}, '_')
  file = "data/#{id}.yaml"
  File.write file, bib.to_hash.to_yaml, encoding: 'UTF-8'
end

# @param hit [Nokogiri::HTML::Element]
# @param agent [Mechanize]
def parse_page(hit, agent)
  bib = { type: 'standard',language: ['en'], script: ['Latn'], contributor: contributor,
          place: ['Geneva'], doctype: 'document' }
  if hit[:href]
    doc = agent.get hit[:href]
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
  item = RelatonBib::BibliographicItem.new bib
  write_file item
end

# @param agent [Mechanize]
# #param url [String]
# @param workers [RelatonBib::WorkersPool]
# @param type [String]
def html_index(agent, url, workers, type)
  result = agent.get "#{url}#{type}/"
  result.xpath(
    '//li/span[1]/a',
    "//div[contains(@class, 'entry-content-wrapper')][.//a[.='Download']]"
  ).each do |hit|
    workers << hit
  end
end

agent = Mechanize.new
workers = RelatonBib::WorkersPool.new 10
workers.worker do |hit|
  begin
    parse_page(hit, agent)
  rescue => e # rubocop:disable Style/RescueStandardError
    warn e.message
    warn e.backtrace
  end
end
t1 = Time.now
puts "Started at: #{t1}"

url = 'https://www.ecma-international.org/publications-and-standards/'
html_index agent, url, workers, 'standards'
html_index agent, url, workers, 'technical-reports'
html_index agent, url, workers, 'mementos'

workers.end
workers.result

t2 = Time.now
puts "Stopped at: #{t2}"
puts "Done in: #{(t2 - t1).round} sec."
