require "digest"
require "etc"
require "json"
require "open-uri"

class OsvScanner
  class ScanFailed < StandardError; end

  VERSION = "2.6.0".freeze
  BUILDS = {
    "Linux-x86_64" => {
      platform: "linux_amd64",
      checksum: "ca69b3d3cd08f889a49dc0a383122f71cc528b83803671df5fd874d97485b108"
    },
    "Linux-aarch64" => {
      platform: "linux_arm64",
      checksum: "2c71403eb443d05891c4f268c3ad771cf4f16e5443463fd7851ef8f454d3c7e4"
    },
    "Darwin-arm64" => {
      platform: "darwin_arm64",
      checksum: "98c460dcd37de25819babd757d04542045b6243113e209edcd4d89fedb0256b4"
    }
  }.freeze

  def initialize(work_dir:)
    @work_dir = work_dir
  end

  def scan(*arguments)
    output = File.join(work_dir, "osv-scanner-#{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}.json")
    system(binary, "scan", "source", *arguments, "--format", "json", "--output-file", output)
    status = Process.last_status.exitstatus
    raise ScanFailed, "osv-scanner exited with status #{status}" unless [0, 1].include?(status)

    JSON.parse(File.read(output))
  end

  private

  attr_reader :work_dir

  def binary
    @binary ||= File.join(work_dir, "osv-scanner").tap do |path|
      contents = URI.open(download_url, "rb", &:read)
      unless Digest::SHA256.hexdigest(contents) == build[:checksum]
        raise ScanFailed, "Checksum mismatch for osv-scanner #{VERSION} (#{build[:platform]})"
      end

      File.binwrite(path, contents)
      File.chmod(0o755, path)
    end
  end

  def download_url
    "https://github.com/google/osv-scanner/releases/download/v#{VERSION}/osv-scanner_#{build[:platform]}"
  end

  def build
    @build ||= BUILDS.fetch("#{Etc.uname[:sysname]}-#{Etc.uname[:machine]}") do |runner|
      raise ScanFailed, "No pinned osv-scanner build for #{runner}"
    end
  end
end
