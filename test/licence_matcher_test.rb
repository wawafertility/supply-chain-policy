require "minitest/autorun"
require_relative "../lib/licence_matcher"

class LicenceMatcherTest < Minitest::Test
  TEXTS = File.expand_path("../licence-texts", __dir__)

  def matcher
    @matcher ||= LicenceMatcher.new
  end

  def text(licence)
    File.read(File.join(TEXTS, "#{licence}.txt"))
  end

  def test_recognises_every_allowed_licence_from_its_spdx_text
    File.readlines(File.expand_path("../licences.txt", __dir__), chomp: true).each do |licence|
      assert_equal licence, matcher.match(text(licence)), "#{licence} did not match its own SPDX text"
    end
  end

  def test_recognises_mit_with_a_real_copyright_line_and_title
    licence = text("MIT").sub("MIT License\n", "(The MIT License)\n").sub(/Copyright.*\n/, "Copyright (c) 2014 Ryan Bigg\n")

    assert_equal "MIT", matcher.match(licence)
  end

  def test_recognises_mit_with_its_title_and_copyright_on_one_line
    licence = text("MIT").sub(/MIT License\n\nCopyright.*\n/, "The MIT License (MIT) Copyright (c) 2016 React Components\n")

    assert_equal "MIT", matcher.match(licence)
  end

  def test_recognises_mit_written_for_materials
    licence = text("MIT").gsub("SOFTWARE IS", "MATERIALS ARE").gsub("Software", "Materials").gsub("SOFTWARE", "MATERIALS")

    assert_equal "MIT", matcher.match(licence)
  end

  def test_recognises_bsd_3_clause_naming_its_organisation
    licence = text("BSD-3-Clause")
      .sub(/Copyright.*\n/, "Copyright 2014 Yahoo! Inc.\nAll rights reserved.\n")
      .sub("the copyright holder nor", "the Yahoo! Inc. nor")
      .sub("THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE", "YAHOO! INC. BE LIABLE")

    assert_equal "BSD-3-Clause", matcher.match(licence)
  end

  def test_recognises_apache_2_0_without_its_appendix
    licence = text("Apache-2.0").sub(/APPENDIX: How to apply.*/m, "")

    assert_equal "Apache-2.0", matcher.match(licence)
  end

  def test_rejects_mit_with_a_restriction_added_at_the_end
    assert_nil matcher.match(text("MIT") + "\nThe Software shall be used for Good, not Evil.\n")
  end

  def test_rejects_mit_with_a_restriction_added_after_the_title
    assert_nil matcher.match(text("MIT").sub("MIT License\n", "MIT License\n\nNo military use.\n"))
  end

  def test_rejects_mit_with_a_right_removed
    assert_nil matcher.match(text("MIT").sub(%r{and/or sell\s+}, ""))
  end

  def test_rejects_bsd_3_clause_with_an_extra_clause
    licence = text("BSD-3-Clause").sub("THIS SOFTWARE IS PROVIDED", "4. This software may not be used in weapons.\n\nTHIS SOFTWARE IS PROVIDED")

    assert_nil matcher.match(licence)
  end

  def test_rejects_apache_2_0_with_a_sentence_added_to_a_grant
    licence = text("Apache-2.0").sub("Grant of Copyright License.", "Grant of Copyright License. Not for commercial use.")

    assert_nil matcher.match(licence)
  end

  def test_rejects_a_copyleft_licence
    licence = <<~GPL
      This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
      Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
      option) any later version.
    GPL

    assert_nil matcher.match(licence)
  end

  def test_rejects_text_with_no_words
    assert_nil matcher.match("\n  \n")
  end
end
