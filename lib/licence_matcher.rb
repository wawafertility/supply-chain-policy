require "set"

class LicenceMatcher
  SHORTLIST_SIMILARITY = 0.8
  NAME_SLOT_EXTRA_WORDS = 8
  MATCH_TIMEOUT_SECONDS = 2
  COPYRIGHT_NOTICE = /
    \A\s*(Portions\s+)?(Copyright|COPYRIGHT|\([cC]\)|©)
    (?!\s+(?i:notice|notices|license|licenses|owner|owners|holder|holders|statement|and|or|law|laws|is|you)\b)
  /x
  COPYRIGHT_MARKER = /(?=Copyright\b|\([cC]\)|©)/
  TITLE_WORDS = %w[
    the license mit expat isc bsd clause new simplified modified apache version zlib x11 unlicense blueoak
    postgresql python unicode ofl sil open font boost software
  ].to_set
  MARKER = /(<<beginOptional>>|<<endOptional>>|<<var;.*?>>)/m
  VARIABLE = /<<var;name="(?<name>[^"]*)";\s*original="(?<original>[^"]*)";\s*match="(?<match>[^"]*)"\s*>>/m

  def initialize(licence_directory: File.expand_path("..", __dir__))
    @word_sets = Dir.glob(File.join(licence_directory, "licence-texts", "*.txt")).to_h do |path|
      [File.basename(path, ".txt"), words(File.read(path)).to_set]
    end
    @patterns = Dir.glob(File.join(licence_directory, "licence-templates", "*.template.txt")).to_h do |path|
      [File.basename(path, ".template.txt"), compile(File.read(path))]
    end
  end

  def match(text)
    candidates = candidate_variants(text)
    return if candidates.first.empty?

    shortlist(candidates.first).find do |licence|
      candidates.any? { |candidate| matches?(patterns.fetch(licence), candidate) }
    end
  end

  def title_line?(line)
    title_words = words(line.to_s.split(COPYRIGHT_MARKER, 2).first.to_s)
    title_words.any? && title_words.all? { |word| TITLE_WORDS.include?(word) }
  end

  private

  attr_reader :word_sets, :patterns

  def candidate_variants(text)
    lines = text.lines.reject { |line| line.match?(COPYRIGHT_NOTICE) }
    title_index = lines.index { |line| !line.strip.empty? }
    variants = [lines]
    variants << lines.reject.with_index { |_line, index| index == title_index } if title_index && title_line?(lines[title_index])
    variants.map { |variant| words(variant.join).join(" ") }
  end

  def shortlist(candidate)
    candidate_set = candidate.split.to_set
    word_sets.select { |_licence, reference| dice(candidate_set, reference) >= SHORTLIST_SIMILARITY }.keys
  end

  def dice(left, right)
    2.0 * (left & right).size / (left.size + right.size)
  end

  def matches?(pattern, candidate)
    pattern.match?(candidate)
  rescue Regexp::TimeoutError
    false
  end

  def compile(template)
    groups = [[]]
    without_copyright_notices(template).split(MARKER).each do |piece|
      case piece
      when "<<beginOptional>>"
        groups.push([])
      when "<<endOptional>>"
        optional = groups.pop
        groups.last << "(?:#{optional.join('\s*')})?"
      when VARIABLE
        groups.last << variable_pattern(Regexp.last_match)
      else
        groups.last.concat(words(piece).map { |word| Regexp.escape(word) })
      end
    end
    Regexp.new("\\A\\s*#{groups.first.join('\s*')}\\s*\\z", timeout: MATCH_TIMEOUT_SECONDS)
  end

  def without_copyright_notices(template)
    template.lines.reject { |line| line.match?(COPYRIGHT_NOTICE) && !line.include?("Optional>>") }.join
  end

  def variable_pattern(variable)
    return "" if variable[:name] == "copyright"
    return "(?:(?>[a-z0-9]{2,})\\s*)?" if variable[:name] == "bullet"

    "(?:#{word_pattern(variable[:match], window: words(variable[:original]).size + NAME_SLOT_EXTRA_WORDS)})"
  end

  def word_pattern(match, window:)
    match
      .downcase
      .gsub("licence", "license")
      .gsub(/(?<!\\)\.(\+|\*|\{\d+(,\d+)?\})/) { Regexp.last_match(1) == "+" ? " wildcardone " : " wildcardany " }
      .gsub(/\\s[+*]?|\[ \\t\\r\\n\\f\]/, " ")
      .gsub(/\{\d+(,\d+)?\}/, "")
      .gsub(/\\[^a-z0-9]/, " ")
      .gsub(/[^a-z0-9 ()|?\[\]]/, " ")
      .squeeze(" ")
      .gsub(" ", '\s*')
      .gsub("wildcardone") { "(?:(?>[a-z0-9]+)\\s*){1,#{window}}" }
      .gsub("wildcardany") { "(?:(?>[a-z0-9]+)\\s*){0,#{window}}" }
  end

  def words(text)
    text
      .downcase
      .gsub(/all rights reserved/, " ")
      .gsub("licence", "license")
      .gsub("https", "http")
      .scan(/[a-z0-9]{2,}/)
  end
end
