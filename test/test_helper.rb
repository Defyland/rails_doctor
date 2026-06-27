# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "json"
require "pathname"
require "rails_doctor"
require_relative "support/integration_app_harness"

module TestSupport
  include IntegrationAppHarness

  class FakeConfig
    attr_accessor :x, :api_only, :force_ssl, :cache_store, :filter_parameters,
      :active_job, :active_storage, :action_mailer, :action_dispatch,
      :database_configuration, :rails_doctor, :session_options, :solid_queue

    def initialize
      @api_only = false
      @force_ssl = true
      @cache_store = :redis_cache_store
      @filter_parameters = %i[password token secret authorization cookie ssn cpf credit_card]
      @active_job = ActiveJobConfig.new
      @active_storage = ActiveStorageConfig.new
      @action_mailer = ActionMailerConfig.new
      @action_dispatch = ActionDispatchConfig.new
      @solid_queue = SolidQueueConfig.new
      @database_configuration = {}
      @rails_doctor = RailsDoctor::Configuration.new
      @session_options = {secure: true, httponly: true, same_site: :lax}
      @x = Struct.new(:rails_doctor).new(@rails_doctor)
    end
  end

  class ActiveJobConfig
    attr_accessor :queue_adapter

    def initialize
      @queue_adapter = :solid_queue
    end
  end

  class ActiveStorageConfig
    attr_accessor :service

    def initialize
      @service = :amazon
    end
  end

  class SolidQueueConfig
    attr_accessor :connects_to

    def initialize
      @connects_to = nil
    end
  end

  class ActionMailerConfig
    attr_accessor :default_url_options

    def initialize
      @default_url_options = {host: "example.com"}
    end
  end

  class ActionDispatchConfig
    attr_accessor :cookies_same_site_protection

    def initialize
      @cookies_same_site_protection = :lax
    end
  end

  class FakeApplication
    attr_reader :cache, :root, :config
    attr_accessor :secret_key_base

    def initialize(root:, config:, secret_key_base: "x" * 64, cache: nil)
      @cache = cache
      @root = Pathname(root)
      @config = config
      @secret_key_base = secret_key_base
    end
  end

  def fake_config
    FakeConfig.new
  end

  def with_tmp_app(config: fake_config, secret_key_base: "x" * 64, cache: nil)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      yield FakeApplication.new(root: dir, config: config, secret_key_base: secret_key_base, cache: cache), Pathname(dir)
    end
  end
end
