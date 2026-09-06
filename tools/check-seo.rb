# frozen_string_literal: true

require 'json'
require 'date'
require 'nokogiri'
require 'yaml'

site_dir = ARGV.fetch(0, '_site')
source_dir = File.expand_path('..', __dir__)
failures = []

check = lambda do |condition, message|
  failures << message unless condition
end

# Jekyll applies typographic quotes to metadata during rendering.
normalize_description = lambda do |value|
  value.to_s.tr("‘’“”", %q(''"")).split.join(' ')
end

read_page = lambda do |path|
  Nokogiri::HTML(File.read(File.join(site_dir, path)))
end

schema_for = lambda do |page|
  scripts = page.css('script[type="application/ld+json"]')
  raise 'Expected exactly one JSON-LD block per page' unless scripts.length == 1

  JSON.parse(scripts.first.text)
end

home = read_page.call('index.html')
check.call(home.at_css('title').text == 'Security Research & CTF Writeups | devploit / blog',
           'The home title must describe the blog and preserve its brand')
check.call(schema_for.call(home)['name'] == 'devploit / blog',
           'The WebSite name must match the blog brand')

{
  'index.html' => 'WebSite',
  'about/index.html' => 'AboutPage',
  'tags/index.html' => 'CollectionPage',
  'categories/index.html' => 'CollectionPage',
  'archives/index.html' => 'CollectionPage'
}.each do |path, expected_type|
  page = read_page.call(path)
  check.call(schema_for.call(page)['@type'] == expected_type,
             "#{path}: expected #{expected_type} structured data")
end

post_pages = Dir.glob(File.join(site_dir, 'posts/*/index.html'))
check.call(!post_pages.empty?, 'The built site must contain posts')

post_pages.each do |path|
  page = Nokogiri::HTML(File.read(path))
  schema = schema_for.call(page)
  author = schema.fetch('author', {})
  check.call(schema['@type'] == 'BlogPosting', "#{path}: missing BlogPosting type")
  check.call(author['@type'] == 'Person' && author['name'] == 'Daniel Púa' &&
             author['url'] == 'https://blog.devploit.dev/about/',
             "#{path}: missing author name, type, or profile URL")
  check.call(page.at_css('.post-meta a[href="https://blog.devploit.dev/about/"]'),
             "#{path}: the visible byline must link to the author profile")
  check.call(schema.fetch('image', {})['@type'] == 'ImageObject',
             "#{path}: the structured image type must be ImageObject")

  cover = page.at_css('img.preview-img')
  check.call(cover && cover['src'] && cover['src'] == cover['data-src'] &&
             cover['loading'] == 'eager' && cover['fetchpriority'] == 'high',
             "#{path}: the cover must load directly without JavaScript")
  check.call(cover && cover['width'].to_i.positive? && cover['height'].to_i.positive?,
             "#{path}: the cover must reserve its intrinsic dimensions")
  page.css('.post-content img').each do |image|
    check.call(image['src'] && image['src'] == image['data-src'],
               "#{path}: content images must expose their source URL")
  end
end

# Compare the output to editorial metadata, so a heading or opening paragraph
# cannot silently become the search description again.
Dir.glob(File.join(source_dir, '_posts/*.md')).each do |path|
  front_matter = YAML.safe_load(File.read(path).split(/^---\s*$/, 3)[1], [Date, Time])
  slug = File.basename(path, '.md').sub(/^\d{4}-\d{2}-\d{2}-/, '')
  page = read_page.call("posts/#{slug}/index.html")
  expected = normalize_description.call(front_matter.fetch('description'))
  description = page.at_css('meta[name="description"]')
  check.call(description && normalize_description.call(description['content']) == expected,
             "#{path}: the search description must match the front matter")
  check.call(normalize_description.call(schema_for.call(page)['description']) == expected,
             "#{path}: the structured description must match the front matter")
end

if failures.any?
  warn failures.join("\n")
  abort "SEO checks failed: #{failures.length}"
end

puts "SEO checks passed for the home page, four tabs, and #{post_pages.length} posts."
