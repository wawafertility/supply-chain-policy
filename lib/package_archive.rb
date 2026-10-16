require "json"
require "open-uri"
require "stringio"
require "zlib"

class PackageArchive
  LICENCE_FILE = /\A([a-z0-9]+[.\-_])?(licen[cs]e|copying|unlicense)([.\-_].*)?\z/i
  NOTICE_FILE = /\Anotice([.\-_].*)?\z/i
  BLOCK = 512
  REGULAR_FILE_TYPES = ["0", "\0"].freeze

  Contents = Data.define(:licence_texts, :notice_texts, :declared_licence, :author)

  def self.fetch(ecosystem:, name:, version:)
    new(ecosystem:, name:, version:).contents
  end

  def initialize(ecosystem:, name:, version:)
    @ecosystem = ecosystem
    @name = name
    @version = version
  end

  def contents
    files = ecosystem == "RubyGems" ? gem_files : npm_files
    manifest = files["package.json"] ? JSON.parse(files["package.json"]) : {}
    Contents.new(
      licence_texts: files.select { |file, _text| file.match?(LICENCE_FILE) }.sort.to_h,
      notice_texts: files.select { |file, _text| file.match?(NOTICE_FILE) }.sort.to_h,
      declared_licence: declared_licence(manifest),
      author: author(manifest)
    )
  rescue OpenURI::HTTPError
    nil
  end

  private

  attr_reader :ecosystem, :name, :version

  def npm_files
    URI.open("https://registry.npmjs.org/#{name}/-/#{name.split("/").last}-#{version}.tgz", "rb") do |archive|
      Zlib::GzipReader.wrap(archive) { |tarball| top_level_files(tarball, depth: 2) }
    end
  end

  def gem_files
    data = URI.open("https://rubygems.org/downloads/#{name}-#{version}.gem", "rb") do |archive|
      tar_entries(archive) { |path| path == "data.tar.gz" }.fetch("data.tar.gz")
    end
    Zlib::GzipReader.wrap(StringIO.new(data)) { |tarball| top_level_files(tarball, depth: 1) }
  end

  def top_level_files(tarball, depth:)
    entries = tar_entries(tarball) do |path|
      parts = path.split("/")
      parts.size == depth && (parts.last.match?(LICENCE_FILE) || parts.last.match?(NOTICE_FILE) || parts.last == "package.json")
    end
    entries.to_h { |path, data| [path.split("/").last, data.force_encoding(Encoding::UTF_8).scrub] }
  end

  def tar_entries(tarball)
    entries = {}
    while (header = tarball.read(BLOCK)) && header.bytesize == BLOCK && !header.delete("\0").empty?
      size = header[124, 12].delete("\0 ").to_i(8)
      data = tarball.read(size).to_s
      tarball.read((BLOCK - (size % BLOCK)) % BLOCK)
      path = tar_path(header)
      entries[path] = data if REGULAR_FILE_TYPES.include?(header[156]) && yield(path)
    end
    entries
  end

  def tar_path(header)
    name = header[0, 100].split("\0").first.to_s
    prefix = header[257, 6] == "ustar\0" ? header[345, 155].split("\0").first.to_s : ""
    prefix.empty? ? name : "#{prefix}/#{name}"
  end

  def declared_licence(manifest)
    licence = manifest["license"] || manifest["licenses"]
    licence = licence.map { |entry| entry.is_a?(Hash) ? entry["type"] : entry }.join(" OR ") if licence.is_a?(Array)
    licence.is_a?(Hash) ? licence["type"] : licence
  end

  def author(manifest)
    author = manifest["author"]
    author.is_a?(Hash) ? author["name"] : author
  end
end
