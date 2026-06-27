# frozen_string_literal: true

RailsDoctor.register "rails.production.force_ssl_disabled" do |check|
  check.severity = :high
  check.description = "Production should force HTTPS unless TLS is terminated and enforced before Rails."

  check.run do |context|
    next unless context.production?

    unless context.config.respond_to?(:force_ssl) && context.config.force_ssl
      check.fail!(
        "force_ssl is disabled in production",
        hint: "Set config.force_ssl = true or document the upstream TLS enforcement check.",
        evidence: {environment: context.environment, force_ssl: context.config.respond_to?(:force_ssl) && context.config.force_ssl}
      )
    end
  end
end

RailsDoctor.register "rails.cookies.same_site_not_strict" do |check|
  check.severity = :medium
  check.description = "Flags weak same_site cookie defaults."

  check.run do |context|
    same_site = context.config.action_dispatch.cookies_same_site_protection if context.config.respond_to?(:action_dispatch)
    if context.production? && !%i[lax strict].include?(same_site)
      check.fail!(
        "cookies_same_site_protection is not configured to lax or strict",
        hint: "Set config.action_dispatch.cookies_same_site_protection = :lax or :strict.",
        evidence: {same_site: same_site.inspect}
      )
    end
  end
end

RailsDoctor.register "rails.session.cookie_flags_weak" do |check|
  check.severity = :high
  check.description = "Production session cookies should enforce secure transport and http-only access."

  check.run do |context|
    next unless context.production?
    next if context.config.respond_to?(:api_only) && context.config.api_only
    next unless context.config.respond_to?(:session_options)

    options = Hash.try_convert(context.config.session_options) || {}
    secure = options.key?(:secure) ? options[:secure] : options["secure"]
    httponly = options.key?(:httponly) ? options[:httponly] : options["httponly"]
    force_ssl = context.config.respond_to?(:force_ssl) && context.config.force_ssl

    issues = []
    issues << "secure_not_enabled" if secure != true && !force_ssl
    issues << "httponly_disabled" if httponly == false

    next if issues.empty?

    check.fail!(
      "session cookie flags are weak in production",
      hint: "Set secure: true and avoid httponly: false in the session store configuration for production.",
      evidence: {
        issues: issues,
        secure: secure,
        httponly: httponly,
        force_ssl: force_ssl
      }
    )
  end
end

RailsDoctor.register "rails.cache_store.memory_store_in_production" do |check|
  check.severity = :medium
  check.description = "Production cache should survive process restarts and scale beyond one process."

  check.run do |context|
    next unless context.production?

    store = Array(context.config.cache_store).first
    if store.nil? || store == :memory_store || store == :null_store
      check.fail!(
        "cache store is not production-grade",
        hint: "Use a shared cache store such as Redis, Memcached, Solid Cache, or document why cache locality is acceptable.",
        evidence: {cache_store: context.config.cache_store.inspect}
      )
    end
  end
end
