# frozen_string_literal: true

RailsDoctor.register "database.pool.too_small" do |check|
  check.severity = :high
  check.description = "Database pool must be at least Puma max threads per process."

  check.run do |context|
    pool = context.database_pool_size
    threads = context.puma_max_threads
    next if pool.nil? || threads.nil?

    if pool < threads
      check.fail!(
        "Database pool is smaller than Puma thread count",
        hint: "Set pool >= RAILS_MAX_THREADS for each web process.",
        evidence: {
          database_pool: pool,
          database_pool_source: context.database_pool_source,
          puma_threads: threads,
          puma_threads_source: context.puma_max_threads_source
        }
      )
    end
  rescue ArgumentError => error
    check.fail!(
      "database pool or Puma thread count is not an integer",
      hint: "Use numeric DB_POOL/RAILS_MAX_DB_POOL and RAILS_MAX_THREADS values.",
      evidence: {
        error: error.message,
        database_pool: context.database_pool_raw_value,
        database_pool_source: context.database_pool_source,
        rails_max_threads: context.puma_max_threads_raw_value,
        puma_threads_source: context.puma_max_threads_source
      }
    )
  end
end

RailsDoctor.register "database.migrations.pending" do |check|
  check.severity = :high
  check.description = "Detects pending Active Record migrations when Active Record is loaded."

  check.run do |_context|
    next unless defined?(ActiveRecord::Migration)

    ActiveRecord::Migration.check_pending!
  rescue ActiveRecord::PendingMigrationError => error
    check.fail!(
      "database has pending migrations",
      hint: "Run bin/rails db:migrate for the target environment before deploy.",
      evidence: {error: error.message.lines.first.to_s.strip}
    )
  end
end
