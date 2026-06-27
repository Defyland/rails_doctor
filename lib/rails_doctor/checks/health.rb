# frozen_string_literal: true

RailsDoctor.register "health.readiness_route_missing" do |check|
  check.severity = :low
  check.description = "A boot-only health route should be complemented by dependency readiness."

  check.run do |context|
    has_boot_route, has_readiness, evidence = if context.route_definitions.any?
      route_definitions = context.route_definitions
      boot_route = route_definitions.any? do |route|
        route[:path] == "/up" || route.dig(:defaults, "controller") == "rails/health"
      end
      readiness_route = route_definitions.any? do |route|
        route[:path].match?(%r{(?:\A|/)(?:readiness|ready|readyz)(?:/|\z)})
      end

      [
        boot_route,
        readiness_route,
        {
          boot_health_route: boot_route,
          readiness_route: readiness_route,
          route_source: "route_set"
        }
      ]
    elsif context.file?("config/routes.rb")
      routes = context.read("config/routes.rb").to_s
      boot_route = routes.include?("/up") || routes.include?("rails/health")
      readiness_route = routes.match?(%r{readiness|ready|readyz|/ready})

      [
        boot_route,
        readiness_route,
        {
          boot_health_route: boot_route,
          readiness_route: readiness_route,
          route_source: "config/routes.rb"
        }
      ]
    else
      next
    end

    if has_boot_route && !has_readiness
      check.fail!(
        "health route exists but readiness route was not found",
        hint: "Add a readiness endpoint that verifies required dependencies such as database, cache, queue, and storage.",
        evidence: evidence
      )
    end
  end
end
