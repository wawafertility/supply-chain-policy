require "fileutils"
require "json"
require_relative "licence_matcher"
require_relative "package_archive"

class LicenceNotices
  CACHE_DIRECTORY = File.join(ENV.fetch("XDG_CACHE_HOME", File.join(Dir.home, ".cache")), "wawa-licence-notices")
  DOWNLOAD_THREADS = 16
  PACKAGE_LINE = /\APackage: (?<name>\S+) (?<version>\S+)\z/
  RULE = "=" * 80
  INTRODUCTION = <<~TEXT.freeze
    Third-party software licences

    This software includes the open source packages listed below. Each entry gives the package's copyright
    notices and the licence it is distributed under. The full licence texts follow the list.
  TEXT
  NO_ARCHIVE = PackageArchive::Contents.new(licence_texts: {}, notice_texts: {}, declared_licence: nil, author: nil)

  def initialize(policy_root:)
    @policy_root = policy_root
    @matcher = LicenceMatcher.new(licence_directory: policy_root)
  end

  def write(path, packages)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text(build(packages)))
  end

  def packages_in(path)
    return [] unless File.exist?(path)

    File.foreach(path, chomp: true).filter_map do |line|
      match = line.match(PACKAGE_LINE)
      "#{match[:name]} #{match[:version]}" if match
    end
  end

  private

  attr_reader :policy_root, :matcher

  def build(packages)
    texts = {}
    entries = archives(packages).map { |package, contents| entry(package, contents || NO_ARCHIVE, texts) }
    { "packages" => entries, "texts" => texts.sort.to_h }
  end

  def entry(package, contents, texts)
    keys = contents.licence_texts.map do |file, body|
      licence = matcher.match(body)
      key = licence || "#{package.name} #{package.version} #{file}"
      texts[key] ||= licence ? reference_text(licence) : body.strip
      key
    end
    if reference?(contents.declared_licence) && !keys.include?(contents.declared_licence)
      keys << contents.declared_licence
      texts[contents.declared_licence] ||= reference_text(contents.declared_licence)
    end

    {
      "name" => package.name,
      "version" => package.version,
      "licence" => licence_label(contents.declared_licence, keys),
      "copyright" => copyright_lines(contents.licence_texts.values),
      "author" => contents.author,
      "notice" => contents.notice_texts.values.map(&:strip).join("\n\n"),
      "texts" => keys
    }
  end

  def licence_label(declared_licence, keys)
    return declared_licence if declared_licence
    return "Not declared" if keys.empty?

    keys.join(", ")
  end

  def copyright_lines(licence_texts)
    licence_texts.flat_map { |body| body.lines.filter_map { |line| copyright_statement(line) } }.uniq
  end

  def copyright_statement(line)
    return line.strip if line.match?(LicenceMatcher::COPYRIGHT_NOTICE)

    title, statement = line.split(LicenceMatcher::COPYRIGHT_MARKER, 2)
    statement.strip if statement && matcher.title_line?(title)
  end

  def reference?(licence)
    licence && File.exist?(reference_path(licence))
  end

  def reference_text(licence)
    File.read(reference_path(licence)).strip
  end

  def reference_path(licence)
    File.join(policy_root, "licence-texts", "#{licence}.txt")
  end

  def text(notices)
    packages = notices["packages"].map { |package| package_section(package) }
    licence_texts = notices["texts"].map { |key, body| "#{RULE}\nLicence text: #{key}\n\n#{body}\n" }
    [INTRODUCTION, *packages, *licence_texts].join("\n")
  end

  def package_section(package)
    lines = [RULE, "Package: #{package["name"]} #{package["version"]}", "Licence: #{package["licence"]}"]
    lines.concat(package["copyright"])
    lines << "Author: #{package["author"]}" if package["copyright"].empty? && package["author"]
    lines << "Licence text: #{package["texts"].join(", ")}" if package["texts"].any?
    lines.push("", package["notice"]) unless package["notice"].empty?
    "#{lines.join("\n")}\n"
  end

  def archives(packages)
    queue = Queue.new
    packages.each { |package| queue << package }
    queue.close
    results = {}
    lock = Mutex.new
    workers = Array.new(DOWNLOAD_THREADS) do
      Thread.new do
        while (package = queue.pop)
          contents = cached_archive(package)
          lock.synchronize { results[package] = contents }
        end
      end
    end
    workers.each(&:join)
    packages.to_h { |package| [package, results[package]] }
  end

  def cached_archive(package)
    path = File.join(CACHE_DIRECTORY, package.ecosystem, "#{package.name.tr("/", "+")}@#{package.version}.json")
    if File.exist?(path)
      cached = JSON.parse(File.read(path))
      return cached && PackageArchive::Contents.new(**cached.transform_keys(&:to_sym))
    end

    contents = PackageArchive.fetch(ecosystem: package.ecosystem, name: package.name, version: package.version)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(contents&.to_h))
    contents
  end
end
