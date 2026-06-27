# frozen_string_literal: true

module RailsDoctor
  module GitHubActions
    module_function

    def command(level:, title:, message:)
      "::#{level} title=#{escape_property(title)}::#{escape_data(message)}"
    end

    def escape_property(value)
      value.to_s
        .gsub("%", "%25")
        .gsub("\r", "%0D")
        .gsub("\n", "%0A")
        .gsub(":", "%3A")
        .gsub(",", "%2C")
    end

    def escape_data(value)
      value.to_s
        .gsub("%", "%25")
        .gsub("\r", "%0D")
        .gsub("\n", "%0A")
    end
  end
end
