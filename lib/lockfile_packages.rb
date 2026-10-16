require "json"

class LockfilePackages
  Package = Data.define(:ecosystem, :name, :version) do
    def label = "#{name} #{version}"
  end

  def initialize(scanner:)
    @scanner = scanner
  end

  def distributed_packages(lockfile, include_dev: false, exclude: [])
    packages = File.basename(lockfile) == "package-lock.json" ? npm_packages(lockfile, include_dev:) : scanned_packages(lockfile)
    packages
      .reject { |package| exclude.any? { |pattern| package.name.match?(/\A(?:#{pattern})\z/) } }
      .uniq
      .sort_by { |package| [package.name, package.version] }
  end

  private

  attr_reader :scanner

  def npm_packages(lockfile, include_dev:)
    JSON.parse(File.read(lockfile)).fetch("packages").filter_map do |path, details|
      next unless path.include?("node_modules/") && details["version"]
      next if details["link"] || (details["dev"] && !include_dev)

      Package.new(ecosystem: "npm", name: details["name"] || path.split("node_modules/").last, version: details["version"])
    end
  end

  def scanned_packages(lockfile)
    scanner.scan("--all-packages", "--lockfile", lockfile).fetch("results", []).flat_map do |result|
      result.fetch("packages").map do |package|
        details = package.fetch("package")
        Package.new(ecosystem: details["ecosystem"], name: details["name"], version: details["version"])
      end
    end
  end
end
