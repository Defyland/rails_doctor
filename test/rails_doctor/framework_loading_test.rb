# frozen_string_literal: true

require "test_helper"

class RailsDoctorFrameworkLoadingTest < Minitest::Test
  def test_railtie_can_be_required_directly
    require "rails_doctor/railtie"

    assert_equal "RailsDoctor::Railtie", RailsDoctor::Railtie.name
  end

  def test_rails_command_file_defines_doctor_command
    require "rails/command"
    require "rails/commands/doctor/doctor_command"

    assert_equal "Rails::Command::DoctorCommand", Rails::Command::DoctorCommand.name
  end
end
