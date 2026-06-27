# frozen_string_literal: true

require "test_helper"

class RailsDoctorGitHubActionsTest < Minitest::Test
  def test_command_escapes_title_and_message
    output = RailsDoctor::GitHubActions.command(
      level: "warning",
      title: "database:pool,warning",
      message: "line 1\n100% full"
    )

    assert_equal "::warning title=database%3Apool%2Cwarning::line 1%0A100%25 full", output
  end
end
