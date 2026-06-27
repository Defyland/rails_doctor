# frozen_string_literal: true

require "test_helper"

class RailsDoctorDocumentationLinksTest < Minitest::Test
  LOCAL_HOME_SEGMENT = "/" + "Users" + "/"
  WORKSPACE_SEGMENT = "backend" + "-challenges"

  def test_public_markdown_does_not_contain_local_absolute_paths
    offenders = public_markdown_files.filter_map do |path|
      matches = path.readlines.each_with_index.filter_map do |line, index|
        "#{path}:#{index + 1}" if line.include?(LOCAL_HOME_SEGMENT) || line.include?(WORKSPACE_SEGMENT)
      end

      matches unless matches.empty?
    end.flatten

    assert_empty offenders
  end

  private

  def public_markdown_files
    root = Pathname(__dir__).join("../..").expand_path
    [root.join("README.md")] + root.glob("docs/**/*.md")
  end
end
