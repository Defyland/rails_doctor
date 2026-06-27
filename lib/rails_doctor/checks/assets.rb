# frozen_string_literal: true

RailsDoctor.register "assets.production_build_missing" do |check|
  check.severity = :medium
  check.description = "Production deploys need compiled assets or an external asset pipeline."

  check.run do |context|
    next unless context.production?

    manifest_exists = context.file?("public/assets/.manifest.json") ||
      context.file?("public/assets/manifest.json") ||
      context.file?("public/vite/.vite/manifest.json")
    next if manifest_exists

    check.fail!(
      "asset build manifest is missing",
      hint: "Run the asset build step or configure an external asset host with a documented manifest strategy.",
      evidence: {checked: ["public/assets/.manifest.json", "public/assets/manifest.json", "public/vite/.vite/manifest.json"]}
    )
  end
end
